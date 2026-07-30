import type {
  BackupContainerKind,
  ImportStats,
} from '../../entities/import-record.entity';
import type {
  CoverState,
  PublicationStatus,
} from '../../entities/manga.entity';
import type { CategoryDto, ChapterRefDto } from '../library/library.dto';

/** Default titles per delta page (override with `?limit=`). */
export const SYNC_DEFAULT_LIMIT = 500;
/** Hard ceiling so one request can't try to serialize the whole library. */
export const SYNC_MAX_LIMIT = 1000;

/**
 * One title as the on-device mirror stores it: the union of what the library
 * grid and the Title Details screen render, and nothing more.
 *
 * Deliberately excludes the chapter list — 182k rows the app never displays.
 * Reading progress is carried as the pre-computed aggregates plus the two
 * chapter pointers the details screen actually shows.
 */
export interface SyncMangaDto {
  id: string;
  /** Monotonic version stamped by the DB trigger; int64 as a decimal string. */
  rowVersion: string;
  sourceId: string;
  sourceName: string;
  title: string;
  author: string | null;
  artist: string | null;
  description: string | null;
  genres: string[];
  status: PublicationStatus;
  thumbnailUrl: string | null;
  coverPath: string | null;
  coverState: CoverState;
  notes: string;
  favorite: boolean;
  dateAdded: number;
  updatedAt: number;
  chapterCount: number;
  readCount: number;
  unreadCount: number;
  lastReadAt: number | null;
  lastReadChapter: ChapterRefDto | null;
  nextChapter: ChapterRefDto | null;
  categoryIds: string[];
  importIds: string[];
}

/** One page of changes above the client's cursor. */
export interface SyncPageDto {
  changed: SyncMangaDto[];
  /** Ids of titles deleted since the cursor (from `sync_tombstone`). */
  deleted: string[];
  /** New high-water mark for the client to persist. */
  cursor: string;
  hasMore: boolean;
  /** Changes identity when Postgres is restored — clients must then full-resync. */
  serverEpoch: string;
}

/**
 * The small always-complete payloads plus the one figure the device can't
 * derive locally. Categories and import records are tiny and append-only, so
 * they're replaced wholesale rather than versioned.
 */
export interface SyncMetaDto {
  serverEpoch: string;
  cursor: string;
  totalTitles: number;
  categories: CategoryDto[];
  imports: SyncImportRecordDto[];
  /** Postgres + archived backups + cover files, in bytes (server-only). */
  vaultSizeBytes: number;
}

export interface SyncImportRecordDto {
  id: string;
  fileName: string;
  fileSize: number;
  sha256: string;
  sourceApp: string;
  container: BackupContainerKind;
  importedAt: number;
  /** Same shape as `ImportRecordDto.stats` — the history cell renders it. */
  stats: Partial<ImportStats>;
}
