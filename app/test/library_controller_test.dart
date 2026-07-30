import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/features/library/library_controller.dart';

/// In-memory repository: slices a fixed list by offset/limit and honors the
/// status / favorite filters — enough to exercise paging and refetch.
class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository(this.all, {this.favorites});

  // Paging/filtering is what these tests cover; details and categories aren't.
  @override
  Future<VaultManga> get(String id) => throw UnimplementedError();

  @override
  Future<List<Category>> categories() async => const [];

  final List<MangaListItem> all;

  /// Ids treated as favorites. When null, every item is a favorite (DB default).
  final Set<String>? favorites;
  int queries = 0;
  bool? lastFavorite;

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
  }) async {
    queries++;
    lastFavorite = favorite;
    var filtered = all;
    if (status.isNotEmpty) {
      filtered = filtered.where((m) => status.contains(m.status)).toList();
    }
    if (favorite != null) {
      final favIds = favorites ?? all.map((m) => m.id).toSet();
      filtered =
          filtered.where((m) => favIds.contains(m.id) == favorite).toList();
    }
    return LibraryPage(
      items: filtered.skip(offset).take(limit).toList(),
      total: filtered.length,
      offset: offset,
      limit: limit,
    );
  }
}

MangaListItem _item(int i, {String status = 'ongoing'}) => MangaListItem(
      id: 'id-$i',
      title: 'Title $i',
      author: null,
      status: status,
      coverPath: null,
      coverState: 'none',
      sourceName: 'Src',
      sourceId: '1',
      chapterCount: i,
      unreadCount: 0,
      lastReadAt: null,
    );

ProviderContainer _containerWith(FakeLibraryRepository repo) {
  final container = ProviderContainer(overrides: [
    libraryRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('refresh loads the first page and reports hasMore', () async {
    final repo = FakeLibraryRepository(List.generate(45, _item.call));
    final container = _containerWith(repo);

    await container.read(libraryControllerProvider.notifier).refresh();
    final state = container.read(libraryControllerProvider);

    expect(state.status, LibraryStatus.ready);
    expect(state.items, hasLength(40));
    expect(state.total, 45);
    expect(state.hasMore, isTrue);
  });

  test('loadMore appends the next page and stops at the end', () async {
    final repo = FakeLibraryRepository(List.generate(45, _item.call));
    final container = _containerWith(repo);
    final controller = container.read(libraryControllerProvider.notifier);

    await controller.refresh();
    await controller.loadMore();
    final state = container.read(libraryControllerProvider);

    expect(state.items, hasLength(45));
    expect(state.hasMore, isFalse);

    // No further pages are requested once exhausted.
    final before = repo.queries;
    await controller.loadMore();
    expect(repo.queries, before);
  });

  test('setStatus re-queries with the filter applied', () async {
    final repo = FakeLibraryRepository([
      _item(1, status: 'ongoing'),
      _item(2, status: 'completed'),
      _item(3, status: 'completed'),
    ]);
    final container = _containerWith(repo);
    final controller = container.read(libraryControllerProvider.notifier);

    await controller.refresh();
    controller.setStatus('completed');
    await Future<void>.delayed(Duration.zero);
    final state = container.read(libraryControllerProvider);

    expect(state.filters.status, 'completed');
    expect(state.total, 2);
    expect(state.items.every((m) => m.status == 'completed'), isTrue);
  });

  test('setFavorite toggles to non-favorites by default-on', () async {
    final repo = FakeLibraryRepository(
      [_item(1), _item(2), _item(3)],
      favorites: {'id-1', 'id-2'},
    );
    final container = _containerWith(repo);
    final controller = container.read(libraryControllerProvider.notifier);

    await controller.refresh();
    expect(repo.lastFavorite, isTrue);
    expect(container.read(libraryControllerProvider).total, 2);

    controller.setFavorite(false);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(libraryControllerProvider);

    expect(state.filters.favorite, isFalse);
    expect(repo.lastFavorite, isFalse);
    expect(state.total, 1);
    expect(state.items.single.id, 'id-3');
  });

  test('an empty result surfaces as isEmpty, not loading', () async {
    final repo = FakeLibraryRepository(const []);
    final container = _containerWith(repo);

    await container.read(libraryControllerProvider.notifier).refresh();
    final state = container.read(libraryControllerProvider);

    expect(state.status, LibraryStatus.ready);
    expect(state.isEmpty, isTrue);
  });
}
