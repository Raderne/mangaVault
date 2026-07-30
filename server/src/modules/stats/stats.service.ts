import { readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';

import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

import type { PublicationStatus } from '../../entities/manga.entity';
import {
  PUBLICATION_STATUSES,
  type MangaListItemDto,
} from '../library/library.dto';
import { LibraryService } from '../library/library.service';
import { stalenessOf } from './staleness';
import type {
  BackupHealthDto,
  LibraryStatsDto,
  ResumeItemDto,
} from './stats.dto';

const DAY_MS = 24 * 60 * 60 * 1000;

interface TitleRow {
  total_titles: number;
  favorite_titles: number;
  added_last_7_days: number;
  source_count: number;
  covers_archived: number;
  covers_failed: number;
}

interface ChapterRow {
  total_chapters: number;
  read_chapters: number;
}

interface ImportRow {
  import_count: number;
  last_import_at: string | null;
}

interface StatusRow {
  status: PublicationStatus;
  n: number;
}

interface SourceAppRow {
  source_app: string;
  n: number;
}

interface HealthRow {
  source_app: string;
  last_import_at: string;
  import_count: number;
  title_count: number;
}

interface ResumeRow {
  id: string;
  title: string;
  author: string | null;
  status: PublicationStatus;
  cover_path: string | null;
  cover_state: MangaListItemDto['coverState'];
  source_name: string;
  source_id: string;
  chapter_count: number;
  unread_count: number;
  read_count: number;
  last_read_at: string;
  next_name: string;
  next_number: number;
}

/**
 * Dashboard aggregates. Every figure is derived on read — there is no stats
 * table to keep in sync, and at this scale (~1.2k titles / ~124k chapters) the
 * grouped scans are cheap. `vaultSizeBytes` mixes the Postgres database size
 * with the on-disk archive (backup files + covers), since "how big is my vault"
 * spans both.
 */
@Injectable()
export class StatsService {
  private readonly storageDir: string;

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly library: LibraryService,
    config: ConfigService,
  ) {
    this.storageDir = config.get<string>('STORAGE_DIR') ?? './storage';
  }

  /** Headline counters for the dashboard's stat cells. */
  async libraryStats(now = Date.now()): Promise<LibraryStatsDto> {
    const weekAgo = now - 7 * DAY_MS;

    const [titles, chapters, imports, statusRows, sourceAppRows, sizeBytes] =
      await Promise.all([
        this.dataSource.query<TitleRow[]>(
          `SELECT COUNT(*)::int                                            AS total_titles,
                  COUNT(*) FILTER (WHERE favorite)::int                    AS favorite_titles,
                  COUNT(*) FILTER (WHERE date_added >= $1)::int            AS added_last_7_days,
                  COUNT(DISTINCT source_id)::int                           AS source_count,
                  COUNT(*) FILTER (WHERE cover_state = 'archived')::int     AS covers_archived,
                  COUNT(*) FILTER (WHERE cover_state = 'failed')::int       AS covers_failed
           FROM manga`,
          [weekAgo],
        ),
        this.dataSource.query<ChapterRow[]>(
          `SELECT COUNT(*)::int                      AS total_chapters,
                  COUNT(*) FILTER (WHERE read)::int  AS read_chapters
           FROM chapter`,
        ),
        this.dataSource.query<ImportRow[]>(
          `SELECT COUNT(*)::int         AS import_count,
                  MAX(imported_at)      AS last_import_at
           FROM import_record`,
        ),
        this.dataSource.query<StatusRow[]>(
          `SELECT status, COUNT(*)::int AS n FROM manga GROUP BY status`,
        ),
        this.dataSource.query<SourceAppRow[]>(
          `SELECT ir.source_app, COUNT(DISTINCT mi.manga_id)::int AS n
           FROM import_record ir
           JOIN manga_import mi ON mi.import_id = ir.id
           GROUP BY ir.source_app`,
        ),
        this.vaultSizeBytes(),
      ]);

    // Every status key is present (zeroed) so the client can render a full
    // breakdown without null-checking each band.
    const byStatus = Object.fromEntries(
      PUBLICATION_STATUSES.map((s) => [s, 0]),
    ) as Record<PublicationStatus, number>;
    for (const row of statusRows) byStatus[row.status] = row.n;

    const bySourceApp: Record<string, number> = {};
    for (const row of sourceAppRows) {
      bySourceApp[row.source_app || 'unknown'] = row.n;
    }

    const t = titles[0];
    const c = chapters[0];
    const i = imports[0];
    return {
      totalTitles: t?.total_titles ?? 0,
      favoriteTitles: t?.favorite_titles ?? 0,
      totalChapters: c?.total_chapters ?? 0,
      readChapters: c?.read_chapters ?? 0,
      addedLast7Days: t?.added_last_7_days ?? 0,
      sourceCount: t?.source_count ?? 0,
      bySourceApp,
      byStatus,
      coversArchived: t?.covers_archived ?? 0,
      coversFailed: t?.covers_failed ?? 0,
      importCount: i?.import_count ?? 0,
      lastImportAt:
        i?.last_import_at === null ? null : Number(i.last_import_at),
      vaultSizeBytes: sizeBytes,
    };
  }

  /** One freshness row per backup source app, newest import first. */
  async backupHealth(now = Date.now()): Promise<BackupHealthDto[]> {
    const rows = await this.dataSource.query<HealthRow[]>(
      `SELECT COALESCE(NULLIF(ir.source_app, ''), 'unknown') AS source_app,
              MAX(ir.imported_at)                            AS last_import_at,
              COUNT(DISTINCT ir.id)::int                     AS import_count,
              COUNT(DISTINCT mi.manga_id)::int               AS title_count
       FROM import_record ir
       LEFT JOIN manga_import mi ON mi.import_id = ir.id
       GROUP BY 1
       ORDER BY 2 DESC`,
    );
    return rows.map((r): BackupHealthDto => {
      const lastImportAt = Number(r.last_import_at);
      return {
        sourceApp: r.source_app,
        lastImportAt,
        importCount: r.import_count,
        titleCount: r.title_count,
        staleness: stalenessOf(lastImportAt, now),
      };
    });
  }

  /** Newest titles in the archive — the dashboard's "recently added" shelf. */
  async recentlyAdded(limit: number): Promise<MangaListItemDto[]> {
    const page = await this.library.query({
      status: [],
      categoryIds: [],
      sourceIds: [],
      sortBy: 'dateAdded',
      sortDir: 'desc',
      offset: 0,
      limit,
    });
    return page.items;
  }

  /**
   * Titles that were read at some point and still have an unread chapter,
   * most recently read first. The next chapter comes from a LATERAL pick so one
   * query answers both "what do I resume" and "where do I resume".
   */
  async resumeReading(limit: number): Promise<ResumeItemDto[]> {
    const rows = await this.dataSource.query<ResumeRow[]>(
      `WITH agg AS (
         SELECT manga_id,
                COUNT(*)::int                          AS chapter_count,
                COUNT(*) FILTER (WHERE NOT read)::int  AS unread_count,
                COUNT(*) FILTER (WHERE read)::int      AS read_count,
                MAX(last_read_at)                      AS last_read_at
         FROM chapter
         GROUP BY manga_id
         HAVING MAX(last_read_at) IS NOT NULL
            AND COUNT(*) FILTER (WHERE NOT read) > 0
         -- Order + limit inside the CTE so the LATERAL "next chapter" lookup
         -- runs for the handful of rows returned, not every candidate title.
         ORDER BY MAX(last_read_at) DESC, manga_id ASC
         LIMIT $1
       )
       SELECT m.id, m.title, m.author, m.status, m.cover_path, m.cover_state,
              m.source_name, m.source_id,
              agg.chapter_count, agg.unread_count, agg.read_count,
              agg.last_read_at,
              nxt.name           AS next_name,
              nxt.chapter_number AS next_number
       FROM agg
       JOIN manga m ON m.id = agg.manga_id
       JOIN LATERAL (
         SELECT c.name, c.chapter_number
         FROM chapter c
         WHERE c.manga_id = m.id AND NOT c.read
         ORDER BY c.chapter_number ASC NULLS LAST, c.source_order ASC
         LIMIT 1
       ) nxt ON TRUE
       ORDER BY agg.last_read_at DESC, m.id ASC`,
      [limit],
    );

    return rows.map((r): ResumeItemDto => ({
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
      readCount: r.read_count,
      lastReadAt: Number(r.last_read_at),
      nextChapter: { name: r.next_name, number: r.next_number },
    }));
  }

  // ---- internals ----

  /** DB size + archived backup files + cover files. */
  private async vaultSizeBytes(): Promise<number> {
    const [dbSize, imports, covers] = await Promise.all([
      this.dataSource
        .query<{ size: string }[]>(
          `SELECT pg_database_size(current_database())::text AS size`,
        )
        .then((rows) => Number(rows[0]?.size ?? 0))
        .catch(() => 0),
      this.dirSize(join(this.storageDir, 'imports')),
      this.dirSize(join(this.storageDir, 'covers')),
    ]);
    return dbSize + imports + covers;
  }

  /**
   * Total size of the files directly inside `dir`, or 0 when it doesn't exist
   * yet. Both archive directories are flat, so a single readdir + stat per file
   * is enough (a missing size must never fail the whole dashboard).
   */
  private async dirSize(dir: string): Promise<number> {
    let entries: string[];
    try {
      entries = await readdir(dir);
    } catch {
      return 0;
    }
    const sizes = await Promise.all(
      entries.map((name) =>
        stat(join(dir, name))
          .then((s) => (s.isFile() ? s.size : 0))
          .catch(() => 0),
      ),
    );
    let total = 0;
    for (const size of sizes) total += size;
    return total;
  }
}
