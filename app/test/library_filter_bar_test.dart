import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/features/library/library_controller.dart';
import 'package:mangavault/features/library/library_screen.dart';
import 'package:mangavault/features/sync/sync_controller.dart';
import 'package:mangavault/theme/app_theme.dart';

class _FakeRepo implements LibraryRepository {
  _FakeRepo(this.total);
  final int total;

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async =>
      LibraryPage(items: const [], total: total, offset: 0, limit: limit);

  @override
  Future<VaultManga> get(String id) => throw UnimplementedError();

  @override
  Future<List<Category>> categories() async => const [];
}

/// Stub sync so the screen's bootstrap never touches the network.
class _NoopSync extends SyncController {
  @override
  SyncState build() => const SyncIdle();
  @override
  Future<void> bootstrap() async {}
  @override
  Future<void> run({bool force = false}) async {}
}

/// Pump the Library screen at a given width and text scale.
///
/// Filters moved into a bottom sheet, so the screen itself now shows only a
/// single-line meta row. These tests guard the layout that replaced the inline
/// filter bar, which overflowed horizontally on narrow phones once the
/// "Synced …" label joined it.
Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  double width = 320,
  double textScale = 1.0,
  int? syncedAt = 1700000000000,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.memory();
  addTearDown(db.close);
  if (syncedAt != null) {
    // Same write path as LibrarySyncService: the singleton row already exists
    // (the migration seeds it), so this is an update, not an insert.
    await db.update(db.syncMeta).write(
          SyncMetaCompanion(lastSyncedAt: Value(syncedAt)),
        );
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(_FakeRepo(1234)),
        appDatabaseProvider.overrideWithValue(db),
        syncControllerProvider.overrideWith(_NoopSync.new),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const LibraryScreen(),
      ),
    ),
  );
  await tester.pump();
  // lastSyncedAtProvider reads the mirror asynchronously, so the meta line
  // needs a couple more frames before the "synced …" part appears.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  return ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
}

/// Every painted descendant of the screen must stay within its horizontal
/// bounds. Checking a Row's own rect would prove nothing — an overflowing
/// RenderFlex still reports the *constrained* size — so the children are what
/// must be measured.
void _expectNoHorizontalOverflow(WidgetTester tester) {
  final screen = tester.getRect(find.byType(LibraryScreen));
  for (final finder in [
    find.textContaining('1,234'),
    find.textContaining('synced'),
  ]) {
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    expect(rect.right, lessThanOrEqualTo(screen.right + 0.5),
        reason: 'meta line overflows the screen');
    expect(rect.left, greaterThanOrEqualTo(screen.left - 0.5));
  }
}

void main() {
  testWidgets('meta line fits on a narrow phone', (tester) async {
    await _pumpLibrary(tester);
    expect(find.textContaining('1,234 favorites'), findsOneWidget);
    expect(find.textContaining('synced'), findsOneWidget);
    _expectNoHorizontalOverflow(tester);
  });

  testWidgets('meta line fits at an enlarged system font', (tester) async {
    // 1.6x on a 320pt screen is what broke the old inline filter bar.
    await _pumpLibrary(tester, textScale: 1.6);
    _expectNoHorizontalOverflow(tester);
  });

  testWidgets('meta line fits with a status filter applied', (tester) async {
    final container = await _pumpLibrary(tester, textScale: 1.4);
    container.read(libraryControllerProvider.notifier).setStatus('on_hiatus');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('hiatus'), findsOneWidget);
    _expectNoHorizontalOverflow(tester);
  });

  testWidgets('meta line omits the sync label before the first sync',
      (tester) async {
    await _pumpLibrary(tester, syncedAt: null);
    expect(find.textContaining('synced'), findsNothing);
    expect(find.textContaining('1,234 favorites'), findsOneWidget);
  });

  testWidgets('the tune action opens the filter sheet', (tester) async {
    await _pumpLibrary(tester, width: 400);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Filter & sort'), findsOneWidget);
    expect(find.text('ONGOING'), findsOneWidget);
    expect(find.text('Title A–Z'), findsOneWidget);
  });

  testWidgets('choosing a sort in the sheet updates the grid', (tester) async {
    final container = await _pumpLibrary(tester, width: 400);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most chapters'));
    await tester.pumpAndSettle();

    final filters = container.read(libraryControllerProvider).filters;
    expect(filters.sortBy, 'chapterCount');
    expect(filters.sortDir, 'desc');
  });

  testWidgets('reset returns the sheet to defaults', (tester) async {
    final container = await _pumpLibrary(tester, width: 400);
    container.read(libraryControllerProvider.notifier).setStatus('completed');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    final filters = container.read(libraryControllerProvider).filters;
    expect(filters.status, '');
    expect(filters.favorite, isTrue);
    expect(filters.sortBy, 'title');
  });

  testWidgets('the tune icon is badged only when filters are non-default',
      (tester) async {
    final container = await _pumpLibrary(tester, width: 400);
    Badge badge() => tester.widget<Badge>(find.byType(Badge));

    expect(badge().isLabelVisible, isFalse);

    container.read(libraryControllerProvider.notifier).setStatus('ongoing');
    await tester.pump();
    expect(badge().isLabelVisible, isTrue);
  });
}
