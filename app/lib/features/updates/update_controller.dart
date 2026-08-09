import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../data/updates/apk_installer.dart';
import '../../data/updates/update_models.dart';
import '../../data/updates/update_repository.dart';

/// The running app's own identity, read from the installed package.
class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.buildNumber,
    required this.packageName,
  });

  /// Fallback for platforms/tests where `package_info_plus` has no answer.
  /// 0.0.0 sorts below every real release, so an unknown build is treated as
  /// out of date rather than silently up to date.
  static const unknown = InstalledApp(
    version: AppVersion(0, 0, 0),
    buildNumber: '0',
    packageName: 'dev.mangavault.mangavault',
  );

  final AppVersion version;
  final String buildNumber;
  final String packageName;

  /// `1.0.0 (build 1)` — the About screen's version line.
  String get display => 'v${version.name} (build $buildNumber)';
}

final installedAppProvider = FutureProvider<InstalledApp>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return InstalledApp(
      version: AppVersion.tryParse(info.version) ?? InstalledApp.unknown.version,
      buildNumber: info.buildNumber.isEmpty ? '0' : info.buildNumber,
      packageName: info.packageName,
    );
  } on Object {
    return InstalledApp.unknown;
  }
});

/// Every release the repo has published, newest first — the About screen's
/// changelog history. Separate from [updateControllerProvider] because it is
/// read-only, cacheable, and only needed once that screen is open.
final releaseHistoryProvider = FutureProvider<List<AppRelease>>((ref) async {
  return ref.read(updateRepositoryProvider).history(limit: 15);
});

/// Where the updater is in the check → download → install sequence.
sealed class UpdateState {
  const UpdateState();

  /// The release this state is about, when there is one.
  AppRelease? get release => null;
}

/// Never checked in this session.
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate(this.checkedAt);

  final DateTime checkedAt;
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.available);

  final AppRelease available;

  @override
  AppRelease? get release => available;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.available, this.received, this.total);

  final AppRelease available;

  final int received;

  /// -1 until the server declares a content length.
  final int total;

  @override
  AppRelease? get release => available;

  /// Null while the size is unknown, so the UI can show an indeterminate bar
  /// instead of a bar frozen at zero.
  double? get fraction =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

/// Downloaded and verified present on disk; waiting for the user to install.
class UpdateReady extends UpdateState {
  const UpdateReady(this.available, this.apk, {this.needsPermission = false});

  final AppRelease available;
  final File apk;

  /// The install was attempted and Android refused for want of the
  /// "install unknown apps" grant. Turns the CTA into a Settings trip.
  final bool needsPermission;

  @override
  AppRelease? get release => available;
}

class UpdateFailed extends UpdateState {
  const UpdateFailed(this.message, {this.isOffline = false, this.available});

  final String message;
  final bool isOffline;

  /// Kept so a failed *download* can be retried without re-checking.
  final AppRelease? available;

  @override
  AppRelease? get release => available;
}

/// Drives the whole update lifecycle: check GitHub, download the APK with
/// progress, hand it to Android's installer.
///
/// Deliberately **never** auto-downloads or auto-installs. This app is
/// sideloaded and its user chose that; spending someone's mobile data and
/// replacing their binary without a tap would be the wrong default. The
/// automatic part is only the check, and only on a throttle.
class UpdateController extends Notifier<UpdateState> {
  /// How stale a check may be before the app quietly repeats it. Releases are
  /// occasional; polling GitHub more often than this only spends rate limit.
  static const checkInterval = Duration(hours: 6);

  static const _lastCheckedKey = 'update_last_checked_ms';
  static const _skippedKey = 'update_skipped_version';

  CancelToken? _cancelToken;
  bool _disposed = false;

  /// Dismissing the dashboard banner is a within-session gesture, not a
  /// preference — it should come back next launch if the update is still there.
  bool _bannerDismissed = false;

  /// Version the user chose to skip; suppresses the banner but never the
  /// About screen, which must always tell the truth about what's available.
  String? _skipped;
  bool _skippedLoaded = false;

  UpdateRepository get _repo => ref.read(updateRepositoryProvider);
  ApkInstaller get _installer => ref.read(apkInstallerProvider);

