import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup_apps/backup_app_models.dart';
import '../library/library_models.dart';
import '../sources/source_models.dart';
import '../stats/stats_models.dart';
import '../local/app_database.dart';
import 'sync_models.dart';
import 'sync_repository.dart';

/// How many titles to pull per request. 500 keeps a page around 650 KB against
/// the real library — small enough to commit quickly, large enough that a full
/// resync of ~2,000 titles is a handful of round trips.
const int kSyncPageSize = 500;

/// Progress of an in-flight sync, for the UI banner.
class SyncProgress {
  const SyncProgress({required this.received, required this.total});

  final int received;

  /// Server's title count; 0 until `/sync/meta` answers.
  final int total;

  double get fraction =>
      total <= 0 ? 0 : (received / total).clamp(0.0, 1.0).toDouble();
}

/// Pulls server changes into the on-device mirror.
///
/// This is the "Library Sync service" of the design: it is the only thing that
/// talks to the server about library data, and every screen reads the SQLite
/// mirror it maintains. It never pushes — the server stays authoritative.
class LibrarySyncService {
  LibrarySyncService(this._repo, this._db);

  final SyncRepository _repo;
  final AppDatabase _db;

  /// A second caller joins the running sync instead of starting a duplicate
  /// pull (mirrors the server's single-active-job guard for cover archiving).
  Future<int>? _inFlight;

  bool get isSyncing => _inFlight != null;

