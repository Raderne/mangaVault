import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/files/file_access.dart';
import 'package:mangavault/core/files/vault_file_system.dart';
import 'package:mangavault/core/files/watched_folders.dart';
import 'package:mangavault/data/import/import_models.dart';
import 'package:mangavault/data/import/import_repository.dart';
import 'package:mangavault/features/backups/auto_import_controller.dart';
import 'package:mangavault/features/backups/import_controller.dart';
import 'package:mangavault/features/sync/sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_file_system.dart';

const _folder = '/storage/emulated/0/Mihon/autobackup';

FileEntry _entry(String name, int modifiedMillis) => FileEntry(
      path: '$_folder/$name',
      name: name,
      isDirectory: false,
      modifiedMillis: modifiedMillis,
    );

ImportRecord _record(String fileName) => ImportRecord(
      id: fileName,
      fileName: fileName,
      fileSize: 1,
      sourceApp: 'app.mihon',
      container: 'gzip-proto',
      importedAt: 0,
      stats: const ImportSummary(
        titlesTotal: 1,
        titlesNew: 1,
        titlesMerged: 0,
        chaptersTotal: 0,
        categoriesTotal: 0,
        warnings: [],
      ),
    );

StagedImport _staged(String fileName, {String sourceApp = 'app.mihon'}) =>
    StagedImport(
      id: fileName,
      fileMeta: ImportFileMeta(
        fileName: fileName,
        fileSize: 1,
        sha256: fileName,
        sourceApp: sourceApp,
        container: 'gzip-proto',
      ),
      summary: const ImportSummary(
        titlesTotal: 1,
        titlesNew: 1,
        titlesMerged: 0,
        chaptersTotal: 0,
        categoriesTotal: 0,
        warnings: [],
      ),
      preview: const [],
      expiresAt: 0,
    );

/// Records what the watcher pushed at the server, with no HTTP anywhere.
class FakeImportRepository extends ImportRepository {
  FakeImportRepository({this.sourceApp = 'app.mihon'}) : super(Dio());

  /// What a staged file comes back tagged with — `''` is the "the filename
  /// didn't say which app" case the folder's own id has to cover.
  final String sourceApp;

  final staged = <String>[];
  final committed = <String>[];
  final tagged = <String, String>{};
  final discarded = <String>[];

  @override
  Future<StagedImport> stageFile(String path, String fileName) async {
    staged.add(path);
    return _staged(fileName, sourceApp: sourceApp);
  }

  @override
  Future<StagedImport> setSourceApp(String stagedId, String app) async {
    tagged[stagedId] = app;
    return _staged(stagedId, sourceApp: app);
  }

  @override
  Future<String> commit(String stagedId) async {
    committed.add(stagedId);
    return 'job-$stagedId';
  }

  @override
  Stream<ImportEvent> streamEvents(String jobId) => Stream.fromIterable([
        const StartEvent(fileName: 'x', total: 1),
        DoneEvent(_record(jobId)),
      ]);

  @override
  Future<void> discard(String stagedId) async => discarded.add(stagedId);

  @override
  Future<List<ImportRecord>> history() async => const [];
}

class _GrantedAccess extends FileAccessController {
  @override
  FileAccessStatus build() => FileAccessStatus.granted;

  @override
  Future<void> refresh() async {}
}

class _SeededSettings extends AutoImportSettingsController {
  _SeededSettings(this.seed);
  final AutoImportSettings seed;

  @override
  AutoImportSettings build() => seed;
}

class _SilentSync extends SyncController {
  @override
  SyncState build() => const SyncIdle();

  @override
  Future<void> run({bool force = false}) async {}

  @override
  Future<void> bootstrap() async {}
}

