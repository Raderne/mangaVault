import type { PublicationStatus } from '../../entities/manga.entity';
import type { ChapterRefDto, MangaListItemDto } from '../library/library.dto';

/** How long ago the newest backup for a source app was imported. */
export type Staleness = 'fresh' | 'aging' | 'stale';

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
