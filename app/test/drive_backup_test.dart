import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/config/server_config_controller.dart';
import 'package:mangavault/core/google/google_account.dart';
import 'package:mangavault/data/drive/drive_store.dart';
import 'package:mangavault/data/export/export_models.dart';
import 'package:mangavault/data/export/export_repository.dart';
import 'package:mangavault/data/sync/sync_models.dart';
import 'package:mangavault/data/sync/sync_repository.dart';
import 'package:mangavault/features/backups/drive/drive_backup_controller.dart';
import 'package:mangavault/features/backups/drive/drive_backup_plan.dart';
import 'package:mangavault/features/backups/drive/drive_backup_settings.dart';
import 'package:mangavault/features/backups/import_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDriveStore implements DriveStore {
  FakeDriveStore({
    List<String> existing = const [],
    this.failUpload = false,
    this.failOnUpload = 0,
  }) {
    for (var i = 0; i < existing.length; i++) {
      files.add(DriveManagedFile(id: existing[i], createdAtMs: 1000 - i));
    }
  }

  final bool failUpload;

  /// 1-based upload attempt that throws. Zero never throws on its own.
  final int failOnUpload;
  final files = <DriveManagedFile>[];
  final uploads = <(String, bool)>[];
  final runIds = <String?>[];
  final deleted = <String>[];
  var closed = false;

  @override
  Future<String> upload(
    String name,
    Uint8List bytes, {
    required bool automatic,
    String? runId,
    String? partKey,
    int? partCount,
  }) async {
    final attempt = uploads.length + 1;
    if (failUpload || attempt == failOnUpload) {
      throw Exception('network down');
    }
    uploads.add((name, automatic));
    runIds.add(runId);
    final id = 'id$attempt';
    if (automatic) {
      files.insert(
        0,
        DriveManagedFile(
          id: id,
          runId: runId,
          partKey: partKey,
          partCount: partCount,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    return id;
  }

  @override
  Future<List<DriveManagedFile>> automaticFiles() async => [...files];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    files.removeWhere((file) => file.id == id);
  }

  @override
  void close() => closed = true;
}

class FakeExportRepository extends ExportRepository {
  FakeExportRepository({this.titles = 3, this.skipNonFavorites = false})
    : super(Dio());

  final int titles;
  final bool skipNonFavorites;
  final scopes = <ExportScope>[];

  @override
  Future<ExportFacets> facets() async => const ExportFacets(
    totalTitles: 3,
    favoriteTitles: 1,
    totalChapters: 1,
    apps: [
      ExportFacetOption(id: 'app.mihon', label: 'Mihon', count: 2),
      ExportFacetOption(id: 'app.komikku', label: 'Komikku', count: 1),
    ],
    sources: [],
    categories: [],
    statuses: [],
  );

  @override
  Future<ExportPreview> preview(
    ExportScope scope, {
    CancelToken? cancelToken,
  }) async {
    final empty =
        titles == 0 || (skipNonFavorites && scope.filters.favorite == false);
    return ExportPreview(
      titles: empty ? 0 : titles,
      chapters: 1,
      readChapters: 0,
      categories: 0,
      sources: 1,
      trackedTitles: 0,
      fileName: 'mangavault_2026-09-26_16-00.tachibk',
      estimatedBytes: 10,
      sample: const [],
    );
  }

  @override
  Future<ExportedBackup> build(
    ExportScope scope, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    scopes.add(scope);
    return ExportedBackup(
      fileName: 'mangavault_${scopes.length}.tachibk',
      bytes: Uint8List.fromList([1, 2, 3]),
      titles: 3,
    );
  }
}

class FakeSyncRepository extends SyncRepository {
  FakeSyncRepository(this.cursor) : super(Dio());
  String cursor;

  @override
  Future<SyncMetaSnapshot> meta() async => SyncMetaSnapshot(
    serverEpoch: 'epoch',
    cursor: cursor,
    totalTitles: 0,
    categories: const [],
    imports: const [],
    vaultSizeBytes: 0,
  );
}

class _SeededSettings extends DriveBackupSettingsController {
  _SeededSettings(this.seed);
  final DriveBackupSettings seed;

  @override
  DriveBackupSettings build() => seed;
}

class _Import extends ImportController {
  @override
  ImportState build() => const ImportIdle();

  void set(ImportState next) => state = next;
}

final _later = DateTime.now().add(const Duration(hours: 25));

/// Seeded with a check that happened *now*, so the controller's own launch
/// check is never due and can't race the test's explicit one.
({ProviderContainer container, List<bool> opened, FakeExportRepository exports})
_setup({
  required FakeDriveStore? store,
  DriveBackupSettings settings = const DriveBackupSettings(),
  String cursor = '42',
  FakeExportRepository? exports,
}) {
  final opened = <bool>[];
  final exportRepo = exports ?? FakeExportRepository();
  final container = ProviderContainer(
    overrides: [
      isConfiguredProvider.overrideWithValue(true),
      exportRepositoryProvider.overrideWithValue(exportRepo),
      syncRepositoryProvider.overrideWithValue(FakeSyncRepository(cursor)),
      importControllerProvider.overrideWith(_Import.new),
      driveOpenerProvider.overrideWithValue(({
        required bool interactive,
      }) async {
        opened.add(interactive);
        return store;
      }),
      driveBackupSettingsProvider.overrideWith(
        () => _SeededSettings(
          settings.copyWith(
            lastCheckAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, opened: opened, exports: exportRepo);
}

const _automatic = DriveBackupSettings(mode: DriveUploadMode.automatic);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DriveBackupSettings', () {
    test('manual mode is never due', () {
      const s = DriveBackupSettings(intervalHours: 6);
      expect(s.isDue(_later), isFalse);
    });

    test('automatic mode is due once the interval has passed', () {
      final now = DateTime(2026, 9, 13, 12);
      final s = _automatic.copyWith(
        intervalHours: 12,
        lastCheckAtMs: now
            .subtract(const Duration(hours: 11))
            .millisecondsSinceEpoch,
      );
      expect(s.isDue(now), isFalse);
      expect(s.isDue(now.add(const Duration(hours: 1))), isTrue);
    });

    test('a different epoch counts as a change even at the same cursor', () {
      const s = DriveBackupSettings(lastEpoch: 'a', lastCursor: '7');
      expect(s.changedSince('a', '7'), isFalse);
      expect(s.changedSince('a', '8'), isTrue);
      expect(s.changedSince('b', '7'), isTrue);
    });

    test('corrupt JSON falls back to defaults', () {
      final s = DriveBackupSettings.fromJson({'mode': 42, 'intervalHours': 5});
      expect(s.mode, DriveUploadMode.manual);
      expect(s.intervalHours, 24);
      expect(s.plan.layout, DriveOutputLayout.single);
    });

    test('an old single filename survives loading', () {
      final s = DriveBackupSettings.fromJson({
        'lastFileName': 'mangavault_old.tachibk',
      });
      expect(s.lastFileNames, ['mangavault_old.tachibk']);
    });

    test('changing the plan clears the cursor', () {
      final t = _setup(
        store: FakeDriveStore(),
        settings: _automatic.copyWith(lastEpoch: 'epoch', lastCursor: '42'),
      );

      t.container
          .read(driveBackupSettingsProvider.notifier)
          .setPlan(
            const DriveBackupPlan(layout: DriveOutputLayout.splitByFavorite),
          );

      final settings = t.container.read(driveBackupSettingsProvider);
      expect(settings.lastCursor, isEmpty);
      expect(settings.lastEpoch, isEmpty);
      expect(settings.plan.layout, DriveOutputLayout.splitByFavorite);
    });
  });

  group('Drive backup plan', () {
    test('favorite split makes two complementary files', () {
      final parts = expandDrivePlan(
        const DriveBackupPlan(layout: DriveOutputLayout.splitByFavorite),
      );

      expect(parts.map((part) => part.suffix), ['favorites', 'not-favorites']);
      expect(parts[0].scope.filters.favorite, isTrue);
      expect(parts[1].scope.filters.favorite, isFalse);
    });

    test('app split uses every app when none are selected', () {
      final parts = expandDrivePlan(
        const DriveBackupPlan(layout: DriveOutputLayout.splitByApp),
        appIds: const ['app.mihon', 'app.komikku'],
      );

      expect(parts.map((part) => part.scope.filters.sourceApps), [
        {'app.komikku'},
        {'app.mihon'},
      ]);
      expect(
        driveObjectName('mangavault_2026-09-26_16-00.tachibk', parts[1].suffix),
        'mangavault_2026-09-26_16-00_from-app.mihon.tachibk',
      );
    });

    test('retention keeps five complete runs and an in-progress run', () {
      final stale = staleDriveFileIds([
        for (var i = 0; i < 6; i++)
          DriveManagedFile(
            id: 'old$i',
            runId: 'run$i',
            partKey: 'all',
            partCount: 1,
            createdAtMs: 100 + i,
          ),
        const DriveManagedFile(
          id: 'half',
          runId: 'current',
          partKey: 'favorites',
          partCount: 2,
          createdAtMs: 1000,
        ),
        const DriveManagedFile(id: 'legacy', createdAtMs: 1),
      ], protectRunId: 'current');

      expect(stale, containsAll(['old0', 'legacy']));
      expect(stale, isNot(contains('half')));
      expect(stale, isNot(contains('old5')));
    });
  });

  group('DriveBackupController', () {
    test('uploads the whole vault when due and records the cursor', () async {
      final store = FakeDriveStore();
      final t = _setup(store: store, settings: _automatic);
      final controller = t.container.read(driveBackupProvider.notifier);

      await controller.check(now: _later);

      expect(store.uploads, [('mangavault_1.tachibk', true)]);
      expect(t.opened, [false], reason: 'unattended runs never show UI');
      expect(store.closed, isTrue);
      final settings = t.container.read(driveBackupSettingsProvider);
      expect(settings.lastCursor, '42');
      expect(settings.lastUploadLabel, 'mangavault_1.tachibk');
    });

    test('prunes automatic uploads beyond the newest five', () async {
      final store = FakeDriveStore(
        existing: [for (var i = 6; i >= 1; i--) 'old$i'],
      );
      final t = _setup(store: store, settings: _automatic);

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      // New one + old6..old3 survive; old2 and old1 go.
      expect(store.deleted, ['old2', 'old1']);
    });

    test('skips building when nothing changed since the last upload', () async {
      final store = FakeDriveStore();
      final t = _setup(
        store: store,
        settings: _automatic.copyWith(lastEpoch: 'epoch', lastCursor: '42'),
      );

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      expect(t.opened, isEmpty);
      expect(store.uploads, isEmpty);
      expect(
        t.container.read(driveBackupProvider).message,
        contains('Nothing changed'),
      );
    });

    test('manual mode does nothing on its own, but Upload now works', () async {
      final store = FakeDriveStore();
      final t = _setup(store: store);
      final controller = t.container.read(driveBackupProvider.notifier);

      await controller.check(now: _later);
      expect(store.uploads, isEmpty);

      await controller.check(force: true);
      expect(store.uploads, hasLength(1));
      expect(t.opened, [true], reason: 'a tap may show the sign-in sheet');
    });

    test(
      'lost authorization asks to reconnect and is retried next time',
      () async {
        final t = _setup(store: null, settings: _automatic);

        await t.container.read(driveBackupProvider.notifier).check(now: _later);

        expect(
          t.container.read(driveBackupProvider).message,
          contains('reconnect'),
        );
        expect(
          t.container.read(driveBackupSettingsProvider).lastCursor,
          isEmpty,
        );
      },
    );

    test('a failed upload is reported and not recorded', () async {
      final store = FakeDriveStore(failUpload: true);
      final t = _setup(store: store, settings: _automatic);

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      expect(
        t.container.read(driveBackupProvider).message,
        contains('network down'),
      );
      expect(t.container.read(driveBackupSettingsProvider).lastUploadAtMs, 0);
      expect(store.closed, isTrue);
    });

    test('an import finishing triggers an upload when enabled', () async {
      final store = FakeDriveStore();
      final t = _setup(store: store, settings: _automatic);
      t.container.read(driveBackupProvider);

      (t.container.read(importControllerProvider.notifier) as _Import).set(
        const ImportDone([]),
      );
      await pumpEventQueue();

      expect(store.uploads, hasLength(1));
    });

    test('switching to automatic makes the first check due at once', () {
      final t = _setup(store: FakeDriveStore());
      final settings = t.container.read(driveBackupSettingsProvider.notifier);

      settings.setMode(DriveUploadMode.automatic);

      expect(
        t.container.read(driveBackupSettingsProvider).isDue(DateTime.now()),
        isTrue,
      );
    });

    test('a favorite split uploads both files as one run', () async {
      final store = FakeDriveStore();
      final t = _setup(
        store: store,
        settings: _automatic.copyWith(
          plan: const DriveBackupPlan(
            layout: DriveOutputLayout.splitByFavorite,
          ),
        ),
      );

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      expect(store.uploads.map((upload) => upload.$1), [
        'mangavault_1_favorites.tachibk',
        'mangavault_2_not-favorites.tachibk',
      ]);
      expect(store.runIds, [
        '${_later.microsecondsSinceEpoch}',
        '${_later.microsecondsSinceEpoch}',
      ]);
      expect(
        t.container.read(driveBackupSettingsProvider).lastFileNames,
        hasLength(2),
      );
    });

    test('an empty split part is skipped', () async {
      final store = FakeDriveStore();
      final t = _setup(
        store: store,
        exports: FakeExportRepository(skipNonFavorites: true),
        settings: _automatic.copyWith(
          plan: const DriveBackupPlan(
            layout: DriveOutputLayout.splitByFavorite,
          ),
        ),
      );

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      expect(store.uploads, [('mangavault_1_favorites.tachibk', true)]);
    });

    test('a failed later part removes the files already uploaded', () async {
      final store = FakeDriveStore(failOnUpload: 2);
      final t = _setup(
        store: store,
        settings: _automatic.copyWith(
          plan: const DriveBackupPlan(
            layout: DriveOutputLayout.splitByFavorite,
          ),
        ),
      );

      await t.container.read(driveBackupProvider.notifier).check(now: _later);

      expect(store.deleted, ['id1']);
      expect(t.container.read(driveBackupSettingsProvider).lastCursor, isEmpty);
      expect(store.closed, isTrue);
    });

    test(
      'a changed plan uploads even when the old cursor still matches',
      () async {
        final store = FakeDriveStore();
        final t = _setup(
          store: store,
          settings: _automatic.copyWith(lastEpoch: 'epoch', lastCursor: '42'),
        );
        t.container
            .read(driveBackupSettingsProvider.notifier)
            .setPlan(
              const DriveBackupPlan(layout: DriveOutputLayout.splitByApp),
            );

        await t.container.read(driveBackupProvider.notifier).check(now: _later);

        expect(store.uploads, hasLength(2));
        expect(t.exports.scopes.map((scope) => scope.filters.sourceApps), [
          {'app.komikku'},
          {'app.mihon'},
        ]);
      },
    );

    test('an import finishing does nothing when after-import is off', () async {
      final store = FakeDriveStore();
      final t = _setup(
        store: store,
        settings: _automatic.copyWith(afterImport: false),
      );
      t.container.read(driveBackupProvider);

      (t.container.read(importControllerProvider.notifier) as _Import).set(
        const ImportDone([]),
      );
      await pumpEventQueue();

      expect(store.uploads, isEmpty);
    });
  });
}
