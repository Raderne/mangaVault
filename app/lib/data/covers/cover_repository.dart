import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/config/server_config.dart';
import '../../core/config/server_config_controller.dart';
import 'cover_models.dart';

/// Talks to the server's `/covers/*` endpoints — cover archiving (M4). The
/// archived image itself is served at `GET /covers/:id`; because Flutter's
/// `Image.network` uses its own HTTP client (not Dio), callers must attach
/// [CoverUrls.authHeaders] so the bearer-guarded route lets it through.
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

}

/// Builds cover image URLs and their auth header for the *currently connected*
/// server.
///
/// These used to be statics over the compile-time config. They can't be:
/// the server address and token are chosen at runtime now, and a cover URL
/// built against a stale origin either 404s or — worse, after a server
/// switch — points at somebody else's image.
class CoverUrls {
  const CoverUrls(this.config);

  final ServerConfig config;

  /// URL of the archived cover, or null while it isn't archived yet (the UI
  /// renders a placeholder in that case) or before the app is set up.
  String? cover(String coverState, String mangaId) =>
      coverState == 'archived' && config.isConfigured
          ? '${config.apiBase}/covers/$mangaId'
          : null;

  /// Bearer header for loading a guarded cover image via `CachedNetworkImage`,
  /// which doesn't go through Dio and so doesn't inherit the client's headers.
  Map<String, String> get authHeaders => config.apiToken.isEmpty
      ? const {}
      : {'Authorization': 'Bearer ${config.apiToken}'};
}

final coverUrlsProvider = Provider<CoverUrls>(
  (ref) => CoverUrls(ref.watch(serverConfigProvider)),
);

final coverRepositoryProvider = Provider<CoverRepository>(
  (ref) => CoverRepository(ref.watch(apiClientProvider)),
);
