# Phase 1 — Data Structures

Three layers, in data-flow order:

1. **Wire layer** — mirrors Mihon's protobuf exactly (never edit field numbers).
2. **Domain layer** — normalized MangaVault model the app works with.
3. **Persistence layer** — SQLite schema + vault folder layout.

---

## 1. Wire layer: `.tachibk` protobuf schema

Transcribed from `MihonApp/mihon/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/`.
Use as `backup.proto` (proto2-style optionality; kotlinx omits fields at default values).

```proto
syntax = "proto3";
package mangavault.tachibk;

message Backup {
  repeated BackupManga backupManga = 1;
  repeated BackupCategory backupCategories = 2;
  // 100 reserved (legacy broken source model)
  repeated BackupSource backupSources = 101;
  repeated BackupPreference backupPreferences = 104;
  repeated BackupSourcePreferences backupSourcePreferences = 105;
  repeated BackupExtensionRepos backupExtensionRepo = 106;
}

message BackupManga {
  int64 source = 1;                 // required in practice
  string url = 2;                   // required; RELATIVE url (no scheme/domain)
  string title = 3;
  optional string artist = 4;
  optional string author = 5;
  optional string description = 6;
  repeated string genre = 7;
  int32 status = 8;                 // SManga: 0 unknown, 1 ongoing, 2 completed, 3 licensed,
                                    //         4 publishing finished, 5 cancelled, 6 on hiatus
  optional string thumbnailUrl = 9; // absolute URL
  // 10-12, 15 reserved (1.x-only fields)
  int64 dateAdded = 13;             // epoch millis
  int32 viewer = 14;                // legacy, superseded by viewer_flags
  repeated BackupChapter chapters = 16;
  repeated int64 categories = 17;   // values = BackupCategory.order (NOT id)
  repeated BackupTracking tracking = 18;
  bool favorite = 100;              // default TRUE when absent
  int32 chapterFlags = 101;
  // 102 reserved (legacy broken history model)
  optional int32 viewer_flags = 103;
  repeated BackupHistory history = 104;
  int32 updateStrategy = 105;       // enum: 0 ALWAYS_UPDATE, 1 ONLY_FETCH_ONCE
  int64 lastModifiedAt = 106;
  optional int64 favoriteModifiedAt = 107;
  repeated string excludedScanlators = 108;
  int64 version = 109;
  string notes = 110;
  bool initialized = 111;
  // Forks may use higher numbers — ignore unknown fields, never fail on them.
}

message BackupChapter {
  string url = 1;                   // relative url, unique per manga
  string name = 2;
  optional string scanlator = 3;
  bool read = 4;
  bool bookmark = 5;
  int64 lastPageRead = 6;
  int64 dateFetch = 7;              // epoch millis
  int64 dateUpload = 8;             // epoch millis
  float chapterNumber = 9;          // -1 = unknown
  int64 sourceOrder = 10;
  int64 lastModifiedAt = 11;
  int64 version = 12;
}

message BackupHistory {
  string url = 1;                   // chapter url
  int64 lastRead = 2;               // epoch millis
  int64 readDuration = 3;           // millis
}

message BackupTracking {
  int32 syncId = 1;                 // tracker id (1 MyAnimeList, 2 AniList, 3 Kitsu,
                                    //  4 Shikimori, 5 Bangumi, 6 Komga, 7 MangaUpdates, ...)
  int64 libraryId = 2;
  int32 mediaIdInt = 3;             // deprecated; use if != 0, else mediaId
  string trackingUrl = 4;
  string title = 5;
  float lastChapterRead = 6;
  int32 totalChapters = 7;
  float score = 8;
  int32 status = 9;                 // tracker-specific status enum
  int64 startedReadingDate = 10;
  int64 finishedReadingDate = 11;
  bool private = 12;
  int64 mediaId = 100;
}

message BackupCategory {
  string name = 1;
  int64 order = 2;                  // referenced by BackupManga.categories
  int64 id = 3;
  int64 flags = 100;
}

message BackupSource {
  string name = 1;
  int64 sourceId = 2;
}

message BackupExtensionRepos {
  string baseUrl = 1;
  string name = 2;
  string shortName = 3;
  string website = 4;
  string signingKeyFingerprint = 5;
}

// kotlinx polymorphic encoding: wrapper with serialName + payload message.
// serialName examples (fork package prefix varies — match on the class-name SUFFIX):
//   "eu.kanade.tachiyomi.data.backup.models.IntPreferenceValue", ...BooleanPreferenceValue, etc.
// Payload message is { <type> value = 1; } for Int/Long/Float/String/Boolean,
// and { repeated string value = 1; } for StringSetPreferenceValue.
message BackupPreference {
  string key = 1;
  PreferenceValueWrapper value = 2;
}
message PreferenceValueWrapper {
  string serialName = 1;
  bytes payload = 2;                // decode per serialName suffix
}
message BackupSourcePreferences {
  string sourceKey = 1;
  repeated BackupPreference prefs = 2;
}
```

