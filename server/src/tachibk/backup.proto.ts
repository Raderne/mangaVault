/**
 * Wire schema for `.tachibk` backups, transcribed from Mihon's protobuf models
 * (`MihonApp/mihon/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/`)
 * and `docs/phase-1-data-structures.md` §1.
 *
 * IMPORTANT: field numbers are the wire contract and MUST NEVER change — old
 * backups and every fork depend on them. Unknown fields (forks add higher
 * numbers) are ignored automatically by the decoder; never fail on them.
 *
 * Embedded as a string (rather than a `.proto` asset file) so it is bundled
 * into `dist/` with zero build-step asset copying and the pure lib stays
 * self-contained.
 *
 * proto3 note: `favorite` is `optional` on purpose. kotlinx defaults it to TRUE
 * when absent, but a present `false` must stay false — `optional` gives us
 * presence tracking so the normalizer can apply `favorite ?? true` correctly.
 * All other scalar defaults happen to match proto3's zero-value default.
 */
export const BACKUP_PROTO = `
syntax = "proto3";
package mangavault.tachibk;

message Backup {
  repeated BackupManga backupManga = 1;
  repeated BackupCategory backupCategories = 2;
  repeated BackupSource backupSources = 101;
  repeated BackupPreference backupPreferences = 104;
  repeated BackupSourcePreferences backupSourcePreferences = 105;
  repeated BackupExtensionRepos backupExtensionRepo = 106;
}

message BackupManga {
  int64 source = 1;
  string url = 2;
  string title = 3;
  optional string artist = 4;
  optional string author = 5;
  optional string description = 6;
  repeated string genre = 7;
  int32 status = 8;
  optional string thumbnailUrl = 9;
  int64 dateAdded = 13;
  int32 viewer = 14;
  repeated BackupChapter chapters = 16;
  repeated int64 categories = 17;
  repeated BackupTracking tracking = 18;
  optional bool favorite = 100;
  int32 chapterFlags = 101;
  optional int32 viewer_flags = 103;
  repeated BackupHistory history = 104;
  int32 updateStrategy = 105;
  int64 lastModifiedAt = 106;
  optional int64 favoriteModifiedAt = 107;
  repeated string excludedScanlators = 108;
  int64 version = 109;
  string notes = 110;
  bool initialized = 111;
}

message BackupChapter {
  string url = 1;
  string name = 2;
  optional string scanlator = 3;
  bool read = 4;
  bool bookmark = 5;
  int64 lastPageRead = 6;
  int64 dateFetch = 7;
  int64 dateUpload = 8;
  float chapterNumber = 9;
  int64 sourceOrder = 10;
  int64 lastModifiedAt = 11;
  int64 version = 12;
}

message BackupHistory {
  string url = 1;
  int64 lastRead = 2;
  int64 readDuration = 3;
}

message BackupTracking {
  int32 syncId = 1;
  int64 libraryId = 2;
  int32 mediaIdInt = 3;
  string trackingUrl = 4;
  string title = 5;
  float lastChapterRead = 6;
  int32 totalChapters = 7;
  float score = 8;
  int32 status = 9;
  int64 startedReadingDate = 10;
  int64 finishedReadingDate = 11;
  bool private = 12;
  int64 mediaId = 100;
}

message BackupCategory {
  string name = 1;
  int64 order = 2;
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

message BackupPreference {
  string key = 1;
  PreferenceValueWrapper value = 2;
}

message PreferenceValueWrapper {
  string serialName = 1;
  bytes payload = 2;
}

message BackupSourcePreferences {
  string sourceKey = 1;
  repeated BackupPreference prefs = 2;
}
`;
