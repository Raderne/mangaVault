import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/backup_apps/backup_app_models.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/data/local/local_library_dao.dart';
import 'package:mangavault/data/sync/library_sync_service.dart';
import 'package:mangavault/data/sync/sync_models.dart';
import 'package:mangavault/data/sync/sync_repository.dart';

SyncManga _manga(
  String id, {
  String? title,
  String version = '1',
  int chapterCount = 0,
  int readCount = 0,
  List<String> categoryIds = const [],
  List<String> importIds = const [],
}) =>
    SyncManga(
      id: id,
      rowVersion: version,
      sourceId: 'src',
      sourceName: 'Source',
      title: title ?? 'Title $id',
      author: 'Author $id',
      artist: null,
      description: null,
      genres: const ['Action'],
      status: 'ongoing',
      thumbnailUrl: null,
      coverPath: null,
      coverState: 'none',
      notes: '',
      favorite: true,
      dateAdded: 0,
      updatedAt: 0,
      chapterCount: chapterCount,
      readCount: readCount,
      unreadCount: chapterCount - readCount,
      lastReadAt: null,
      lastReadChapter: null,
      nextChapter: null,
      categoryIds: categoryIds,
      importIds: importIds,
    );

SyncPage _page({
  List<SyncManga> changed = const [],
  List<String> deleted = const [],
  required String cursor,
  bool hasMore = false,
  String epoch = 'epoch-1',
}) =>
    SyncPage(
      changed: changed,
      deleted: deleted,
      cursor: cursor,
      hasMore: hasMore,
      serverEpoch: epoch,
    );

/// Serves scripted pages and records what was requested.
class FakeSyncRepository implements SyncRepository {
  FakeSyncRepository({
    required this.pages,
    this.epoch = 'epoch-1',
    this.categories = const [],
    this.imports = const [],
    this.backupApps = const [],
    this.totalTitles = 0,
    this.vaultSizeBytes = 0,
    this.failOnPage,
    this.metaCursor = '999999',
  });

  /// High-water mark reported by `/sync/meta`. Defaults high so it never trips
  /// the "cursor ahead of server" resync guard except where a test intends to.
  final String metaCursor;

  /// Pages keyed by the `since` cursor they answer.
  final Map<String, SyncPage> pages;
  final String epoch;
  final List<Category> categories;
  final List<SyncImportRecord> imports;
  final List<BackupApp> backupApps;
  final int totalTitles;
  final int vaultSizeBytes;

  /// Cursor whose request should throw, to exercise partial-sync recovery.
  final String? failOnPage;

  final List<String> requested = [];
  int metaCalls = 0;

  @override
  Future<SyncPage> changesSince(String since, {int limit = 500}) async {
    requested.add(since);
    if (since == failOnPage) throw Exception('network down');
    return pages[since] ?? _page(cursor: since, epoch: epoch);
  }

  @override
  Future<SyncMetaSnapshot> meta() async {
    metaCalls++;
    return SyncMetaSnapshot(
      serverEpoch: epoch,
      cursor: metaCursor,
      totalTitles: totalTitles,
      categories: categories,
      imports: imports,
      backupApps: backupApps,
      vaultSizeBytes: vaultSizeBytes,
    );
  }
}

