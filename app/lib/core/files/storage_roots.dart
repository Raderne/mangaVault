import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_file_system.dart';

/// A mounted storage volume the browser can start from.
class StorageVolume {
  const StorageVolume({required this.path, required this.label});
  final String path;
  final String label;
}

/// A one-tap destination on the browser's quick-access row.
class QuickFolder {
  const QuickFolder({
    required this.path,
    required this.label,
    this.isRecent = false,
  });

  final String path;
  final String label;

  /// Somewhere the user has been, rather than a well-known location.
  final bool isRecent;
}

/// Folders, relative to a volume root, that a manga backup actually lives in.
///
/// `autobackup` is Mihon's own constant (`StorageManager.kt`
/// `AUTOMATIC_BACKUPS_PATH`) — automatic backups land in `<AppName>/autobackup`,
/// where `<AppName>` is the fork's display name. Manual exports go wherever the
/// user's SAF picker put them, which in practice means `Download`.
const _knownFolders = <String>[
  'Download',
  'Mihon/autobackup',
  'Mihon',
  'Tachiyomi/autobackup',
  'Tachiyomi',
  'Komikku/autobackup',
  'Komikku',
  'Documents',
  'MangaVault',
];

/// The volumes to offer, primary (internal) first.
///
/// The secondary volumes come from `path_provider`, which hands back the
/// *app-scoped* directory on each one (`/storage/XXXX-XXXX/Android/data/` then
/// the package name, then `/files`); the volume root is the part before
/// `/Android/`. There is no plugin-free way to enumerate volumes directly, and
/// this trick needs no new dependency.
Future<List<StorageVolume>> discoverVolumes(VaultFileSystem fs) async {
  final volumes = <StorageVolume>[];
  const primary = '/storage/emulated/0';
  if (await fs.isDirectory(primary)) {
    volumes.add(const StorageVolume(path: primary, label: 'Internal storage'));
  }

  try {
    final scoped = await getExternalStorageDirectories() ?? const [];
    for (final dir in scoped) {
      final root = _volumeRootOf(dir.path);
      if (root == null) continue;
      if (volumes.any((v) => v.path == root)) continue;
      if (!await fs.isDirectory(root)) continue;
      volumes.add(
        StorageVolume(
          path: root,
          label: root == primary ? 'Internal storage' : 'SD card',
        ),
      );
    }
  } catch (_) {
    // Plugin unavailable (widget tests, or a platform without volumes).
  }

  if (volumes.isEmpty) {
    volumes.add(const StorageVolume(path: primary, label: 'Internal storage'));
  }
  return volumes;
}

String? _volumeRootOf(String scopedPath) {
  final marker = scopedPath.indexOf('/Android/');
  if (marker <= 0) return null;
  return scopedPath.substring(0, marker);
}

/// Well-known folders that exist on [volumeRoot], plus [recents].
///
/// Existence is checked rather than assumed: a chip pointing at a folder the
/// device doesn't have is a dead tap, and offering `Tachiyomi/` to someone who
/// only ever ran Komikku is noise.
Future<List<QuickFolder>> discoverQuickFolders(
  VaultFileSystem fs,
  String volumeRoot,
  List<String> recents,
) async {
  final folders = <QuickFolder>[];
  final seen = <String>{};

  for (final relative in _knownFolders) {
    final path = p.posix.join(volumeRoot, relative);
    if (!seen.add(path)) continue;
    if (!await fs.isDirectory(path)) continue;
    folders.add(QuickFolder(path: path, label: _labelFor(relative)));
  }

  for (final path in recents) {
    if (!seen.add(path)) continue;
    if (!await fs.isDirectory(path)) continue;
    folders.add(
      QuickFolder(path: path, label: p.posix.basename(path), isRecent: true),
    );
  }
  return folders;
}

/// `Mihon/autobackup` reads better as "Mihon backups" on a chip.
String _labelFor(String relative) {
  final parts = p.posix.split(relative);
  if (parts.length == 2 && parts[1] == 'autobackup') {
    return '${parts[0]} backups';
  }
  return parts.last == 'Download' ? 'Downloads' : parts.last;
}

const _kLastFolder = 'files.lastFolder';
const _kRecentFolders = 'files.recentFolders';
const _kRecentCap = 5;

/// Folders the user has browsed, newest first, mirrored into
/// `shared_preferences`.
///
/// Device-local UI state, so it stays out of the on-device mirror — the same
/// rule `LibraryDisplayController` follows. The first element doubles as "where
/// the browser opens next time".
class FolderMemoryController extends Notifier<List<String>> {
  @override
  List<String> build() {
    Future<void>.microtask(_load);
    return const [];
  }

  /// Where the browser should open. Null means "start at the volume root".
  String? get lastFolder => state.isEmpty ? null : state.first;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // A `remember()` that landed while the read was in flight is newer than
      // anything on disk — restoring the stored list over it would silently
      // send the next browse back to the previous folder.
      if (state.isNotEmpty) return;
      final recents = prefs.getStringList(_kRecentFolders) ?? const [];
      final last = prefs.getString(_kLastFolder);
      // The last folder is the head of the list, not a separate key's worth of
      // state that could disagree with it.
      state = [
        if (last != null && last.isNotEmpty) last,
        ...recents.where((r) => r != last),
      ].take(_kRecentCap).toList();
    } catch (_) {
      // No storage available — an empty history is a fine starting point.
    }
  }

  /// Record that the user settled on [path] (picked a file from it, or saved
  /// into it). Navigating *through* a folder deliberately doesn't count, or the
  /// list would fill with every parent on the way down.
  void remember(String path) {
    if (path.isEmpty) return;
    final next = [path, ...state.where((r) => r != path)].take(_kRecentCap).toList();
    if (_sameOrder(next, state)) return;
    state = next;
    _persist(next);
  }

  Future<void> _persist(List<String> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastFolder, folders.first);
      await prefs.setStringList(_kRecentFolders, folders);
    } catch (_) {
      // Best-effort: the in-memory list is already updated.
    }
  }

  static bool _sameOrder(List<String> a, List<String> b) =>
      a.length == b.length && !a.indexed.any((e) => b[e.$1] != e.$2);
}

final folderMemoryProvider =
    NotifierProvider<FolderMemoryController, List<String>>(
  FolderMemoryController.new,
);

final storageVolumesProvider = FutureProvider<List<StorageVolume>>(
  (ref) => discoverVolumes(ref.watch(vaultFileSystemProvider)),
);
