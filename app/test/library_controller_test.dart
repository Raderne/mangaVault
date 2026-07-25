import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/features/library/library_controller.dart';

/// In-memory repository: slices a fixed list by offset/limit and honors the
/// status filter — enough to exercise paging and refetch.
class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository(this.all) : super(Dio());
  final List<MangaListItem> all;
  int queries = 0;

  @override
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
    queries++;
    final filtered = status.isEmpty
        ? all
        : all.where((m) => status.contains(m.status)).toList();
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

  test('an empty result surfaces as isEmpty, not loading', () async {
    final repo = FakeLibraryRepository(const []);
    final container = _containerWith(repo);

    await container.read(libraryControllerProvider.notifier).refresh();
    final state = container.read(libraryControllerProvider);

    expect(state.status, LibraryStatus.ready);
    expect(state.isEmpty, isTrue);
  });
}
