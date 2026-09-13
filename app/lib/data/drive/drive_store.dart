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
  /// if the user has never had one or has since deleted it.
  Future<void> upload(String name, Uint8List bytes, {required bool automatic});

  /// Ids of automatic uploads only, newest first.
  Future<List<String>> automaticBackupIds();

  Future<void> delete(String id);

  /// Release the authenticated HTTP client.
  void close();
}

/// Opens a [DriveStore] for the connected account, or returns null when there
/// is no usable authorization. With [interactive] false it never shows UI — an
/// unattended upload must not pop a sign-in sheet over whatever the user is
/// doing.
typedef DriveOpener = Future<DriveStore?> Function({required bool interactive});

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
      q: "mimeType = '$_kFolderMime' and name = '$kDriveFolderName' "
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
  Future<void> upload(
    String name,
    Uint8List bytes, {
    required bool automatic,
  }) async {
    final folder = await _folder();
    await _api.files.create(
      drive.File()
        ..name = name
        ..parents = [folder]
        ..mimeType = 'application/gzip'
        ..appProperties = {_kKindKey: automatic ? 'auto' : 'manual'},
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
  }

  @override
  Future<List<String>> automaticBackupIds() async {
    final folder = await _folder();
    final res = await _api.files.list(
      q: "'$folder' in parents and trashed = false and "
          "appProperties has { key='$_kKindKey' and value='auto' }",
      orderBy: 'createdTime desc',
      spaces: 'drive',
      pageSize: 100,
      $fields: 'files(id)',
    );
    return [for (final f in res.files ?? const <drive.File>[]) ?f.id];
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
