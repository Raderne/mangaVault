import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import 'update_models.dart';

/// Something the user can act on, raised by [UpdateRepository].
///
/// The updater is the one screen where a raw Dio message would surface to a
/// non-developer, so every failure is translated at the boundary.
class UpdateException implements Exception {
  const UpdateException(this.message, {this.isOffline = false});

  final String message;

  /// True when retrying later is the whole fix — the UI drops the "report
  /// this" tone for these.
  final bool isOffline;

  @override
  String toString() => message;
}

/// Reads published releases and fetches their APK.
abstract interface class UpdateRepository {
  /// Newest installable stable release, or null when the repo has none.
  Future<AppRelease?> latest();

  /// Recent releases, newest first — the changelog history list.
  Future<List<AppRelease>> history({int limit = 10});

  /// Downloads [release]'s APK, reporting `(received, total)` as it goes.
  /// `total` is -1 until the server declares a content length.
  Future<File> downloadApk(
    AppRelease release, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  });

  /// Removes previously downloaded APKs. Best-effort.
  Future<void> clearDownloads();
}

/// [UpdateRepository] over the public GitHub Releases API.
///
/// Uses its **own** Dio, not `apiClientProvider`: that client carries the
/// vault's bearer token and points at the user's server. Sending our API token
/// to github.com would leak it, and the update path must keep working when the
/// server is down — which is exactly when someone reinstalls the app.
class GithubUpdateRepository implements UpdateRepository {
  GithubUpdateRepository({Dio? dio, String? owner, String? repo})
      : _owner = owner ?? AppConfig.updateRepoOwner,
        _repo = repo ?? AppConfig.updateRepoName,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.github.com',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'X-GitHub-Api-Version': '2022-11-28',
                  // GitHub rejects API calls without a User-Agent.
                  'User-Agent': 'MangaVault-App',
                },
              ),
            );

  final Dio _dio;
  final String _owner;
  final String _repo;

  @override
  Future<AppRelease?> latest() async {
    // `/releases/latest` already excludes drafts and pre-releases, but it 404s
    // on a repo whose only releases are pre-releases — so fall back to the list
    // and filter, rather than telling the user they're up to date when the
    // repo simply has no stable build yet.
    final releases = await history(limit: 10);
    for (final release in releases) {
      if (!release.isPreRelease) return release;
    }
    return null;
  }

  @override
  Future<List<AppRelease>> history({int limit = 10}) async {
    final json = await _get<List<dynamic>>(
      '/repos/$_owner/$_repo/releases',
      query: {'per_page': limit},
    );
    return json
        .whereType<Map<String, dynamic>>()
        .where((r) => r['draft'] != true)
        .map(AppRelease.fromJson)
        .nonNulls
        .toList();
  }

  @override
  Future<File> downloadApk(
    AppRelease release, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = release.apkUrl;
    if (url == null) {
      throw const UpdateException('This release has no APK attached.');
    }

    final dir = await _downloadDir();
    // Version-stamped so a half-finished download of an older build can never
    // be mistaken for this one.
    final file = File(p.join(dir.path, 'manga-vault-${release.version.name}.apk'));
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();

    try {
      await _dio.download(
        url,
        partial.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          headers: const {'Accept': 'application/octet-stream'},
          receiveTimeout: const Duration(minutes: 5),
          followRedirects: true,
        ),
      );
    } on DioException catch (error) {
      if (await partial.exists()) await partial.delete();
      if (CancelToken.isCancel(error)) rethrow;
      throw _translate(error, 'Could not download the update');
    }

    // Rename only once the body is complete, so the installable path never
    // points at a truncated APK.
    if (await file.exists()) await file.delete();
    return partial.rename(file.path);
  }

  @override
  Future<void> clearDownloads() async {
    try {
      final dir = await _downloadDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    } on Object {
      // Housekeeping only — never surface a cleanup failure to the user.
    }
  }

  Future<Directory> _downloadDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'updates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<T> _get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<T>(path, queryParameters: query);
      final data = response.data;
      if (data == null) {
        throw const UpdateException('GitHub returned an empty response.');
      }
      return data;
    } on DioException catch (error) {
      throw _translate(error, 'Could not reach GitHub');
    }
  }

  UpdateException _translate(DioException error, String prefix) {
    final status = error.response?.statusCode;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        UpdateException('$prefix — you appear to be offline.', isOffline: true),
      _ when status == 403 || status == 429 => const UpdateException(
          "GitHub's rate limit is reached. Try again in an hour.",
        ),
      _ when status == 404 => const UpdateException(
          'No releases found for this app yet.',
        ),
      _ when status != null => UpdateException('$prefix (HTTP $status).'),
      _ => UpdateException('$prefix.'),
    };
  }
}

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => GithubUpdateRepository(),
);