Container framing (before protobuf decode):

```ts
type BackupContainer =
  | { kind: 'gzip-proto' }   // first 2 bytes 0x1f 0x8b  → gunzip → protobuf
  | { kind: 'raw-proto' }    // anything else            → protobuf directly
  | { kind: 'legacy-json' }; // first bytes '{' …        → legacy Tachiyomi JSON importer
```

---

## 2. Domain layer (TypeScript)

Normalized model. IDs are MangaVault-generated (`vaultId`); source identity is preserved
separately so the same title imported from two forks/backups can be merged.

```ts
// ---------- identity ----------
/** Stable identity of a title within a source app ecosystem. */
export interface SourceKey {
  sourceId: string;      // int64 as decimal string (JS number is unsafe for 64-bit)
  mangaUrl: string;      // relative url, exactly as in backup
}

export type VaultId = string;      // uuid v7

// ---------- library ----------
export type PublicationStatus =
  | 'unknown' | 'ongoing' | 'completed' | 'licensed'
  | 'publishing_finished' | 'cancelled' | 'on_hiatus';

export interface VaultManga {
  id: VaultId;
  key: SourceKey;
  sourceName: string;            // from backupSources, e.g. "MangaDex"
  title: string;
  author?: string;
  artist?: string;
  description?: string;
  genres: string[];
  status: PublicationStatus;
  thumbnailUrl?: string;         // original remote URL (kept for re-fetch)
  coverPath?: string;            // relative path inside vault, once archived
  coverState: 'none' | 'pending' | 'archived' | 'failed';
  notes: string;
  favorite: boolean;
  dateAdded: number;             // epoch millis (from source app)
  categories: VaultId[];         // resolved category ids (not orders)
  chapters: VaultChapter[];
  tracking: VaultTracking[];
  // provenance
  importIds: VaultId[];          // every ImportRecord that touched this title
  updatedAt: number;
}

export interface VaultChapter {
  id: VaultId;
  url: string;
  name: string;
  chapterNumber: number;         // -1 = unknown
  scanlator?: string;
  read: boolean;
  bookmark: boolean;
  lastPageRead: number;
  dateUpload: number;
  dateFetch: number;
  sourceOrder: number;
  lastReadAt?: number;           // merged from BackupHistory
  readDuration: number;          // millis, summed from history
}

export interface VaultCategory {
  id: VaultId;
  name: string;
  order: number;
}

export interface VaultTracking {
  tracker: TrackerId;
  remoteId: string;              // int64-safe
  trackingUrl: string;
  title: string;
  lastChapterRead: number;
  totalChapters: number;
  score: number;
  status: number;                // raw tracker status
  startedAt?: number;
  finishedAt?: number;
}

export type TrackerId =
  | 'myanimelist' | 'anilist' | 'kitsu' | 'shikimori'
  | 'bangumi' | 'komga' | 'mangaupdates' | `unknown:${number}`;

// ---------- imports / provenance ----------
export interface ImportRecord {
  id: VaultId;
  fileName: string;
  fileSize: number;
  sha256: string;                // dedup identical files
  sourceApp: string;             // parsed from filename prefix, e.g. "app.mihon"
  container: 'gzip-proto' | 'raw-proto' | 'legacy-json';
  importedAt: number;
  stats: ImportStats;
}

export interface ImportStats {
  titlesTotal: number;
  titlesNew: number;
  titlesMerged: number;          // matched an existing SourceKey
  chaptersTotal: number;
  categoriesTotal: number;
  warnings: string[];            // non-fatal decode issues
}

/** Per-title merge outcome, shown in the import review UI. */
export interface MergeResult {
  key: SourceKey;
  action: 'created' | 'merged' | 'skipped';
  fieldConflicts: Array<{ field: string; kept: unknown; incoming: unknown }>;
}

// ---------- sources registry ----------
export interface KnownSource {
  sourceId: string;
  name: string;                  // accumulated from backupSources across imports
  baseUrl?: string;              // optional, user- or registry-supplied; enables links
  coverFetchHint?: { referer?: string; userAgent?: string };
}

// ---------- dashboard ----------
export interface LibraryStats {
  totalTitles: number;
  totalChapters: number;
  readChapters: number;
  bySourceApp: Record<string, number>;
  byStatus: Record<PublicationStatus, number>;
  coversArchived: number;
  coversFailed: number;
  lastImportAt?: number;
  vaultSizeBytes: number;
}

export interface BackupHealth {
  sourceApp: string;             // e.g. "app.mihon"
  lastImportAt: number;
  staleness: 'fresh' | 'aging' | 'stale';  // <30d / <90d / older
}
```

