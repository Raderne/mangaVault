import { Injectable, Logger } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

import {
  BackupDenormalizer,
  BackupEncoder,
  buildBackupFileName,
} from '../../tachibk';
import type {
  NormalizedBackup,
  NormalizedChapter,
  NormalizedManga,
  NormalizedTracking,
  PublicationStatus,
  TrackerId,
} from '../../tachibk';
import type {
  ExportFacetOptionDto,
  ExportFacetsDto,
  ExportPreviewDto,
  ExportPreviewItemDto,
  ExportScopeDto,
} from './export.dto';

/**
 * How many titles' children are loaded per round trip. A full vault can hold
 * hundreds of thousands of chapters; batching keeps one export from pulling the
 * entire `chapter` table into memory in a single result set.
 */
const CHILD_BATCH = 500;

/** Titles shown in the preview list — enough to confirm the scope, not a page. */
const SAMPLE_SIZE = 8;

/**
 * Rough per-row contribution to the gzipped file, measured against real
 * exports. Only ever rendered with a `~`; the download reports the true size.
 */
const EST_BYTES_PER_TITLE = 110;
const EST_BYTES_PER_CHAPTER = 26;

interface MangaRow {
  id: string;
  source_id: string;
  manga_url: string;
  source_name: string;
  title: string;
  author: string | null;
  artist: string | null;
  description: string | null;
  genres: string[] | null;
  status: PublicationStatus;
  thumbnail_url: string | null;
  notes: string;
  favorite: boolean;
  date_added: string;
  updated_at: string;
}

interface ChapterRow {
  manga_id: string;
  url: string;
  name: string;
  chapter_number: number;
  scanlator: string | null;
  read: boolean;
  bookmark: boolean;
  last_page_read: string;
  date_upload: string;
  date_fetch: string;
  source_order: string;
  last_read_at: string | null;
  read_duration: string;
}

interface TrackingRow {
  manga_id: string;
  tracker: string;
  remote_id: string;
  tracking_url: string;
  title: string;
  last_chapter_read: number;
  total_chapters: number;
  score: number;
  status: number;
  started_at: string | null;
  finished_at: string | null;
}

interface CategoryLinkRow {
  manga_id: string;
  name: string;
  sort: number;
}

interface CountsRow {
  titles: number;
  chapters: number;
  read_chapters: number;
  sources: number;
  categories: number;
  tracked: number;
}

interface FacetRow {
  id: string;
  label: string;
  count: number;
}

const num = (v: string | number | null | undefined): number =>
  v === null || v === undefined ? 0 : Number(v);

const emptyToUndef = (v: string | null): string | undefined =>
  v === null || v === '' ? undefined : v;

/**
 * Builds `.tachibk` files out of the vault — the mirror image of the import
 * pipeline, and the answer to "what if MangaVault disappears": every title it
 * holds can be handed back to Mihon or any fork in the format they already read.
 *
 * Nothing is persisted. The file is assembled per request and streamed straight
 * back, so there is no export storage to grow, prune, or keep in sync with
 * deletions ({@link ExportController} streams it).
 */
