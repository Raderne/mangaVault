import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the library renders each title.
enum LibraryLayout {
  /// Cover cell with the title, status and meta overlaid — the mockup grid.
  comfortable,

  /// Cover-only cells with a one-line title, so more fit on screen.
  compact,

  /// A scannable row per title: small cover, title, author, progress.
  list,
}

/// Grid column counts offered per layout. A comfortable card carries three
/// lines of overlaid text, which stops being legible past three columns.
const List<int> kComfortableColumns = [2, 3];
const List<int> kCompactColumns = [3, 4, 5];

/// User-chosen presentation of the library grid.
///
/// Device-local UI state, deliberately *not* stored in the on-device mirror:
/// that database is a disposable projection of the server and holds nothing the
/// server doesn't. This lives in `shared_preferences` instead.
class LibraryDisplay {
  const LibraryDisplay({
    this.layout = LibraryLayout.comfortable,
    this.comfortableColumns = 2,
    this.compactColumns = 3,
    this.showUnreadBadge = true,
    this.showSourceName = true,
  });

  final LibraryLayout layout;
  final int comfortableColumns;
  final int compactColumns;

  /// Corner badge with the unread chapter count (hidden when zero).
  final bool showUnreadBadge;

  /// Whether the card's meta line names the source.
  final bool showSourceName;

  bool get isGrid => layout != LibraryLayout.list;

  /// Columns for the active layout (meaningless in list mode).
  int get columns => switch (layout) {
        LibraryLayout.comfortable => comfortableColumns,
        LibraryLayout.compact => compactColumns,
        LibraryLayout.list => 1,
      };

  /// Column options for the active layout.
  List<int> get columnOptions => layout == LibraryLayout.compact
      ? kCompactColumns
      : kComfortableColumns;

  bool get isDefault =>
      layout == LibraryLayout.comfortable &&
      comfortableColumns == 2 &&
      compactColumns == 3 &&
      showUnreadBadge &&
      showSourceName;

  LibraryDisplay copyWith({
    LibraryLayout? layout,
    int? comfortableColumns,
    int? compactColumns,
    bool? showUnreadBadge,
    bool? showSourceName,
  }) =>
      LibraryDisplay(
        layout: layout ?? this.layout,
        comfortableColumns: comfortableColumns ?? this.comfortableColumns,
        compactColumns: compactColumns ?? this.compactColumns,
        showUnreadBadge: showUnreadBadge ?? this.showUnreadBadge,
        showSourceName: showSourceName ?? this.showSourceName,
      );
}

const _kLayout = 'library.layout';
const _kComfortableColumns = 'library.columns.comfortable';
const _kCompactColumns = 'library.columns.compact';
const _kUnreadBadge = 'library.showUnreadBadge';
const _kSourceName = 'library.showSourceName';

/// Holds [LibraryDisplay] and mirrors it into `shared_preferences`.
///
/// `build()` returns the defaults synchronously and the stored values are
/// folded in when they load, so the first frame never waits on disk. Both the
/// load and the save swallow platform failures: a preference that can't be
/// persisted must not break browsing the library (and keeps widget tests that
/// don't register the plugin working).
class LibraryDisplayController extends Notifier<LibraryDisplay> {
  @override
  LibraryDisplay build() {
    Future<void>.microtask(_load);
    return const LibraryDisplay();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final layoutName = prefs.getString(_kLayout);
      state = LibraryDisplay(
        layout: LibraryLayout.values.firstWhere(
          (l) => l.name == layoutName,
          orElse: () => LibraryLayout.comfortable,
        ),
        comfortableColumns: _clampTo(
          prefs.getInt(_kComfortableColumns),
          kComfortableColumns,
          2,
        ),
        compactColumns:
            _clampTo(prefs.getInt(_kCompactColumns), kCompactColumns, 3),
        showUnreadBadge: prefs.getBool(_kUnreadBadge) ?? true,
        showSourceName: prefs.getBool(_kSourceName) ?? true,
      );
    } catch (_) {
      // No storage available — the defaults already in `state` stand.
    }
  }

  void setLayout(LibraryLayout layout) {
    if (layout == state.layout) return;
    state = state.copyWith(layout: layout);
    _persist((p) => p.setString(_kLayout, layout.name));
  }

  /// Set the column count for whichever grid layout is active.
  void setColumns(int columns) {
    if (columns == state.columns || state.layout == LibraryLayout.list) return;
    if (state.layout == LibraryLayout.compact) {
      state = state.copyWith(compactColumns: columns);
      _persist((p) => p.setInt(_kCompactColumns, columns));
    } else {
      state = state.copyWith(comfortableColumns: columns);
      _persist((p) => p.setInt(_kComfortableColumns, columns));
    }
  }

  void setShowUnreadBadge(bool value) {
    state = state.copyWith(showUnreadBadge: value);
    _persist((p) => p.setBool(_kUnreadBadge, value));
  }

  void setShowSourceName(bool value) {
    state = state.copyWith(showSourceName: value);
    _persist((p) => p.setBool(_kSourceName, value));
  }

  void reset() {
    state = const LibraryDisplay();
    _persist((p) async {
      await p.remove(_kLayout);
      await p.remove(_kComfortableColumns);
      await p.remove(_kCompactColumns);
      await p.remove(_kUnreadBadge);
      await p.remove(_kSourceName);
    });
  }

  Future<void> _persist(Future<void> Function(SharedPreferences) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // Best-effort: the in-memory state is already updated.
    }
  }

  static int _clampTo(int? value, List<int> allowed, int fallback) =>
      value != null && allowed.contains(value) ? value : fallback;
}

final libraryDisplayProvider =
    NotifierProvider<LibraryDisplayController, LibraryDisplay>(
  LibraryDisplayController.new,
);
