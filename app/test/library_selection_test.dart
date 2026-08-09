import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/backup_apps/backup_app_models.dart';
import 'package:mangavault/data/library/deleted_models.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/data/library/library_write_repository.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/features/library/library_screen.dart';
import 'package:mangavault/features/library/library_selection.dart';
import 'package:mangavault/features/sync/sync_controller.dart';
import 'package:mangavault/theme/app_theme.dart';

/// Read side: serves a fixed set of titles and records what was forgotten
/// locally after a delete.
class _FakeRepo extends LibraryRepository {
  _FakeRepo(this._items);

  List<MangaListItem> _items;
  final List<String> forgotten = [];

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    List<String> sourceApps = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async =>
      LibraryPage(
          items: _items, total: _items.length, offset: 0, limit: limit);

  @override
  Future<VaultManga> get(String id) => throw UnimplementedError();

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<List<SourceOption>> sources() async => const [];

  @override
  Future<List<SourceAppOption>> sourceApps() async => const [];

  @override
  Future<Map<String, String>> backupAppNames() async => const {};

  @override
  Future<void> forgetTitles(List<String> ids) async {
    forgotten.addAll(ids);
    _items = _items.where((i) => !ids.contains(i.id)).toList();
  }
}

/// Write side: never touches the network.
class _FakeWrite implements LibraryWriteRepository {
  _FakeWrite({this.fails = false});

  final bool fails;
  final List<List<String>> calls = [];

  @override
  Future<int> deleteTitles(List<String> ids) async {
    calls.add(ids);
    if (fails) throw Exception('server unreachable');
    return ids.length;
  }

  @override
  Future<DeletedTitlesPage> deletedTitles() async =>
      const DeletedTitlesPage(items: [], totalBytes: 0);

  @override
  Future<RestoreResult> restore(List<String> ids) async =>
      RestoreResult(restored: ids.length, skipped: 0);

  @override
  Future<int> purgeDeleted(List<String> ids) async => ids.length;
}

class _NoopSync extends SyncController {
  @override
  SyncState build() => const SyncIdle();
  @override
  Future<void> bootstrap() async {}
  @override
  Future<void> run({bool force = false}) async {}
}

MangaListItem _item(String title) => MangaListItem(
      id: title,
      title: title,
      author: null,
      status: 'ongoing',
      coverPath: null,
      coverState: 'none',
      sourceName: 'MangaDex',
      sourceId: '2499283573021220255',
      chapterCount: 7,
      unreadCount: 2,
      lastReadAt: null,
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeRepo repo,
  required _FakeWrite write,
}) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.memory();
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      libraryWriteRepositoryProvider.overrideWithValue(write),
      appDatabaseProvider.overrideWithValue(db),
      syncControllerProvider.overrideWith(_NoopSync.new),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: const LibraryScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  return ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
}

void main() {
  group('selection controller', () {
    test('long-press begins, tap toggles, and exiting clears', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(librarySelectionProvider.notifier);

      notifier.begin('a');
      expect(container.read(librarySelectionProvider).active, isTrue);
      expect(container.read(librarySelectionProvider).count, 1);

      notifier.toggle('b');
      expect(container.read(librarySelectionProvider).count, 2);
      notifier.toggle('a');
      expect(container.read(librarySelectionProvider).contains('a'), isFalse);

      // Clearing keeps selection mode; only exit leaves it, so an accidental
      // deselect doesn't yank the toolbar away.
      notifier.clear();
      expect(container.read(librarySelectionProvider).active, isTrue);
      expect(container.read(librarySelectionProvider).count, 0);

      notifier.exit();
      expect(container.read(librarySelectionProvider).active, isFalse);
    });

    test('selectAll takes the loaded ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(librarySelectionProvider.notifier)
          .selectAll(['a', 'b', 'c']);
      expect(container.read(librarySelectionProvider).count, 3);
    });
  });

  testWidgets('long-press selects a title and the toolbar reports the count',
      (tester) async {
    final repo = _FakeRepo([_item('Solo Leveling'), _item('Omniscient Reader')]);
    final container =
        await _pump(tester, repo: repo, write: _FakeWrite());

    await tester.longPress(find.text('Solo Leveling'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(container.read(librarySelectionProvider).contains('Solo Leveling'),
        isTrue);

    // A plain tap now toggles instead of navigating.
    await tester.tap(find.text('Omniscient Reader'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // Select-all flips to select-none once everything loaded is picked.
    await tester.tap(find.byIcon(Icons.deselect));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('deleting asks first, then removes the titles', (tester) async {
    final repo = _FakeRepo([_item('Solo Leveling'), _item('Omniscient Reader')]);
    final write = _FakeWrite();
    final container = await _pump(tester, repo: repo, write: write);

    await tester.longPress(find.text('Solo Leveling'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Nothing happens until the confirmation is accepted.
    expect(find.text('Delete this title?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(write.calls, isEmpty);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(write.calls, [
      ['Solo Leveling']
    ]);
    expect(repo.forgotten, ['Solo Leveling']);
    // The card is gone, selection mode is over, and the outcome is reported.
    expect(find.text('Solo Leveling'), findsNothing);
    expect(container.read(librarySelectionProvider).active, isFalse);
    expect(find.text('Title deleted'), findsOneWidget);
  });

  testWidgets('a failed delete keeps the selection and says so', (tester) async {
    final repo = _FakeRepo([_item('Solo Leveling')]);
    final write = _FakeWrite(fails: true);
    final container = await _pump(tester, repo: repo, write: write);

    await tester.longPress(find.text('Solo Leveling'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repo.forgotten, isEmpty);
    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(container.read(librarySelectionProvider).count, 1);
    expect(find.textContaining("Couldn't delete"), findsOneWidget);
  });
}
