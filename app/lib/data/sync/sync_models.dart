// Dart mirrors of the server's sync DTOs
// (server/src/modules/sync/sync.dto.ts). Manual `fromJson` in the same style as
// the library, import and stats models — no codegen outside the drift layer.

import '../backup_apps/backup_app_models.dart';
import '../library/library_models.dart';
import '../stats/stats_models.dart';

/// One mirrored title: the union of what the grid and details screens render.
/// Chapters are not included — only the aggregates and the two chapter refs.
class SyncManga {
  const SyncManga({
    required this.id,
    required this.rowVersion,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.author,
    required this.artist,
    required this.description,
    required this.genres,
    required this.status,
    required this.thumbnailUrl,
    required this.coverPath,
    required this.coverState,
    required this.notes,
    required this.favorite,
    required this.dateAdded,
    required this.updatedAt,
    required this.chapterCount,
    required this.readCount,
    required this.unreadCount,
    required this.lastReadAt,
    required this.lastReadChapter,
    required this.nextChapter,
    required this.categoryIds,
    required this.importIds,
  });

  final String id;

  /// Server version as a decimal string — int64, never parsed into a Dart int.
  final String rowVersion;
  final String sourceId;
  final String sourceName;
  final String title;
  final String? author;
  final String? artist;
  final String? description;
  final List<String> genres;
  final String status;
  final String? thumbnailUrl;
  final String? coverPath;
  final String coverState;
  final String notes;
  final bool favorite;
  final int dateAdded;
  final int updatedAt;
  final int chapterCount;
  final int readCount;
  final int unreadCount;
  final int? lastReadAt;
  final ChapterRef? lastReadChapter;
  final ChapterRef? nextChapter;
  final List<String> categoryIds;
  final List<String> importIds;

  factory SyncManga.fromJson(Map<String, dynamic> j) => SyncManga(
        id: j['id'] as String,
        rowVersion: (j['rowVersion'] as String?) ?? '0',
        sourceId: (j['sourceId'] as String?) ?? '',
        sourceName: (j['sourceName'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        author: j['author'] as String?,
        artist: j['artist'] as String?,
        description: j['description'] as String?,
        genres: _stringList(j['genres']),
        status: (j['status'] as String?) ?? 'unknown',
        thumbnailUrl: j['thumbnailUrl'] as String?,
        coverPath: j['coverPath'] as String?,
        coverState: (j['coverState'] as String?) ?? 'none',
        notes: (j['notes'] as String?) ?? '',
        favorite: (j['favorite'] as bool?) ?? true,
        dateAdded: (j['dateAdded'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        readCount: (j['readCount'] as num?)?.toInt() ?? 0,
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        lastReadAt: (j['lastReadAt'] as num?)?.toInt(),
        lastReadChapter: j['lastReadChapter'] == null
            ? null
            : ChapterRef.fromJson(j['lastReadChapter'] as Map<String, dynamic>),
        nextChapter: j['nextChapter'] == null
            ? null
            : ChapterRef.fromJson(j['nextChapter'] as Map<String, dynamic>),
        categoryIds: _stringList(j['categoryIds']),
        importIds: _stringList(j['importIds']),
      );
}

/// One page of changes above the client's cursor.
class SyncPage {
  const SyncPage({
    required this.changed,
    required this.deleted,
    required this.cursor,
    required this.hasMore,
    required this.serverEpoch,
  });

  final List<SyncManga> changed;
  final List<String> deleted;
  final String cursor;
  final bool hasMore;
  final String serverEpoch;

  factory SyncPage.fromJson(Map<String, dynamic> j) => SyncPage(
        changed: ((j['changed'] as List?) ?? const [])
            .map((e) => SyncManga.fromJson(e as Map<String, dynamic>))
            .toList(),
        deleted: _stringList(j['deleted']),
        cursor: (j['cursor'] as String?) ?? '0',
        hasMore: (j['hasMore'] as bool?) ?? false,
        serverEpoch: (j['serverEpoch'] as String?) ?? '',
      );
}

/// A backup that contributed to the library — mirrored for the Backups history
/// cell and the dashboard's per-source-app health.
class SyncImportRecord {
  const SyncImportRecord({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.sourceApp,
    required this.container,
    required this.importedAt,
    required this.stats,
  });

  final String id;
  final String fileName;
  final int fileSize;
  final String sha256;
  final String sourceApp;
  final String container;
  final int importedAt;

  /// Raw `import_record.stats` object, stored verbatim so the Backups history
  /// cell can render new/merged counts offline.
  final Map<String, dynamic> stats;

  factory SyncImportRecord.fromJson(Map<String, dynamic> j) =>
      SyncImportRecord(
        id: j['id'] as String,
        fileName: (j['fileName'] as String?) ?? '',
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        sha256: (j['sha256'] as String?) ?? '',
        sourceApp: (j['sourceApp'] as String?) ?? '',
        container: (j['container'] as String?) ?? '',
        importedAt: (j['importedAt'] as num?)?.toInt() ?? 0,
        stats: (j['stats'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Server identity, the current high-water mark, and the small payloads that
/// are always sent whole.
class SyncMetaSnapshot {
  const SyncMetaSnapshot({
    required this.serverEpoch,
    required this.cursor,
    required this.totalTitles,
    required this.categories,
    required this.imports,
    required this.vaultSizeBytes,
    this.backupApps = const [],
    this.vaultStorage = const VaultStorage(),
  });

  final String serverEpoch;
  final String cursor;
  final int totalTitles;
  final List<Category> categories;
  final List<SyncImportRecord> imports;

  /// The backup-app registry, replaced wholesale like categories and imports.
  /// It only names ids — a title's apps are derived from its import links.
  final List<BackupApp> backupApps;
  final int vaultSizeBytes;

  /// Database / covers / backups split — the mirror stores the parts so the
  /// dashboard can show where the space went while offline.
  final VaultStorage vaultStorage;

  factory SyncMetaSnapshot.fromJson(Map<String, dynamic> j) => SyncMetaSnapshot(
        serverEpoch: (j['serverEpoch'] as String?) ?? '',
        cursor: (j['cursor'] as String?) ?? '0',
        totalTitles: (j['totalTitles'] as num?)?.toInt() ?? 0,
        categories: ((j['categories'] as List?) ?? const [])
            .map((e) => Category.fromJson(e as Map<String, dynamic>))
            .toList(),
        imports: ((j['imports'] as List?) ?? const [])
            .map((e) => SyncImportRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        backupApps: ((j['backupApps'] as List?) ?? const [])
            .map((e) => BackupApp.fromJson(e as Map<String, dynamic>))
            .toList(),
        vaultSizeBytes: (j['vaultSizeBytes'] as num?)?.toInt() ?? 0,
        vaultStorage: VaultStorage.fromJson(
          (j['vaultStorage'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

List<String> _stringList(Object? raw) =>
    ((raw as List?) ?? const []).whereType<String>().toList();
