import { Injectable, Logger } from '@nestjs/common';

import {
  SourceSearchError,
  type SearchableSource,
  type SourceCandidate,
  type SourceSearchAdapter,
} from './source-search.port';

/** Package this adapter serves — all 61 language variants MangaDex publishes. */
export const MANGADEX_PACKAGE = 'eu.kanade.tachiyomi.extension.all.mangadex';

const API = 'https://api.mangadex.org';
const CDN = 'https://uploads.mangadex.org';

/** Hits per query. Mihon reads page 1 only; more would just add noise. */
const LIMIT = 10;

/**
 * MangaDex needs every rating listed explicitly or it silently hides anything
 * not "safe" — which would make an adult title look like it had been removed.
 */
const CONTENT_RATINGS = ['safe', 'suggestive', 'erotica', 'pornographic'];

interface MangaDexRelationship {
  type: string;
  attributes?: { name?: string; fileName?: string };
}

interface MangaDexManga {
  id: string;
  attributes?: {
    title?: Record<string, string>;
    altTitles?: Array<Record<string, string>>;
    lastChapter?: string | null;
  };
  relationships?: MangaDexRelationship[];
}

/**
 * Live search against MangaDex's public API.
 *
 * MangaDex is the first adapter for three reasons: it is far and away the most
 * common migration *target*, it publishes a documented JSON API that needs no
 * key, and — unlike a scraped site — its identifiers are stable UUIDs, so a
 * migrated title keeps resolving years later.
 *
 * The url shape is the load-bearing detail. It must be byte-identical to what
 * the Mihon extension writes (`/manga/<uuid>`, confirmed in the keiyoushi
 * extension's `MangaDexHelper.createBasicManga`), because the whole point of
 * migrating is that the vault can be exported back to a `.tachibk` that Mihon
 * opens correctly. A url that merely *works in a browser* would silently
 * produce a backup full of entries Mihon cannot resolve.
 */
@Injectable()
export class MangaDexAdapter implements SourceSearchAdapter {
  readonly packageName = MANGADEX_PACKAGE;
  readonly displayName = 'MangaDex API';
  private readonly logger = new Logger(MangaDexAdapter.name);

  async search(
    source: SearchableSource,
    query: string,
    signal?: AbortSignal,
  ): Promise<SourceCandidate[]> {
    const trimmed = query.trim();
    if (!trimmed) return [];

    const params = new URLSearchParams();
    params.set('title', trimmed);
    params.set('limit', String(LIMIT));
    params.append('includes[]', 'author');
    params.append('includes[]', 'cover_art');
    for (const rating of CONTENT_RATINGS) {
      params.append('contentRating[]', rating);
    }
    // The vault row belongs to one language variant of the source, so results
    // are restricted to sources that actually have that translation — matching
    // what the user would see in Mihon on the same source id.
    const lang = normalizeLang(source.lang);
    if (lang) params.append('availableTranslatedLanguage[]', lang);

    const body = await this.get(`${API}/manga?${params.toString()}`, signal);
    const data = Array.isArray(body?.data) ? (body.data as MangaDexManga[]) : [];

    return data.flatMap((manga) => {
      const names = allTitles(manga);
      const title = pickTitle(manga, lang) ?? names[0];
      if (!manga.id || !title) return [];
      return [
        {
          sourceId: source.sourceId,
          // Exactly what the Mihon extension stores.
          url: `/manga/${manga.id}`,
          title,
          // MangaDex routinely files the name a reader knows a work by under
          // `altTitles` and puts a romanized original in `title`, so the
          // matcher gets both.
          altTitles: names.filter((n) => n !== title),
          author: pickAuthor(manga),
          thumbnailUrl: pickCover(manga),
          chapterCount: pickChapterCount(manga),
          via: 'adapter' as const,
        },
      ];
    });
  }

