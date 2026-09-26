import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drive_backup_plan.dart';

enum DriveUploadMode { manual, automatic }

/// Hours between automatic checks. No "off" — that is [DriveUploadMode.manual].
const kDriveIntervals = <int>[6, 12, 24];

/// Complete Drive backup runs kept. A split backup counts as one run, and a
/// file sent by the old export wizard is never pruned.
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
    this.lastFileNames = const [],
    this.lastEpoch = '',
    this.lastCursor = '',
    this.plan = const DriveBackupPlan(),
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
  final List<String> lastFileNames;

  /// What both manual and automatic uploads send.
  final DriveBackupPlan plan;

  String get lastUploadLabel => switch (lastFileNames.length) {
    0 => '',
    1 => lastFileNames.single,
    _ => '${lastFileNames.length} files',
  };

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
    List<String>? lastFileNames,
    String? lastEpoch,
    String? lastCursor,
    DriveBackupPlan? plan,
  }) => DriveBackupSettings(
    mode: mode ?? this.mode,
    intervalHours: intervalHours ?? this.intervalHours,
    afterImport: afterImport ?? this.afterImport,
    lastCheckAtMs: lastCheckAtMs ?? this.lastCheckAtMs,
    lastUploadAtMs: lastUploadAtMs ?? this.lastUploadAtMs,
    lastFileNames: lastFileNames ?? this.lastFileNames,
    lastEpoch: lastEpoch ?? this.lastEpoch,
    lastCursor: lastCursor ?? this.lastCursor,
    plan: plan ?? this.plan,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'intervalHours': intervalHours,
    'afterImport': afterImport,
    'lastCheckAtMs': lastCheckAtMs,
    'lastUploadAtMs': lastUploadAtMs,
    'lastFileNames': lastFileNames,
    'lastFileName': lastUploadLabel,
    'lastEpoch': lastEpoch,
    'lastCursor': lastCursor,
    'plan': plan.toJson(),
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
      lastFileNames: _fileNames(json),
      lastEpoch: json['lastEpoch'] as String? ?? '',
      lastCursor: json['lastCursor'] as String? ?? '',
      plan: DriveBackupPlan.fromJson(json['plan']),
    );
  }

  static List<String> _fileNames(Map json) {
    final names = json['lastFileNames'];
    if (names is List) {
      return [
        for (final name in names)
          if (name is String && name.isNotEmpty) name,
      ];
    }
    final legacy = json['lastFileName'];
    return legacy is String && legacy.isNotEmpty ? [legacy] : const [];
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
  void setMode(DriveUploadMode mode) => _write(
    state.copyWith(
      mode: mode,
      lastCheckAtMs: mode == DriveUploadMode.automatic && !state.isAutomatic
          ? 0
          : null,
    ),
  );

  void setInterval(int hours) => _write(state.copyWith(intervalHours: hours));

  void setAfterImport(bool value) => _write(state.copyWith(afterImport: value));

  /// A different selection invalidates the "already backed up" cursor, so the
  /// next check uploads it instead of reporting that nothing changed.
  void setPlan(DriveBackupPlan plan) {
    final changed = plan.signature != state.plan.signature;
    _write(
      changed
          ? DriveBackupSettings(
              mode: state.mode,
              intervalHours: state.intervalHours,
              afterImport: state.afterImport,
              lastUploadAtMs: state.lastUploadAtMs,
              lastFileNames: state.lastFileNames,
              plan: plan,
            )
          : state.copyWith(plan: plan),
    );
  }

  void markChecked(DateTime at, {String? epoch, String? cursor}) => _write(
    state.copyWith(
      lastCheckAtMs: at.millisecondsSinceEpoch,
      lastEpoch: epoch,
      lastCursor: cursor,
    ),
  );

  /// Record a finished upload of the current plan.
  void markUploaded(
    List<String> fileNames,
    DateTime at, {
    String? epoch,
    String? cursor,
  }) => _write(
    state.copyWith(
      lastFileNames: fileNames,
      lastUploadAtMs: at.millisecondsSinceEpoch,
      lastCheckAtMs: cursor == null ? null : at.millisecondsSinceEpoch,
      lastEpoch: epoch,
      lastCursor: cursor,
    ),
  );

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
