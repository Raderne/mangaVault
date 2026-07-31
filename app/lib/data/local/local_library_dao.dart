import 'dart:convert';

import 'package:drift/drift.dart';

import '../import/import_models.dart';
import '../library/library_models.dart';
import '../stats/stats_models.dart';
import 'app_database.dart';
import 'tables.dart';

part 'local_library_dao.g.dart';

const int _dayMs = 24 * 60 * 60 * 1000;
const int _freshMaxMs = 30 * _dayMs;
const int _agingMaxMs = 90 * _dayMs;

/// Mirrors the server's `staleness.ts` so the dashboard reads the same offline
/// as it does online.
Staleness stalenessFor(int? lastImportAt, int now) {
  if (lastImportAt == null || lastImportAt <= 0) return Staleness.stale;
  final age = now - lastImportAt;
  if (age < _freshMaxMs) return Staleness.fresh;
  if (age < _agingMaxMs) return Staleness.aging;
  return Staleness.stale;
}

/// Reads the on-device mirror.
///
/// Deliberately exposes the *same shapes* the HTTP repositories used to return
/// (`LibraryPage`, `VaultManga`, `LibraryStats`, …) so swapping the read path
/// to local is a provider rebind rather than a rewrite of the controllers.
@DriftAccessor(
  tables: [
    LocalManga,
    LocalCategory,
    LocalMangaCategory,
    LocalImportRecord,
    LocalMangaImport,
    SyncMeta,
  ],
)
class LocalLibraryDao extends DatabaseAccessor<AppDatabase>
    with _$LocalLibraryDaoMixin {
  LocalLibraryDao(super.db);

  // ---- library ----------------------------------------------------------

  /// A filtered, sorted, paginated slice of the mirror — the local counterpart
  /// of `GET /library`, with the identical parameter list.
  Future<LibraryPage> queryPage({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async {
    Expression<bool> where(_) => _predicate(
          text: text,
          status: status,
          categoryIds: categoryIds,
          sourceIds: sourceIds,
          favorite: favorite,
        );

    final countExp = localManga.id.count();
    final countQuery = selectOnly(localManga)
      ..addColumns([countExp])
      ..where(where(localManga));
    final total = await countQuery
        .map((row) => row.read(countExp) ?? 0)
        .getSingleOrNull();

    final query = select(localManga)
      ..where(where)
      ..orderBy(_ordering(sortBy, sortDir))
      ..limit(limit, offset: offset);
    final rows = await query.get();

    return LibraryPage(
      items: rows.map(_toListItem).toList(),
      total: total ?? 0,
      offset: offset,
      limit: limit,
    );
  }

  /// Full record for one title — the local counterpart of `GET /library/:id`.
  Future<VaultManga> get(String id) async {
    final row = await (select(localManga)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('title $id is not in the local library');
    }

    final categoryRows = await (select(localCategory).join([
      innerJoin(
        localMangaCategory,
        localMangaCategory.categoryId.equalsExp(localCategory.id),
      ),
    ])..where(localMangaCategory.mangaId.equals(id)))
        .get();
    final categories = categoryRows
        .map((r) => r.readTable(localCategory))
        .map((c) => CategoryRef(id: c.id, name: c.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final importRows = await (select(localImportRecord).join([
      innerJoin(
        localMangaImport,
        localMangaImport.importId.equalsExp(localImportRecord.id),
      ),
    ])..where(localMangaImport.mangaId.equals(id)))
        .get();
    final archive = importRows
        .map((r) => r.readTable(localImportRecord))
        .map((i) => ArchiveEntry(
              id: i.id,
              fileName: i.fileName,
              sourceApp: i.sourceApp,
              container: i.container,
              importedAt: i.importedAt,
            ))
        .toList()
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));

    return VaultManga(
      id: row.id,
      sourceId: row.sourceId,
      sourceName: row.sourceName,
      title: row.title,
      author: row.author,
      artist: row.artist,
      description: row.description,
      genres: decodeGenres(row.genresJson),
      status: row.status,
      coverPath: row.coverPath,
      coverState: row.coverState,
      notes: row.notes,
      dateAdded: row.dateAdded,
      chapterCount: row.chapterCount,
      readCount: row.readCount,
      unreadCount: row.unreadCount,
      lastReadChapter: _chapterRef(
        row.lastReadChapterName,
        row.lastReadChapterNumber,
      ),
      nextChapter: _chapterRef(row.nextChapterName, row.nextChapterNumber),
      categories: categories,
      archive: archive,
    );
  }

  /// Categories with their title counts — local `GET /categories`.
  Future<List<Category>> categories() async {
    final count = localMangaCategory.mangaId.count();
    final query = select(localCategory).join([
      leftOuterJoin(
        localMangaCategory,
        localMangaCategory.categoryId.equalsExp(localCategory.id),
      ),
    ])
      ..addColumns([count])
      ..groupBy([localCategory.id])
      ..orderBy([
        OrderingTerm.asc(localCategory.sort),
        OrderingTerm.asc(localCategory.name),
      ]);

    final rows = await query.get();
    return rows.map((r) {
      final c = r.readTable(localCategory);
      return Category(
        id: c.id,
        name: c.name,
        sort: c.sort,
        count: r.read(count) ?? 0,
      );
    }).toList();
  }

  /// Every source that has at least one title in the mirror, most titles first.
  ///
  /// The server's `known_source` table lists sources we've *seen*; this lists
  /// the ones you can actually filter by. `MAX(source_name)` because the name
  /// is denormalized onto each title and older backups may have left it blank —
  /// any non-empty spelling wins over `''`.
  Future<List<SourceOption>> sources() async {
    final rows = await customSelect(
      '''
      SELECT source_id            AS source_id,
             MAX(source_name)     AS source_name,
             COUNT(*)             AS n
        FROM local_manga
       GROUP BY source_id
       ORDER BY n DESC, source_name ASC
      ''',
      readsFrom: {localManga},
    ).get();

    return rows
        .map((r) => SourceOption(
              id: r.read<String>('source_id'),
              name: r.read<String?>('source_name') ?? '',
              count: r.read<int>('n'),
            ))
        .toList();
  }

  /// Drop titles from the mirror, with their category and import links.
  ///
  /// Called after the server confirms a delete, so the grid updates without
  /// waiting for the next delta. The tombstone still arrives later and deletes
  /// the same (already absent) rows — deliberately idempotent.
  Future<void> deleteTitles(List<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(localManga)..where((t) => t.id.isIn(ids))).go();
      await (delete(localMangaCategory)..where((t) => t.mangaId.isIn(ids))).go();
      await (delete(localMangaImport)..where((t) => t.mangaId.isIn(ids))).go();
    });
  }

  // ---- dashboard aggregates --------------------------------------------

  /// Every figure the dashboard shows except `vaultSizeBytes`, which is
  /// server-only and arrives via `/sync/meta` (stored in [SyncMeta]).
  Future<LibraryStats> libraryStats({int? now}) async {
    final nowMs = now ?? DateTime.now().millisecondsSinceEpoch;
    final weekAgo = nowMs - 7 * _dayMs;

    final totals = await customSelect(
      '''
      SELECT COUNT(*)                                            AS total_titles,
             COALESCE(SUM(CASE WHEN favorite THEN 1 ELSE 0 END), 0) AS favorite_titles,
             COALESCE(SUM(chapter_count), 0)                     AS total_chapters,
             COALESCE(SUM(read_count), 0)                        AS read_chapters,
             COALESCE(SUM(CASE WHEN date_added > ? THEN 1 ELSE 0 END), 0) AS added_recent,
             COUNT(DISTINCT source_id)                           AS source_count,
             COALESCE(SUM(CASE WHEN cover_state = 'archived' THEN 1 ELSE 0 END), 0) AS covers_archived,
             COALESCE(SUM(CASE WHEN cover_state = 'failed'   THEN 1 ELSE 0 END), 0) AS covers_failed
        FROM local_manga
      ''',
      variables: [Variable.withInt(weekAgo)],
      readsFrom: {localManga},
    ).getSingle();

    final statusRows = await customSelect(
      'SELECT status, COUNT(*) AS n FROM local_manga GROUP BY status',
      readsFrom: {localManga},
    ).get();

    final sourceAppRows = await customSelect(
      '''
      SELECT ir.source_app AS source_app, COUNT(DISTINCT mi.manga_id) AS n
        FROM local_import_record ir
        JOIN local_manga_import mi ON mi.import_id = ir.id
       GROUP BY ir.source_app
      ''',
      readsFrom: {localImportRecord, localMangaImport},
    ).get();

    final importAgg = await customSelect(
      'SELECT COUNT(*) AS n, MAX(imported_at) AS last_at FROM local_import_record',
      readsFrom: {localImportRecord},
    ).getSingle();

    final meta = await syncState();

    // Every status band is present (zeroed) so the UI never null-checks.
    final byStatus = <String, int>{
      for (final s in kPublicationStatuses) s: 0,
    };
    for (final r in statusRows) {
      byStatus[r.read<String>('status')] = r.read<int>('n');
    }

    return LibraryStats(
      totalTitles: totals.read<int>('total_titles'),
      favoriteTitles: totals.read<int>('favorite_titles'),
      totalChapters: totals.read<int>('total_chapters'),
      readChapters: totals.read<int>('read_chapters'),
      addedLast7Days: totals.read<int>('added_recent'),
      sourceCount: totals.read<int>('source_count'),
      bySourceApp: {
        for (final r in sourceAppRows)
          _sourceAppLabel(r.read<String?>('source_app')): r.read<int>('n'),
      },
      byStatus: byStatus,
      coversArchived: totals.read<int>('covers_archived'),
      coversFailed: totals.read<int>('covers_failed'),
      importCount: importAgg.read<int>('n'),
      lastImportAt: importAgg.read<int?>('last_at'),
      vaultSizeBytes: meta?.vaultSizeBytes ?? 0,
      vaultStorage: VaultStorage(
        databaseBytes: meta?.vaultDatabaseBytes ?? 0,
        coversBytes: meta?.vaultCoversBytes ?? 0,
        backupsBytes: meta?.vaultBackupsBytes ?? 0,
        totalBytes: meta?.vaultSizeBytes ?? 0,
      ),
    );
  }

  /// Per-source-app backup freshness, newest import first.
  Future<List<BackupHealth>> backupHealth({int? now}) async {
    final nowMs = now ?? DateTime.now().millisecondsSinceEpoch;
    final rows = await customSelect(
      '''
      SELECT ir.source_app                  AS source_app,
             MAX(ir.imported_at)            AS last_import_at,
             COUNT(DISTINCT ir.id)          AS import_count,
             COUNT(DISTINCT mi.manga_id)    AS title_count
        FROM local_import_record ir
        LEFT JOIN local_manga_import mi ON mi.import_id = ir.id
       GROUP BY ir.source_app
       ORDER BY last_import_at DESC
      ''',
      readsFrom: {localImportRecord, localMangaImport},
    ).get();

    return rows.map((r) {
      final last = r.read<int?>('last_import_at') ?? 0;
      return BackupHealth(
        sourceApp: _sourceAppLabel(r.read<String?>('source_app')),
        lastImportAt: last,
        importCount: r.read<int>('import_count'),
        titleCount: r.read<int>('title_count'),
        staleness: stalenessFor(last, nowMs),
      );
    }).toList();
  }

  /// Most recently added titles — the dashboard's "recently added" shelf.
  Future<List<MangaListItem>> recentlyAdded(int limit) async {
    final query = select(localManga)
      ..orderBy([
        (t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc),
        (t) => OrderingTerm.asc(t.titleLower),
      ])
      ..limit(limit);
    return (await query.get()).map(_toListItem).toList();
  }

  /// Titles with a next unread chapter, most recently read first.
  Future<List<ResumeItem>> resumeReading(int limit) async {
    final query = select(localManga)
      ..where((t) => t.nextChapterName.isNotNull() & t.readCount.isBiggerThanValue(0))
      ..orderBy([
        // NULLS LAST: SQLite sorts NULL first in DESC, which would bury the
        // titles that actually have a read timestamp.
        (t) => OrderingTerm.asc(t.lastReadAt.isNull()),
        (t) => OrderingTerm(expression: t.lastReadAt, mode: OrderingMode.desc),
        (t) => OrderingTerm.asc(t.titleLower),
      ])
      ..limit(limit);

    return (await query.get())
        .map((row) => ResumeItem(
              manga: _toListItem(row),
              readCount: row.readCount,
              nextChapter: ChapterRef(
                name: row.nextChapterName ?? '',
                number: row.nextChapterNumber ?? -1,
              ),
            ))
        .toList();
  }

  /// Mirrored backup history for the Backups screen, newest import first.
  Future<List<ImportRecord>> importHistory() async {
    final rows = await (select(localImportRecord)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.importedAt, mode: OrderingMode.desc),
          ]))
        .get();

    return rows
        .map((r) => ImportRecord(
              id: r.id,
              fileName: r.fileName,
              fileSize: r.fileSize,
              sourceApp: r.sourceApp,
              container: r.container,
              importedAt: r.importedAt,
              stats: ImportSummary.fromJson(_decodeStats(r.statsJson)),
            ))
        .toList();
  }

  // ---- sync bookkeeping -------------------------------------------------

  Future<SyncMetaData?> syncState() =>
      (select(syncMeta)..where((t) => t.id.equals(0))).getSingleOrNull();

  /// One cheap stream every local-read provider can watch, bumped once per
  /// committed sync transaction — instead of each screen watching many tables.
  Stream<int> watchRevision() =>
      (select(syncMeta)..where((t) => t.id.equals(0)))
          .watchSingleOrNull()
          .map((row) => row?.localRevision ?? 0)
          .distinct();

  // ---- internals --------------------------------------------------------

  Expression<bool> _predicate({
    required String text,
    required List<String> status,
    required List<String> categoryIds,
    required List<String> sourceIds,
    required bool? favorite,
  }) {
    var predicate = const Constant(true);
    Expression<bool> acc = predicate;

    final trimmed = text.trim().toLowerCase();
    if (trimmed.isNotEmpty) {
      // The escape char must be declared to SQLite, or the backslashes below
      // are matched literally and a search for "%" finds nothing.
      final pattern = '%${_escapeLike(trimmed)}%';
      acc = acc &
          (localManga.titleLower.like(pattern, escapeChar: r'\') |
              localManga.authorLower.like(pattern, escapeChar: r'\'));
    }
    if (status.isNotEmpty) acc = acc & localManga.status.isIn(status);
    if (sourceIds.isNotEmpty) acc = acc & localManga.sourceId.isIn(sourceIds);
    if (favorite != null) acc = acc & localManga.favorite.equals(favorite);
    if (categoryIds.isNotEmpty) {
      acc = acc &
          existsQuery(
            select(localMangaCategory)
              ..where((c) =>
                  c.mangaId.equalsExp(localManga.id) &
                  c.categoryId.isIn(categoryIds)),
          );
    }
    return acc;
  }

  /// Mirrors the server's ordering: chosen field, NULLs last, then a stable
  /// title + id tiebreak so paging never repeats or drops a row.
  List<OrderClauseGenerator<$LocalMangaTable>> _ordering(
    String sortBy,
    String sortDir,
  ) {
    final mode = sortDir == 'asc' ? OrderingMode.asc : OrderingMode.desc;
    GeneratedColumn<Object> column(t) => switch (sortBy) {
          'dateAdded' => t.dateAdded,
          'lastReadAt' => t.lastReadAt,
          'chapterCount' => t.chapterCount,
          'unreadCount' => t.unreadCount,
          _ => t.titleLower,
        } as GeneratedColumn<Object>;

    return [
      (t) => OrderingTerm.asc(column(t).isNull()),
      (t) => OrderingTerm(expression: column(t), mode: mode),
      (t) => OrderingTerm.asc(t.titleLower),
      (t) => OrderingTerm.asc(t.id),
    ];
  }

  MangaListItem _toListItem(LocalMangaRow r) => MangaListItem(
        id: r.id,
        title: r.title,
        author: r.author,
        status: r.status,
        coverPath: r.coverPath,
        coverState: r.coverState,
        sourceName: r.sourceName,
        sourceId: r.sourceId,
        chapterCount: r.chapterCount,
        unreadCount: r.unreadCount,
        lastReadAt: r.lastReadAt,
      );

  ChapterRef? _chapterRef(String? name, double? number) =>
      name == null ? null : ChapterRef(name: name, number: number ?? -1);
}

/// The server's dense status set, so `byStatus` always has every band.
const List<String> kPublicationStatuses = [
  'unknown',
  'ongoing',
  'completed',
  'licensed',
  'publishing_finished',
  'cancelled',
  'on_hiatus',
];

/// Matches the server's `COALESCE(NULLIF(source_app, ''), 'unknown')`.
String _sourceAppLabel(String? raw) =>
    (raw == null || raw.isEmpty) ? 'unknown' : raw;

Map<String, dynamic> _decodeStats(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {
    // A malformed cache entry must not break the Backups screen.
  }
  return const {};
}

List<String> decodeGenres(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) return parsed.whereType<String>().toList();
  } catch (_) {
    // A malformed cache entry must not break the details screen.
  }
  return const [];
}

/// `LIKE` treats `%`, `_` and `\` specially; a title containing them must not
/// turn into a wildcard search.
String _escapeLike(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
