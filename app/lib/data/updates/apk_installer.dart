import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why an install could not be started.
enum InstallFailure {
  /// "Install unknown apps" is off for Manga Vault. The only fix is a trip to
  /// Settings, which is why this is a distinct outcome rather than an error
  /// string — the UI turns it into a button.
  notPermitted,

  /// The downloaded file vanished (cache eviction between download and tap).
  missingFile,

  /// No package installer, or the platform isn't Android.
  unsupported,

  unknown,
}

/// Outcome of handing an APK to the system installer. Success only means the
/// installer *opened* — Android owns the confirm/deny flow from there, and the
/// app is about to be replaced, so there is no completion callback to await.
sealed class InstallResult {
  const InstallResult();
}

class InstallStarted extends InstallResult {
  const InstallStarted();
}

class InstallRejected extends InstallResult {
  const InstallRejected(this.reason, this.message);

  final InstallFailure reason;
  final String message;
}

/// Hands a downloaded APK to Android's package installer.
abstract interface class ApkInstaller {
  /// Whether this build can install APKs at all (Android only).
  bool get isSupported;

  /// Whether the user has granted "install unknown apps" to Manga Vault.
  Future<bool> canInstall();

  /// Opens the system screen where that grant is given. False when no such
  /// screen could be launched.
  Future<bool> openInstallSettings();

  Future<InstallResult> install(File apk);
}

class AndroidApkInstaller implements ApkInstaller {
  const AndroidApkInstaller([
    this._channel = const MethodChannel('dev.mangavault/installer'),
  ]);

  final MethodChannel _channel;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> canInstall() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openInstallSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<InstallResult> install(File apk) async {
    if (!isSupported) {
      return const InstallRejected(
        InstallFailure.unsupported,
        'Installing updates is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<bool>('install', {'path': apk.path});
      return const InstallStarted();
    } on PlatformException catch (error) {
      return switch (error.code) {
        'not_permitted' => const InstallRejected(
            InstallFailure.notPermitted,
            'Manga Vault needs permission to install apps.',
          ),
        'missing_file' => const InstallRejected(
            InstallFailure.missingFile,
            'The downloaded update is no longer on disk.',
          ),
        'no_installer' => const InstallRejected(
            InstallFailure.unsupported,
            'This device has no package installer.',
          ),
        _ => InstallRejected(
            InstallFailure.unknown,
            error.message ?? 'The installer could not be opened.',
          ),
      };
    } on MissingPluginException {
      return const InstallRejected(
        InstallFailure.unsupported,
        'Installing updates is not available in this build.',
      );
    }
  }
}

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const AndroidApkInstaller(),
);
