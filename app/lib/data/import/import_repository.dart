import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/sse/sse_parser.dart';
import 'import_models.dart';

/// Talks to the server's `/imports/*` endpoints: upload/stage a backup, start a
/// streamed commit, watch its progress over SSE, discard, and list history.
class ImportRepository {
  ImportRepository(this._dio);

  final Dio _dio;

  /// Upload a backup file's bytes and get the staged preview.
  Future<StagedImport> stage(String fileName, List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final res = await _dio.post<Map<String, dynamic>>('/imports/stage', data: form);
    return StagedImport.fromJson(res.data!);
  }

  /// Tag a staged import with the app it came from, before committing it.
  ///
  /// Pass `''` to leave it unknown. Returns the re-staged DTO so the review
  /// cell re-renders from the server's answer rather than a local guess.
  Future<StagedImport> setSourceApp(String stagedId, String sourceApp) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/imports/stage/$stagedId',
      data: {'sourceApp': sourceApp},
    );
    return StagedImport.fromJson(res.data!);
  }

  /// Start the streamed commit; returns the job id to stream events from.
  Future<String> commit(String stagedId) async {
    final res = await _dio.post<Map<String, dynamic>>('/imports/stage/$stagedId/commit');
    return res.data!['jobId'] as String;
  }

  /// Live commit progress. Yields [ImportEvent]s until the terminal done/error.
  Stream<ImportEvent> streamEvents(String jobId) async* {
    final res = await _dio.get<ResponseBody>(
      '/imports/jobs/$jobId/events',
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    final chunks = res.data!.stream.map((bytes) => utf8.decode(bytes, allowMalformed: true));
    await for (final data in parseSseData(chunks)) {
      yield ImportEvent.fromJson(jsonDecode(data) as Map<String, dynamic>);
    }
  }

  Future<void> discard(String stagedId) async {
    await _dio.delete<void>('/imports/stage/$stagedId');
  }

  Future<List<ImportRecord>> history() async {
    final res = await _dio.get<List<dynamic>>('/imports');
    return (res.data ?? const [])
        .map((e) => ImportRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(ref.watch(apiClientProvider)),
);
