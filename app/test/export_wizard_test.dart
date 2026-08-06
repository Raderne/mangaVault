import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/backup_apps/backup_app_models.dart';
import 'package:mangavault/data/backup_apps/backup_apps_repository.dart';
import 'package:mangavault/data/export/export_models.dart';
import 'package:mangavault/data/export/export_repository.dart';
import 'package:mangavault/features/backups/export/export_controller.dart';
import 'package:mangavault/features/backups/export/export_screen.dart';
import 'package:mangavault/theme/app_theme.dart';

/// Fake repository: records the scopes it was asked about, answers instantly.
class FakeExportRepository extends ExportRepository {
  FakeExportRepository({this.facetsResult, this.previewTitles = 12})
      : super(Dio());

  final ExportFacets? facetsResult;
  final int previewTitles;

  /// Every scope the wizard previewed, in order — the assertion surface for
  /// "did the chip actually change the request".
  final previewed = <ExportScope>[];
  final built = <ExportScope>[];

  @override
  Future<ExportFacets> facets() async => facetsResult ?? _facets();

  @override
  Future<ExportPreview> preview(ExportScope scope,
      {CancelToken? cancelToken}) async {
    previewed.add(scope);
    return ExportPreview(
      titles: previewTitles,
      chapters: previewTitles * 10,
      readChapters: 4,
      categories: 2,
      sources: 1,
      trackedTitles: 1,
      fileName: '${scope.targetApp.isEmpty ? 'mangavault' : scope.targetApp}'
          '_2026-08-06_12-00.tachibk',
      estimatedBytes: 4096,
      sample: const [
        ExportPreviewItem(
          id: 'a',
          title: 'Solo Leveling',
          sourceName: 'MangaDex',
          chapterCount: 179,
          readCount: 179,
          favorite: true,
        ),
      ],
    );
  }

  @override
  Future<ExportedBackup> build(
    ExportScope scope, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    built.add(scope);
    throw UnimplementedError('the save dialog is not exercised in widget tests');
  }
}

ExportFacets _facets() => const ExportFacets(
      totalTitles: 120,
      favoriteTitles: 40,
      totalChapters: 5000,
      apps: [
        ExportFacetOption(id: 'app.mihon', label: 'Mihon', count: 90),
        ExportFacetOption(id: 'app.komikku', label: 'Komikku', count: 30),
      ],
      sources: [
        ExportFacetOption(id: '1234', label: 'MangaDex', count: 100),
        ExportFacetOption(id: '5678', label: 'Other', count: 20),
      ],
      categories: [
        ExportFacetOption(id: 'c1', label: 'Reading', count: 12),
      ],
      statuses: [
        ExportFacetOption(id: 'ongoing', label: 'ongoing', count: 80),
      ],
    );

/// The registry behind the "name it for which app" chips. Stubbed so no test
/// reaches the network for it.
const _registry = [
  BackupApp(id: 'app.mihon', displayName: 'Mihon', importCount: 3),
  BackupApp(id: 'app.komikku', displayName: 'Komikku', importCount: 1),
];

Widget _app(FakeExportRepository repo) => ProviderScope(
      overrides: [
        exportRepositoryProvider.overrideWithValue(repo),
        backupAppsProvider.overrideWith((ref) async => _registry),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const ExportScreen()),
    );

/// Settle past the controller's preview debounce.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// A phone-width but very tall viewport.
///
/// Width stays realistic (400dp) so the layout is the one a phone gets, while
/// the height keeps the whole step on screen: the step bodies are lazy
/// `ListView`s, so anything below the fold is not in the tree at all and these
/// tests would be asserting on scroll position rather than on behaviour.
void _phoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 2000);
  addTearDown(tester.view.reset);
}

