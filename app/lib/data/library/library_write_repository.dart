import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'deleted_models.dart';

/// How many titles one bulk-delete request carries. The server caps a request
/// at 1000 ids; this stays well under it so a "select all" on a large library
/// arrives as a few small requests instead of one that times out.
const int kDeleteChunkSize = 200;

/// The library's **write** surface, plus the deletion registry.
///
/// Reads of *library content* come from the on-device mirror
/// ([LibraryRepository]); writes must go to the server, which owns the archive.
/// The mirror is corrected afterwards so the grid updates immediately, and the
/// delete's tombstone reconciles every other device on its next sync.
///
/// The deletion registry is read straight from the server rather than mirrored:
/// it is small, rarely opened, and every action on it (restore, purge) needs the
/// server anyway — so mirroring it would buy nothing but a drift schema bump.
class LibraryWriteRepository {
  LibraryWriteRepository(this._dio);

  final Dio _dio;

  /// Permanently delete titles. Returns how many rows the server actually
  /// removed (ids that were already gone simply don't count).
  Future<int> deleteTitles(List<String> ids) async {
    var deleted = 0;
    for (final chunk in _chunks(ids)) {
      final res = await _dio.post<Map<String, dynamic>>(
        '/library/delete',
        data: {'ids': chunk},
      );
      deleted += (res.data?['deleted'] as num?)?.toInt() ?? 0;
    }
    return deleted;
  }

  /// Titles that were deleted, and are therefore skipped by every import until
  /// they're restored or purged. Newest deletion first, with the registry's
  /// size on disk so the screen can state what the recycle bin costs.
  Future<DeletedTitlesPage> deletedTitles() async {
    final res = await _dio.get<Map<String, dynamic>>('/library/deleted');
    return DeletedTitlesPage.fromJson(res.data ?? const {});
  }

  /// Put deleted titles back. Ids are **registry** ids, not old manga ids.
  Future<RestoreResult> restore(List<String> registryIds) async {
    var restored = 0;
    var skipped = 0;
    for (final chunk in _chunks(registryIds)) {
      final res = await _dio.post<Map<String, dynamic>>(
        '/library/deleted/restore',
        data: {'ids': chunk},
      );
      final result = RestoreResult.fromJson(res.data ?? const {});
      restored += result.restored;
      skipped += result.skipped;
    }
    return RestoreResult(restored: restored, skipped: skipped);
  }

  /// Forget registry entries without restoring: the titles stay gone, but a
  /// future backup import is free to add them again.
  Future<int> purgeDeleted(List<String> registryIds) async {
    var purged = 0;
    for (final chunk in _chunks(registryIds)) {
      final res = await _dio.post<Map<String, dynamic>>(
        '/library/deleted/purge',
        data: {'ids': chunk},
      );
      purged += (res.data?['purged'] as num?)?.toInt() ?? 0;
    }
    return purged;
  }

  Iterable<List<String>> _chunks(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += kDeleteChunkSize) {
      yield ids.sublist(
        i,
        i + kDeleteChunkSize > ids.length ? ids.length : i + kDeleteChunkSize,
      );
    }
  }
}

final libraryWriteRepositoryProvider = Provider<LibraryWriteRepository>(
  (ref) => LibraryWriteRepository(ref.watch(apiClientProvider)),
);
