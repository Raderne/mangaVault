import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DriveUploadMode { manual, automatic }

/// Hours between automatic checks. No "off" — that is [DriveUploadMode.manual].
const kDriveIntervals = <int>[6, 12, 24];

/// Automatic uploads kept on Drive. Pruned only after a new one succeeds, and
/// never touches a file the user sent by hand.
const kDriveKeepAutomatic = 5;

/// Everything the Drive uploader persists. Device-local, like
/// `AutoImportSettings`: which Google account a phone uses means nothing to the
/// vault.
class DriveBackupSettings {
  const DriveBackupSettings({
    this.mode = DriveUploadMode.manual,
    this.intervalHours = 24,
    this.afterImport = true,
    this.lastCheckAtMs = 0,
    this.lastUploadAtMs = 0,
    this.lastFileName = '',
    this.lastEpoch = '',
    this.lastCursor = '',
  });

  final DriveUploadMode mode;
  final int intervalHours;

  /// Also upload right after an import commits — the moment the library most
  /// obviously changed.
  final bool afterImport;

  /// Last automatic check that finished (uploaded, or found nothing new). A
  /// failed one is not recorded, so it is retried on the next resume.
  final int lastCheckAtMs;

  final int lastUploadAtMs;
  final String lastFileName;

  /// The server's `/sync/meta` epoch and cursor at the last automatic upload.
  /// The cursor is the vault's `row_version` high-water mark, so an unchanged
  /// pair means the backup on Drive is still current.
  final String lastEpoch;
  final String lastCursor;

  bool get isAutomatic => mode == DriveUploadMode.automatic;

  /// Whether an automatic check is owed. A throttle on a resume, not a timer.
  bool isDue(DateTime now) =>
      isAutomatic &&
      now.millisecondsSinceEpoch - lastCheckAtMs >=
          Duration(hours: intervalHours).inMilliseconds;

  bool changedSince(String epoch, String cursor) =>
      epoch != lastEpoch || cursor != lastCursor;

  DriveBackupSettings copyWith({
    DriveUploadMode? mode,
    int? intervalHours,
    bool? afterImport,
    int? lastCheckAtMs,
    int? lastUploadAtMs,
    String? lastFileName,
    String? lastEpoch,
    String? lastCursor,
  }) =>
      DriveBackupSettings(
        mode: mode ?? this.mode,
        intervalHours: intervalHours ?? this.intervalHours,
        afterImport: afterImport ?? this.afterImport,
        lastCheckAtMs: lastCheckAtMs ?? this.lastCheckAtMs,
        lastUploadAtMs: lastUploadAtMs ?? this.lastUploadAtMs,
        lastFileName: lastFileName ?? this.lastFileName,
        lastEpoch: lastEpoch ?? this.lastEpoch,
        lastCursor: lastCursor ?? this.lastCursor,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'intervalHours': intervalHours,
        'afterImport': afterImport,
        'lastCheckAtMs': lastCheckAtMs,
        'lastUploadAtMs': lastUploadAtMs,
        'lastFileName': lastFileName,
        'lastEpoch': lastEpoch,
        'lastCursor': lastCursor,
      };

  /// Corrupt or missing values fall back to defaults rather than bricking the
  /// screen.
  static DriveBackupSettings fromJson(Object? json) {
    if (json is! Map) return const DriveBackupSettings();
    final interval = (json['intervalHours'] as num?)?.toInt();
    return DriveBackupSettings(
      mode: json['mode'] == DriveUploadMode.automatic.name
          ? DriveUploadMode.automatic
          : DriveUploadMode.manual,
      intervalHours: kDriveIntervals.contains(interval) ? interval! : 24,
      afterImport: json['afterImport'] as bool? ?? true,
      lastCheckAtMs: (json['lastCheckAtMs'] as num?)?.toInt() ?? 0,
      lastUploadAtMs: (json['lastUploadAtMs'] as num?)?.toInt() ?? 0,
      lastFileName: json['lastFileName'] as String? ?? '',
      lastEpoch: json['lastEpoch'] as String? ?? '',
      lastCursor: json['lastCursor'] as String? ?? '',
    );
  }
}

const _kSettings = 'drive.settings';

/// Mirrors [DriveBackupSettings] into `shared_preferences`, following
/// `AutoImportSettingsController` — including its `_touched` guard.
class DriveBackupSettingsController extends Notifier<DriveBackupSettings> {
  bool _touched = false;

  /// Completes once saved settings are loaded. The uploader's launch check
  /// awaits it; reading before then would see the defaults (manual) and
  /// silently skip every cold start.
  Future<void> ready = Future.value();

  @override
  DriveBackupSettings build() {
    ready = Future<void>.microtask(_load);
    return const DriveBackupSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_touched) return;
      final raw = prefs.getString(_kSettings);
      if (raw == null) return;
      state = DriveBackupSettings.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable prefs — defaults are a fine starting point.
    }
  }

  /// Switching to automatic restarts the clock, so the first check is due at
  /// once rather than an interval after some long-past run.
  void setMode(DriveUploadMode mode) => _write(state.copyWith(
        mode: mode,
        lastCheckAtMs:
            mode == DriveUploadMode.automatic && !state.isAutomatic ? 0 : null,
      ));

  void setInterval(int hours) => _write(state.copyWith(intervalHours: hours));

  void setAfterImport(bool value) =>
      _write(state.copyWith(afterImport: value));

  void markChecked(DateTime at) =>
      _write(state.copyWith(lastCheckAtMs: at.millisecondsSinceEpoch));

  /// Record a finished upload. Only an automatic (full-vault) upload carries
  /// [epoch]/[cursor]: a hand-picked slice from the wizard says nothing about
  /// whether the *whole* vault is on Drive.
  void markUploaded(
    String fileName,
    DateTime at, {
    String? epoch,
    String? cursor,
  }) =>
      _write(state.copyWith(
        lastFileName: fileName,
        lastUploadAtMs: at.millisecondsSinceEpoch,
        lastCheckAtMs: cursor == null ? null : at.millisecondsSinceEpoch,
        lastEpoch: epoch,
        lastCursor: cursor,
      ));

  void _write(DriveBackupSettings next) {
    _touched = true;
    state = next;
    _persist(next);
  }

  Future<void> _persist(DriveBackupSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    } catch (_) {
      // Best-effort: the in-memory settings are already updated.
    }
  }
}

final driveBackupSettingsProvider =
    NotifierProvider<DriveBackupSettingsController, DriveBackupSettings>(
  DriveBackupSettingsController.new,
);
