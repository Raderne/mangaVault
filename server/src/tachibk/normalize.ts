import type {
  NormalizedBackup,
  NormalizedChapter,
  NormalizedManga,
  NormalizedTracking,
  ParsedBackup,
  PublicationStatus,
  TrackerId,
} from './domain';
import type { WireChapter, WireManga, WireTracking } from './wire';

/** SManga status int -> domain status (docs/phase-1 §1). */
const STATUS: Record<number, PublicationStatus> = {
  0: 'unknown',
  1: 'ongoing',
  2: 'completed',
  3: 'licensed',
  4: 'publishing_finished',
  5: 'cancelled',
  6: 'on_hiatus',
};

/** Tracker syncId -> domain TrackerId (docs/phase-1 §1). */
const TRACKERS: Record<number, TrackerId> = {
  1: 'myanimelist',
  2: 'anilist',
  3: 'kitsu',
  4: 'shikimori',
  5: 'bangumi',
  6: 'komga',
  7: 'mangaupdates',
};

/**
 * Normalizes a parsed wire backup into the domain model: applies Mihon defaults,
 * resolves category orders -> names, folds reading history into chapters, and
 * maps tracker/status enums. Pure — same input always yields the same output.
 */
export class BackupNormalizer {
  normalize(parsed: ParsedBackup): NormalizedBackup {
    const wire = parsed.wire;
    const warnings = parsed.warnings;

    // order (as decimal string) -> category name, for BackupManga.categories.
    const orderToName = new Map<string, string>();
    const categories = (wire.backupCategories ?? []).map((c) => {
      const order = toInt(c.order);
      const name = c.name ?? '';
      orderToName.set(String(order), name);
      return { name, order };
    });

    const sourceIdToName = new Map<string, string>();
    for (const s of wire.backupSources ?? []) {
      if (s.sourceId != null)
        sourceIdToName.set(String(s.sourceId), s.name ?? '');
    }

    const manga = (wire.backupManga ?? [])
      .filter((m) => {
        const ok = !!m.url && m.source != null;
        if (!ok)
          warnings.push(
            `skipped a manga missing source/url ("${m.title ?? '?'}")`,
          );
        return ok;
      })
      .map((m) =>
        this.normalizeManga(m, orderToName, sourceIdToName, warnings),
      );

    const sources = [...sourceIdToName.entries()].map(([sourceId, name]) => ({
      sourceId,
      name,
    }));

    return { manga, categories, sources };
  }

  private normalizeManga(
    m: WireManga,
    orderToName: Map<string, string>,
    sourceIdToName: Map<string, string>,
    warnings: string[],
  ): NormalizedManga {
    const sourceId = String(m.source);
    const chapters = this.foldHistory(m, warnings);
    const categoryNames = (m.categories ?? [])
      .map((order) => orderToName.get(String(order)))
      .filter((n): n is string => n != null && n !== '');

    return {
      key: { sourceId, mangaUrl: m.url ?? '' },
      sourceName: sourceIdToName.get(sourceId) ?? '',
      title: m.title ?? '',
      author: emptyToUndef(m.author),
      artist: emptyToUndef(m.artist),
      description: emptyToUndef(m.description),
      genres: m.genre ?? [],
      status: STATUS[m.status ?? 0] ?? 'unknown',
      thumbnailUrl: emptyToUndef(m.thumbnailUrl),
      notes: m.notes ?? '',
      favorite: m.favorite ?? true, // Mihon default: absent => TRUE
      dateAdded: toInt(m.dateAdded),
      lastModifiedAt: toInt(m.lastModifiedAt),
      categoryNames,
      chapters,
      tracking: (m.tracking ?? []).map((t) => this.normalizeTracking(t)),
    };
  }

  /** Union chapters + fold BackupHistory (max lastRead, sum readDuration) by url. */
  private foldHistory(m: WireManga, warnings: string[]): NormalizedChapter[] {
    const lastReadByUrl = new Map<string, number>();
    const durationByUrl = new Map<string, number>();
    for (const h of m.history ?? []) {
      if (!h.url) continue;
      const lastRead = toInt(h.lastRead);
      const duration = toInt(h.readDuration);
      lastReadByUrl.set(
        h.url,
        Math.max(lastReadByUrl.get(h.url) ?? 0, lastRead),
      );
      durationByUrl.set(h.url, (durationByUrl.get(h.url) ?? 0) + duration);
    }

    const seen = new Set<string>();
    const chapters: NormalizedChapter[] = [];
    for (const c of m.chapters ?? []) {
      const url = c.url ?? '';
      if (!url) {
        warnings.push(`skipped a chapter with no url in "${m.title ?? '?'}"`);
        continue;
      }
      if (seen.has(url)) continue; // union by url within a single backup
      seen.add(url);
      chapters.push(
        this.normalizeChapter(
          c,
          lastReadByUrl.get(url),
          durationByUrl.get(url) ?? 0,
        ),
      );
    }
    return chapters;
  }

  private normalizeChapter(
    c: WireChapter,
    lastReadAt: number | undefined,
    readDuration: number,
  ): NormalizedChapter {
    return {
      url: c.url ?? '',
      name: c.name ?? '',
      chapterNumber: typeof c.chapterNumber === 'number' ? c.chapterNumber : -1,
      scanlator: emptyToUndef(c.scanlator),
      read: c.read ?? false,
      bookmark: c.bookmark ?? false,
      lastPageRead: toInt(c.lastPageRead),
      dateUpload: toInt(c.dateUpload),
      dateFetch: toInt(c.dateFetch),
      sourceOrder: toInt(c.sourceOrder),
      lastReadAt: lastReadAt && lastReadAt > 0 ? lastReadAt : undefined,
      readDuration,
    };
  }

  private normalizeTracking(t: WireTracking): NormalizedTracking {
    const syncId = t.syncId ?? 0;
    // mediaIdInt is deprecated: use it only when non-zero, else the int64 mediaId.
    const remoteId =
      t.mediaIdInt && t.mediaIdInt !== 0
        ? String(t.mediaIdInt)
        : String(t.mediaId ?? '0');
    return {
      tracker: TRACKERS[syncId] ?? (`unknown:${syncId}` as TrackerId),
      remoteId,
      trackingUrl: t.trackingUrl ?? '',
      title: t.title ?? '',
      lastChapterRead: t.lastChapterRead ?? 0,
      totalChapters: t.totalChapters ?? 0,
      score: t.score ?? 0,
      status: t.status ?? 0,
      startedAt: undefinedIfZero(t.startedReadingDate),
      finishedAt: undefinedIfZero(t.finishedReadingDate),
    };
  }
}

/** int64 decimal string (or undefined) -> JS number. Safe: epoch millis < 2^53. */
function toInt(v: string | number | undefined): number {
  if (v == null) return 0;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}
function undefinedIfZero(v: string | number | undefined): number | undefined {
  const n = toInt(v);
  return n > 0 ? n : undefined;
}
function emptyToUndef(v: string | undefined): string | undefined {
  return v == null || v === '' ? undefined : v;
}
