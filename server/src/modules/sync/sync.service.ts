import { Injectable } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

import { BackupAppsService } from '../backup-apps/backup-apps.service';
import type { ChapterRefDto } from '../library/library.dto';
import { LibraryService } from '../library/library.service';
import { StatsService } from '../stats/stats.service';
import {
  SYNC_DEFAULT_LIMIT,
  SYNC_MAX_LIMIT,
  type SyncImportRecordDto,
  type SyncMangaDto,
  type SyncMetaDto,
  type SyncPageDto,
} from './sync.dto';

/** Raw row from the delta query — BIGINTs arrive as strings. */
interface ChangeRow {
  id: string;
  row_version: string;
  source_id: string;
  source_name: string;
  title: string;
  author: string | null;
  artist: string | null;
  description: string | null;
  genres: string[] | null;
  status: SyncMangaDto['status'];
  thumbnail_url: string | null;
  cover_path: string | null;
  cover_state: SyncMangaDto['coverState'];
  notes: string;
  favorite: boolean;
  date_added: string;
  updated_at: string;
  chapter_count: number;
  read_count: number;
  last_read_at: string | null;
  last_read_name: string | null;
  last_read_number: number | null;
  next_name: string | null;
  next_number: number | null;
  category_ids: string[] | null;
  import_ids: string[] | null;
}

interface ImportRow {
  id: string;
  file_name: string;
  file_size: string;
  sha256: string;
  source_app: string;
  container: SyncImportRecordDto['container'];
  imported_at: string;
  stats: SyncImportRecordDto['stats'] | null;
}

const toRef = (
  name: string | null,
  number: number | null,
): ChapterRefDto | null =>
  name === null ? null : { name, number: number ?? -1 };

/**
 * Delta feed backing the on-device library mirror.
 *
 * Ordering is by `manga.row_version`, a monotonic counter stamped by database
 * triggers on every write to a title *or any of its children* (see the
 * sync-row-version migration). `manga.updated_at` cannot serve this role: it
 * carries the backup's `lastModifiedAt`, so it moves backwards, and cover
 * archiving never touches it.
 *
 * Pagination is keyset, not offset — rows mutate while a client is mid-sync,
 * and an offset would skip or repeat titles as they shift position.
 */
