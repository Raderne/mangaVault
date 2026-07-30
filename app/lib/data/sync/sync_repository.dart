import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'sync_models.dart';

/// The app's only network reader for library data. Every screen now reads from
/// the on-device mirror; this repository is what fills it.
class SyncRepository {
  SyncRepository(this._dio);

  final Dio _dio;

  /// Titles changed (and ids deleted) above [since], oldest version first.
  Future<SyncPage> changesSince(String since, {int limit = 500}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/sync/library',
      queryParameters: {'since': since, 'limit': limit},
    );
    return SyncPage.fromJson(res.data!);
  }

  /// Server epoch + cursor, the full category/import lists, and vault size.
  Future<SyncMetaSnapshot> meta() async {
    final res = await _dio.get<Map<String, dynamic>>('/sync/meta');
    return SyncMetaSnapshot.fromJson(res.data!);
  }
}

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepository(ref.watch(apiClientProvider)),
);
