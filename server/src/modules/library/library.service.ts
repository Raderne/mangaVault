import { Injectable } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { withSyncLock } from '../../common/sync-lock';
import { MangaEntity } from '../../entities';
import { CoverService } from '../covers/cover.service';
import type {
  ArchiveEntryDto,
  CategoryDto,
  ChapterRefDto,
  DeleteTitlesResultDto,
  LibraryPageDto,
  LibraryQueryDto,
  LibrarySortField,
  MangaListItemDto,
  VaultMangaDto,
} from './library.dto';

/** Raw row shapes for the hand-written SQL (bigints arrive as strings). */
interface ListRow {
  id: string;
  title: string;
  author: string | null;
  status: MangaListItemDto['status'];
  cover_path: string | null;
  cover_state: MangaListItemDto['coverState'];
  source_name: string;
  source_id: string;
  chapter_count: number;
  unread_count: number;
  last_read_at: string | null;
}

interface AggRow {
  total: number;
  read_count: number;
  last_read_at: string | null;
}

interface ChapterRefRow {
  name: string;
  chapter_number: number;
}

interface CategoryRow {
  id: string;
  name: string;
  sort: number;
  count: number;
}

/** SQL expression each sort field maps to (output-column aliases where computed). */
const SORT_EXPR: Record<LibrarySortField, string> = {
  title: 'm.title',
  dateAdded: 'm.date_added',
  lastReadAt: 'last_read_at',
  chapterCount: 'chapter_count',
  unreadCount: 'unread_count',
};

const nullableNumber = (v: string | null): number | null =>
  v === null ? null : Number(v);

