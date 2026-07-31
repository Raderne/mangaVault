import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/data/local/local_library_dao.dart';
import 'package:mangavault/data/stats/stats_models.dart';

/// Insert a title with just the fields a test cares about.
Future<void> seed(
  AppDatabase db, {
  required String id,
  required String title,
  String status = 'ongoing',
  String sourceId = 'src-1',
  String sourceName = 'Source One',
  String? author,
  bool favorite = true,
  int dateAdded = 0,
  int chapterCount = 0,
  int readCount = 0,
  int? lastReadAt,
  String coverState = 'none',
  String? nextChapterName,
  double? nextChapterNumber,
  String genresJson = '[]',
}) async {
  await db.into(db.localManga).insert(
        LocalMangaCompanion.insert(
          id: id,
          rowVersion: '1',
          sourceId: sourceId,
          title: title,
          titleLower: title.toLowerCase(),
          authorLower: Value((author ?? '').toLowerCase()),
          sourceName: Value(sourceName),
          author: Value(author),
          status: Value(status),
          favorite: Value(favorite),
          dateAdded: Value(dateAdded),
          chapterCount: Value(chapterCount),
          readCount: Value(readCount),
          unreadCount: Value(chapterCount - readCount),
          lastReadAt: Value(lastReadAt),
          coverState: Value(coverState),
          nextChapterName: Value(nextChapterName),
          nextChapterNumber: Value(nextChapterNumber),
          genresJson: Value(genresJson),
        ),
      );
}

