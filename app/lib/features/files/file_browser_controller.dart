import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/files/storage_roots.dart';
import '../../core/files/vault_file_system.dart';

/// What the browser is being opened for.
enum FileBrowserMode {
  /// Pick one or more backups to import.
  open,

  /// Pick a folder and a name to write an export into.
  save,
}

/// The whole browser in one immutable value.
///
/// A single value rather than a sealed union, for the same reason
/// [ExportState] is one: the location, sort and search have to survive a failed
/// listing, or an unreadable folder would drop the user back to the volume root
/// with their filters cleared.
@immutable
class FileBrowserState {
  const FileBrowserState({
    this.mode = FileBrowserMode.open,
    this.directory = '',
    this.volumes = const [],
    this.quickFolders = const [],
    this.entries = const AsyncValue.loading(),
    this.sort = FileSort.modified,
    this.search = '',
    this.showAllFiles = false,
    this.selected = const {},
  });

  final FileBrowserMode mode;
  final String directory;
  final List<StorageVolume> volumes;
  final List<QuickFolder> quickFolders;

  /// The current folder's raw contents. Sorting and filtering are applied by
  /// [visible], so changing either doesn't re-hit the disk.
  final AsyncValue<List<FileEntry>> entries;

  final FileSort sort;
  final String search;

  /// Whether files the import flow can't take are listed (muted) as well.
  final bool showAllFiles;

  /// Paths of the selected backups. Paths, not entries, so a refresh that
  /// rebuilds the list doesn't drop the selection.
  final Set<String> selected;

  /// The volume [directory] sits on, for the breadcrumb's leading segment.
  StorageVolume? get volume {
    for (final v in volumes) {
      if (directory == v.path || p.posix.isWithin(v.path, directory)) return v;
    }
    return volumes.isEmpty ? null : volumes.first;
  }

  /// True when there is nowhere further up to go — going above a volume root
  /// lands in `/storage`, which is unreadable and looks like a bug.
  bool get isAtVolumeRoot {
    final root = volume?.path;
    return root == null || directory == root || !p.posix.isWithin(root, directory);
  }

  /// Path segments below the volume root, for the breadcrumb.
  List<String> get crumbs {
    final root = volume?.path;
    if (root == null || !p.posix.isWithin(root, directory)) return const [];
    return p.posix.split(p.posix.relative(directory, from: root));
  }

  /// What the list actually renders: folders first, then files, with the
  /// current sort and search applied.
  List<FileEntry> get visible {
    final all = entries.value ?? const <FileEntry>[];
    final query = search.trim().toLowerCase();
    final filtered = all.where((e) {
      if (!e.isDirectory && !e.isBackup && !showAllFiles) return false;
      if (query.isEmpty) return true;
      return e.name.toLowerCase().contains(query);
    }).toList();
    return sortEntries(filtered, sort);
  }

  /// Files hidden by the "show all files" toggle, so the empty state can say so
  /// rather than claiming the folder is empty.
  int get hiddenFileCount => showAllFiles
      ? 0
      : (entries.value ?? const <FileEntry>[])
          .where((e) => !e.isDirectory && !e.isBackup)
          .length;

  /// A file is only pickable when the import flow could actually take it.
  bool canSelect(FileEntry entry) =>
      mode == FileBrowserMode.open && entry.isBackup;

  FileBrowserState copyWith({
    FileBrowserMode? mode,
    String? directory,
    List<StorageVolume>? volumes,
    List<QuickFolder>? quickFolders,
    AsyncValue<List<FileEntry>>? entries,
    FileSort? sort,
    String? search,
    bool? showAllFiles,
    Set<String>? selected,
  }) =>
      FileBrowserState(
        mode: mode ?? this.mode,
        directory: directory ?? this.directory,
        volumes: volumes ?? this.volumes,
        quickFolders: quickFolders ?? this.quickFolders,
        entries: entries ?? this.entries,
        sort: sort ?? this.sort,
        search: search ?? this.search,
        showAllFiles: showAllFiles ?? this.showAllFiles,
        selected: selected ?? this.selected,
      );
}

/// Drives the in-app file browser: where we are, what's there, what's picked.
class FileBrowserController extends Notifier<FileBrowserState> {
  /// Guards against a slow listing landing after the user has moved on. Two
  /// taps into nested folders can otherwise show the first folder's contents
  /// under the second folder's breadcrumb.
  int _listSeq = 0;

  @override
  FileBrowserState build() => const FileBrowserState();

