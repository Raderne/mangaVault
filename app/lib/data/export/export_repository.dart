import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'export_models.dart';

/// Building a `.tachibk` can take a while on a large vault — well past the
/// client's default 30s read timeout, which is tuned for JSON responses.
const _buildTimeout = Duration(minutes: 5);

/// Talks to the server's `/exports/*` endpoints: facet lists, scope previews,
/// and the build itself.
///
/// Nothing is stored server-side — a build streams the file back in the
/// response — so there is no history to list and no id to hold on to.
class ExportRepository {
  ExportRepository(this._dio);

  final Dio _dio;

  /// Selectable values (apps, sources, categories, statuses) with title counts.
  Future<ExportFacets> facets() async {
    final res = await _dio.get<Map<String, dynamic>>('/exports/facets');
    return ExportFacets.fromJson(res.data!);
  }

  /// What this scope would produce — counts, filename, size — without building.
  Future<ExportPreview> preview(ExportScope scope,
      {CancelToken? cancelToken}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/exports/preview',
      data: scope.toJson(),
      cancelToken: cancelToken,
    );
    return ExportPreview.fromJson(res.data!);
  }

  /// Build the backup and return its bytes.
  ///
  /// The filename comes from the response headers rather than being rebuilt
  /// client-side: the server stamps it at build time, and two clocks would
  /// otherwise disagree about the minute the backup was made.
  Future<ExportedBackup> build(
    ExportScope scope, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.post<List<int>>(
      '/exports/build',
      data: scope.toJson(),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: _buildTimeout,
        sendTimeout: _buildTimeout,
      ),
    );

    final headers = res.headers;
    return ExportedBackup(
      fileName: headers.value('x-export-file-name') ?? 'backup.tachibk',
      bytes: Uint8List.fromList(res.data ?? const []),
      titles: int.tryParse(headers.value('x-export-titles') ?? '') ?? 0,
    );
  }
}

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepository(ref.watch(apiClientProvider)),
);

/// The facet lists behind the scope builder. Read live: an export is an online
/// action, and the counts must reflect the server's state, not the mirror's.
final exportFacetsProvider = FutureProvider<ExportFacets>(
  (ref) => ref.watch(exportRepositoryProvider).facets(),
);
