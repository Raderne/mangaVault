/**
 * Normalized MangaVault domain model — the pure output of the parsing lib,
 * consumed by the import module. Mirrors `docs/phase-1-data-structures.md` §2,
 * minus persistence-only fields (vault ids, importIds) which the DB assigns.
 *
 * Kept free of Nest/TypeORM so the whole `tachibk/` lib is unit-testable.
 */

export type PublicationStatus =
  | 'unknown'
  | 'ongoing'
  | 'completed'
  | 'licensed'
  | 'publishing_finished'
  | 'cancelled'
  | 'on_hiatus';

export type TrackerId =
  | 'myanimelist'
  | 'anilist'
  | 'kitsu'
  | 'shikimori'
  | 'bangumi'
  | 'komga'
  | 'mangaupdates'
  | `unknown:${number}`;

/** Stable identity of a title within a source app ecosystem. */
export interface SourceKey {
  sourceId: string; // int64 as decimal string
  mangaUrl: string; // relative url, exactly as in backup
}

export interface NormalizedChapter {
  url: string;
  name: string;
  chapterNumber: number; // -1 = unknown
  scanlator?: string;
  read: boolean;
  bookmark: boolean;
  lastPageRead: number;
  dateUpload: number;
  dateFetch: number;
  sourceOrder: number;
  lastReadAt?: number; // folded from history (max)
  readDuration: number; // folded from history (sum)
}

export interface NormalizedTracking {
  tracker: TrackerId;
  remoteId: string; // int64-safe
  trackingUrl: string;
  title: string;
  lastChapterRead: number;
  totalChapters: number;
  score: number;
  status: number;
  startedAt?: number;
  finishedAt?: number;
}

export interface NormalizedManga {
  key: SourceKey;
  sourceName: string;
  title: string;
  author?: string;
  artist?: string;
  description?: string;
  genres: string[];
  status: PublicationStatus;
  thumbnailUrl?: string;
  notes: string;
  favorite: boolean;
  dateAdded: number; // epoch millis
  lastModifiedAt: number; // epoch millis — drives newest-wins merge
  categoryNames: string[]; // resolved from category orders
  chapters: NormalizedChapter[];
  tracking: NormalizedTracking[];
}

export interface NormalizedCategory {
  name: string;
  order: number;
}

export interface NormalizedSource {
  sourceId: string;
  name: string;
}

export interface NormalizedBackup {
  manga: NormalizedManga[];
  categories: NormalizedCategory[];
  sources: NormalizedSource[];
}

export type BackupContainerKind = 'gzip-proto' | 'raw-proto' | 'legacy-json';

export interface ParsedBackup {
  wire: WireBackupLike;
  container: BackupContainerKind;
  sourceApp: string; // from filename prefix, '' if unrecognized
  warnings: string[];
}

/** The parser emits the wire model; legacy JSON is adapted into the same shape. */
export type WireBackupLike = import('./wire').WireBackup;
