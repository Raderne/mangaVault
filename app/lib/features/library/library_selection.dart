import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_cache.dart';
import '../../data/covers/cover_repository.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_write_repository.dart';
import '../sync/sync_controller.dart';
import 'library_controller.dart';

/// Deletes titles from the vault and reconciles everything that renders them.
///
/// The server owns the archive, so the request goes out first; only once it
/// succeeds are the rows dropped from the mirror. The delete's tombstone still
/// arrives on the next delta and removes the same (already absent) rows, which
/// is why the local step is idempotent.
class TitleDeleter {
  const TitleDeleter(this._ref);

  final Ref _ref;

  /// Delete [ids] and return how many titles the server actually removed.
  ///
  /// Throws whatever the network layer throws — the caller reports it; nothing
  /// is removed locally unless the server confirmed the delete.
  Future<int> delete(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final deleted =
        await _ref.read(libraryWriteRepositoryProvider).deleteTitles(ids);

    await _ref.read(libraryRepositoryProvider).forgetTitles(ids);
    // Drop the cards immediately, then bump the revision so the dashboard,
    // details and any other local reader re-read too.
    _ref.read(libraryControllerProvider.notifier).removeItems(ids.toSet());
    _ref.read(localRevisionProvider.notifier).bump();

    // The cover files are gone server-side, so drop any cached image before it
    // outlives the title. Deliberately **not** awaited: this is opportunistic
    // local cleanup, and the disk cache can take its time (or fail outright)
    // without that holding up a delete the server has already committed.
    for (final id in ids) {
      final url = CoverRepository.coverUrl('archived', id);
      if (url == null) continue;
      unawaited(CoverCache.evict(id, url).catchError((Object _) {}));
    }
    return deleted;
  }
}

final titleDeleterProvider = Provider<TitleDeleter>(TitleDeleter.new);

/// Multi-select state for the library grid.
class LibrarySelection {
  const LibrarySelection({
    this.active = false,
    this.ids = const {},
    this.busy = false,
  });

  /// Whether the grid is in selection mode. Stays true with zero selected, so
  /// clearing every card doesn't yank the toolbar away mid-gesture — leaving is
  /// an explicit action.
  final bool active;
  final Set<String> ids;

  /// A delete is in flight; the toolbar's actions are disabled meanwhile.
  final bool busy;

  int get count => ids.length;
  bool contains(String id) => ids.contains(id);
}

class LibrarySelectionController extends Notifier<LibrarySelection> {
  @override
  LibrarySelection build() => const LibrarySelection();

  /// Enter selection mode with one title picked (the long-press entry point).
  void begin(String id) {
    state = LibrarySelection(active: true, ids: {id});
  }

  void toggle(String id) {
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = LibrarySelection(active: true, ids: next, busy: state.busy);
  }

  /// Select every title currently loaded in the grid.
  void selectAll(Iterable<String> ids) {
    state = LibrarySelection(active: true, ids: ids.toSet(), busy: state.busy);
  }

  void clear() {
    state = LibrarySelection(active: true, ids: const {}, busy: state.busy);
  }

  /// Leave selection mode entirely.
  void exit() => state = const LibrarySelection();

  /// Delete everything selected, then leave selection mode.
  ///
  /// Returns the number of titles removed; rethrows on failure with the
  /// selection intact so the user can retry.
  Future<int> deleteSelected() async {
    final ids = state.ids.toList();
    if (ids.isEmpty) return 0;
    state = LibrarySelection(active: true, ids: state.ids, busy: true);
    try {
      final deleted = await ref.read(titleDeleterProvider).delete(ids);
      state = const LibrarySelection();
      return deleted;
    } catch (_) {
      state = LibrarySelection(active: true, ids: state.ids);
      rethrow;
    }
  }
}

final librarySelectionProvider =
    NotifierProvider<LibrarySelectionController, LibrarySelection>(
  LibrarySelectionController.new,
);