@Injectable()
export class LibraryService {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(MangaEntity)
    private readonly mangaRepo: Repository<MangaEntity>,
    private readonly covers: CoverService,
  ) {}

  /** Paginated, filtered, sorted library slice for the archive grid. */
  async query(q: LibraryQueryDto): Promise<LibraryPageDto> {
    const params: unknown[] = [];
    const bind = (value: unknown): string => {
      params.push(value);
      return `$${params.length}`;
    };

    const conds: string[] = [];
    const text = q.text?.trim();
    if (text) {
      const tsq = bind(text);
      const like = bind(`%${text}%`);
      conds.push(
        `(m.search_tsv @@ plainto_tsquery('simple', ${tsq}) OR m.title ILIKE ${like})`,
      );
    }
    if (q.status.length) conds.push(`m.status = ANY(${bind(q.status)})`);
    if (q.sourceIds.length) {
      conds.push(`m.source_id = ANY(${bind(q.sourceIds)})`);
    }
    if (q.categoryIds.length) {
      conds.push(
        `EXISTS (SELECT 1 FROM manga_category mc
                 WHERE mc.manga_id = m.id
                   AND mc.category_id = ANY(${bind(q.categoryIds)}::uuid[]))`,
      );
    }
    if (q.favorite !== undefined) {
      conds.push(`m.favorite = ${bind(q.favorite)}`);
    }
    const whereSql = conds.length ? `WHERE ${conds.join(' AND ')}` : '';

    const totalRows = await this.dataSource.query<{ n: number }[]>(
      `SELECT COUNT(*)::int AS n FROM manga m ${whereSql}`,
      params,
    );
    const total = totalRows[0]?.n ?? 0;

    const dir = q.sortDir === 'asc' ? 'ASC' : 'DESC';
    const limit = bind(q.limit);
    const offset = bind(q.offset);

    // The chapter aggregate is a single grouped scan joined back per title, so
    // chapter/unread counts and last-read are available for both display and
    // sorting without an N+1.
    const rows = await this.dataSource.query<ListRow[]>(
      `SELECT m.id, m.title, m.author, m.status, m.cover_path, m.cover_state,
              m.source_name, m.source_id,
              COALESCE(agg.chapter_count, 0)::int AS chapter_count,
              COALESCE(agg.unread_count, 0)::int  AS unread_count,
              agg.last_read_at                    AS last_read_at
       FROM manga m
       LEFT JOIN (
         SELECT manga_id,
                COUNT(*)                          AS chapter_count,
                COUNT(*) FILTER (WHERE NOT read)  AS unread_count,
                MAX(last_read_at)                 AS last_read_at
         FROM chapter
         GROUP BY manga_id
       ) agg ON agg.manga_id = m.id
       ${whereSql}
       ORDER BY ${SORT_EXPR[q.sortBy]} ${dir} NULLS LAST, m.title ASC, m.id ASC
       LIMIT ${limit} OFFSET ${offset}`,
      params,
    );

    return {
      items: rows.map((r): MangaListItemDto => ({
        id: r.id,
        title: r.title,
        author: r.author,
        status: r.status,
        coverPath: r.cover_path,
        coverState: r.cover_state,
        sourceName: r.source_name,
        sourceId: r.source_id,
        chapterCount: r.chapter_count,
        unreadCount: r.unread_count,
        lastReadAt: nullableNumber(r.last_read_at),
      })),
      total,
      offset: q.offset,
      limit: q.limit,
    };
  }

  /** Full title record with computed reading progress and archive history. */
  async get(id: string): Promise<VaultMangaDto | null> {
    const m = await this.mangaRepo.findOne({
      where: { id },
      relations: { categories: true, tracking: true, imports: true },
    });
    if (!m) return null;

    const [agg] = await this.dataSource.query<AggRow[]>(
      `SELECT COUNT(*)::int                        AS total,
              COUNT(*) FILTER (WHERE read)::int     AS read_count,
              MAX(last_read_at)                     AS last_read_at
       FROM chapter WHERE manga_id = $1`,
      [id],
    );
    const [lastRead] = await this.dataSource.query<ChapterRefRow[]>(
      `SELECT name, chapter_number FROM chapter
       WHERE manga_id = $1 AND last_read_at IS NOT NULL
       ORDER BY last_read_at DESC LIMIT 1`,
      [id],
    );
    const [next] = await this.dataSource.query<ChapterRefRow[]>(
      `SELECT name, chapter_number FROM chapter
       WHERE manga_id = $1 AND NOT read
       ORDER BY chapter_number ASC NULLS LAST, source_order ASC LIMIT 1`,
      [id],
    );

    const total = agg?.total ?? 0;
    const readCount = agg?.read_count ?? 0;
    const toRef = (r?: ChapterRefRow): ChapterRefDto | null =>
      r ? { name: r.name, number: r.chapter_number } : null;

    return {
      id: m.id,
      sourceId: m.sourceId,
      mangaUrl: m.mangaUrl,
      sourceName: m.sourceName,
      title: m.title,
      author: m.author,
      artist: m.artist,
      description: m.description,
      genres: m.genres ?? [],
      status: m.status,
      thumbnailUrl: m.thumbnailUrl,
      coverPath: m.coverPath,
      coverState: m.coverState,
      notes: m.notes,
      favorite: m.favorite,
      dateAdded: m.dateAdded,
      updatedAt: m.updatedAt,
      chapterCount: total,
      readCount,
      unreadCount: Math.max(0, total - readCount),
      lastReadAt: nullableNumber(agg?.last_read_at ?? null),
      lastReadChapter: toRef(lastRead),
      nextChapter: toRef(next),
      categories: m.categories
        .map((c) => ({ id: c.id, name: c.name }))
        .sort((a, b) => a.name.localeCompare(b.name)),
      tracking: m.tracking.map((t) => ({
        tracker: t.tracker,
        title: t.title,
        trackingUrl: t.trackingUrl,
        lastChapterRead: t.lastChapterRead,
        totalChapters: t.totalChapters,
        score: t.score,
      })),
      archive: m.imports
        .map((imp): ArchiveEntryDto => ({
          id: imp.id,
          fileName: imp.fileName,
          sourceApp: imp.sourceApp,
          container: imp.container,
          importedAt: imp.importedAt,
        }))
        .sort((a, b) => b.importedAt - a.importedAt),
    };
  }

  /**
   * Permanently remove titles from the vault.
   *
   * Chapters, tracking rows and the category/import links all disappear with
   * the row (every child FK is `ON DELETE CASCADE`), and the `AFTER DELETE`
   * trigger writes a `sync_tombstone` — so the next delta removes the title
   * from every device mirror with no protocol change.
   *
   * The transaction takes the sync lock because that tombstone draws its
   * `row_version` from the shared sequence: without it a concurrent cover write
   * could commit a higher version first and a client would advance its cursor
   * straight past this deletion.
   *
   * Cover files are unlinked *after* the commit — `cover_path` is the only
   * pointer to them, but a rolled-back delete must not leave a surviving title
   * pointing at a file that is already gone.
   */
  async deleteMany(ids: string[]): Promise<DeleteTitlesResultDto> {
    if (ids.length === 0) return { deleted: 0, coversRemoved: 0 };

    // Read the paths and delete in one transaction. Deliberately two
    // statements rather than `DELETE … RETURNING`: TypeORM hands back
    // `[rows, affectedCount]` for a returning DELETE, and a plain SELECT keeps
    // the row shape unambiguous.
    const removed = await withSyncLock(this.dataSource, async (mgr) => {
      const rows = await mgr.query<{ cover_path: string | null }[]>(
        `SELECT cover_path FROM manga WHERE id = ANY($1::uuid[])`,
        [ids],
      );
      await mgr.query(`DELETE FROM manga WHERE id = ANY($1::uuid[])`, [ids]);
      return rows;
    });

    const coversRemoved = await this.covers.deleteCoverFiles(
      removed
        .map((r) => r.cover_path)
        .filter((p): p is string => p !== null && p.length > 0),
    );
    return { deleted: removed.length, coversRemoved };
  }

  /** Categories with title counts, ordered by their configured sort. */
  async listCategories(): Promise<CategoryDto[]> {
    const rows = await this.dataSource.query<CategoryRow[]>(
      `SELECT c.id, c.name, c.sort, COUNT(mc.manga_id)::int AS count
       FROM category c
       LEFT JOIN manga_category mc ON mc.category_id = c.id
       GROUP BY c.id
       ORDER BY c.sort ASC, c.name ASC`,
    );
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      sort: r.sort,
      count: r.count,
    }));
  }
}