void main() {
  late AppDatabase db;
  late LocalLibraryDao dao;

  setUp(() async {
    db = AppDatabase.memory();
    dao = LocalLibraryDao(db);
    // The singleton meta row is created by the migration strategy.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  group('queryPage', () {
    setUp(() async {
      await seed(db,
          id: 'a',
          title: 'Alpha Archivist',
          author: 'Author One',
          chapterCount: 3,
          readCount: 2,
          lastReadAt: 500,
          dateAdded: 100);
      await seed(db,
          id: 'b',
          title: 'Beta Compendium',
          status: 'completed',
          author: 'Author Two',
          chapterCount: 5,
          dateAdded: 300);
      await seed(db,
          id: 'c',
          title: 'Gamma Chronicle',
          status: 'on_hiatus',
          favorite: false,
          dateAdded: 200);
    });

    test('paginates with a total covering the whole match', () async {
      final p = await dao.queryPage(limit: 2);
      expect(p.total, 3);
      expect(p.items.map((i) => i.title),
          ['Alpha Archivist', 'Beta Compendium']);

      final p2 = await dao.queryPage(limit: 2, offset: 2);
      expect(p2.total, 3);
      expect(p2.items.map((i) => i.title), ['Gamma Chronicle']);
    });

    test('filters by status', () async {
      final p = await dao.queryPage(status: ['completed']);
      expect(p.total, 1);
      expect(p.items.single.title, 'Beta Compendium');
    });

    test('filters by favorite', () async {
      expect((await dao.queryPage(favorite: true)).total, 2);
      final others = await dao.queryPage(favorite: false);
      expect(others.items.single.title, 'Gamma Chronicle');
    });

    test('filters by source', () async {
      await seed(db, id: 'd', title: 'Delta', sourceId: 'src-2');
      final p = await dao.queryPage(sourceIds: ['src-2']);
      expect(p.items.single.title, 'Delta');
    });

    test('searches title and author, case-insensitively', () async {
      expect((await dao.queryPage(text: 'beta')).items.single.title,
          'Beta Compendium');
      expect((await dao.queryPage(text: 'AUTHOR ONE')).items.single.title,
          'Alpha Archivist');
      expect((await dao.queryPage(text: 'nothing here')).total, 0);
    });

    test('treats LIKE wildcards in the search term literally', () async {
      await seed(db, id: 'w', title: '100% Perfect');
      // A bare '%' must not match every row.
      final p = await dao.queryPage(text: '%');
      expect(p.items.map((i) => i.title), ['100% Perfect']);
    });

    test('sorts by each supported field', () async {
      Future<List<String>> titles(String by, String dir) async =>
          (await dao.queryPage(sortBy: by, sortDir: dir))
              .items
              .map((i) => i.title)
              .toList();

      expect(await titles('title', 'asc'),
          ['Alpha Archivist', 'Beta Compendium', 'Gamma Chronicle']);
      expect(await titles('title', 'desc'),
          ['Gamma Chronicle', 'Beta Compendium', 'Alpha Archivist']);
      expect((await titles('dateAdded', 'desc')).first, 'Beta Compendium');
      expect((await titles('chapterCount', 'desc')).first, 'Beta Compendium');
      expect((await titles('unreadCount', 'desc')).first, 'Beta Compendium');
    });

    test('sorts nulls last regardless of direction', () async {
      // Only Alpha has a lastReadAt; the other two must never outrank it.
      expect((await dao.queryPage(sortBy: 'lastReadAt', sortDir: 'desc'))
          .items
          .first
          .title,
          'Alpha Archivist');
      expect((await dao.queryPage(sortBy: 'lastReadAt', sortDir: 'asc'))
          .items
          .first
          .title,
          'Alpha Archivist');
    });

    test('filters by category', () async {
      await db.into(db.localCategory).insert(
            LocalCategoryCompanion.insert(id: 'cat-1', name: 'Seinen'),
          );
      await db.into(db.localMangaCategory).insert(
            LocalMangaCategoryCompanion.insert(
                mangaId: 'b', categoryId: 'cat-1'),
          );
      final p = await dao.queryPage(categoryIds: ['cat-1']);
      expect(p.items.single.title, 'Beta Compendium');
    });
  });

  group('get', () {
    test('returns the record with categories and archive history', () async {
      await seed(db,
          id: 'a',
          title: 'Alpha',
          author: 'Writer',
          chapterCount: 4,
          readCount: 1,
          genresJson: '["Action","Drama"]',
          nextChapterName: 'Chapter 2',
          nextChapterNumber: 2);
      await db.into(db.localCategory).insert(
            LocalCategoryCompanion.insert(id: 'c1', name: 'Seinen'),
          );
      await db.into(db.localMangaCategory).insert(
            LocalMangaCategoryCompanion.insert(mangaId: 'a', categoryId: 'c1'),
          );
      await db.into(db.localImportRecord).insert(
            LocalImportRecordCompanion.insert(
              id: 'i1',
              fileName: 'app.mihon_2026.tachibk',
              sourceApp: const Value('app.mihon'),
              container: const Value('gzip-proto'),
              importedAt: const Value(999),
            ),
          );
      await db.into(db.localMangaImport).insert(
            LocalMangaImportCompanion.insert(mangaId: 'a', importId: 'i1'),
          );

      final m = await dao.get('a');
      expect(m.title, 'Alpha');
      expect(m.genres, ['Action', 'Drama']);
      expect(m.readFraction, closeTo(0.25, 1e-9));
      expect(m.nextChapter?.name, 'Chapter 2');
      expect(m.categories.single.name, 'Seinen');
      expect(m.archive.single.sourceApp, 'app.mihon');
    });

    test('throws for an unknown id', () async {
      expect(() => dao.get('missing'), throwsStateError);
    });

    test('survives a malformed genres payload', () async {
      await seed(db, id: 'a', title: 'Alpha', genresJson: 'not json');
      expect((await dao.get('a')).genres, isEmpty);
    });
  });

  test('categories carry title counts', () async {
    await seed(db, id: 'a', title: 'Alpha');
    await db.into(db.localCategory).insert(
          LocalCategoryCompanion.insert(id: 'c1', name: 'Seinen', sort: const Value(1)),
        );
    await db.into(db.localCategory).insert(
          LocalCategoryCompanion.insert(id: 'c2', name: 'Empty', sort: const Value(2)),
        );
    await db.into(db.localMangaCategory).insert(
          LocalMangaCategoryCompanion.insert(mangaId: 'a', categoryId: 'c1'),
        );

    final cats = await dao.categories();
    expect(cats.map((c) => c.name), ['Seinen', 'Empty']);
    expect(cats.first.count, 1);
    expect(cats.last.count, 0);
  });

  group('sources', () {
    test('are grouped with counts, busiest first', () async {
      await seed(db, id: 'a', title: 'Alpha', sourceId: 's1', sourceName: 'MangaDex');
      await seed(db, id: 'b', title: 'Beta', sourceId: 's1', sourceName: 'MangaDex');
      await seed(db, id: 'c', title: 'Gamma', sourceId: 's2', sourceName: 'Comick');

      final sources = await dao.sources();
      expect(sources.map((s) => s.id), ['s1', 's2']);
      expect(sources.first.count, 2);
      expect(sources.last.label, 'Comick');
    });

    test('an unnamed source falls back to its id, and any name wins over ""',
        () async {
      // The same source recorded with and without a name across two backups.
      await seed(db, id: 'a', title: 'Alpha', sourceId: 's1', sourceName: '');
      await seed(db, id: 'b', title: 'Beta', sourceId: 's1', sourceName: 'Comick');
      await seed(db, id: 'c', title: 'Gamma', sourceId: '982606170401027267',
          sourceName: '');

      final byId = {for (final s in await dao.sources()) s.id: s};
      expect(byId['s1']!.label, 'Comick');
      expect(byId['982606170401027267']!.label, '982606170401027267');
    });
  });

  test('deleteTitles removes the row and its links', () async {
    await seed(db, id: 'a', title: 'Alpha');
    await seed(db, id: 'b', title: 'Beta');
    await db.into(db.localCategory).insert(
          LocalCategoryCompanion.insert(id: 'c1', name: 'Seinen'),
        );
    await db.into(db.localMangaCategory).insert(
          LocalMangaCategoryCompanion.insert(mangaId: 'a', categoryId: 'c1'),
        );

    await dao.deleteTitles(['a']);

    expect((await dao.queryPage()).items.map((i) => i.id), ['b']);
    expect(await dao.categories().then((c) => c.first.count), 0);
    // Idempotent: the tombstone for the same id arrives on the next sync.
    await dao.deleteTitles(['a']);
    expect((await dao.queryPage()).total, 1);
  });

  group('dashboard aggregates', () {
    setUp(() async {
      await seed(db,
          id: 'a',
          title: 'Alpha',
          chapterCount: 10,
          readCount: 4,
          coverState: 'archived',
          dateAdded: 1000,
          lastReadAt: 50,
          nextChapterName: 'Ch 5',
          nextChapterNumber: 5);
      await seed(db,
          id: 'b',
          title: 'Beta',
          status: 'completed',
          sourceId: 'src-2',
          chapterCount: 6,
          readCount: 6,
          coverState: 'failed',
          favorite: false,
          dateAdded: 2000);
      await db.into(db.localImportRecord).insert(
            LocalImportRecordCompanion.insert(
              id: 'i1',
              fileName: 'f.tachibk',
              sourceApp: const Value('app.mihon'),
              importedAt: const Value(5000),
            ),
          );
      await db.into(db.localMangaImport).insert(
            LocalMangaImportCompanion.insert(mangaId: 'a', importId: 'i1'),
          );
    });

    test('libraryStats sums the mirrored counters', () async {
      final s = await dao.libraryStats(now: 3000);
      expect(s.totalTitles, 2);
      expect(s.favoriteTitles, 1);
      expect(s.totalChapters, 16);
      expect(s.readChapters, 10);
      expect(s.sourceCount, 2);
      expect(s.coversArchived, 1);
      expect(s.coversFailed, 1);
      expect(s.importCount, 1);
      expect(s.lastImportAt, 5000);
      expect(s.bySourceApp, {'app.mihon': 1});
      // Dense status map: every band present.
      expect(s.byStatus.keys.toSet(), kPublicationStatuses.toSet());
      expect(s.byStatus['ongoing'], 1);
      expect(s.byStatus['completed'], 1);
      expect(s.byStatus['licensed'], 0);
      // Only 'b' was added within the 7-day window ending at now=3000.
      expect(s.addedLast7Days, 2);
    });

    test('vaultSizeBytes comes from the synced meta row', () async {
      expect((await dao.libraryStats()).vaultSizeBytes, 0);
      await db.update(db.syncMeta).write(
            const SyncMetaCompanion(vaultSizeBytes: Value(4242)),
          );
      expect((await dao.libraryStats()).vaultSizeBytes, 4242);
    });

    test('backupHealth grades staleness per source app', () async {
      final health = await dao.backupHealth(now: 5000 + 10 * 86400000);
      expect(health.single.sourceApp, 'app.mihon');
      expect(health.single.titleCount, 1);
      expect(health.single.staleness, Staleness.fresh);

      final old = await dao.backupHealth(now: 5000 + 200 * 86400000);
      expect(old.single.staleness, Staleness.stale);
    });

    test('recentlyAdded is newest first', () async {
      final items = await dao.recentlyAdded(10);
      expect(items.map((i) => i.title), ['Beta', 'Alpha']);
    });

    test('resumeReading only offers titles with a next chapter', () async {
      final items = await dao.resumeReading(10);
      expect(items.single.manga.title, 'Alpha');
      expect(items.single.nextChapter.name, 'Ch 5');
      expect(items.single.readFraction, closeTo(0.4, 1e-9));
    });
  });

  test('watchRevision emits distinct revisions as sync commits', () async {
    final seen = <int>[];
    final sub = dao.watchRevision().listen(seen.add);
    await Future<void>.delayed(Duration.zero);

    await db.update(db.syncMeta).write(
          const SyncMetaCompanion(localRevision: Value(1)),
        );
    await Future<void>.delayed(Duration.zero);
    await db.update(db.syncMeta).write(
          const SyncMetaCompanion(localRevision: Value(2)),
        );
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();
    expect(seen, [0, 1, 2]);
  });
}
