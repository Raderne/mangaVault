import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/features/library/library_screen.dart';
import 'package:mangavault/features/title_details/title_details_screen.dart';
import 'package:mangavault/theme/app_theme.dart';

class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository({this.items = const [], this.manga}) : super(Dio());
  final List<MangaListItem> items;
  final VaultManga? manga;

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async =>
      LibraryPage(items: items, total: items.length, offset: 0, limit: limit);

  @override
  Future<VaultManga> get(String id) async => manga!;

  @override
  Future<List<Category>> categories() async => const [];
}

MangaListItem _item(String title) => MangaListItem(
      id: title,
      title: title,
      author: null,
      status: 'ongoing',
      coverPath: null,
      coverState: 'none',
      sourceName: 'MangaDex',
      sourceId: '1',
      chapterCount: 7,
      unreadCount: 2,
      lastReadAt: null,
    );

VaultManga _manga() => VaultManga.fromJson({
      'id': 'm1',
      'sourceName': 'MangaDex',
      'title': 'Alpha Archivist',
      'author': 'Author One',
      'description': 'A quiet tale of archives.',
      'genres': ['Action'],
      'status': 'ongoing',
      'coverState': 'none',
      'notes': '',
      'dateAdded': 1700000000000,
      'chapterCount': 10,
      'readCount': 4,
      'unreadCount': 6,
      'nextChapter': {'name': 'Chapter 5', 'number': 5},
      'categories': const [],
      'archive': [
        {
          'id': 'imp1',
          'fileName': 'app.mihon_x.tachibk',
          'sourceApp': 'app.mihon',
          'container': 'gzip-proto',
          'importedAt': 1700000000000,
        },
      ],
    });

void main() {
  testWidgets('library grid renders titles from the API', (tester) async {
    final repo = FakeLibraryRepository(items: [_item('Solo Leveling'), _item('Omniscient Reader')]);

    await tester.pumpWidget(ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: buildAppTheme(), home: const LibraryScreen()),
    ));
    await tester.pump(); // run initial fetch microtask
    await tester.pump(const Duration(milliseconds: 500)); // finish entrance

    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('Omniscient Reader'), findsOneWidget);
    // Total count chip.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('empty library shows the no-match state', (tester) async {
    final repo = FakeLibraryRepository(items: const []);

    await tester.pumpWidget(ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: buildAppTheme(), home: const LibraryScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No titles match'), findsOneWidget);
  });

  testWidgets('title details renders synopsis, progress and archive history',
      (tester) async {
    // Tall surface so the lazily-built detail cells are all laid out.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeLibraryRepository(manga: _manga());

    await tester.pumpWidget(ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const TitleDetailsScreen(titleId: 'm1'),
      ),
    ));
    await tester.pump(); // resolve details future
    await tester.pump(const Duration(milliseconds: 600)); // finish stagger

    expect(find.text('A quiet tale of archives.'), findsOneWidget);
    expect(find.text('4 / 10 read'), findsOneWidget);
    expect(find.textContaining('Chapter 5'), findsOneWidget);
    expect(find.text('app.mihon_x.tachibk'), findsOneWidget);
  });
}