void main() {
  late AppDatabase db;
  late LocalLibraryDao dao;

  setUp(() {
    db = AppDatabase.memory();
    dao = LocalLibraryDao(db);
  });

  tearDown(() => db.close());

  LibrarySyncService serviceWith(FakeSyncRepository repo) =>
      LibrarySyncService(repo, db);

  test('a full sync walks every page and stores the titles', () async {
    final repo = FakeSyncRepository(
      totalTitles: 3,
      vaultSizeBytes: 999,
      pages: {
        '0': _page(
          changed: [_manga('a', version: '1'), _manga('b', version: '2')],
          cursor: '2',
          hasMore: true,
        ),
        '2': _page(changed: [_manga('c', version: '3')], cursor: '3'),
      },
    );

    final written = await serviceWith(repo).sync();

    expect(written, 3);
    expect(repo.requested, ['0', '2']);
    final page = await dao.queryPage();
    expect(page.total, 3);
    expect(page.items.map((i) => i.id).toSet(), {'a', 'b', 'c'});

    final state = await db.syncStateRow();
    expect(state!.cursor, '3');
    expect(state.serverEpoch, 'epoch-1');
    expect(state.vaultSizeBytes, 999);
    expect(state.lastSyncedAt, isNotNull);
  });

  test('a second sync resumes from the stored cursor', () async {
    final first = FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a', version: '5')], cursor: '5')},
    );
    await serviceWith(first).sync();

    final second = FakeSyncRepository(
      pages: {
        '5': _page(
          changed: [_manga('b', version: '6')],
          cursor: '6',
        ),
      },
    );
    final written = await serviceWith(second).sync();

    expect(second.requested, ['5']);
    expect(written, 1);
    expect((await dao.queryPage()).total, 2);
  });

  test('an updated title replaces its row rather than duplicating it',
      () async {
    await serviceWith(FakeSyncRepository(
      pages: {
        '0': _page(
          changed: [_manga('a', title: 'Old Title', chapterCount: 2)],
          cursor: '1',
        ),
      },
    )).sync();

    await serviceWith(FakeSyncRepository(
      pages: {
        '1': _page(
          changed: [
            _manga('a',
                title: 'New Title',
                version: '9',
                chapterCount: 5,
                readCount: 5),
          ],
          cursor: '9',
        ),
      },
    )).sync();

    final page = await dao.queryPage();
    expect(page.total, 1);
    expect(page.items.single.title, 'New Title');
    expect(page.items.single.chapterCount, 5);
    expect(page.items.single.unreadCount, 0);
  });

  test('a tombstone removes the title and its junction rows', () async {
    await serviceWith(FakeSyncRepository(
      categories: const [Category(id: 'c1', name: 'Seinen', sort: 0, count: 1)],
      pages: {
        '0': _page(
          changed: [_manga('a', categoryIds: ['c1'], importIds: ['i1'])],
          cursor: '1',
        ),
      },
    )).sync();
    expect((await dao.queryPage()).total, 1);

    await serviceWith(FakeSyncRepository(
      pages: {'1': _page(deleted: ['a'], cursor: '2')},
    )).sync();

    expect((await dao.queryPage()).total, 0);
    // The junction rows must go too, or category counts drift upward forever.
    final cats = await dao.categories();
    expect(cats.where((c) => c.id == 'c1').fold(0, (n, c) => n + c.count), 0);
  });

  test('dropping a category membership is reflected locally', () async {
    await serviceWith(FakeSyncRepository(
      categories: const [Category(id: 'c1', name: 'Seinen', sort: 0, count: 1)],
      pages: {
        '0': _page(changed: [_manga('a', categoryIds: ['c1'])], cursor: '1'),
      },
    )).sync();
    expect((await dao.queryPage(categoryIds: ['c1'])).total, 1);

    // Same title re-sent with no categories: membership must disappear.
    await serviceWith(FakeSyncRepository(
      categories: const [Category(id: 'c1', name: 'Seinen', sort: 0, count: 0)],
      pages: {
        '1': _page(changed: [_manga('a', version: '2')], cursor: '2'),
      },
    )).sync();

    expect((await dao.queryPage(categoryIds: ['c1'])).total, 0);
  });

  test('a changed server epoch wipes the mirror and re-pulls', () async {
    await serviceWith(FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a'), _manga('b')], cursor: '2')},
    )).sync();
    expect((await dao.queryPage()).total, 2);

    // Postgres restored from a dump: versions rewound, so the stored cursor is
    // meaningless and stale rows must not survive.
    final restored = FakeSyncRepository(
      epoch: 'epoch-2',
      pages: {
        '0': _page(changed: [_manga('z')], cursor: '1', epoch: 'epoch-2'),
      },
    );
    await serviceWith(restored).sync();

    expect(restored.requested.first, '0');
    final page = await dao.queryPage();
    expect(page.total, 1);
    expect(page.items.single.id, 'z');
    expect((await db.syncStateRow())!.serverEpoch, 'epoch-2');
  });

  test('a cursor ahead of the server forces a full resync', () async {
    await serviceWith(FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a'), _manga('b')], cursor: '900')},
    )).sync();
    expect((await db.syncStateRow())!.cursor, '900');

    // Restored from a dump: row_version rewound but server_epoch survived the
    // restore, so only the cursor comparison can detect it.
    final restored = FakeSyncRepository(
      metaCursor: '10',
      pages: {'0': _page(changed: [_manga('z')], cursor: '10')},
    );
    await serviceWith(restored).sync();

    expect(restored.requested, ['0']);
    final page = await dao.queryPage();
    expect(page.total, 1);
    expect(page.items.single.id, 'z');
  });

  test('force re-pulls from scratch even when the epoch matches', () async {
    await serviceWith(FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a')], cursor: '1')},
    )).sync();

    final forced = FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a'), _manga('b')], cursor: '2')},
    );
    await serviceWith(forced).sync(force: true);

    expect(forced.requested, ['0']);
    expect((await dao.queryPage()).total, 2);
  });

  test('a failed sync leaves the previous library intact', () async {
    await serviceWith(FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a'), _manga('b')], cursor: '2')},
    )).sync();

    final failing = FakeSyncRepository(failOnPage: '2', pages: const {});
    await expectLater(serviceWith(failing).sync(), throwsException);

    // Still readable, still at the old cursor — an unreachable server degrades
    // to stale data rather than an empty screen.
    expect((await dao.queryPage()).total, 2);
    expect((await db.syncStateRow())!.cursor, '2');
  });

  test('a full resync that fails on its first page keeps the old data',
      () async {
    await serviceWith(FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a')], cursor: '1')},
    )).sync();

    // force starts from 0 and would wipe — but the wipe only happens inside the
    // first successful page's transaction.
    final failing = FakeSyncRepository(failOnPage: '0', pages: const {});
    await expectLater(serviceWith(failing).sync(force: true), throwsException);

    expect((await dao.queryPage()).total, 1);
  });

  test('a partially applied sync resumes from the last committed page',
      () async {
    final flaky = FakeSyncRepository(
      pages: {
        '0': _page(changed: [_manga('a', version: '1')], cursor: '1', hasMore: true),
      },
      failOnPage: '1',
    );
    await expectLater(serviceWith(flaky).sync(), throwsException);

    // Page one committed before the failure, so its cursor survived.
    expect((await dao.queryPage()).total, 1);
    expect((await db.syncStateRow())!.cursor, '1');

    final resumed = FakeSyncRepository(
      pages: {'1': _page(changed: [_manga('b', version: '2')], cursor: '2')},
    );
    await serviceWith(resumed).sync();

    expect(resumed.requested, ['1']);
    expect((await dao.queryPage()).total, 2);
  });

  test('categories and imports are replaced wholesale', () async {
    await serviceWith(FakeSyncRepository(
      categories: const [
        Category(id: 'c1', name: 'Seinen', sort: 0, count: 0),
        Category(id: 'c2', name: 'Shonen', sort: 1, count: 0),
      ],
      imports: [
        SyncImportRecord(
          id: 'i1',
          fileName: 'a.tachibk',
          fileSize: 10,
          sha256: 'sha',
          sourceApp: 'app.mihon',
          container: 'gzip-proto',
          importedAt: 100,
          stats: const {'titlesNew': 3, 'titlesMerged': 1},
        ),
      ],
      pages: {'0': _page(cursor: '0')},
    )).sync();

    expect((await dao.categories()).map((c) => c.name), ['Seinen', 'Shonen']);
    final history = await dao.importHistory();
    expect(history.single.fileName, 'a.tachibk');
    expect(history.single.stats.titlesNew, 3);
    expect(history.single.stats.titlesMerged, 1);

    // A later sync where one category is gone must drop it locally.
    await serviceWith(FakeSyncRepository(
      categories: const [Category(id: 'c1', name: 'Seinen', sort: 0, count: 0)],
      pages: {'0': _page(cursor: '0')},
    )).sync();

    expect((await dao.categories()).map((c) => c.name), ['Seinen']);
  });

  test('the backup-app registry is mirrored and replaced wholesale', () async {
    // Names live only in the registry; without it every filter chip and history
    // row would have to read `app.mihon` instead of "Mihon" while offline.
    await serviceWith(FakeSyncRepository(
      backupApps: const [
        BackupApp(id: 'app.mihon', displayName: 'Mihon', curated: true),
        BackupApp(id: 'my.reader', displayName: 'My Reader'),
      ],
      pages: {'0': _page(cursor: '0')},
    )).sync();

    expect(await dao.backupAppNames(),
        {'app.mihon': 'Mihon', 'my.reader': 'My Reader'});

    await serviceWith(FakeSyncRepository(
      backupApps: const [
        BackupApp(id: 'app.mihon', displayName: 'Mihon', curated: true),
      ],
      pages: {'0': _page(cursor: '0')},
    )).sync();

    expect(await dao.backupAppNames(), {'app.mihon': 'Mihon'});
  });

  test('a concurrent sync joins the running one instead of double-pulling',
      () async {
    final repo = FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a')], cursor: '1')},
    );
    final service = serviceWith(repo);

    final results = await Future.wait([service.sync(), service.sync()]);

    expect(results, [1, 1]);
    expect(repo.metaCalls, 1);
    expect(repo.requested, ['0']);
  });

  test('ensureBootstrapped only syncs when the mirror is empty', () async {
    final first = FakeSyncRepository(
      pages: {'0': _page(changed: [_manga('a')], cursor: '1')},
    );
    expect(await serviceWith(first).ensureBootstrapped(), 1);

    final second = FakeSyncRepository(pages: const {});
    expect(await serviceWith(second).ensureBootstrapped(), 0);
    expect(second.metaCalls, 0);
  });
}
