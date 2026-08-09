import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Whether the app may read the device's shared storage.
enum FileAccessStatus {
  /// Not asked yet — the first check hasn't come back.
  unknown,
  granted,
  denied,

  /// Refused in a way a prompt can't undo; only the app's settings page can.
  permanentlyDenied,
}

extension FileAccessStatusX on FileAccessStatus {
  bool get isGranted => this == FileAccessStatus.granted;
}

/// Reads and requests all-files access.
///
/// **The grant is a Settings toggle, not a dialog.** `MANAGE_EXTERNAL_STORAGE`
/// sends the user to a system settings page and the request future resolves the
/// moment the app is backgrounded — routinely *before* the toggle is flipped, so
/// its return value is not to be trusted on its own. The resume re-check below
/// is what actually makes the grant land, and removing it is the classic way
/// this feature ships looking broken.
class FileAccessController extends Notifier<FileAccessStatus> {
  AppLifecycleListener? _lifecycle;

  @override
  FileAccessStatus build() {
    _lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() => _lifecycle?.dispose());
    Future<void>.microtask(refresh);
    return FileAccessStatus.unknown;
  }

  /// Re-read the current grant without prompting.
  Future<void> refresh() async {
    final next = await _read();
    if (next != state) state = next;
  }

  /// Ask for access. Returns the status after the attempt.
  ///
  /// On Android 11+ this opens the "All files access" settings page; on older
  /// releases, where `MANAGE_EXTERNAL_STORAGE` does not exist, it falls back to
  /// the legacy storage permission. Branching on the returned status rather
  /// than the API level keeps `device_info_plus` out of the dependency list.
  Future<FileAccessStatus> request() async {
    var status = await _requestSafely(Permission.manageExternalStorage);
    if (!status.isGranted) {
      final legacy = await _requestSafely(Permission.storage);
      if (legacy.isGranted) status = legacy;
    }
    state = _map(status);
    return state;
  }

  Future<FileAccessStatus> _read() async {
    if (await _statusSafely(Permission.manageExternalStorage) ==
        PermissionStatus.granted) {
      return FileAccessStatus.granted;
    }
    return _map(await _statusSafely(Permission.storage));
  }

  static FileAccessStatus _map(PermissionStatus status) => switch (status) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional =>
          FileAccessStatus.granted,
        PermissionStatus.permanentlyDenied =>
          FileAccessStatus.permanentlyDenied,
        _ => FileAccessStatus.denied,
      };

  // Both wrappers swallow the MissingPluginException that widget tests without
  // the plugin registered would otherwise throw, so a screen that merely reads
  // the status stays testable.
  static Future<PermissionStatus> _statusSafely(Permission permission) async {
    try {
      return await permission.status;
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  static Future<PermissionStatus> _requestSafely(Permission permission) async {
    try {
      return await permission.request();
    } catch (_) {
      return PermissionStatus.denied;
    }
  }
}

final fileAccessProvider =
    NotifierProvider<FileAccessController, FileAccessStatus>(
  FileAccessController.new,
);

/// Open the app's own settings page, for a permanently denied grant.
Future<void> openFileAccessSettings() async {
  try {
    await openAppSettings();
  } catch (_) {
    // Nothing else to offer; the gate still shows the system-picker fallback.
  }
}