  VaultFileSystem get _fs => ref.read(vaultFileSystemProvider);

  /// Start a browsing session. Called once per opened browser.
  Future<void> open({
    required FileBrowserMode mode,
    String? startDirectory,
  }) async {
    final volumes = await discoverVolumes(_fs);
    final remembered = ref.read(folderMemoryProvider.notifier).lastFolder;
    final fallback = volumes.first.path;

    // A remembered folder can have been deleted, or lived on an SD card that
    // isn't in the phone any more — check before opening onto nothing.
    var start = startDirectory ?? remembered ?? fallback;
    if (!await _fs.isDirectory(start)) start = fallback;

    state = FileBrowserState(
      mode: mode,
      directory: start,
      volumes: volumes,
      entries: const AsyncValue.loading(),
    );
    await Future.wait([_loadEntries(), _loadQuickFolders()]);
  }

  Future<void> navigateTo(String directory) async {
    if (directory == state.directory) return;
    // Search and selection are per-folder: carrying either across a navigation
    // hides files in the new folder, or imports one the user can no longer see.
    state = state.copyWith(
      directory: directory,
      entries: const AsyncValue.loading(),
      search: '',
      selected: const {},
    );
    await _loadEntries();
  }

  Future<void> goUp() async {
    if (state.isAtVolumeRoot) return;
    await navigateTo(p.posix.dirname(state.directory));
  }

  /// Jump to the [depth]-th breadcrumb segment (0 = the volume root itself).
  Future<void> jumpToCrumb(int depth) async {
    final root = state.volume?.path;
    if (root == null) return;
    final crumbs = state.crumbs.take(depth).toList();
    await navigateTo(crumbs.isEmpty ? root : p.posix.joinAll([root, ...crumbs]));
  }

  Future<void> switchVolume(StorageVolume volume) async {
    await navigateTo(volume.path);
    await _loadQuickFolders();
  }

  Future<void> refresh() async {
    state = state.copyWith(entries: const AsyncValue.loading());
    await _loadEntries();
  }

  void setSort(FileSort sort) => state = state.copyWith(sort: sort);

  void setSearch(String search) => state = state.copyWith(search: search);

  void toggleShowAllFiles() =>
      state = state.copyWith(showAllFiles: !state.showAllFiles);

  void toggleSelected(FileEntry entry) {
    if (!state.canSelect(entry)) return;
    final next = {...state.selected};
    if (!next.remove(entry.path)) next.add(entry.path);
    state = state.copyWith(selected: next);
  }

  /// The picked files, in the order they're shown.
  List<FileEntry> get selectedEntries => state.visible
      .where((e) => state.selected.contains(e.path))
      .toList();

  /// Create [name] under the current folder and navigate into it.
  /// Returns an error message, or null on success.
  Future<String?> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Give the folder a name.';
    // These are the characters Android's FAT/ext layers reject or mangle; a
    // separator would also silently create a nested path.
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(trimmed)) {
      return r'A folder name cannot contain \ / : * ? " < > |';
    }
    final path = p.posix.join(state.directory, trimmed);
    if (await _fs.exists(path)) return 'That folder already exists.';
    try {
      await _fs.createDirectory(path);
    } on FileAccessException catch (e) {
      return e.message;
    }
    await navigateTo(path);
    return null;
  }

  /// Record the folder the user settled on, so the next open starts there.
  void rememberCurrentFolder() =>
      ref.read(folderMemoryProvider.notifier).remember(state.directory);

  Future<void> _loadEntries() async {
    final seq = ++_listSeq;
    try {
      final entries = await _fs.list(state.directory);
      if (seq != _listSeq) return; // a newer navigation won
      state = state.copyWith(entries: AsyncValue.data(entries));
    } on FileAccessException catch (e, stack) {
      if (seq != _listSeq) return;
      state = state.copyWith(entries: AsyncValue.error(e, stack));
    } catch (e, stack) {
      if (seq != _listSeq) return;
      state = state.copyWith(entries: AsyncValue.error(e, stack));
    }
  }

  Future<void> _loadQuickFolders() async {
    final root = state.volume?.path;
    if (root == null) return;
    final folders = await discoverQuickFolders(
      _fs,
      root,
      ref.read(folderMemoryProvider),
    );
    state = state.copyWith(quickFolders: folders);
  }
}

final fileBrowserProvider =
    NotifierProvider<FileBrowserController, FileBrowserState>(
  FileBrowserController.new,
);
