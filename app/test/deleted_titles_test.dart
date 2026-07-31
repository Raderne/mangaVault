import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/deleted_models.dart';
import 'package:mangavault/data/library/library_write_repository.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/features/library/deleted_titles_screen.dart';
import 'package:mangavault/features/sync/sync_controller.dart';
import 'package:mangavault/theme/app_theme.dart';

class _FakeWrite implements LibraryWriteRepository {
  _FakeWrite(this._entries);

  List<DeletedTitle> _entries;
  final List<List<String>> restored = [];
  final List<List<String>> purged = [];

  @override
  Future<DeletedTitlesPage> deletedTitles() async =>
      DeletedTitlesPage(items: _entries, totalBytes: 77 * 1024);

  @override
  Future<RestoreResult> restore(List<String> ids) async {
    restored.add(ids);
    _entries = _entries.where((e) => !ids.contains(e.id)).toList();
    return RestoreResult(restored: ids.length, skipped: 0);
  }

  @override
  Future<int> purgeDeleted(List<String> ids) async {
    purged.add(ids);
    _entries = _entries.where((e) => !ids.contains(e.id)).toList();
    return ids.length;
  }

  @override
  Future<int> deleteTitles(List<String> ids) async => ids.length;
}

class _NoopSync extends SyncController {
  int runs = 0;

  @override
  SyncState build() => const SyncIdle();
  @override
  Future<void> bootstrap() async {}
  @override
  Future<void> run({bool force = false}) async {
    runs++;
  }
}

DeletedTitle _entry(
  String id, {
  String title = 'Solo Leveling',
  int seenCount = 0,
  String sourceName = 'MangaDex',
  String sourceId = '2499283573021220255',
}) =>
    DeletedTitle(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      title: title,
      chapterCount: 12,
      readCount: 4,
      deletedAt: DateTime.now().millisecondsSinceEpoch - 3600 * 1000,
      lastSeenAt: seenCount > 0 ? DateTime.now().millisecondsSinceEpoch : null,
      seenCount: seenCount,
    );

Future<void> _pump(WidgetTester tester, _FakeWrite write) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.memory();
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      libraryWriteRepositoryProvider.overrideWithValue(write),
      appDatabaseProvider.overrideWithValue(db),
      syncControllerProvider.overrideWith(_NoopSync.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const DeletedTitlesScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('lists deleted titles and flags the ones a backup wanted back',
      (tester) async {
    final write = _FakeWrite([
      _entry('r1', title: 'Solo Leveling', seenCount: 2),
      _entry('r2', title: 'Omniscient Reader'),
    ]);
    await _pump(tester, write);

    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('Omniscient Reader'), findsOneWidget);
    expect(find.text('in 2 backups since'), findsOneWidget);
    // The bin states what it costs, so the snapshots aren't left to imagination.
    expect(find.text('2 titles · 77.0 KB'), findsOneWidget);
    // Nothing selected yet, so the action bar isn't there.
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('selecting and restoring calls the server and re-syncs',
      (tester) async {
    final write = _FakeWrite([_entry('r1'), _entry('r2', title: 'Beta')]);
    await _pump(tester, write);

    await tester.tap(find.text('Solo Leveling'));
    await tester.pumpAndSettle();
    expect(find.text('Restore 1'), findsOneWidget);

    await tester.tap(find.text('Restore 1'));
    await tester.pumpAndSettle();

    expect(write.restored, [
      ['r1']
    ]);
    expect(find.text('1 restored'), findsOneWidget);
    // The restored title is a new row server-side; only a sync surfaces it.
    expect(find.text('Solo Leveling'), findsNothing);
  });

  testWidgets('removing from the list asks first and does not restore',
      (tester) async {
    final write = _FakeWrite([_entry('r1')]);
    await _pump(tester, write);

    await tester.tap(find.text('Solo Leveling'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove this entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(write.purged, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    // The dialog's confirm button, not the action bar's.
    await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
    await tester.pumpAndSettle();

    expect(write.purged, [
      ['r1']
    ]);
    expect(write.restored, isEmpty);
  });

  testWidgets('an empty registry explains what the screen is for',
      (tester) async {
    await _pump(tester, _FakeWrite(const []));
    expect(find.text('Nothing deleted'), findsOneWidget);
  });
}
