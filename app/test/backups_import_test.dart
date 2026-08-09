import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/import/import_models.dart';
import 'package:mangavault/data/import/import_repository.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/features/backups/backups_screen.dart';
import 'package:mangavault/features/backups/import_controller.dart';
import 'package:mangavault/features/sync/sync_controller.dart';
import 'package:mangavault/theme/app_theme.dart';

/// Fake repository: scripted event stream, no real HTTP.
class FakeImportRepository extends ImportRepository {
  FakeImportRepository(this.events, {this.records = const []}) : super(Dio());
  final List<ImportEvent> events;
  final List<ImportRecord> records;

  @override
  Future<String> commit(String stagedId) async => 'job-$stagedId';

  @override
  Stream<ImportEvent> streamEvents(String jobId) => Stream.fromIterable(events);

  @override
  Future<List<ImportRecord>> history() async => records;

  @override
  Future<void> discard(String stagedId) async {}

  /// Ids the source-app PATCH was called for, and what it was tagged with.
  final tagged = <String, String>{};

  /// Paths uploaded through the streaming path, in order.
  final streamed = <String>[];

  @override
  Future<StagedImport> stageFile(String path, String fileName) async {
    streamed.add(path);
    return _stagedNamed(fileName, sourceApp: 'app.mihon');
  }

  @override
  Future<StagedImport> setSourceApp(String stagedId, String sourceApp) async {
    tagged[stagedId] = sourceApp;
    return _stagedNamed(stagedId, sourceApp: sourceApp);
  }
}

/// Controller seeded into a given state (bypasses file_picker).
class SeededController extends ImportController {
  SeededController(this.seed);
  final ImportState seed;
  @override
  ImportState build() => seed;
}

/// Stands in for the real sync so tests never touch a database or the network,
/// and so the import → sync hand-off can be asserted directly.
class RecordingSyncController extends SyncController {
  int runs = 0;

  @override
  SyncState build() => const SyncIdle();

  @override
  Future<void> run({bool force = false}) async => runs++;

  @override
  Future<void> bootstrap() async {}
}

/// In-memory mirror for the Backups screen's import-history cell, so no test
/// opens a real database file.
AppDatabase _memoryDb() {
  final db = AppDatabase.memory();
  addTearDown(db.close);
  return db;
}

ImportRecord _record() => ImportRecord(
      id: 'r1',
      fileName: 'x.tachibk',
      fileSize: 1,
      sourceApp: 'app.mihon',
      container: 'gzip-proto',
      importedAt: DateTime.now().millisecondsSinceEpoch,
      stats: const ImportSummary(
        titlesTotal: 2,
        titlesNew: 1,
        titlesMerged: 1,
        chaptersTotal: 0,
        categoriesTotal: 0,
        warnings: [],
      ),
    );