/// Seeds a container whose last scan is *now*, so nothing runs until a test
/// asks — the watcher's own launch scan would otherwise race every assertion.
ProviderContainer _container({
  required FakeFileSystem fs,
  required FakeImportRepository repo,
  required List<WatchedFolder> folders,
  int intervalHours = 12,
  ImportState? importState,
}) {
  final container = ProviderContainer(
    overrides: [
      vaultFileSystemProvider.overrideWithValue(fs),
      importRepositoryProvider.overrideWithValue(repo),
      fileAccessProvider.overrideWith(_GrantedAccess.new),
      syncControllerProvider.overrideWith(_SilentSync.new),
      autoImportSettingsProvider.overrideWith(
        () => _SeededSettings(
          AutoImportSettings(
            folders: folders,
            intervalHours: intervalHours,
            lastScanAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      ),
      if (importState != null)
        importControllerProvider.overrideWith(() => _SeededImport(importState)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _SeededImport extends ImportController {
  _SeededImport(this.seed);
  final ImportState seed;

  @override
  ImportState build() => seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('newestUnseen', () {
    const fresh = WatchedFolder(path: _folder, appId: 'app.mihon');

    test('picks the newest backup and ignores everything else in the folder',
        () {
      final picked = newestUnseen([
        _entry('app.mihon_2026-09-01_02-00.tachibk', 1000),
        _entry('app.mihon_2026-09-03_02-00.tachibk', 3000),
        _entry('cover.jpg', 9999),
        const FileEntry(
          path: '$_folder/old',
          name: 'old',
          isDirectory: true,
          modifiedMillis: 9999,
        ),
      ], fresh);

      expect(picked?.name, 'app.mihon_2026-09-03_02-00.tachibk');
    });

    test('returns null once the newest file has already been imported', () {
      final folder = fresh.copyWith(
        lastFileName: 'app.mihon_2026-09-03_02-00.tachibk',
        lastModifiedMs: 3000,
      );
      final picked = newestUnseen([
        _entry('app.mihon_2026-09-01_02-00.tachibk', 1000),
        _entry('app.mihon_2026-09-03_02-00.tachibk', 3000),
      ], folder);

      expect(picked, isNull);
    });

    test('a sibling written in the same second is still new', () {
      // A fork that writes two backups at once gives them identical mtimes, so
      // the timestamp alone would wrongly mark the second one as seen.
      final folder = fresh.copyWith(
        lastFileName: 'app.mihon_a.tachibk',
        lastModifiedMs: 3000,
      );
      final picked = newestUnseen([
        _entry('app.mihon_a.tachibk', 3000),
        _entry('app.mihon_b.tachibk', 3000),
      ], folder);

      expect(picked?.name, 'app.mihon_b.tachibk');
    });

    test('an empty folder yields nothing', () {
      expect(newestUnseen(const [], fresh), isNull);
    });
  });

  group('throttle', () {
    test('is not due before the interval has elapsed', () {
      final now = DateTime(2026, 9, 12, 12);
      final settings = AutoImportSettings(
        intervalHours: 12,
        lastScanAtMs:
            now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
      );
      expect(settings.isDue(now), isFalse);
      expect(settings.isDue(now.add(const Duration(hours: 8))), isTrue);
    });

    test('off is never due', () {
      final now = DateTime(2026, 9, 12, 12);
      const settings = AutoImportSettings(intervalHours: 0);
      expect(settings.isDue(now), isFalse);
    });
  });

  group('scan', () {
    test('imports the newest backup and does not import it twice', () async {
      final fs = FakeFileSystem()
        ..addFile('$_folder/app.mihon_2026-09-01.tachibk', modifiedMillis: 1000)
        ..addFile('$_folder/app.mihon_2026-09-03.tachibk', modifiedMillis: 3000);
      final repo = FakeImportRepository();
      final container = _container(
        fs: fs,
        repo: repo,
        folders: const [WatchedFolder(path: _folder, appId: 'app.mihon')],
      );

      await container.read(autoImportProvider.notifier).scan(force: true);

      expect(repo.staged, ['$_folder/app.mihon_2026-09-03.tachibk']);
      expect(repo.committed, ['app.mihon_2026-09-03.tachibk']);
      expect(
        container.read(autoImportProvider).message,
        'Imported 1 new backup.',
      );

      // The folder now remembers it, so a second scan over the same folder
      // finds nothing new — this is what stops every resume re-uploading the
      // same file.
      await container.read(autoImportProvider.notifier).scan(force: true);

      expect(repo.staged, hasLength(1));
      expect(
        container.read(autoImportProvider).message,
        'No new backups found.',
      );
    });

    test('tags the import with the folder app when the filename does not',
        () async {
      final fs = FakeFileSystem()
        ..addFile('$_folder/library.tachibk', modifiedMillis: 3000);
      final repo = FakeImportRepository(sourceApp: '');
      final container = _container(
        fs: fs,
        repo: repo,
        folders: const [WatchedFolder(path: _folder, appId: 'app.komikku')],
      );

      await container.read(autoImportProvider.notifier).scan(force: true);

      // Nobody is around to answer ImportNeedsApp, so the folder's own id is
      // what keeps the import moving.
      expect(repo.tagged, {'library.tachibk': 'app.komikku'});
      expect(repo.committed, ['library.tachibk']);
    });

    test('does not touch an import the user is already part-way through',
        () async {
      final fs = FakeFileSystem()
        ..addFile('$_folder/app.mihon_2026-09-03.tachibk', modifiedMillis: 3000);
      final repo = FakeImportRepository();
      final container = _container(
        fs: fs,
        repo: repo,
        folders: const [WatchedFolder(path: _folder, appId: 'app.mihon')],
        importState: ImportReview([_staged('waiting.tachibk')]),
      );

      await container.read(autoImportProvider.notifier).scan(force: true);

      expect(repo.staged, isEmpty);
      expect(repo.committed, isEmpty);
      expect(
        container.read(autoImportProvider).message,
        'Paused — an import is already in progress.',
      );
      // The user's staged queue is exactly where they left it.
      expect(container.read(importControllerProvider), isA<ImportReview>());
    });

    test('an unreadable folder is reported, not thrown', () async {
      final fs = FakeFileSystem()..unreadable.add(_folder);
      final repo = FakeImportRepository();
      final container = _container(
        fs: fs,
        repo: repo,
        folders: const [WatchedFolder(path: _folder, appId: 'app.mihon')],
      );

      await container.read(autoImportProvider.notifier).scan(force: true);

      expect(repo.staged, isEmpty);
      expect(
        container.read(autoImportProvider).message,
        contains("won't let this app read"),
      );
    });

    test('the throttle blocks an unforced scan but "Scan now" runs anyway',
        () async {
      final fs = FakeFileSystem()
        ..addFile('$_folder/app.mihon_2026-09-03.tachibk', modifiedMillis: 3000);
      final repo = FakeImportRepository();
      final container = _container(
        fs: fs,
        repo: repo,
        folders: const [WatchedFolder(path: _folder, appId: 'app.mihon')],
      );

      // lastScanAt is now, so the 12h interval has not elapsed.
      await container.read(autoImportProvider.notifier).scan();
      expect(repo.staged, isEmpty);

      await container.read(autoImportProvider.notifier).scan(force: true);
      expect(repo.staged, hasLength(1));
    });
  });

  group('isBusy', () {
    test('terminal states are replaceable, in-flight ones are not', () {
      // Without this the watcher would deadlock on its own ImportDone the
      // moment it succeeded once.
      expect(const ImportIdle().isBusy, isFalse);
      expect(const ImportDone([]).isBusy, isFalse);
      expect(const ImportFailed('x').isBusy, isFalse);
      expect(const ImportStaging('x').isBusy, isTrue);
      expect(ImportReview([_staged('x.tachibk')]).isBusy, isTrue);
    });
  });

  group('settings persistence', () {
    test('a watched folder survives a round-trip through JSON', () {
      const folder = WatchedFolder(
        path: _folder,
        appId: 'app.mihon',
        lastFileName: 'x.tachibk',
        lastModifiedMs: 3000,
        lastImportedAtMs: 4000,
      );
      final back = WatchedFolder.fromJson(folder.toJson())!;

      expect(back.path, folder.path);
      expect(back.appId, 'app.mihon');
      expect(back.lastFileName, 'x.tachibk');
      expect(back.lastModifiedMs, 3000);
    });

    test('a row with no path is dropped rather than crashing the screen', () {
      expect(WatchedFolder.fromJson({'appId': 'app.mihon'}), isNull);
      expect(WatchedFolder.fromJson('nonsense'), isNull);
    });
  });
}