### Merge rules (dedup across backups)

- Match on `SourceKey` (`sourceId` + `mangaUrl`).
- Scalars: keep the value from the backup with the newer `lastModifiedAt`; never overwrite a
  non-empty local value with an empty incoming one.
- `chapters`: union by chapter `url`; `read`/`bookmark` are OR-merged; `lastPageRead`,
  `lastReadAt` take max.
- `favorite`: OR. `notes`: keep both if different (concatenate with divider), flag conflict.
- Nothing is ever deleted by an import (archive semantics).

---

## 3. Persistence layer

### 3.1 Vault folder layout

```
<vault-root>/
  vault.db              # SQLite
  covers/<vaultId>.<ext>
  imports/<sha256>.tachibk   # original files kept verbatim (fail-safe of the fail-safe)
  exports/
```

### 3.2 SQLite schema

```sql
CREATE TABLE manga (
  id            TEXT PRIMARY KEY,
  source_id     TEXT NOT NULL,
  manga_url     TEXT NOT NULL,
  source_name   TEXT NOT NULL DEFAULT '',
  title         TEXT NOT NULL,
  author        TEXT, artist TEXT, description TEXT,
  genres        TEXT NOT NULL DEFAULT '[]',   -- JSON array
  status        TEXT NOT NULL DEFAULT 'unknown',
  thumbnail_url TEXT,
  cover_path    TEXT,
  cover_state   TEXT NOT NULL DEFAULT 'none',
  notes         TEXT NOT NULL DEFAULT '',
  favorite      INTEGER NOT NULL DEFAULT 1,
  date_added    INTEGER NOT NULL DEFAULT 0,
  updated_at    INTEGER NOT NULL,
  UNIQUE (source_id, manga_url)
);

CREATE TABLE chapter (
  id             TEXT PRIMARY KEY,
  manga_id       TEXT NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
  url            TEXT NOT NULL,
  name           TEXT NOT NULL,
  chapter_number REAL NOT NULL DEFAULT -1,
  scanlator      TEXT,
  read           INTEGER NOT NULL DEFAULT 0,
  bookmark       INTEGER NOT NULL DEFAULT 0,
  last_page_read INTEGER NOT NULL DEFAULT 0,
  date_upload    INTEGER NOT NULL DEFAULT 0,
  date_fetch     INTEGER NOT NULL DEFAULT 0,
  source_order   INTEGER NOT NULL DEFAULT 0,
  last_read_at   INTEGER,
  read_duration  INTEGER NOT NULL DEFAULT 0,
  UNIQUE (manga_id, url)
);

CREATE TABLE category (
  id    TEXT PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE,
  sort  INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE manga_category (
  manga_id    TEXT NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
  category_id TEXT NOT NULL REFERENCES category(id) ON DELETE CASCADE,
  PRIMARY KEY (manga_id, category_id)
);

CREATE TABLE tracking (
  id        TEXT PRIMARY KEY,
  manga_id  TEXT NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
  tracker   TEXT NOT NULL,
  remote_id TEXT NOT NULL,
  tracking_url TEXT NOT NULL DEFAULT '',
  title     TEXT NOT NULL DEFAULT '',
  last_chapter_read REAL NOT NULL DEFAULT 0,
  total_chapters    INTEGER NOT NULL DEFAULT 0,
  score     REAL NOT NULL DEFAULT 0,
  status    INTEGER NOT NULL DEFAULT 0,
  started_at INTEGER, finished_at INTEGER,
  UNIQUE (manga_id, tracker)
);

CREATE TABLE import_record (
  id         TEXT PRIMARY KEY,
  file_name  TEXT NOT NULL,
  file_size  INTEGER NOT NULL,
  sha256     TEXT NOT NULL UNIQUE,
  source_app TEXT NOT NULL DEFAULT '',
  container  TEXT NOT NULL,
  imported_at INTEGER NOT NULL,
  stats      TEXT NOT NULL DEFAULT '{}'      -- JSON ImportStats
);
CREATE TABLE manga_import (
  manga_id  TEXT NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
  import_id TEXT NOT NULL REFERENCES import_record(id) ON DELETE CASCADE,
  PRIMARY KEY (manga_id, import_id)
);

CREATE TABLE known_source (
  source_id TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  base_url  TEXT,
  fetch_hint TEXT                              -- JSON coverFetchHint
);

CREATE INDEX idx_manga_title   ON manga(title);
CREATE INDEX idx_manga_status  ON manga(status);
CREATE INDEX idx_chapter_manga ON chapter(manga_id);
```

Full-text search over `title || author || genres` via FTS5 shadow table `manga_fts`
(kept in sync by triggers) — needed for instant search at 1,000+ titles.