void main() {
  group('ExportScope', () {
    test('defaults to the whole vault, losslessly', () {
      const scope = ExportScope();
      expect(scope.mode, ExportMode.all);
      expect(scope.includes.isLossless, isTrue);
      expect(scope.filters.isEmpty, isTrue);
      expect(scope.toJson()['mode'], 'all');
    });

    test('drops readProgress from the wire when chapters are excluded', () {
      // Progress lives on chapter rows; sending `readProgress: true` alongside
      // `chapters: false` would ask the server for something incoherent.
      const includes = ExportIncludes(chapters: false);
      expect(includes.toJson()['readProgress'], isFalse);
      expect(includes.isLossless, isFalse);
    });

    test('counts active filters for the custom-preset readout', () {
      const filters = ExportFilters(
        sourceApps: {'app.mihon'},
        favorite: true,
        unreadOnly: true,
      );
      expect(filters.activeCount, 3);
      expect(filters.isEmpty, isFalse);
    });

    test('clearFavorite removes the facet rather than setting it false', () {
      const filters = ExportFilters(favorite: true);
      expect(filters.copyWith(clearFavorite: true).favorite, isNull);
      expect(filters.copyWith(favorite: false).favorite, isFalse);
    });

    test('omits an empty search string from the request', () {
      expect(const ExportFilters().toJson().containsKey('text'), isFalse);
      expect(const ExportFilters(text: 'solo').toJson()['text'], 'solo');
    });
  });

  group('Export wizard', () {
    testWidgets('opens on Select with a live count of the whole vault',
        (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      expect(find.text('Create Backup'), findsOneWidget);
      expect(find.text('Everything'), findsOneWidget);
      expect(find.text('120 titles — the whole vault'), findsOneWidget);
      // The summary bar answers "how big is this" before any choice is made.
      expect(find.textContaining('12'), findsWidgets);
      expect(repo.previewed.first.mode, ExportMode.all);
    });

    testWidgets('the favorites preset narrows the scope it previews',
        (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      await tester.tap(find.text('Favorites only'));
      await _settle(tester);

      expect(repo.previewed.last.mode, ExportMode.filter);
      expect(repo.previewed.last.filters.favorite, isTrue);
    });

    testWidgets('custom selection reveals the facet builder', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      expect(find.text('FROM READING APP'), findsNothing);

      await tester.tap(find.text('Custom selection'));
      await _settle(tester);

      expect(find.text('FROM READING APP'), findsOneWidget);
      expect(find.text('MIHON'), findsOneWidget);
      expect(find.text('FROM SOURCE'), findsOneWidget);
      expect(find.text('MANGADEX'), findsOneWidget);
      expect(find.text('CATEGORIES'), findsOneWidget);
    });

    testWidgets('tapping an app chip filters by that app', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      await tester.tap(find.text('Custom selection'));
      await _settle(tester);
      await tester.tap(find.text('MIHON'));
      await _settle(tester);

      expect(repo.previewed.last.filters.sourceApps, {'app.mihon'});

      // Tapping it again clears it — the chip is a toggle, not a radio.
      await tester.tap(find.text('MIHON'));
      await _settle(tester);
      expect(repo.previewed.last.filters.sourceApps, isEmpty);
    });

    testWidgets('a source chip selects that source', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      await tester.tap(find.text('Custom selection'));
      await _settle(tester);
      await tester.tap(find.text('MANGADEX'));
      await _settle(tester);

      expect(repo.previewed.last.filters.sourceIds, {'1234'});
      expect(repo.previewed.last.mode, ExportMode.filter);
    });

    testWidgets('walks Select → Options → Review and back', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('INCLUDE IN THE BACKUP'), findsOneWidget);
      expect(find.text('Reading progress'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('READY TO CREATE'), findsOneWidget);
      expect(find.text('Create backup'), findsOneWidget);
      expect(find.text('mangavault_2026-08-06_12-00.tachibk'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await _settle(tester);
      expect(find.text('INCLUDE IN THE BACKUP'), findsOneWidget);
    });

    testWidgets('turning off chapters disables the progress switch',
        (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      await tester.tap(find.text('Chapters'));
      await _settle(tester);

      expect(repo.previewed.last.includes.chapters, isFalse);
      expect(find.text('Needs chapters — progress lives on them.'),
          findsOneWidget);
      // Inert, not merely dimmed.
      final progress = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Reading progress'),
      );
      expect(progress.onChanged, isNull);
      expect(progress.value, isFalse);
    });

    testWidgets('a partial scope is called out on review', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);
      await tester.tap(find.text('Tracker links'));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      expect(find.text('This is a partial backup'), findsOneWidget);
      expect(
        find.textContaining('will not contain tracker links'),
        findsOneWidget,
      );
      expect(find.text('Excluded'), findsOneWidget);
    });

    testWidgets('the target app changes the file name', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository();
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      await tester.tap(find.text('KOMIKKU'));
      await _settle(tester);

      expect(repo.previewed.last.targetApp, 'app.komikku');
      expect(
        find.text('app.komikku_2026-08-06_12-00.tachibk'),
        findsOneWidget,
      );
    });

    testWidgets('an empty scope blocks Next and says so', (tester) async {
      _phoneViewport(tester);
      final repo = FakeExportRepository(previewTitles: 0);
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      expect(find.text('Nothing matches this selection'), findsOneWidget);
      final next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);
    });

  });

  group('ExportController', () {
    /// Drives the controller directly: the debounce is a timing property, and
    /// pumping a widget tree to observe it would measure the pump, not the
    /// debounce.
    Future<(ExportController, FakeExportRepository)> boot() async {
      final repo = FakeExportRepository();
      final container = ProviderContainer(
        overrides: [exportRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final controller = container.read(exportControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (controller, repo);
    }

    test('previews the default scope on open', () async {
      final (_, repo) = await boot();
      expect(repo.previewed, hasLength(1));
      expect(repo.previewed.single.mode, ExportMode.all);
    });

    test('collapses a burst of edits into one preview', () async {
      final (controller, repo) = await boot();
      final before = repo.previewed.length;

      controller.toggleApp('app.mihon');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.toggleApp('app.komikku');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.toggleSource('1234');
      await Future<void>.delayed(const Duration(milliseconds: 450));

      // Three edits, one request — carrying all three selections.
      expect(repo.previewed.length - before, 1);
      expect(
        repo.previewed.last.filters.sourceApps,
        {'app.mihon', 'app.komikku'},
      );
      expect(repo.previewed.last.filters.sourceIds, {'1234'});
      expect(repo.previewed.last.mode, ExportMode.filter);
    });

    test('touching a facet switches out of the Everything preset', () async {
      final (controller, repo) = await boot();
      expect(repo.previewed.last.mode, ExportMode.all);

      controller.toggleCategory('c1');
      await Future<void>.delayed(const Duration(milliseconds: 450));

      // Otherwise the chip would be recorded but ignored by the server, which
      // drops filters entirely in `all` mode.
      expect(repo.previewed.last.mode, ExportMode.filter);
      expect(repo.previewed.last.filters.categoryIds, {'c1'});
    });

    test('clearing filters keeps the scope in filter mode', () async {
      final (controller, repo) = await boot();
      controller.toggleApp('app.mihon');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      controller.clearFilters();
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(repo.previewed.last.filters.isEmpty, isTrue);
      expect(repo.previewed.last.mode, ExportMode.filter);
    });

    test('reset returns to the default scope and re-previews', () async {
      final (controller, repo) = await boot();
      controller.applyFavoritesPreset();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(controller.state.scope.filters.favorite, isTrue);

      controller.reset();
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(controller.state.scope.mode, ExportMode.all);
      expect(controller.state.step, ExportStep.select);
      expect(repo.previewed.last.mode, ExportMode.all);
    });
  });
}
