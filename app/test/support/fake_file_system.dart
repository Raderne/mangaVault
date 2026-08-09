import 'package:mangavault/core/files/vault_file_system.dart';
import 'package:path/path.dart' as p;

/// In-memory stand-in for the device filesystem.
///
/// The browser tests must not touch real disk: the result would depend on
/// whatever happens to be in the runner's home directory, and there is no
/// `/storage/emulated/0` to browse on a desktop anyway.
class FakeFileSystem implements VaultFileSystem {
  final Map<String, _Node> _nodes = {};

  /// Paths that throw on [list], to exercise the unreadable-folder path.
  final Set<String> unreadable = {};

  /// Everything [writeBytes] was asked to write, by path.
  final Map<String, List<int>> written = {};

  /// When true, every write fails — the "chose a folder Android won't let us
  /// write to" case.
  bool readOnly = false;

  /// Create [path] and every parent above it.
  void addDirectory(String path) {
    var current = path;
    while (current.isNotEmpty && current != '/') {
      _nodes.putIfAbsent(current, () => _Node(isDirectory: true));
      final parent = p.posix.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  void addFile(String path, {int size = 1024, int modifiedMillis = 0}) {
    addDirectory(p.posix.dirname(path));
    _nodes[path] = _Node(
      isDirectory: false,
      size: size,
      modifiedMillis: modifiedMillis,
    );
  }

  @override
  Future<List<FileEntry>> list(String directory) async {
    if (unreadable.contains(directory)) {
      throw const FileAccessException("Android won't let this app read that folder.");
    }
    final entries = <FileEntry>[];
    _nodes.forEach((path, node) {
      if (p.posix.dirname(path) != directory || path == directory) return;
      entries.add(
        FileEntry(
          path: path,
          name: p.posix.basename(path),
          isDirectory: node.isDirectory,
          sizeBytes: node.size,
          modifiedMillis: node.modifiedMillis,
        ),
      );
    });
    return entries;
  }

  @override
  Future<bool> exists(String path) async => _nodes.containsKey(path);

  @override
  Future<bool> isDirectory(String path) async =>
      _nodes[path]?.isDirectory ?? false;

  @override
  Future<void> createDirectory(String path) async => addDirectory(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (readOnly) throw const FileAccessException('Permission denied');
    written[path] = bytes;
    addFile(path, size: bytes.length);
  }
}

class _Node {
  _Node({required this.isDirectory, this.size = 0, this.modifiedMillis = 0});
  final bool isDirectory;
  final int size;
  final int modifiedMillis;
}
