import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// True for the two things MangaVault can import.
///
/// Lifted out of `ImportController` so the file browser and the staging code
/// agree on what counts as a backup. `.tachibk` has no registered MIME type,
/// which is the whole reason the browser can't lean on a system content filter.
bool isBackupFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.tachibk') || lower.endsWith('.json');
}

/// How a folder listing is ordered. Folders always sort ahead of files
/// regardless — the order below only ever applies within each of those groups.
enum FileSort {
  /// Newest first. The default: the backup you want is nearly always the last
  /// one your reading app wrote.
  modified,
  name,
  size,
}

extension FileSortLabel on FileSort {
  String get label => switch (this) {
        FileSort.modified => 'Date',
        FileSort.name => 'Name',
        FileSort.size => 'Size',
      };
}

/// One row in a folder listing.
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedMillis = 0,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;

  /// Epoch millis, or 0 when the platform wouldn't say.
  final int modifiedMillis;

  /// Whether this is a file the import flow can actually take.
  bool get isBackup => !isDirectory && isBackupFileName(name);

  @override
  bool operator ==(Object other) => other is FileEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// The seam between the browser and the real disk.
///
/// It exists so the widget tests can run against an in-memory tree: the suite
/// has never touched the real filesystem and must not start, or its results
/// would depend on whatever happens to be in the runner's home directory.
abstract class VaultFileSystem {
  Future<List<FileEntry>> list(String directory);
  Future<bool> exists(String path);
  Future<bool> isDirectory(String path);
  Future<void> createDirectory(String path);
  Future<void> writeBytes(String path, List<int> bytes);
}

/// Raised when a folder can't be listed at all. Per-entry failures are dropped
/// silently instead — one unreadable file must not blank the whole folder.
class FileAccessException implements Exception {
  const FileAccessException(this.message);
  final String message;

  @override
  String toString() => message;
}

class IoFileSystem implements VaultFileSystem {
  const IoFileSystem();

  @override
  Future<List<FileEntry>> list(String directory) async {
    final dir = Directory(directory);
    final List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } on FileSystemException catch (e) {
      throw FileAccessException(_listMessage(e));
    }

    final entries = <FileEntry>[];
    for (final entity in entities) {
      // `p.posix`, not `p`, everywhere the browser handles a path: these are
      // always Android paths, and the default context follows the *host*
      // platform — which turns every join into a backslash under a Windows
      // test runner.
      final name = p.posix.basename(entity.path);
      if (name.startsWith('.')) continue; // dotfiles are never a backup
      try {
        final stat = await entity.stat();
        final isDir = stat.type == FileSystemEntityType.directory;
        entries.add(
          FileEntry(
            path: entity.path,
            name: name,
            isDirectory: isDir,
            sizeBytes: isDir ? 0 : stat.size,
            modifiedMillis: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } on FileSystemException {
        // A single entry we can't stat (a dangling link, a protected child).
        // Skipping it is right; failing the listing over it is not.
        continue;
      }
    }
    return entries;
  }

  @override
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

  @override
  Future<bool> isDirectory(String path) async =>
      await FileSystemEntity.type(path) == FileSystemEntityType.directory;

  @override
  Future<void> createDirectory(String path) async {
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (e) {
      throw FileAccessException(e.osError?.message ?? 'Could not create folder');
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    try {
      await File(path).writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      throw FileAccessException(e.osError?.message ?? 'Could not write file');
    }
  }

  /// `errno` 13 is EACCES — by far the likeliest failure here, and the one the
  /// user can actually do something about.
  static String _listMessage(FileSystemException e) =>
      e.osError?.errorCode == 13
          ? "Android won't let this app read that folder."
          : e.osError?.message ?? "Couldn't read that folder.";
}

/// Sort a listing: folders first, then [sort] within each group.
List<FileEntry> sortEntries(List<FileEntry> entries, FileSort sort) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return switch (sort) {
      FileSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      FileSort.size => b.sizeBytes.compareTo(a.sizeBytes),
      // Ties on mtime are common (a batch export writes several in the same
      // second), so fall through to name rather than leaving them arbitrary.
      FileSort.modified => b.modifiedMillis != a.modifiedMillis
          ? b.modifiedMillis.compareTo(a.modifiedMillis)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
  });
  return sorted;
}

final vaultFileSystemProvider =
    Provider<VaultFileSystem>((ref) => const IoFileSystem());
