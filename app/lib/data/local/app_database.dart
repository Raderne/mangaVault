import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// On-device projection of the server library.
///
/// This is a **cache, not an archive** — the vault lives in Postgres and
/// `storage/` on the server. Nothing here is authoritative and nothing is lost
/// by deleting the file, which is why [MigrationStrategy] below simply wipes
/// and re-pulls instead of carrying hand-written migrations forward.
@DriftDatabase(
  tables: [
    LocalManga,
    LocalCategory,
    LocalMangaCategory,
    LocalImportRecord,
    LocalMangaImport,
    LocalBackupApp,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory instance for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// 2 (2026-07-31): `sync_meta` gained the vault storage breakdown.
  /// 3 (2026-08-02): added `local_backup_app` — the backup-app registry.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedMeta();
        },
        // Destructive by design: the mirror is disposable, so a schema bump
        // drops everything and clears the cursor, and the next sync refetches
        // the library in a few seconds. Cheaper and far less error-prone than
        // maintaining migrations for a cache.
        onUpgrade: (m, from, to) async {
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
          await _seedMeta();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (!details.wasCreated) await _seedMeta();
        },
      );

  /// Empty every table and reset the sync bookkeeping to first-run state.
  ///
  /// Used when the app is pointed at a **different server**. The mirror holds
  /// one server's library keyed by that server's ids, and the sync cursor is
  /// only meaningful against the server that issued it — carrying either across
  /// a switch would show the previous vault's titles under the new server's
  /// credentials, then fail to reconcile them. Cheap to do: the next sync
  /// refetches everything.
  Future<void> wipe() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
      await _seedMeta();
    });
  }

  /// The singleton sync bookkeeping row (cursor, epoch, last-synced, …).
  Future<SyncMetaData?> syncStateRow() =>
      (select(syncMeta)..where((t) => t.id.equals(0))).getSingleOrNull();

  /// Guarantee the singleton meta row exists so callers can always update it.
  Future<void> _seedMeta() async {
    await into(syncMeta).insertOnConflictUpdate(
      const SyncMetaCompanion(id: Value(0)),
    );
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mangavault_library.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// One database per app run; closed with the provider container.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
