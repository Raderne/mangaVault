/**
 * TypeScript view of the decoded `.tachibk` wire model (see backup.proto.ts).
 *
 * Produced by `Type.toObject(msg, { longs: String, defaults: false })`:
 *  - every int64 field is a decimal **string** (JS numbers are unsafe > 2^53);
 *  - absent fields are `undefined` (defaults are applied later, in the
 *    normalizer, so we can honour Mihon's non-zero defaults like favorite=true).
 */
export interface WireBackup {
  backupManga?: WireManga[];
  backupCategories?: WireCategory[];
  backupSources?: WireSource[];
  // backupPreferences / backupSourcePreferences / backupExtensionRepo decoded
  // but not surfaced to the domain layer in v1.
}

export interface WireManga {
  source?: string; // int64
  url?: string;
  title?: string;
  artist?: string;
  author?: string;
  description?: string;
  genre?: string[];
  status?: number;
  thumbnailUrl?: string;
  dateAdded?: string; // int64 epoch millis
  chapters?: WireChapter[];
  categories?: string[]; // int64 order values
  tracking?: WireTracking[];
  favorite?: boolean; // optional: undefined => default TRUE
  history?: WireHistory[];
  lastModifiedAt?: string; // int64 epoch millis
  excludedScanlators?: string[];
  notes?: string;
  initialized?: boolean;
}

export interface WireChapter {
  url?: string;
  name?: string;
  scanlator?: string;
  read?: boolean;
  bookmark?: boolean;
  lastPageRead?: string; // int64
  dateFetch?: string; // int64
  dateUpload?: string; // int64
  chapterNumber?: number; // float, -1 = unknown
  sourceOrder?: string; // int64
}

export interface WireHistory {
  url?: string;
  lastRead?: string; // int64 epoch millis
  readDuration?: string; // int64 millis
}

export interface WireTracking {
  syncId?: number;
  mediaIdInt?: number; // deprecated; use if != 0
  trackingUrl?: string;
  title?: string;
  lastChapterRead?: number; // float
  totalChapters?: number;
  score?: number; // float
  status?: number;
  startedReadingDate?: string; // int64
  finishedReadingDate?: string; // int64
  mediaId?: string; // int64
}

export interface WireCategory {
  name?: string;
  order?: string; // int64
  id?: string; // int64
}

export interface WireSource {
  name?: string;
  sourceId?: string; // int64
}