@Injectable()
export class SyncService {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly library: LibraryService,
    private readonly stats: StatsService,
    private readonly backupApps: BackupAppsService,
  ) {}

  /** Changes strictly above `since`, oldest version first. */
  async changesSince(since: string, limit: number): Promise<SyncPageDto> {
    const capped = Math.min(Math.max(limit, 1), SYNC_MAX_LIMIT);

    const rows = await this.dataSource.query<ChangeRow[]>(
      `SELECT m.id, m.row_version::text AS row_version,
              m.source_id, m.source_name, m.title, m.author, m.artist,
              m.description, m.genres, m.status, m.thumbnail_url,
              m.cover_path, m.cover_state, m.notes, m.favorite,
              m.date_added::text AS date_added,
              m.updated_at::text AS updated_at,
              COALESCE(agg.chapter_count, 0)::int AS chapter_count,
              COALESCE(agg.read_count, 0)::int    AS read_count,
              agg.last_read_at                    AS last_read_at,
              lr.name          AS last_read_name,
              lr.chapter_number AS last_read_number,
              nx.name          AS next_name,
              nx.chapter_number AS next_number,
              cat.ids          AS category_ids,
              imp.ids          AS import_ids
         FROM manga m
         LEFT JOIN LATERAL (
           SELECT COUNT(*)                         AS chapter_count,
                  COUNT(*) FILTER (WHERE read)     AS read_count,
                  MAX(last_read_at)                AS last_read_at
             FROM chapter WHERE manga_id = m.id
         ) agg ON TRUE
         LEFT JOIN LATERAL (
           SELECT name, chapter_number FROM chapter
            WHERE manga_id = m.id AND last_read_at IS NOT NULL
            ORDER BY last_read_at DESC LIMIT 1
         ) lr ON TRUE
         LEFT JOIN LATERAL (
           SELECT name, chapter_number FROM chapter
            WHERE manga_id = m.id AND NOT read
            ORDER BY chapter_number ASC NULLS LAST, source_order ASC LIMIT 1
         ) nx ON TRUE
         LEFT JOIN LATERAL (
           SELECT array_agg(category_id::text) AS ids
             FROM manga_category WHERE manga_id = m.id
         ) cat ON TRUE
         LEFT JOIN LATERAL (
           SELECT array_agg(import_id::text) AS ids
             FROM manga_import WHERE manga_id = m.id
         ) imp ON TRUE
        WHERE m.row_version > $1
        ORDER BY m.row_version ASC
        LIMIT $2`,
      [since, capped],
    );

    const deletedRows = await this.dataSource.query<
      { entity_id: string; row_version: string }[]
    >(
      `SELECT entity_id, row_version::text AS row_version
         FROM sync_tombstone
        WHERE entity = 'manga' AND row_version > $1
        ORDER BY row_version ASC
        LIMIT $2`,
      [since, capped],
    );

    // Changes and tombstones are two independently-limited streams over the
    // same version axis, so the cursor may only advance to a point below which
    // BOTH are complete. Advancing to the overall maximum would silently skip
    // rows: a full page of changes at v1..v500 alongside a tombstone at v700
    // must not move the cursor past 500.
    const changedCut = rows.length === capped;
    const deletedCut = deletedRows.length === capped;
    const lastChanged = rows.length
      ? BigInt(rows[rows.length - 1].row_version)
      : null;
    const lastDeleted = deletedRows.length
      ? BigInt(deletedRows[deletedRows.length - 1].row_version)
      : null;

    let cursor: bigint;
    if (changedCut && deletedCut) {
      cursor = lastChanged! < lastDeleted! ? lastChanged! : lastDeleted!;
    } else if (changedCut) {
      cursor = lastChanged!;
    } else if (deletedCut) {
      cursor = lastDeleted!;
    } else {
      // Both streams are exhausted — everything up to the highest delivered
      // version (or the caller's cursor, if nothing changed) is now safe.
      const all = [lastChanged, lastDeleted].filter((v) => v !== null);
      cursor = all.length
        ? all.reduce((a, b) => (a > b ? a : b))
        : BigInt(since);
    }

    // Drop anything above the safe cursor; it is re-delivered on the next page.
    const changed = rows.filter((r) => BigInt(r.row_version) <= cursor);
    const deleted = deletedRows.filter((d) => BigInt(d.row_version) <= cursor);

    return {
      changed: changed.map((r) => this.toDto(r)),
      deleted: deleted.map((d) => d.entity_id),
      cursor: cursor.toString(),
      hasMore: changedCut || deletedCut,
      serverEpoch: await this.serverEpoch(),
    };
  }

  /** Full category + import lists, the current high-water mark, and vault size. */
  async meta(): Promise<SyncMetaDto> {
    const [
      epoch,
      cursorRows,
      totalRows,
      categories,
      importRows,
      storage,
      backupApps,
    ] = await Promise.all([
      this.serverEpoch(),
      this.dataSource.query<{ cursor: string | null }[]>(
        `SELECT GREATEST(
                    COALESCE((SELECT MAX(row_version) FROM manga), 0),
                    COALESCE((SELECT MAX(row_version) FROM sync_tombstone), 0)
                  )::text AS cursor`,
      ),
      this.dataSource.query<{ n: number }[]>(
        `SELECT COUNT(*)::int AS n FROM manga`,
      ),
      this.library.listCategories(),
      this.dataSource.query<ImportRow[]>(
        `SELECT id, file_name, file_size::text AS file_size, sha256,
                  source_app, container, imported_at::text AS imported_at,
                  stats
             FROM import_record
            ORDER BY imported_at DESC`,
      ),
      this.stats.vaultStorage(),
      this.backupApps.list(),
    ]);

    return {
      serverEpoch: epoch,
      cursor: cursorRows[0]?.cursor ?? '0',
      totalTitles: totalRows[0]?.n ?? 0,
      categories,
      imports: importRows.map((r) => ({
        id: r.id,
        fileName: r.file_name,
        fileSize: Number(r.file_size),
        sha256: r.sha256,
        sourceApp: r.source_app,
        container: r.container,
        importedAt: Number(r.imported_at),
        stats: r.stats ?? {},
      })),
      backupApps,
      vaultSizeBytes: storage.totalBytes,
      vaultStorage: storage,
    };
  }

  // ---- internals ----

  private async serverEpoch(): Promise<string> {
    const rows = await this.dataSource.query<{ server_epoch: string }[]>(
      `SELECT server_epoch FROM sync_state LIMIT 1`,
    );
    return rows[0]?.server_epoch ?? '';
  }

  private toDto(r: ChangeRow): SyncMangaDto {
    const chapterCount = r.chapter_count;
    const readCount = r.read_count;
    return {
      id: r.id,
      rowVersion: r.row_version,
      sourceId: r.source_id,
      sourceName: r.source_name,
      title: r.title,
      author: r.author,
      artist: r.artist,
      description: r.description,
      genres: r.genres ?? [],
      status: r.status,
      thumbnailUrl: r.thumbnail_url,
      coverPath: r.cover_path,
      coverState: r.cover_state,
      notes: r.notes,
      favorite: r.favorite,
      dateAdded: Number(r.date_added),
      updatedAt: Number(r.updated_at),
      chapterCount,
      readCount,
      unreadCount: Math.max(0, chapterCount - readCount),
      lastReadAt: r.last_read_at === null ? null : Number(r.last_read_at),
      lastReadChapter: toRef(r.last_read_name, r.last_read_number),
      nextChapter: toRef(r.next_name, r.next_number),
      categoryIds: r.category_ids ?? [],
      importIds: r.import_ids ?? [],
    };
  }
}

export { SYNC_DEFAULT_LIMIT };