@Injectable()
export class ExportService {
  private readonly logger = new Logger(ExportService.name);
  private readonly denormalizer = new BackupDenormalizer();
  private readonly encoder = new BackupEncoder();

  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  /** Every selectable value with its title count, for the scope builder. */
  async facets(): Promise<ExportFacetsDto> {
    const [totals] = await this.dataSource.query<
      { titles: number; favorites: number; chapters: number }[]
    >(
      `SELECT COUNT(*)::int                              AS titles,
              COUNT(*) FILTER (WHERE m.favorite)::int    AS favorites,
              (SELECT COUNT(*)::int FROM chapter)        AS chapters
       FROM manga m`,
    );

    // Same COALESCE bucketing as the library filter and the stats queries, so
    // an app chip means the same set of titles everywhere in the product.
    const apps = await this.dataSource.query<FacetRow[]>(
      `SELECT COALESCE(NULLIF(ir.source_app, ''), 'unknown') AS id,
              COALESCE(NULLIF(ba.display_name, ''),
                       NULLIF(ir.source_app, ''), 'Unknown app') AS label,
              COUNT(DISTINCT mi.manga_id)::int                AS count
       FROM import_record ir
       JOIN manga_import mi ON mi.import_id = ir.id
       LEFT JOIN backup_app ba ON ba.id = ir.source_app
       GROUP BY 1, 2
       ORDER BY count DESC, label ASC`,
    );

    const sources = await this.dataSource.query<FacetRow[]>(
      `SELECT m.source_id                                        AS id,
              COALESCE(NULLIF(MAX(m.source_name), ''),
                       MAX(ks.name), m.source_id)                AS label,
              COUNT(*)::int                                      AS count
       FROM manga m
       LEFT JOIN known_source ks ON ks.source_id = m.source_id
       GROUP BY m.source_id
       ORDER BY count DESC, label ASC`,
    );

    const categories = await this.dataSource.query<FacetRow[]>(
      `SELECT c.id::text AS id, c.name AS label, COUNT(mc.manga_id)::int AS count
       FROM category c
       LEFT JOIN manga_category mc ON mc.category_id = c.id
       GROUP BY c.id, c.name, c.sort
       ORDER BY c.sort ASC, c.name ASC`,
    );

    const statuses = await this.dataSource.query<FacetRow[]>(
      `SELECT m.status AS id, m.status AS label, COUNT(*)::int AS count
       FROM manga m GROUP BY m.status ORDER BY count DESC`,
    );

    const opt = (r: FacetRow): ExportFacetOptionDto => ({
      id: r.id,
      label: r.label,
      count: r.count,
    });

    return {
      totalTitles: totals?.titles ?? 0,
      favoriteTitles: totals?.favorites ?? 0,
      totalChapters: totals?.chapters ?? 0,
      apps: apps.map(opt),
      sources: sources.map(opt),
      categories: categories.map(opt),
      statuses: statuses.map(opt),
    };
  }

  /** What this scope would produce, without building the file. */
  async preview(scope: ExportScopeDto): Promise<ExportPreviewDto> {
    const { whereSql, params } = this.buildWhere(scope);

    // One CTE, one evaluation of the predicate, one round trip. The scope has
    // to be a CTE rather than repeated subqueries: the predicate is written
    // against the alias `m`, so any other alias would silently resolve `m.…`
    // against an outer query instead.
    const [counts] = await this.dataSource.query<CountsRow[]>(
      `WITH scope AS (SELECT m.id, m.source_id FROM manga m ${whereSql})
       SELECT (SELECT COUNT(*)::int FROM scope)                    AS titles,
              (SELECT COUNT(*)::int FROM chapter ch
                 JOIN scope s ON s.id = ch.manga_id)               AS chapters,
              (SELECT COUNT(*)::int FROM chapter ch
                 JOIN scope s ON s.id = ch.manga_id
                WHERE ch.read)                                     AS read_chapters,
              (SELECT COUNT(DISTINCT source_id)::int FROM scope)   AS sources,
              (SELECT COUNT(DISTINCT mc.category_id)::int
                 FROM manga_category mc
                 JOIN scope s ON s.id = mc.manga_id)               AS categories,
              (SELECT COUNT(DISTINCT t.manga_id)::int
                 FROM tracking t
                 JOIN scope s ON s.id = t.manga_id)                AS tracked`,
      params,
    );

    const sample = await this.dataSource.query<
      {
        id: string;
        title: string;
        source_name: string;
        chapter_count: number;
        read_count: number;
        favorite: boolean;
      }[]
    >(
      `SELECT m.id, m.title, m.source_name, m.favorite,
              COUNT(ch.id)::int                        AS chapter_count,
              COUNT(ch.id) FILTER (WHERE ch.read)::int AS read_count
       FROM manga m
       LEFT JOIN chapter ch ON ch.manga_id = m.id
       ${whereSql}
       GROUP BY m.id
       ORDER BY m.title ASC
       LIMIT ${SAMPLE_SIZE}`,
      params,
    );

    const titles = counts?.titles ?? 0;
    // A scope that excludes chapters carries none of their weight, so the
    // estimate has to respect the include flags or it lies by an order of
    // magnitude on a chapter-heavy library.
    const chapters = scope.include.chapters ? (counts?.chapters ?? 0) : 0;

    return {
      titles,
      chapters,
      readChapters: scope.include.readProgress
        ? (counts?.read_chapters ?? 0)
        : 0,
      categories: scope.include.categories ? (counts?.categories ?? 0) : 0,
      sources: counts?.sources ?? 0,
      trackedTitles: scope.include.tracking ? (counts?.tracked ?? 0) : 0,
      fileName: buildBackupFileName(scope.targetApp),
      estimatedBytes:
        titles * EST_BYTES_PER_TITLE + chapters * EST_BYTES_PER_CHAPTER,
      sample: sample.map((r): ExportPreviewItemDto => ({
        id: r.id,
        title: r.title,
        sourceName: r.source_name,
        chapterCount: r.chapter_count,
        readCount: r.read_count,
        favorite: r.favorite,
      })),
    };
  }