/// A staged file with a chosen id and source-app tag; `''` is the "the filename
/// didn't say which app" case the picker exists for.
StagedImport _stagedNamed(String id, {String sourceApp = ''}) => StagedImport(
      id: id,
      fileMeta: ImportFileMeta(
        fileName: '$id.tachibk',
        fileSize: 1,
        sha256: id,
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

StagedImport _staged() => StagedImport(
      id: 's1',
      fileMeta: const ImportFileMeta(
        fileName: 'x.tachibk',
        fileSize: 1,
        sha256: 'a',
        sourceApp: 'app.mihon',
        container: 'gzip-proto',
      ),
      summary: const ImportSummary(
        titlesTotal: 2,
        titlesNew: 2,
        titlesMerged: 0,
        chaptersTotal: 0,
        categoriesTotal: 0,
        warnings: [],
      ),
      preview: const [],
      expiresAt: 0,
    );

void main() {
  group('staging from the file browser', () {
    ProviderContainer containerFor(FakeImportRepository repo) {
      final container = ProviderContainer(overrides: [
        importRepositoryProvider.overrideWithValue(repo),
        appDatabaseProvider.overrideWithValue(_memoryDb()),
        syncControllerProvider.overrideWith(RecordingSyncController.new),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('stagePaths streams each backup and lands in review', () async {
      final repo = FakeImportRepository(const []);
      final container = containerFor(repo);

      await container.read(importControllerProvider.notifier).stagePaths([
        '/storage/emulated/0/Download/app.mihon_2026-08-01.tachibk',
        '/storage/emulated/0/Download/legacy.json',
      ]);

      // Sent by path, not read into memory first.
      expect(repo.streamed, [
        '/storage/emulated/0/Download/app.mihon_2026-08-01.tachibk',
        '/storage/emulated/0/Download/legacy.json',
      ]);
      final state = container.read(importControllerProvider);
      expect(state, isA<ImportReview>());
      expect((state as ImportReview).queue, hasLength(2));
    });

    test('stagePaths ignores anything that is not a backup', () async {
      final repo = FakeImportRepository(const []);
      final container = containerFor(repo);

      await container
          .read(importControllerProvider.notifier)
          .stagePaths(['/storage/emulated/0/Download/holiday.jpg']);

      expect(repo.streamed, isEmpty);
      expect(container.read(importControllerProvider), isA<ImportFailed>());
    });
  });

  group('source app attribution', () {
    ProviderContainer containerFor(
      ImportState seed,
      FakeImportRepository repo,
    ) {
      final container = ProviderContainer(overrides: [
        importRepositoryProvider.overrideWithValue(repo),
        importControllerProvider.overrideWith(() => SeededController(seed)),
        appDatabaseProvider.overrideWithValue(_memoryDb()),
        syncControllerProvider.overrideWith(RecordingSyncController.new),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('tagging the last unidentified file moves on to review', () async {
      final repo = FakeImportRepository(const []);
      final container = containerFor(
        ImportNeedsApp(queue: [_stagedNamed('s1')], index: 0),
        repo,
      );

      await container
          .read(importControllerProvider.notifier)
          .setSourceApp('s1', 'app.komikku');

      expect(repo.tagged, {'s1': 'app.komikku'});
      final state = container.read(importControllerProvider);
      expect(state, isA<ImportReview>());
      expect((state as ImportReview).queue.single.fileMeta.sourceApp,
          'app.komikku');
    });

    test('asks about each unidentified file in turn, skipping tagged ones',
        () async {
      final repo = FakeImportRepository(const []);
      // Middle file already carries an app id from its filename.
      final container = containerFor(
        ImportNeedsApp(
          queue: [
            _stagedNamed('s1'),
            _stagedNamed('s2', sourceApp: 'app.mihon'),
            _stagedNamed('s3'),
          ],
          index: 0,
        ),
        repo,
      );
      final controller = container.read(importControllerProvider.notifier);

      await controller.setSourceApp('s1', 'app.komikku');
      final next = container.read(importControllerProvider);
      expect(next, isA<ImportNeedsApp>());
      expect((next as ImportNeedsApp).current.id, 's3');

      await controller.setSourceApp('s3', 'app.komikku');
      expect(container.read(importControllerProvider), isA<ImportReview>());
    });

    test('skipping does not re-ask the same file', () async {
      final repo = FakeImportRepository(const []);
      final container = containerFor(
        ImportNeedsApp(
          queue: [_stagedNamed('s1'), _stagedNamed('s2')],
          index: 0,
        ),
        repo,
      );
      final controller = container.read(importControllerProvider.notifier);

      // An empty tag means "leave it unknown" — the file stays untagged, so a
      // routing pass that rescanned from the start would ask about it forever.
      await controller.setSourceApp('s1', '');
      final next = container.read(importControllerProvider);
      expect((next as ImportNeedsApp).current.id, 's2');

      await controller.setSourceApp('s2', '');
      final done = container.read(importControllerProvider);
      expect(done, isA<ImportReview>());
      expect((done as ImportReview).queue.map((s) => s.fileMeta.sourceApp),
          ['', '']);
    });

    test('retagStaged replaces the app on an already-reviewed file', () async {
      final repo = FakeImportRepository(const []);
      final container = containerFor(
        ImportReview([_stagedNamed('s1', sourceApp: 'app.mihon')]),
        repo,
      );

      await container
          .read(importControllerProvider.notifier)
          .retagStaged('s1', 'app.komikku');

      final state = container.read(importControllerProvider) as ImportReview;
      expect(state.queue.single.fileMeta.sourceApp, 'app.komikku');
    });
  });

  test('commitAll folds streamed events and ends in ImportDone', () async {
    final record = _record();
    final repo = FakeImportRepository([
      const StartEvent(fileName: 'x.tachibk', total: 2),
      const PhaseEvent(phase: 'categories'),
      const MangaEvent(title: 'A', action: 'created', processed: 1, total: 2),
      const MangaEvent(title: 'B', action: 'merged', processed: 2, total: 2),
      const BatchEvent(committed: 2, total: 2),
      DoneEvent(record),
    ]);

    final sync = RecordingSyncController();
    final container = ProviderContainer(overrides: [
      importRepositoryProvider.overrideWithValue(repo),
      importControllerProvider.overrideWith(() => SeededController(ImportReview([_staged()]))),
      appDatabaseProvider.overrideWithValue(_memoryDb()),
      syncControllerProvider.overrideWith(() => sync),
    ]);
    addTearDown(container.dispose);

    await container.read(importControllerProvider.notifier).commitAll();

    final state = container.read(importControllerProvider);
    expect(state, isA<ImportDone>());
    expect((state as ImportDone).records.single.id, 'r1');
    // A finished import must pull the new titles into the on-device mirror,
    // or the Library and Dashboard would keep showing the pre-import library.
    expect(sync.runs, 1);
  });

  testWidgets('live progress cell renders streamed manga records', (tester) async {
    final committing = ImportCommitting(
      fileName: 'app.mihon_x.tachibk',
      fileIndex: 1,
      fileCount: 1,
      processed: 1,
      total: 3,
      phaseLabel: 'Importing titles… 1 / 3',
      recent: const [MangaEvent(title: 'Solo Leveling', action: 'created', processed: 1, total: 3)],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        importRepositoryProvider.overrideWithValue(FakeImportRepository(const [])),
        importControllerProvider.overrideWith(() => SeededController(committing)),
        appDatabaseProvider.overrideWithValue(_memoryDb()),
        syncControllerProvider.overrideWith(RecordingSyncController.new),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const BackupsScreen()),
    ));
    await tester.pump();

    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.textContaining('1 / 3'), findsWidgets);
  });

  testWidgets('review cell shows new/merged badges and a commit button', (tester) async {
    final staged = StagedImport(
      id: 's1',
      fileMeta: _staged().fileMeta,
      summary: const ImportSummary(
        titlesTotal: 2,
        titlesNew: 1,
        titlesMerged: 1,
        chaptersTotal: 5,
        categoriesTotal: 0,
        warnings: [],
      ),
      preview: const [
        MergeResult(title: 'A', action: 'created', conflicts: []),
        MergeResult(title: 'B', action: 'merged', conflicts: []),
      ],
      expiresAt: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        importRepositoryProvider.overrideWithValue(FakeImportRepository(const [])),
        importControllerProvider.overrideWith(() => SeededController(ImportReview([staged]))),
        appDatabaseProvider.overrideWithValue(_memoryDb()),
        syncControllerProvider.overrideWith(RecordingSyncController.new),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const BackupsScreen()),
    ));
    await tester.pump();

    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('MERGED'), findsOneWidget);
    expect(find.text('Commit import'), findsOneWidget);
  });

  testWidgets('tapping a count chip filters the review list', (tester) async {
    final staged = StagedImport(
      id: 's1',
      fileMeta: _staged().fileMeta,
      summary: const ImportSummary(
        titlesTotal: 3,
        titlesNew: 1,
        titlesMerged: 1,
        titlesSkipped: 1,
        chaptersTotal: 5,
        categoriesTotal: 0,
        warnings: [],
      ),
      preview: const [
        MergeResult(title: 'Created One', action: 'created', conflicts: []),
        MergeResult(title: 'Merged One', action: 'merged', conflicts: []),
        MergeResult(title: 'Skipped One', action: 'skipped', conflicts: []),
      ],
      expiresAt: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        importRepositoryProvider.overrideWithValue(FakeImportRepository(const [])),
        importControllerProvider.overrideWith(() => SeededController(ImportReview([staged]))),
        appDatabaseProvider.overrideWithValue(_memoryDb()),
        syncControllerProvider.overrideWith(RecordingSyncController.new),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const BackupsScreen()),
    ));
    await tester.pump();

    expect(find.text('Created One'), findsOneWidget);
    expect(find.text('Skipped One'), findsOneWidget);

    await tester.tap(find.text('1 skipped'));
    await tester.pumpAndSettle();

    expect(find.text('Skipped One'), findsOneWidget);
    expect(find.text('Created One'), findsNothing);
    expect(find.text('Merged One'), findsNothing);
    expect(find.text('Showing 1 of 3'), findsOneWidget);

    // Tapping the active chip again clears the filter.
    await tester.tap(find.text('1 skipped'));
    await tester.pumpAndSettle();
    expect(find.text('Created One'), findsOneWidget);
    expect(find.text('Showing 1 of 3'), findsNothing);

    // …as does "Show all".
    await tester.tap(find.text('1 merged'));
    await tester.pumpAndSettle();
    expect(find.text('Created One'), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Created One'), findsOneWidget);
  });
}
