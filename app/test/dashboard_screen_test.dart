import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/stats/stats_models.dart';
import 'package:mangavault/data/stats/stats_repository.dart';
import 'package:mangavault/features/dashboard/dashboard_screen.dart';
import 'package:mangavault/theme/app_theme.dart';

/// Stats repo returning a fixed snapshot (or throwing, for the error state).
class FakeStatsRepository extends StatsRepository {
  FakeStatsRepository({
    required this.stats,
    this.health = const [],
    this.resume = const [],
    this.recent = const [],
    this.fails = false,
  }) : super(Dio());

  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> health;
  final List<Map<String, dynamic>> resume;
  final List<Map<String, dynamic>> recent;
  final bool fails;

  @override
  Future<LibraryStats> libraryStats() async {
    if (fails) throw Exception('offline');
    return LibraryStats.fromJson(stats);
  }

  @override
  Future<List<BackupHealth>> backupHealth() async {
    if (fails) throw Exception('offline');
    return health.map(BackupHealth.fromJson).toList();
  }

  @override
  Future<List<ResumeItem>> resumeReading({int limit = 10}) async {
    if (fails) throw Exception('offline');
    return resume.map(ResumeItem.fromJson).toList();
  }

  @override
  Future<List<MangaListItem>> recentlyAdded({int limit = 10}) async {
    if (fails) throw Exception('offline');
    return recent.map(MangaListItem.fromJson).toList();
  }
}

Map<String, dynamic> _stats() => {
      'totalTitles': 1228,
      'favoriteTitles': 1200,
      'totalChapters': 124000,
      'readChapters': 31000,
      'addedLast7Days': 12,
      'sourceCount': 7,
      'bySourceApp': {'app.mihon': 1228},
      'byStatus': {'ongoing': 900, 'completed': 328},
      'coversArchived': 614,
      'coversFailed': 3,
      'importCount': 2,
      'lastImportAt': DateTime.now().millisecondsSinceEpoch,
      'vaultSizeBytes': 3221225472,
    };

Future<void> _pumpDashboard(
  WidgetTester tester,
  FakeStatsRepository repo, {
  double textScale = 1.0,
}) async {
  // Tall surface so the lazily-built cells are all laid out.
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Set the scale on the dispatcher, not in a MediaQuery above MaterialApp —
  // MaterialApp installs its own MediaQuery.fromView and would override it.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(ProviderScope(
    overrides: [statsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: buildAppTheme(), home: const DashboardScreen()),
  ));
  await tester.pump(); // resolve the snapshot future
  await tester.pump(const Duration(seconds: 2)); // finish the stagger
}

void main() {
  testWidgets('dashboard renders real figures from the stats API',
      (tester) async {
    final repo = FakeStatsRepository(
      stats: _stats(),
      health: [
        {
          'sourceApp': 'app.mihon',
          'lastImportAt': DateTime.now().millisecondsSinceEpoch,
          'importCount': 2,
          'titleCount': 1228,
          'staleness': 'fresh',
        },
      ],
      resume: [
        {
          'id': 'm1',
          'title': 'Vagabond',
          'status': 'ongoing',
          'coverState': 'none',
          'chapterCount': 327,
          'unreadCount': 27,
          'readCount': 300,
          'nextChapter': {'name': 'Chapter 301', 'number': 301},
        },
      ],
      recent: [
        {
          'id': 'm2',
          'title': 'Blame!',
          'status': 'completed',
          'coverState': 'none',
          'chapterCount': 65,
          'unreadCount': 65,
        },
      ],
    );

    await _pumpDashboard(tester, repo);

    // Hero cell: grouped total + this week's additions.
    expect(find.text('1,228'), findsOneWidget);
    expect(find.text('+12 added this week'), findsOneWidget);
    // Paired stat cells.
    expect(find.text('124,000'), findsOneWidget);
    expect(find.text('3 failed'), findsOneWidget);
    // Reading progress ring (31,000 / 124,000).
    expect(find.text('25%'), findsOneWidget);
    // Backup health row.
    expect(find.text('app.mihon'), findsOneWidget);
    expect(find.text('FRESH'), findsOneWidget);
    // Shelves.
    expect(find.text('Vagabond'), findsOneWidget);
    expect(find.text('Ch. 301'), findsOneWidget);
    expect(find.text('Blame!'), findsOneWidget);
    // Vault footprint.
    expect(find.text('3.0 GB'), findsOneWidget);
  });

  testWidgets('shelf tiles fit an enlarged system font', (tester) async {
    final repo = FakeStatsRepository(
      stats: _stats(),
      resume: [
        {
          'id': 'm1',
          // A long title forces the two-line block, the tight case.
          'title': 'Ane ga Kensei de Imouto ga Kenja de Ore wa Nanimonai',
          'status': 'ongoing',
          'coverState': 'none',
          'chapterCount': 18,
          'unreadCount': 1,
          'readCount': 17,
          'nextChapter': {'name': 'Chapter 0.1', 'number': 0.10000000149011612},
        },
      ],
      recent: [
        {
          'id': 'm2',
          'title': 'Peaceful Camping Life in Another World',
          'status': 'ongoing',
          'coverState': 'none',
          'chapterCount': 105,
          'unreadCount': 105,
        },
      ],
    );

    // The shelf height used to be a constant, which overflowed by 2px once the
    // device font scale pushed the text blocks past it.
    await _pumpDashboard(tester, repo, textScale: 1.3);

    expect(find.text('Ch. 0.1'), findsOneWidget);
    // The scale reached the tree: the caption block is 16px tall at scale 1.0.
    final caption = tester.getRect(find.text('Ch. 0.1'));
    expect(caption.height, greaterThan(16));

    // The tile's last line has to sit inside the shelf's fixed-height box.
    // A RenderFlex overflow here is only reported on a real device, so assert
    // the geometry rather than relying on takeException.
    final shelves = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    final shelf = tester.getRect(find.byWidget(shelves.first));
    expect(caption.bottom, lessThanOrEqualTo(shelf.bottom));
  });

  testWidgets('an empty archive invites the first import', (tester) async {
    final repo = FakeStatsRepository(stats: const {});

    await _pumpDashboard(tester, repo);

    expect(find.text('YOUR VAULT IS EMPTY'), findsOneWidget);
    expect(find.text('Import a backup'), findsOneWidget);
    // No stat cells while there is nothing to count.
    expect(find.text('Reading progress'.toUpperCase()), findsNothing);
  });

  testWidgets('a failed snapshot offers a retry', (tester) async {
    final repo = FakeStatsRepository(stats: const {}, fails: true);

    await _pumpDashboard(tester, repo);

    expect(find.text("Couldn't load your archive stats"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