  /** Assemble and encode the file. Returns the bytes and the name to save as. */
  async build(
    scope: ExportScopeDto,
  ): Promise<{ fileName: string; bytes: Uint8Array; titles: number }> {
    const started = Date.now();
    const backup = await this.collect(scope);
    const bytes = await this.encoder.encode(
      this.denormalizer.denormalize(backup),
    );
    const fileName = buildBackupFileName(scope.targetApp);

    this.logger.log(
      `exported ${backup.manga.length} title(s) as ${fileName} ` +
        `(${bytes.byteLength} bytes, ${Date.now() - started}ms)`,
    );
    return { fileName, bytes, titles: backup.manga.length };
  }

  /**
   * Read the selected slice of the vault into the normalized domain model — the
   * same shape the *import* path produces, which is what lets the encoder be a
   * pure inverse of the parser rather than a second, divergent mapper.
   */
  private async collect(scope: ExportScopeDto): Promise<NormalizedBackup> {
    const { whereSql, params } = this.buildWhere(scope);

    const rows = await this.dataSource.query<MangaRow[]>(
      `SELECT m.id, m.source_id, m.manga_url, m.source_name, m.title, m.author,
              m.artist, m.description, m.genres, m.status, m.thumbnail_url,
              m.notes, m.favorite, m.date_added, m.updated_at
       FROM manga m ${whereSql}
       ORDER BY m.title ASC, m.id ASC`,
      params,
    );
    if (rows.length === 0) return { manga: [], categories: [], sources: [] };

    const ids = rows.map((r) => r.id);
    const chapters = scope.include.chapters
      ? await this.loadChapters(ids, scope.include.readProgress)
      : new Map<string, NormalizedChapter[]>();
    const tracking = scope.include.tracking
      ? await this.loadTracking(ids)
      : new Map<string, NormalizedTracking[]>();
    const { byManga: categoryNames, ordered } = scope.include.categories
      ? await this.loadCategories(ids)
      : { byManga: new Map<string, string[]>(), ordered: [] };

    const manga = rows.map((r): NormalizedManga => ({
      key: { sourceId: r.source_id, mangaUrl: r.manga_url },
      sourceName: r.source_name,
      title: r.title,
      author: emptyToUndef(r.author),
      artist: emptyToUndef(r.artist),
      description: emptyToUndef(r.description),
      genres: r.genres ?? [],
      status: r.status,
      thumbnailUrl: emptyToUndef(r.thumbnail_url),
      notes: r.notes ?? '',
      favorite: r.favorite,
      dateAdded: num(r.date_added),
      lastModifiedAt: num(r.updated_at),
      categoryNames: categoryNames.get(r.id) ?? [],
      chapters: chapters.get(r.id) ?? [],
      tracking: tracking.get(r.id) ?? [],
    }));

    // Only the sources actually represented, and only the categories actually
    // used — a restoring app should not be told about a source it holds no
    // titles from, or made to create empty categories.
    const sourceNames = new Map<string, string>();
    for (const m of manga) {
      if (!sourceNames.has(m.key.sourceId)) {
        sourceNames.set(m.key.sourceId, m.sourceName);
      }
    }

    return {
      manga,
      // Re-indexed 0..n-1: `order` is the wire-level category identity, so it
      // has to be dense and start at zero regardless of the vault's own sort.
      categories: ordered.map((name, order) => ({ name, order })),
      sources: [...sourceNames].map(([sourceId, name]) => ({ sourceId, name })),
    };
  }

