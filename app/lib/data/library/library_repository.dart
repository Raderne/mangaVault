import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import 'library_models.dart';

/// Talks to the server's `/library`, `/library/:id` and `/categories`
/// endpoints — the read side of the archive (M3).
class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// A paginated, filtered, sorted slice of the library.
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/library',
      queryParameters: {
        if (text.trim().isNotEmpty) 'text': text.trim(),
        if (status.isNotEmpty) 'status': status.join(','),
        if (categoryIds.isNotEmpty) 'categoryIds': categoryIds.join(','),
        if (sourceIds.isNotEmpty) 'sourceIds': sourceIds.join(','),
        'sortBy': sortBy,
        'sortDir': sortDir,
        'offset': offset,
        'limit': limit,
      },
    );
    return LibraryPage.fromJson(res.data!);
  }

  /// The full record for one title.
  Future<VaultManga> get(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/library/$id');
    return VaultManga.fromJson(res.data!);
  }

  /// Categories with title counts, for the filter chips.
  Future<List<Category>> categories() async {
    final res = await _dio.get<List<dynamic>>('/categories');
    return (res.data ?? const [])
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Archived-cover URL for an item, or null while covers aren't archived yet
  /// (cover fetching lands in M4 — until then cells render a placeholder).
  static String? coverUrl(String coverState, String mangaId) =>
      coverState == 'archived'
          ? '${AppConfig.baseUrl}/api/v1/covers/$mangaId'
          : null;
}

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(apiClientProvider)),
);