  private async get(
    url: string,
    signal?: AbortSignal,
  ): Promise<{ data?: unknown } | null> {
    let res: Response;
    try {
      res = await fetch(url, {
        headers: {
          Accept: 'application/json',
          // MangaDex asks API consumers to identify themselves.
          'User-Agent': 'MangaVault/1.0 (personal manga archive)',
        },
        signal,
      });
    } catch (err) {
      throw new SourceSearchError(
        this.packageName,
        `MangaDex unreachable (${err instanceof Error ? err.message : String(err)})`,
        err,
      );
    }
    if (res.status === 429) {
      // Their limiter is per-IP and short-lived; the plan run treats this as a
      // per-title failure the user can retry rather than a fatal error.
      throw new SourceSearchError(this.packageName, 'MangaDex rate limit hit');
    }
    if (!res.ok) {
      throw new SourceSearchError(
        this.packageName,
        `MangaDex answered HTTP ${res.status}`,
      );
    }
    try {
      return (await res.json()) as { data?: unknown };
    } catch (err) {
      this.logger.debug(`MangaDex returned unparseable JSON for ${url}`);
      throw new SourceSearchError(
        this.packageName,
        'MangaDex returned invalid JSON',
        err,
      );
    }
  }
}

/**
 * Mihon's source ids carry Mihon language tags (`pt-BR`, `zh-Hans`); MangaDex
 * wants the same tags lower-cased for the region-less ones. `all` means the
 * source is not language-scoped, so no filter is applied.
 */
function normalizeLang(lang: string): string | null {
  const trimmed = lang.trim();
  if (!trimmed || trimmed === 'all' || trimmed === 'other') return null;
  return trimmed;
}

/**
 * Every name this work is published under, primary titles first.
 *
 * Deduplicated, because a work is commonly listed under the same string in
 * several language slots and the matcher would otherwise score it repeatedly.
 */
function allTitles(manga: MangaDexManga): string[] {
  const out: string[] = [];
  const push = (value?: string) => {
    const trimmed = value?.trim();
    if (trimmed && !out.includes(trimmed)) out.push(trimmed);
  };
  for (const value of Object.values(manga.attributes?.title ?? {})) push(value);
  for (const alt of manga.attributes?.altTitles ?? []) {
    for (const value of Object.values(alt)) push(value);
  }
  return out;
}

/**
 * Display title: the source's language, else English, else the first name of
 * any kind. This is only what the review screen shows — matching uses every
 * name via {@link allTitles}.
 */
function pickTitle(manga: MangaDexManga, lang: string | null): string | null {
  const titles = manga.attributes?.title ?? {};
  if (lang && titles[lang]?.trim()) return titles[lang].trim();
  if (titles.en?.trim()) return titles.en.trim();

  // Prefer an English alternate over a romanized primary — it is the name the
  // user is most likely to recognise in the review list.
  for (const alt of manga.attributes?.altTitles ?? []) {
    if (lang && alt[lang]?.trim()) return alt[lang].trim();
  }
  for (const alt of manga.attributes?.altTitles ?? []) {
    if (alt.en?.trim()) return alt.en.trim();
  }
  return allTitles(manga)[0] ?? null;
}

function pickAuthor(manga: MangaDexManga): string | null {
  const author = manga.relationships?.find((r) => r.type === 'author');
  return author?.attributes?.name?.trim() || null;
}

function pickCover(manga: MangaDexManga): string | null {
  const cover = manga.relationships?.find((r) => r.type === 'cover_art');
  const fileName = cover?.attributes?.fileName;
  return fileName ? `${CDN}/covers/${manga.id}/${fileName}` : null;
}

/**
 * `lastChapter` is the highest *numbered* chapter, which is the closest thing
 * MangaDex offers to a count without a second request per title. Only used to
 * corroborate a title match, never on its own.
 */
function pickChapterCount(manga: MangaDexManga): number | null {
  const raw = manga.attributes?.lastChapter;
  if (!raw) return null;
  const n = Number.parseFloat(raw);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}