  private async loadChapters(
    ids: string[],
    readProgress: boolean,
  ): Promise<Map<string, NormalizedChapter[]>> {
    const byManga = new Map<string, NormalizedChapter[]>();
    for (const batch of chunk(ids, CHILD_BATCH)) {
      const rows = await this.dataSource.query<ChapterRow[]>(
        `SELECT manga_id, url, name, chapter_number, scanlator, read, bookmark,
                last_page_read, date_upload, date_fetch, source_order,
                last_read_at, read_duration
         FROM chapter
         WHERE manga_id = ANY($1::uuid[])
         ORDER BY source_order ASC, chapter_number ASC`,
        [batch],
      );
      for (const r of rows) {
        const lastReadAt = num(r.last_read_at);
        const list = byManga.get(r.manga_id) ?? [];
        list.push({
          url: r.url,
          name: r.name,
          chapterNumber: r.chapter_number,
          scanlator: emptyToUndef(r.scanlator),
          // Dropping progress means the chapter list still travels, but the
          // reader starts clean — the "seed a second device" case. Bookmarks
          // survive: they are a deliberate mark, not a side effect of reading.
          read: readProgress ? r.read : false,
          bookmark: r.bookmark,
          lastPageRead: readProgress ? num(r.last_page_read) : 0,
          dateUpload: num(r.date_upload),
          dateFetch: num(r.date_fetch),
          sourceOrder: num(r.source_order),
          lastReadAt: readProgress && lastReadAt > 0 ? lastReadAt : undefined,
          readDuration: readProgress ? num(r.read_duration) : 0,
        });
        byManga.set(r.manga_id, list);
      }
    }
    return byManga;
  }

  private async loadTracking(
    ids: string[],
  ): Promise<Map<string, NormalizedTracking[]>> {
    const byManga = new Map<string, NormalizedTracking[]>();
    for (const batch of chunk(ids, CHILD_BATCH)) {
      const rows = await this.dataSource.query<TrackingRow[]>(
        `SELECT manga_id, tracker, remote_id, tracking_url, title,
                last_chapter_read, total_chapters, score, status,
                started_at, finished_at
         FROM tracking WHERE manga_id = ANY($1::uuid[])`,
        [batch],
      );
      for (const r of rows) {
        const list = byManga.get(r.manga_id) ?? [];
        list.push({
          tracker: r.tracker as TrackerId,
          remoteId: r.remote_id,
          trackingUrl: r.tracking_url,
          title: r.title,
          lastChapterRead: r.last_chapter_read,
          totalChapters: r.total_chapters,
          score: r.score,
          status: r.status,
          startedAt: num(r.started_at) || undefined,
          finishedAt: num(r.finished_at) || undefined,
        });
        byManga.set(r.manga_id, list);
      }
    }
    return byManga;
  }

