import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;

/// The Drive folder every upload lands in. With the `drive.file` scope the app
/// can only see what it created itself, so this is found (or made) by name.
const kDriveFolderName = 'Manga Vault';

const _kFolderMime = 'application/vnd.google-apps.folder';

/// `appProperties` key that marks who put a file there. Retention prunes only
/// `auto` files — a backup the user sent by hand is never deleted for them.
const _kKindKey = 'mangavault';

/// What the app needs from Google Drive, and nothing more.
///
/// An interface for the same reason `VaultFileSystem` is one: the upload and
/// retention logic is the part worth testing, and it should not need a Google
/// account to run.
abstract class DriveStore {
  /// Upload [bytes] as [name] into the Manga Vault folder, creating the folder
  /// if the user has never had one or has since deleted it. Returns the file id.
  ///
  /// [automatic] files belong to the Drive screen's retention pool. A [runId]
  /// groups every part of one backup so retention deletes whole runs.
  Future<String> upload(
    String name,
    Uint8List bytes, {
    required bool automatic,
    String? runId,
    String? partKey,
    int? partCount,
  });

  /// Managed uploads, newest first. Legacy wizard uploads are not included.
  Future<List<DriveManagedFile>> automaticFiles();

  Future<void> delete(String id);

  /// Release the authenticated HTTP client.
  void close();
}

/// Opens a [DriveStore] for the connected account, or returns null when there
/// is no usable authorization. With [interactive] false it never shows UI — an
/// unattended upload must not pop a sign-in sheet over whatever the user is
/// doing.
typedef DriveOpener = Future<DriveStore?> Function({required bool interactive});

/// One managed Drive file. Files without a [runId] are legacy one-file backups.
class DriveManagedFile {
  const DriveManagedFile({
    required this.id,
    this.runId,
    this.partKey,
    this.partCount,
    this.createdAtMs = 0,
  });

  final String id;
  final String? runId;
  final String? partKey;
  final int? partCount;
  final int createdAtMs;
}

/// File ids that retention should delete.
///
/// Keeps the newest [keep] complete runs. An incomplete run is deleted too,
/// except [protectRunId]: Drive's listing can omit a file that was just
/// created, and that must not prune the backup still being uploaded.
List<String> staleDriveFileIds(
  List<DriveManagedFile> files, {
  int keep = 5,
  String? protectRunId,
}) {
  final groups = <String, List<DriveManagedFile>>{};
  for (final file in files) {
    groups.putIfAbsent(file.runId ?? 'legacy:${file.id}', () => []).add(file);
  }

  final complete = <({String key, int newest, List<String> ids})>[];
  final stale = <String>[];
  for (final entry in groups.entries) {
    final group = entry.value;
    final legacy = group.every((file) => file.runId == null);
    final expected = group.fold<int>(
      0,
      (maxCount, file) => file.partCount != null && file.partCount! > maxCount
          ? file.partCount!
          : maxCount,
    );
    final uploadedParts = group
        .map((file) => file.partKey)
        .whereType<String>()
        .toSet()
        .length;
    final done = legacy || (expected > 0 && uploadedParts >= expected);
    if (!done) {
      if (entry.key != protectRunId) {
        stale.addAll(group.map((file) => file.id));
      }
      continue;
    }
    final newest = group.fold<int>(
      0,
      (maxAt, file) => file.createdAtMs > maxAt ? file.createdAtMs : maxAt,
    );
    complete.add((
      key: entry.key,
      newest: newest,
      ids: [for (final file in group) file.id],
    ));
  }

  complete.sort((a, b) => b.newest.compareTo(a.newest));
  final kept = complete.take(keep).map((run) => run.key).toSet();
  if (protectRunId != null) kept.add(protectRunId);
  for (final run in complete) {
    if (!kept.contains(run.key)) stale.addAll(run.ids);
  }
  return stale;
}

class GoogleDriveStore implements DriveStore {
  GoogleDriveStore(this._api, [this._onClose]);

  final drive.DriveApi _api;
  final void Function()? _onClose;

  /// Cached per store: Drive's listing is eventually consistent, so querying
  /// for a folder created a moment ago can miss it and make a second one.
  String? _folderId;

  Future<String> _folder() async {
    final cached = _folderId;
    if (cached != null) return cached;

    final found = await _api.files.list(
      q:
          "mimeType = '$_kFolderMime' and name = '$kDriveFolderName' "
          'and trashed = false',
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id)',
    );
    final existing = found.files?.firstOrNull?.id;
    if (existing != null) return _folderId = existing;

    final created = await _api.files.create(
      drive.File()
        ..name = kDriveFolderName
        ..mimeType = _kFolderMime,
      $fields: 'id',
    );
    return _folderId = created.id!;
  }

  @override
  Future<String> upload(
    String name,
    Uint8List bytes, {
    required bool automatic,
    String? runId,
    String? partKey,
    int? partCount,
  }) async {
    final folder = await _folder();
    final created = await _api.files.create(
      drive.File()
        ..name = name
        ..parents = [folder]
        ..mimeType = 'application/gzip'
        ..appProperties = {
          _kKindKey: automatic ? 'auto' : 'manual',
          'run': ?runId,
          'part': ?partKey,
          if (partCount != null) 'parts': '$partCount',
        },
      // Resumable: a multi-MB backup on a phone connection is exactly the case
      // a single-shot upload loses halfway through.
      uploadMedia: drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/gzip',
      ),
      uploadOptions: drive.UploadOptions.resumable,
      $fields: 'id',
    );
    final id = created.id;
    if (id == null) {
      throw StateError('Google Drive did not return a file id.');
    }
    return id;
  }

  @override
  Future<List<DriveManagedFile>> automaticFiles() async {
    final folder = await _folder();
    final files = <DriveManagedFile>[];
    String? token;
    do {
      final res = await _api.files.list(
        q:
            "'$folder' in parents and trashed = false and "
            "appProperties has { key='$_kKindKey' and value='auto' }",
        orderBy: 'createdTime desc',
        spaces: 'drive',
        pageSize: 100,
        pageToken: token,
        $fields: 'nextPageToken,files(id,createdTime,appProperties)',
      );
      for (final file in res.files ?? const <drive.File>[]) {
        final id = file.id;
        if (id == null) continue;
        final props = file.appProperties ?? const {};
        files.add(
          DriveManagedFile(
            id: id,
            runId: props['run'],
            partKey: props['part'],
            partCount: int.tryParse(props['parts'] ?? ''),
            createdAtMs: file.createdTime?.millisecondsSinceEpoch ?? 0,
          ),
        );
      }
      token = res.nextPageToken;
    } while (token != null && token.isNotEmpty);
    return files;
  }

  @override
  Future<void> delete(String id) => _api.files.delete(id);

  @override
  void close() => _onClose?.call();
}

/// A readable message for a Drive API failure, or null when [e] isn't one.
String? describeDriveError(Object e) {
  if (e is! drive.DetailedApiRequestError) return null;
  if (e.errors.any((d) => d.reason == 'storageQuotaExceeded')) {
    return 'Your Google Drive is full.';
  }
  if (e.status == 401 || e.status == 403) {
    return 'Google Drive refused the upload. Reconnect your account and try '
        'again.';
  }
  return 'Google Drive error ${e.status}: ${e.message}';
}