  /// Pull everything new. Returns the number of titles written.
  ///
  /// [force] discards the local cursor and re-pulls the whole library — used by
  /// an explicit "resync" action, not by ordinary refreshes.
  Future<int> sync({
    bool force = false,
    void Function(SyncProgress)? onProgress,
  }) {
    final running = _inFlight;
    if (running != null) return running;

    final future = _run(force: force, onProgress: onProgress);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Run a sync only if the mirror has never been filled. Called when the
  /// library first opens so a fresh install has something to show.
  Future<int> ensureBootstrapped() async {
    final state = await _db.syncStateRow();
    if (state?.cursor != null) return 0;
    return sync();
  }

  Future<int> _run({
    required bool force,
    void Function(SyncProgress)? onProgress,
  }) async {
    final meta = await _repo.meta();
    final local = await _db.syncStateRow();

    // A different epoch means the app is pointed at another server: local
    // versions are meaningless, so start over.
    final epochChanged =
        local?.serverEpoch != null && local!.serverEpoch != meta.serverEpoch;

    // A local cursor ahead of the server's high-water mark is impossible while
    // versions only increase — it means the database was restored from a dump
    // (which rewinds row_version but *preserves* server_epoch, so the epoch
    // check above cannot catch it). Without this the client would ask for
    // changes above a version the server will never reach again and silently
    // sit on a stale mirror forever.
    final cursorAhead = local?.cursor != null &&
        BigInt.parse(local!.cursor!) > BigInt.parse(meta.cursor);

    final fullResync =
        force || epochChanged || cursorAhead || local?.cursor == null;

    var cursor = fullResync ? '0' : local!.cursor!;
    var wipePending = fullResync;
    var received = 0;

    onProgress?.call(SyncProgress(received: 0, total: meta.totalTitles));

    // Bounded so a server that always reports hasMore can't spin forever.
    for (var page = 0; page < 1000; page++) {
      final result = await _repo.changesSince(cursor, limit: kSyncPageSize);

      await _db.transaction(() async {
        // Wipe inside the first page's transaction, never before it: if the
        // pull fails the user keeps the library they already had on screen.
        if (wipePending) {
          await _clearLibrary();
          wipePending = false;
        }
        await _applyPage(result);
        await _writeMeta(cursor: result.cursor, epoch: result.serverEpoch);
      });

      cursor = result.cursor;
      received += result.changed.length;
      onProgress?.call(
        SyncProgress(received: received, total: meta.totalTitles),
      );

      if (!result.hasMore) break;
    }

    // Categories, imports and the backup-app and source registries are small
    // and effectively append-only, so they are replaced wholesale rather than
    // versioned.
    await _db.transaction(() async {
      await _replaceCategories(meta.categories);
      await _replaceImports(meta.imports);
      await _replaceBackupApps(meta.backupApps);
      await _replaceSources(meta.sources);
      await _writeMeta(
        cursor: cursor,
        epoch: meta.serverEpoch,
        vaultSizeBytes: meta.vaultSizeBytes,
        storage: meta.vaultStorage,
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _bumpRevision();
    });

    return received;
  }

  // ---- writers ----------------------------------------------------------

  Future<void> _applyPage(SyncPage page) async {
    for (final m in page.changed) {
      await _db.into(_db.localManga).insertOnConflictUpdate(_rowFor(m));

      // Junction rows are replaced per title: the server sends the complete
      // membership each time, so a removed category must disappear locally.
      await (_db.delete(_db.localMangaCategory)
            ..where((t) => t.mangaId.equals(m.id)))
          .go();
      for (final categoryId in m.categoryIds) {
        await _db.into(_db.localMangaCategory).insertOnConflictUpdate(
              LocalMangaCategoryCompanion.insert(
                mangaId: m.id,
                categoryId: categoryId,
              ),
            );
      }

      await (_db.delete(_db.localMangaImport)
            ..where((t) => t.mangaId.equals(m.id)))
          .go();
      for (final importId in m.importIds) {
        await _db.into(_db.localMangaImport).insertOnConflictUpdate(
              LocalMangaImportCompanion.insert(
                mangaId: m.id,
                importId: importId,
              ),
            );
      }
    }

    for (final id in page.deleted) {
      await (_db.delete(_db.localManga)..where((t) => t.id.equals(id))).go();
      await (_db.delete(_db.localMangaCategory)
            ..where((t) => t.mangaId.equals(id)))
          .go();
      await (_db.delete(_db.localMangaImport)
            ..where((t) => t.mangaId.equals(id)))
          .go();
    }

    if (page.changed.isNotEmpty || page.deleted.isNotEmpty) {
      await _bumpRevision();
    }
  }

  LocalMangaCompanion _rowFor(SyncManga m) => LocalMangaCompanion.insert(
        id: m.id,
        rowVersion: m.rowVersion,
        sourceId: m.sourceId,
        sourceName: Value(m.sourceName),
        title: m.title,
        titleLower: m.title.toLowerCase(),
        authorLower: Value((m.author ?? '').toLowerCase()),
        author: Value(m.author),
        artist: Value(m.artist),
        description: Value(m.description),
        genresJson: Value(jsonEncode(m.genres)),
        status: Value(m.status),
        thumbnailUrl: Value(m.thumbnailUrl),
        coverPath: Value(m.coverPath),
        coverState: Value(m.coverState),
        notes: Value(m.notes),
        favorite: Value(m.favorite),
        dateAdded: Value(m.dateAdded),
        updatedAt: Value(m.updatedAt),
        chapterCount: Value(m.chapterCount),
        readCount: Value(m.readCount),
        unreadCount: Value(m.unreadCount),
        lastReadAt: Value(m.lastReadAt),
        lastReadChapterName: Value(m.lastReadChapter?.name),
        lastReadChapterNumber: Value(m.lastReadChapter?.number),
        nextChapterName: Value(m.nextChapter?.name),
        nextChapterNumber: Value(m.nextChapter?.number),
      );

  Future<void> _clearLibrary() async {
    await _db.delete(_db.localMangaCategory).go();
    await _db.delete(_db.localMangaImport).go();
    await _db.delete(_db.localManga).go();
    await _db.delete(_db.localCategory).go();
    await _db.delete(_db.localImportRecord).go();
    await _db.delete(_db.localBackupApp).go();
    await _db.delete(_db.localSource).go();
  }

  Future<void> _replaceCategories(List<Category> categories) async {
    await _db.delete(_db.localCategory).go();
    for (final c in categories) {
      await _db.into(_db.localCategory).insertOnConflictUpdate(
            LocalCategoryCompanion.insert(
              id: c.id,
              name: c.name,
              sort: Value(c.sort),
            ),
          );
    }
  }

  Future<void> _replaceImports(List<SyncImportRecord> imports) async {
    await _db.delete(_db.localImportRecord).go();
    for (final i in imports) {
      await _db.into(_db.localImportRecord).insertOnConflictUpdate(
            LocalImportRecordCompanion.insert(
              id: i.id,
              fileName: i.fileName,
              fileSize: Value(i.fileSize),
              sha256: Value(i.sha256),
              sourceApp: Value(i.sourceApp),
              container: Value(i.container),
              importedAt: Value(i.importedAt),
              statsJson: Value(jsonEncode(i.stats)),
            ),
          );
    }
  }

  Future<void> _replaceBackupApps(List<BackupApp> apps) async {
    await _db.delete(_db.localBackupApp).go();
    for (final a in apps) {
      await _db.into(_db.localBackupApp).insertOnConflictUpdate(
            LocalBackupAppCompanion.insert(
              id: a.id,
              displayName: a.displayName,
              accent: Value(a.accent),
              curated: Value(a.curated),
            ),
          );
    }
  }

  /// Replace the source registry.
  ///
  /// Wholesale, like the app registry above: a few dozen rows that the server
  /// recomputes on every request anyway, and a delete-then-insert keeps a
  /// source the server has dropped from lingering with a stale verdict.
  Future<void> _replaceSources(List<VaultSource> sources) async {
    await _db.delete(_db.localSource).go();
    for (final s in sources) {
      await _db.into(_db.localSource).insertOnConflictUpdate(
            LocalSourceCompanion.insert(
              id: s.sourceId,
              name: s.name,
              lang: Value(s.lang),
              homeUrl: Value(s.homeUrl),
              iconUrl: Value(s.iconUrl),
              packageName: Value(s.packageName),
              repoName: Value(s.repoName),
              contentWarning: Value(s.contentWarning),
              registryState: Value(s.registryState.name),
              health: Value(s.health.name),
              healthNote: Value(s.healthNote),
              healthCheckedAt: Value(s.healthCheckedAt),
              titleCount: Value(s.titleCount),
              coverFailedCount: Value(s.coverFailedCount),
            ),
          );
    }
  }

  Future<void> _writeMeta({
    String? cursor,
    String? epoch,
    int? vaultSizeBytes,
    VaultStorage? storage,
    int? syncedAt,
  }) async {
    await (_db.update(_db.syncMeta)..where((t) => t.id.equals(0))).write(
      SyncMetaCompanion(
        cursor: cursor == null ? const Value.absent() : Value(cursor),
        serverEpoch: epoch == null ? const Value.absent() : Value(epoch),
        vaultSizeBytes: vaultSizeBytes == null
            ? const Value.absent()
            : Value(vaultSizeBytes),
        vaultDatabaseBytes: storage == null
            ? const Value.absent()
            : Value(storage.databaseBytes),
        vaultCoversBytes:
            storage == null ? const Value.absent() : Value(storage.coversBytes),
        vaultBackupsBytes: storage == null
            ? const Value.absent()
            : Value(storage.backupsBytes),
        lastSyncedAt:
            syncedAt == null ? const Value.absent() : Value(syncedAt),
      ),
    );
  }

  /// Bump the single counter every local-read provider watches.
  Future<void> _bumpRevision() async {
    await _db.customUpdate(
      'UPDATE sync_meta SET local_revision = local_revision + 1 WHERE id = 0',
      updates: {_db.syncMeta},
      updateKind: UpdateKind.update,
    );
  }
}

final librarySyncServiceProvider = Provider<LibrarySyncService>(
  (ref) => LibrarySyncService(
    ref.watch(syncRepositoryProvider),
    ref.watch(appDatabaseProvider),
  ),
);