  /**
   * Category membership per title, plus the distinct category names in vault
   * sort order — the order the export's dense `order` values are assigned from.
   */
  private async loadCategories(
    ids: string[],
  ): Promise<{ byManga: Map<string, string[]>; ordered: string[] }> {
    const byManga = new Map<string, string[]>();
    const seen = new Map<string, number>(); // name -> sort
    for (const batch of chunk(ids, CHILD_BATCH)) {
      const rows = await this.dataSource.query<CategoryLinkRow[]>(
        `SELECT mc.manga_id, c.name, c.sort
         FROM manga_category mc
         JOIN category c ON c.id = mc.category_id
         WHERE mc.manga_id = ANY($1::uuid[])
         ORDER BY c.sort ASC, c.name ASC`,
        [batch],
      );
      for (const r of rows) {
        const list = byManga.get(r.manga_id) ?? [];
        list.push(r.name);
        byManga.set(r.manga_id, list);
        if (!seen.has(r.name)) seen.set(r.name, r.sort);
      }
    }
    const ordered = [...seen.entries()]
      .sort((a, b) => a[1] - b[1] || a[0].localeCompare(b[0]))
      .map(([name]) => name);
    return { byManga, ordered };
  }

  /**
   * Scope -> SQL predicate over `manga m`.
   *
   * Deliberately the same clause shapes as {@link LibraryService.query}: the
   * wizard's chips are the library's chips, and a scope that previews as N
   * titles must be the same N the library grid shows for that filter.
   */
  private buildWhere(scope: ExportScopeDto): {
    whereSql: string;
    params: unknown[];
  } {
    const params: unknown[] = [];
    const bind = (value: unknown): string => {
      params.push(value);
      return `$${params.length}`;
    };

    if (scope.mode === 'all') return { whereSql: '', params };
    if (scope.mode === 'ids') {
      // An empty pick must select nothing, not everything — the difference
      // between an empty file and accidentally exporting the whole vault.
      if (scope.ids.length === 0) return { whereSql: 'WHERE FALSE', params };
      return {
        whereSql: `WHERE m.id = ANY(${bind(scope.ids)}::uuid[])`,
        params,
      };
    }

    const f = scope.filter;
    const conds: string[] = [];
    const text = f.text?.trim();
    if (text) {
      const tsq = bind(text);
      const like = bind(`%${text}%`);
      conds.push(
        `(m.search_tsv @@ plainto_tsquery('simple', ${tsq}) OR m.title ILIKE ${like})`,
      );
    }
    if (f.status.length) conds.push(`m.status = ANY(${bind(f.status)})`);
    if (f.sourceIds.length)
      conds.push(`m.source_id = ANY(${bind(f.sourceIds)})`);
    if (f.categoryIds.length) {
      conds.push(
        `EXISTS (SELECT 1 FROM manga_category mc
                 WHERE mc.manga_id = m.id
                   AND mc.category_id = ANY(${bind(f.categoryIds)}::uuid[]))`,
      );
    }
    if (f.sourceApps.length) {
      conds.push(
        `EXISTS (SELECT 1 FROM manga_import mi
                   JOIN import_record ir ON ir.id = mi.import_id
                 WHERE mi.manga_id = m.id
                   AND COALESCE(NULLIF(ir.source_app, ''), 'unknown')
                       = ANY(${bind(f.sourceApps)}))`,
      );
    }
    if (f.favorite !== undefined)
      conds.push(`m.favorite = ${bind(f.favorite)}`);
    if (f.unreadOnly) {
      conds.push(
        `EXISTS (SELECT 1 FROM chapter ch WHERE ch.manga_id = m.id AND NOT ch.read)`,
      );
    }
    if (f.startedOnly) {
      conds.push(
        `EXISTS (SELECT 1 FROM chapter ch WHERE ch.manga_id = m.id AND ch.read)`,
      );
    }

    return {
      whereSql: conds.length ? `WHERE ${conds.join(' AND ')}` : '',
      params,
    };
  }
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size)
    out.push(items.slice(i, i + size));
  return out;
}
