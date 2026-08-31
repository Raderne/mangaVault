import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../local/app_database.dart';
import 'migration_models.dart';
import 'source_models.dart';

/// Talks to the server's `/sources/*`, `/extensions` and `/migrations/*`
/// endpoints.
///
/// Note the split with [LocalSourceRepository]: the *list* of sources is
/// mirrored on the device and read from SQLite, because the Sources screen must
/// open instantly and work offline like every other screen. Everything here is
/// an action — checking health, planning, applying — which needs the server by
/// definition.
class SourceRepository {
  SourceRepository(this._dio);

  final Dio _dio;

  /// Sources straight from the server, including replacement suggestions the
  /// mirror does not carry.
  Future<List<VaultSource>> sources() async {
    final res = await _dio.get<List<dynamic>>('/sources');
    return (res.data ?? const [])
        .map((e) => VaultSource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Re-read every extension repository index.
  Future<void> syncRepos() => _dio.post<dynamic>('/sources/repos/sync');

  /// Start (or join) a run that re-checks every source the vault depends on.
  Future<SourceHealthJob> checkHealth() async {
    final res =
        await _dio.post<Map<String, dynamic>>('/sources/health-check');
    final data = res.data!;
    // The start response carries only `jobId`/`total`; normalise it into the
    // same shape the poll returns so the controller has one type to fold.
    return SourceHealthJob(
      jobId: (data['jobId'] as String?) ?? '',
      status: 'running',
      total: (data['total'] as num?)?.toInt() ?? 0,
      done: 0,
      ok: 0,
      degraded: 0,
      unhealthy: 0,
      finished: ((data['total'] as num?)?.toInt() ?? 0) == 0,
    );
  }

  Future<SourceHealthJob> healthJob(String jobId) async {
    final res =
        await _dio.get<Map<String, dynamic>>('/sources/health-jobs/$jobId');
    return SourceHealthJob.fromJson(res.data!);
  }

  /// A run already in progress — a scheduled pass this client never started.
  Future<SourceHealthJob?> activeHealthJob() async {
    final res = await _dio.get<dynamic>('/sources/health-jobs/active');
    final data = res.data;
    return data is Map<String, dynamic>
        ? SourceHealthJob.fromJson(data)
        : null;
  }

  Future<SourceHealthJob> cancelHealthJob(String jobId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/sources/health-jobs/$jobId/cancel',
    );
    return SourceHealthJob.fromJson(res.data!);
  }

  // ---- extensions ----

  Future<ExtensionPage> extensions({
    String? query,
    String? lang,
    bool includeNsfw = false,
    int offset = 0,
    int limit = 40,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/extensions',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (lang != null && lang.isNotEmpty) 'lang': lang,
        if (includeNsfw) 'nsfw': '1',
        'offset': offset,
        'limit': limit,
      },
    );
    return ExtensionPage.fromJson(res.data!);
  }

  // ---- migration ----

  /// Start building a plan. Returns as soon as the job exists; poll [plan].
  Future<MigrationJob> planMigration({
    required String fromSourceId,
    required List<String> toSourceIds,
    List<String>? mangaIds,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/migrations/plan',
      data: {
        'fromSourceId': fromSourceId,
        'toSourceIds': toSourceIds,
        // Omitted entirely when null — the server then takes every title on
        // the source.
        'mangaIds': ?mangaIds,
      },
    );
    return MigrationJob.fromJson(res.data!);
  }

  Future<MigrationPlan> plan(String jobId) async {
    final res = await _dio.get<Map<String, dynamic>>('/migrations/$jobId');
    return MigrationPlan.fromJson(res.data!);
  }

  Future<void> cancelPlan(String jobId) =>
      _dio.post<dynamic>('/migrations/$jobId/cancel');

  /// Choose a different candidate for one title.
  Future<MigrationItem> chooseCandidate({
    required String jobId,
    required String mangaId,
    required int candidateIndex,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/migrations/$jobId/items/$mangaId',
      data: {'candidateIndex': candidateIndex},
    );
    return MigrationItem.fromJson(res.data!);
  }

  /// Point one title at a url the user supplied.
  Future<MigrationItem> setManualTarget({
    required String jobId,
    required String mangaId,
    required String toSourceId,
    required String toMangaUrl,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/migrations/$jobId/items/$mangaId',
      data: {'toSourceId': toSourceId, 'toMangaUrl': toMangaUrl},
    );
    return MigrationItem.fromJson(res.data!);
  }

  Future<MigrationItem> skipItem({
    required String jobId,
    required String mangaId,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/migrations/$jobId/items/$mangaId',
      data: {'skip': true},
    );
    return MigrationItem.fromJson(res.data!);
  }

  /// Apply exactly the titles the user ticked.
  Future<MigrationApplyResult> apply({
    required String jobId,
    required List<String> mangaIds,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/migrations/$jobId/apply',
      data: {'mangaIds': mangaIds},
    );
    return MigrationApplyResult.fromJson(res.data!);
  }

  Future<MigrationItem> undo(String itemId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/migrations/items/$itemId/undo',
    );
    return MigrationItem.fromJson(res.data!);
  }

  /// Fold a conflicting title into the copy already in the vault.
  Future<MigrationItem> mergeConflict(String itemId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/migrations/items/$itemId/merge',
    );
    return MigrationItem.fromJson(res.data!);
  }
}

final sourceRepositoryProvider = Provider<SourceRepository>(
  (ref) => SourceRepository(ref.watch(apiClientProvider)),
);

/// Reads the mirrored source registry — the offline half.
class LocalSourceRepository {
  LocalSourceRepository(this._db);

  final AppDatabase _db;

  /// Every mirrored source, worst health first then by how much of the library
  /// depends on it — the same order the server sorts by, so the screen looks
  /// identical whether it came from the mirror or a refresh.
  Future<List<VaultSource>> sources() async {
    final rows = await _db.select(_db.localSource).get();
    final list = rows
        .map(
          (r) => VaultSource(
            sourceId: r.id,
            name: r.name,
            lang: r.lang,
            homeUrl: r.homeUrl,
            iconUrl: r.iconUrl,
            packageName: r.packageName,
            repoName: r.repoName,
            contentWarning: r.contentWarning,
            registryState: SourceRegistryState.values.firstWhere(
              (s) => s.name == r.registryState,
              orElse: () => SourceRegistryState.unknown,
            ),
            health: SourceHealth.values.firstWhere(
              (h) => h.name == r.health,
              orElse: () => SourceHealth.unknown,
            ),
            healthNote: r.healthNote,
            healthCheckedAt: r.healthCheckedAt,
            titleCount: r.titleCount,
            coverFailedCount: r.coverFailedCount,
          ),
        )
        .toList();
    list.sort((a, b) {
      final rank = _healthRank(a.health) - _healthRank(b.health);
      if (rank != 0) return rank;
      final count = b.titleCount - a.titleCount;
      if (count != 0) return count;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  static int _healthRank(SourceHealth h) => switch (h) {
        SourceHealth.removed => 0,
        SourceHealth.unreachable => 1,
        SourceHealth.blocked => 2,
        SourceHealth.degraded => 3,
        SourceHealth.unknown => 4,
        SourceHealth.ok => 5,
      };
}

final localSourceRepositoryProvider = Provider<LocalSourceRepository>(
  (ref) => LocalSourceRepository(ref.watch(appDatabaseProvider)),
);
