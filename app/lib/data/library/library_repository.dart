import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/sync/sync_controller.dart';
import '../local/local_library_dao.dart';
import 'library_models.dart';

/// The library read surface the UI depends on.
///
/// An interface rather than a concrete class so the backing store can change
/// without touching `LibraryController` or the screens — which is exactly what
/// happened when reads moved from HTTP to the on-device mirror — and so tests
/// can substitute a fake without constructing a database.
abstract class LibraryRepository {
  /// A paginated, filtered, sorted slice of the library.
  Future<LibraryPage> query({
    String text,
    List<String> status,
    List<String> categoryIds,
    List<String> sourceIds,
    bool? favorite,
    String sortBy,
    String sortDir,
    int offset,
    int limit,
  });

  /// The full record for one title.
  Future<VaultManga> get(String id);

  /// Categories with title counts, for the filter chips.
  Future<List<Category>> categories();

  /// Sources present in the library, with title counts, for the source filter.
  Future<List<SourceOption>> sources();

  /// Remove titles from the local mirror after the server has deleted them.
  Future<void> forgetTitles(List<String> ids);
}

/// Reads the library from the **on-device mirror**, not the network.
///
/// The server is still the source of truth; [LibrarySyncService] pulls its
/// changes into SQLite and this reads them back.
class LocalLibraryRepository implements LibraryRepository {
  LocalLibraryRepository(this._dao);

  final LocalLibraryDao _dao;

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) =>
      _dao.queryPage(
        text: text,
        status: status,
        categoryIds: categoryIds,
        sourceIds: sourceIds,
        favorite: favorite,
        sortBy: sortBy,
        sortDir: sortDir,
        offset: offset,
        limit: limit,
      );

  @override
  Future<VaultManga> get(String id) => _dao.get(id);

  @override
  Future<List<Category>> categories() => _dao.categories();

  @override
  Future<List<SourceOption>> sources() => _dao.sources();

  @override
  Future<void> forgetTitles(List<String> ids) => _dao.deleteTitles(ids);
}

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LocalLibraryRepository(ref.watch(localLibraryDaoProvider)),
);
