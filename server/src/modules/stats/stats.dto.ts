import type { PublicationStatus } from '../../entities/manga.entity';
import type { ChapterRefDto, MangaListItemDto } from '../library/library.dto';

/** How long ago the newest backup for a source app was imported. */
export type Staleness = 'fresh' | 'aging' | 'stale';

/**
 * Where the vault's bytes actually are.
 *
 * Measured on a 2,000-title library: 113 MB of Postgres against **613 MB of
 * cover images** and 10 MB of archived backups. One combined number hid that
 * completely, which is what made a 232 kB table look like the thing to worry
 * about.
 */
export interface VaultStorageDto {
  /** `pg_database_size()` — every table, index and TOAST segment. */
  databaseBytes: number;
  /** `STORAGE_DIR/covers` — archived cover images. */
  coversBytes: number;
  /** `STORAGE_DIR/imports` — the original `.tachibk` files, kept verbatim. */
  backupsBytes: number;
  totalBytes: number;
}

/** Headline archive figures backing the dashboard's stat cells. */
export interface LibraryStatsDto {
  totalTitles: number;
  favoriteTitles: number;
  totalChapters: number;
  readChapters: number;
  /** Titles whose `date_added` falls in the last 7 days. */
  addedLast7Days: number;
  /** Distinct Mihon sources represented in the library. */
  sourceCount: number;
  /** Titles contributed per backup source app ("app.mihon", …). */
  bySourceApp: Record<string, number>;
  byStatus: Record<PublicationStatus, number>;
  coversArchived: number;
  coversFailed: number;
  importCount: number;
  lastImportAt: number | null;
  /** Postgres database + archived backups + cover files, in bytes. */
  vaultSizeBytes: number;
  /** The same total, broken down by where it lives. */
  vaultStorage: VaultStorageDto;
}

/** Per-source-app backup freshness for the dashboard health cell. */
export interface BackupHealthDto {
  sourceApp: string;
  lastImportAt: number;
  importCount: number;
  titleCount: number;
  staleness: Staleness;
}

/** A title to continue reading: list row + its next unread chapter. */
export interface ResumeItemDto extends MangaListItemDto {
  readCount: number;
  nextChapter: ChapterRefDto;
}
