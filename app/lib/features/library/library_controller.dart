import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_models.dart';
import '../../data/library/library_repository.dart';
import '../sync/sync_controller.dart';

/// A named sort option surfaced in the sort sheet.
class LibrarySort {
  const LibrarySort(this.label, this.by, this.dir);
  final String label;
  final String by;

  /// Direction applied when this option is first chosen; the user can then
  /// reverse it without leaving the field.
  final String dir;

  /// This field is the one the grid is sorted by, whichever way round.
  bool isActive(LibraryFilters f) => f.sortBy == by;

  bool matches(LibraryFilters f) => f.sortBy == by && f.sortDir == dir;
}

/// The sort options offered in the UI (order = display order).
const List<LibrarySort> kLibrarySorts = [
  LibrarySort('Title A–Z', 'title', 'asc'),
  LibrarySort('Recently added', 'dateAdded', 'desc'),
  LibrarySort('Recently read', 'lastReadAt', 'desc'),
  LibrarySort('Most chapters', 'chapterCount', 'desc'),
  LibrarySort('Most unread', 'unreadCount', 'desc'),
];

/// Status filter chips shown above the grid: label → API status value
/// (empty string = "All titles", i.e. no status filter).
const List<(String, String)> kStatusFilters = [
  ('All titles', ''),
  ('Ongoing', 'ongoing'),
  ('Completed', 'completed'),
  ('On hiatus', 'on_hiatus'),
];

/// The active query parameters for the library grid.
class LibraryFilters {
  const LibraryFilters({
    this.text = '',
    this.status = '',
    this.sourceIds = const [],
    this.favorite = true,
    this.sortBy = 'title',
    this.sortDir = 'asc',
  });

  final String text;

  /// A single status value, or '' for all.
  final String status;

  /// Selected Mihon source ids; empty means every source.
  final List<String> sourceIds;

  /// `true` = library favorites (default); `false` = non-favorites.
  final bool favorite;
  final String sortBy;
  final String sortDir;

  List<String> get statusList => status.isEmpty ? const [] : [status];

  LibraryFilters copyWith({
    String? text,
    String? status,
    List<String>? sourceIds,
    bool? favorite,
    String? sortBy,
    String? sortDir,
  }) =>
      LibraryFilters(
        text: text ?? this.text,
        status: status ?? this.status,
        sourceIds: sourceIds ?? this.sourceIds,
        favorite: favorite ?? this.favorite,
        sortBy: sortBy ?? this.sortBy,
        sortDir: sortDir ?? this.sortDir,
      );
}

enum LibraryStatus { loading, ready, error }

/// Grid state: the accumulated page items, the full match [total], the current
/// [filters], and load/error flags for the initial load vs. pagination.
class LibraryState {
  const LibraryState({
    required this.filters,
    this.items = const [],
    this.total = 0,
    this.status = LibraryStatus.loading,
    this.loadingMore = false,
    this.error,
  });

  final LibraryFilters filters;
  final List<MangaListItem> items;
  final int total;
  final LibraryStatus status;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => items.length < total;
  bool get isEmpty => status == LibraryStatus.ready && items.isEmpty;

  LibraryState copyWith({
    LibraryFilters? filters,
    List<MangaListItem>? items,
    int? total,
    LibraryStatus? status,
    bool? loadingMore,
    Object? error,
  }) =>
      LibraryState(
        filters: filters ?? this.filters,
        items: items ?? this.items,
        total: total ?? this.total,
        status: status ?? this.status,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
      );
}

class LibraryController extends Notifier<LibraryState> {
  static const int _pageSize = 40;

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  LibraryState build() {
    // Every committed sync transaction bumps the local revision; re-read in
    // place so titles appear as they land without a skeleton flash.
    ref.listen(localRevisionProvider, (previous, next) {
      if (previous == null) return;
      reload();
    });
    // Kick off the first page after construction returns.
    Future<void>.microtask(refresh);
    return const LibraryState(filters: LibraryFilters());
  }

  /// Reload from the first page with the current filters.
  Future<void> refresh() => _fetch(reset: true);

  /// Re-fetch the currently loaded items in place — no skeleton flash, scroll
  /// position kept. Used to reveal covers as they finish archiving.
  Future<void> reload() async {
    if (state.status != LibraryStatus.ready) return;
    final f = state.filters;
    final count = state.items.isEmpty ? _pageSize : state.items.length;
    try {
      final page = await _repo.query(
        text: f.text,
        status: f.statusList,
        sourceIds: f.sourceIds,
        favorite: f.favorite,
        sortBy: f.sortBy,
        sortDir: f.sortDir,
        offset: 0,
        limit: count,
      );
      if (!_sameFilters(state.filters, f)) return;
      state = state.copyWith(
        items: page.items,
        total: page.total,
        status: LibraryStatus.ready,
      );
    } catch (_) {
      // Keep the current grid; a failed silent reload is non-fatal.
    }
  }

  /// Append the next page if there is one and we're idle.
  Future<void> loadMore() async {
    if (state.loadingMore ||
        !state.hasMore ||
        state.status != LibraryStatus.ready) {
      return;
    }
    await _fetch(reset: false);
  }