  @override
  UpdateState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelToken?.cancel('disposed');
    });
    return const UpdateIdle();
  }

  /// True when the dashboard should surface the update banner.
  bool get shouldPromptBanner {
    final current = state;
    if (_bannerDismissed) return false;
    return switch (current) {
      UpdateAvailable(:final available) => available.version.name != _skipped,
      UpdateReady() => true,
      _ => false,
    };
  }

  bool get isSkipped => switch (state) {
        UpdateAvailable(:final available) => available.version.name == _skipped,
        _ => false,
      };

  /// Throttled check run once at app start. Silent on failure — an offline
  /// launch must not greet the user with an error they didn't ask for.
  Future<void> autoCheck() async {
    if (!AppConfig.updatesEnabled) return;
    if (state is! UpdateIdle) return;
    final prefs = await _prefs();
    final last = prefs?.getInt(_lastCheckedKey);
    if (last != null) {
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(last),
      );
      if (age < checkInterval) return;
    }
    await check(silent: true);
  }

  /// Ask GitHub what the newest release is.
  ///
  /// [silent] suppresses the error state so a background check can fail
  /// invisibly; a user-initiated check always reports what went wrong.
  Future<void> check({bool silent = false}) async {
    if (!AppConfig.updatesEnabled) return;
    if (state is UpdateChecking || state is UpdateDownloading) return;

    final previous = state;
    state = const UpdateChecking();
    await _loadSkipped();

    try {
      // Sequential, not `(a, b).wait`: a record wait wraps any failure in a
      // ParallelWaitError, which would swallow the UpdateException carrying
      // the message and the offline flag this screen is built around. Reading
      // the installed version first is local and effectively free.
      final installed = await ref.read(installedAppProvider.future);
      final latest = await _repo.latest();
      if (_disposed) return;

      await _rememberCheckTime();
      if (_disposed) return;

      if (latest == null || latest.version <= installed.version) {
        state = UpdateUpToDate(DateTime.now());
        return;
      }
      state = UpdateAvailable(latest);
    } on Object catch (error) {
      if (_disposed) return;
      if (silent) {
        // Leave the UI exactly as it was rather than replacing a known-good
        // "up to date" with a scary banner nobody requested.
        state = previous;
        return;
      }
      state = _failure(error, available: previous.release);
    }
  }

  /// Download the available release's APK.
  Future<void> download() async {
    final available = state.release;
    if (available == null || state is UpdateDownloading) return;
    if (!available.isInstallable) {
      state = UpdateFailed(
        'This release has no APK attached — open it on GitHub instead.',
        available: available,
      );
      return;
    }

    final token = CancelToken();
    _cancelToken = token;
    state = UpdateDownloading(available, 0, available.apkBytes);

    try {
      final apk = await _repo.downloadApk(
        available,
        cancelToken: token,
        onProgress: (received, total) {
          if (_disposed || state is! UpdateDownloading) return;
          state = UpdateDownloading(available, received, total);
        },
      );
      if (_disposed) return;
      state = UpdateReady(available, apk);
    } on Object catch (error) {
      if (_disposed) return;
      if (error is DioException && CancelToken.isCancel(error)) {
        state = UpdateAvailable(available);
        return;
      }
      state = _failure(error, available: available);
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }

  /// Abort an in-flight download and fall back to the "available" state.
  void cancelDownload() {
    _cancelToken?.cancel('cancelled by user');
  }

  /// Hand the downloaded APK to Android. On success the system installer takes
  /// over and this process is about to be replaced, so there is nothing to
  /// await — [UpdateReady] simply stays put behind the system dialog.
  Future<void> install() async {
    final current = state;
    if (current is! UpdateReady) return;

    if (!await current.apk.exists()) {
      if (_disposed) return;
      // The cache was evicted between download and tap. Re-downloading is the
      // fix, so drop back to "available" rather than to a dead end.
      state = UpdateAvailable(current.available);
      return;
    }

    final result = await _installer.install(current.apk);
    if (_disposed) return;
    switch (result) {
      case InstallStarted():
        state = UpdateReady(current.available, current.apk);
      case InstallRejected(reason: InstallFailure.notPermitted):
        state = UpdateReady(
          current.available,
          current.apk,
          needsPermission: true,
        );
      case InstallRejected(reason: InstallFailure.missingFile):
        state = UpdateAvailable(current.available);
      case InstallRejected(:final message):
        state = UpdateFailed(message, available: current.available);
    }
  }

  /// Open the system screen where "install unknown apps" is granted.
  Future<bool> openInstallSettings() => _installer.openInstallSettings();

  /// Re-check the grant after the user comes back from Settings.
  Future<void> recheckPermission() async {
    final current = state;
    if (current is! UpdateReady || !current.needsPermission) return;
    if (await _installer.canInstall()) {
      if (_disposed) return;
      state = UpdateReady(current.available, current.apk);
    }
  }

  /// Stop nagging about this version. The About screen still shows it.
  Future<void> skipCurrent() async {
    final available = state.release;
    if (available == null) return;
    _skipped = available.version.name;
    _bannerDismissed = true;
    (await _prefs())?.setString(_skippedKey, _skipped!);
    // Nothing about the state changed, but `shouldPromptBanner` did — poke
    // listeners so the banner leaves.
    state = switch (state) {
      UpdateAvailable(:final available) => UpdateAvailable(available),
      final other => other,
    };
  }

  /// Hide the banner for this session only.
  void dismissBanner() {
    _bannerDismissed = true;
    state = switch (state) {
      UpdateAvailable(:final available) => UpdateAvailable(available),
      final other => other,
    };
  }

  /// Drop a downloaded APK and start over from "available".
  Future<void> discardDownload() async {
    final available = state.release;
    await _repo.clearDownloads();
    if (_disposed) return;
    state = available == null
        ? const UpdateIdle()
        : UpdateAvailable(available);
  }

  UpdateFailed _failure(Object error, {AppRelease? available}) {
    if (error is UpdateException) {
      return UpdateFailed(
        error.message,
        isOffline: error.isOffline,
        available: available,
      );
    }
    return UpdateFailed(
      'Something went wrong checking for updates.',
      available: available,
    );
  }

  Future<void> _rememberCheckTime() async {
    (await _prefs())?.setInt(
      _lastCheckedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _loadSkipped() async {
    if (_skippedLoaded) return;
    _skippedLoaded = true;
    _skipped = (await _prefs())?.getString(_skippedKey);
  }

  /// Best-effort: a build without the plugin (or a widget test) simply gets no
  /// persistence, which degrades to "check every launch".
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
