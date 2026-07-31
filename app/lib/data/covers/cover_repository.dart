import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import 'cover_models.dart';

/// Talks to the server's `/covers/*` endpoints — cover archiving (M4). The
/// archived image itself is served at `GET /covers/:id`; because Flutter's
/// `Image.network` uses its own HTTP client (not Dio), callers must attach
/// [authHeaders] so the bearer-guarded route lets it through.
class CoverRepository {
  CoverRepository(this._dio);

  final Dio _dio;

  /// Start (or join) the background job archiving every missing cover.
  Future<CoverArchiveStarted> archiveMissing() async {
    final res = await _dio.post<Map<String, dynamic>>('/covers/archive-missing');
    return CoverArchiveStarted.fromJson(res.data!);
  }

  /// Poll a cover-archiving job's progress.
  Future<CoverJobStatus> jobStatus(String jobId) async {
    final res = await _dio.get<Map<String, dynamic>>('/covers/jobs/$jobId');
    return CoverJobStatus.fromJson(res.data!);
  }

  /// The run in progress on the server, or null. Archiving runs outlive this
  /// client, so one may already be going when the app opens — started by an
  /// import or resumed after a server restart.
  Future<CoverJobStatus?> activeJob() async {
    final res = await _dio.get<dynamic>('/covers/jobs/active');
    final data = res.data;
    return data is Map<String, dynamic>
        ? CoverJobStatus.fromJson(data)
        : null;
  }

  /// Ask a running job to stop. Downloads in flight finish first, so the run
  /// reports `cancelled` a moment later.
  Future<CoverJobStatus> cancelJob(String jobId) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/covers/jobs/$jobId/cancel');
    return CoverJobStatus.fromJson(res.data!);
  }

  /// Retry archiving one title's cover.
  Future<CoverResult> retry(String mangaId) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/covers/$mangaId/retry');
    return CoverResult.fromJson(res.data!);
  }

  /// URL of the archived cover, or null while it isn't archived yet (the UI
  /// renders a placeholder in that case).
  static String? coverUrl(String coverState, String mangaId) =>
      coverState == 'archived'
          ? '${AppConfig.baseUrl}/api/v1/covers/$mangaId'
          : null;

  /// Bearer header for loading a guarded cover image via `Image.network`.
  static Map<String, String> get authHeaders => AppConfig.apiToken.isEmpty
      ? const {}
      : {'Authorization': 'Bearer ${AppConfig.apiToken}'};
}

final coverRepositoryProvider = Provider<CoverRepository>(
  (ref) => CoverRepository(ref.watch(apiClientProvider)),
);