  void setStatus(String status) {
    if (status == state.filters.status) return;
    state = state.copyWith(filters: state.filters.copyWith(status: status));
    _fetch(reset: true);
  }

  /// Choose a sort field, or — when it is already the active one — reverse it.
  /// Titles read A–Z and counts/dates read newest-or-most first, so each option
  /// carries its own natural first direction.
  void setSort(LibrarySort sort) {
    final f = state.filters;
    final next = sort.isActive(f)
        ? f.copyWith(sortDir: f.sortDir == 'asc' ? 'desc' : 'asc')
        : f.copyWith(sortBy: sort.by, sortDir: sort.dir);
    state = state.copyWith(filters: next);
    _fetch(reset: true);
  }

  /// Add or remove one source from the source filter (multi-select).
  void toggleSource(String sourceId) {
    final next = [...state.filters.sourceIds];
    if (!next.remove(sourceId)) next.add(sourceId);
    setSources(next);
  }

  /// Replace the source filter wholesale; an empty list means "all sources".
  void setSources(List<String> sourceIds) {
    if (_sameIds(sourceIds, state.filters.sourceIds)) return;
    state = state.copyWith(
      filters: state.filters.copyWith(sourceIds: List.unmodifiable(sourceIds)),
    );
    _fetch(reset: true);
  }

  /// Toggle between favorites (default) and non-favorites.
  void setFavorite(bool favorite) {
    if (favorite == state.filters.favorite) return;
    state =
        state.copyWith(filters: state.filters.copyWith(favorite: favorite));
    _fetch(reset: true);
  }

  void setSearch(String text) {
    if (text == state.filters.text) return;
    state = state.copyWith(filters: state.filters.copyWith(text: text));
    _fetch(reset: true);
  }

  /// Back to status-all / favorites / title A–Z. Keeps the search term, which
  /// the user types separately from the filter sheet.
  void resetFilters() {
    const defaults = LibraryFilters();
    final next = defaults.copyWith(text: state.filters.text);
    if (_sameFilters(next, state.filters)) return;
    state = state.copyWith(filters: next);
    _fetch(reset: true);
  }

  Future<void> _fetch({required bool reset}) async {
    final f = state.filters;
    if (reset) {
      state = state.copyWith(status: LibraryStatus.loading, error: null);
    } else {
      state = state.copyWith(loadingMore: true);
    }

    try {
      final offset = reset ? 0 : state.items.length;
      final pageData = await _repo.query(
        text: f.text,
        status: f.statusList,
        sourceIds: f.sourceIds,
        favorite: f.favorite,
        sortBy: f.sortBy,
        sortDir: f.sortDir,
        offset: offset,
        limit: _pageSize,
      );
      // Filters changed while awaiting (a newer fetch is in flight): drop this
      // now-stale result rather than clobbering the fresh state.
      if (!_sameFilters(state.filters, f)) {
        if (!reset) state = state.copyWith(loadingMore: false);
        return;
      }
      final merged =
          reset ? pageData.items : [...state.items, ...pageData.items];
      state = state.copyWith(
        items: merged,
        total: pageData.total,
        status: LibraryStatus.ready,
        loadingMore: false,
        error: null,
      );
    } catch (e) {
      state = reset
          ? state.copyWith(status: LibraryStatus.error, error: e)
          : state.copyWith(loadingMore: false);
    }
  }

  /// Drop titles from the grid without a round trip — used the moment a delete
  /// is confirmed, so the cards disappear instead of lingering until the next
  /// re-read. [total] is decremented by however many were actually showing.
  void removeItems(Set<String> ids) {
    if (ids.isEmpty || state.items.isEmpty) return;
    final kept = state.items.where((i) => !ids.contains(i.id)).toList();
    final dropped = state.items.length - kept.length;
    if (dropped == 0) return;
    state = state.copyWith(
      items: kept,
      total: (state.total - dropped).clamp(0, state.total),
    );
  }

  bool _sameFilters(LibraryFilters a, LibraryFilters b) =>
      a.text == b.text &&
      a.status == b.status &&
      a.favorite == b.favorite &&
      a.sortBy == b.sortBy &&
      a.sortDir == b.sortDir &&
      _sameIds(a.sourceIds, b.sourceIds);

  static bool _sameIds(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

/// Categories for the filter surface (currently informational; counts included).
final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(localRevisionProvider);
  return ref.watch(libraryRepositoryProvider).categories();
});

/// Sources that actually have titles in the library, for the source filter.
///
/// Counts are whole-library — they don't narrow as you pick a status or flip to
/// non-favorites, so the list stays stable while you're choosing from it.
final librarySourcesProvider = FutureProvider<List<SourceOption>>((ref) {
  ref.watch(localRevisionProvider);
  return ref.watch(libraryRepositoryProvider).sources();
});

/// Full details for one title, keyed by id (Title Details screen).
final mangaDetailsProvider =
    FutureProvider.family<VaultManga, String>((ref, id) {
  ref.watch(localRevisionProvider);
  return ref.watch(libraryRepositoryProvider).get(id);
});
