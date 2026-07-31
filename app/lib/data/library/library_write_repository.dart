import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// How many titles one bulk-delete request carries. The server caps a request
/// at 1000 ids; this stays well under it so a "select all" on a large library
/// arrives as a few small requests instead of one that times out.
const int kDeleteChunkSize = 200;

/// The library's **write** surface — the only place the app mutates the vault.
///
/// Reads come from the on-device mirror ([LibraryRepository]); writes must go
/// to the server, which owns the archive. The mirror is corrected afterwards so
/// the grid updates immediately, and the delete's tombstone reconciles every
/// other device on its next sync.
class LibraryWriteRepository {
  LibraryWriteRepository(this._dio);

  final Dio _dio;

  /// Permanently delete titles. Returns how many rows the server actually
  /// removed (ids that were already gone simply don't count).
  Future<int> deleteTitles(List<String> ids) async {
    var deleted = 0;
    for (var i = 0; i < ids.length; i += kDeleteChunkSize) {
      final chunk = ids.sublist(
        i,
        i + kDeleteChunkSize > ids.length ? ids.length : i + kDeleteChunkSize,
      );
      final res = await _dio.post<Map<String, dynamic>>(
        '/library/delete',
        data: {'ids': chunk},
      );
      deleted += (res.data?['deleted'] as num?)?.toInt() ?? 0;
    }
    return deleted;
  }
}

final libraryWriteRepositoryProvider = Provider<LibraryWriteRepository>(
  (ref) => LibraryWriteRepository(ref.watch(apiClientProvider)),
);
