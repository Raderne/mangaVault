import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_file_system.dart';

/// A device folder the app watches for new backups, and the app that writes
/// into it.
///
/// The [appId] is carried by the folder rather than derived per file because an
/// unattended import has nobody to answer the "which app is this from?"
/// question — see `ImportNeedsApp`. It is handed to
/// `PATCH /imports/stage/:id`, the endpoint that exists to take an explicit id.
/// `''` stays legal and means unknown.
class WatchedFolder {
  const WatchedFolder({
    required this.path,
    this.appId = '',
    this.lastFileName = '',
    this.lastModifiedMs = 0,
    this.lastImportedAtMs = 0,
  });

  final String path;
  final String appId;

  /// The newest file already imported from here, and its mtime. Written only
  /// after a *successful* commit, so a failed one is retried on the next scan
  /// rather than silently burned.
  final String lastFileName;
  final int lastModifiedMs;
  final int lastImportedAtMs;

  DateTime? get lastImportedAt => lastImportedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastImportedAtMs);

  /// Whether [entry] has already been through the importer.
  ///
  /// mtime alone isn't enough: a fork that writes several backups in the same
  /// second gives them identical timestamps, so an equal mtime falls through to
  /// the name — the same tie-break `sortEntries` uses.
  bool hasSeen(FileEntry entry) =>
      entry.modifiedMillis < lastModifiedMs ||
      (entry.modifiedMillis == lastModifiedMs && entry.name == lastFileName);

  WatchedFolder copyWith({
    String? appId,
    String? lastFileName,
    int? lastModifiedMs,
    int? lastImportedAtMs,
  }) =>
      WatchedFolder(
        path: path,
        appId: appId ?? this.appId,
        lastFileName: lastFileName ?? this.lastFileName,
        lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
        lastImportedAtMs: lastImportedAtMs ?? this.lastImportedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'appId': appId,
        'lastFileName': lastFileName,
        'lastModifiedMs': lastModifiedMs,
        'lastImportedAtMs': lastImportedAtMs,
      };

  static WatchedFolder? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    return WatchedFolder(
      path: path,
      appId: json['appId'] as String? ?? '',
      lastFileName: json['lastFileName'] as String? ?? '',
      lastModifiedMs: (json['lastModifiedMs'] as num?)?.toInt() ?? 0,
      lastImportedAtMs: (json['lastImportedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The intervals offered. `off` keeps the folders configured but scans only
/// when the user asks — the watcher is a convenience, not something that should
/// be all-or-nothing to turn off.
const kAutoImportIntervals = <int>[0, 6, 12, 24];

/// Everything the watcher needs, and the whole of what is persisted.
class AutoImportSettings {
  const AutoImportSettings({
    this.folders = const [],
    this.intervalHours = 12,
    this.lastScanAtMs = 0,
  });

  final List<WatchedFolder> folders;

  /// Hours between scans. `0` is off. This throttles a resume; it is not a
  /// timer — nothing runs while the app is closed.
  final int intervalHours;

  final int lastScanAtMs;

  bool get isEnabled => intervalHours > 0 && folders.isNotEmpty;

  DateTime? get lastScanAt =>
      lastScanAtMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(lastScanAtMs);

  /// Whether enough time has passed since the last scan.
  bool isDue(DateTime now) =>
      intervalHours > 0 &&
      now.millisecondsSinceEpoch - lastScanAtMs >=
          Duration(hours: intervalHours).inMilliseconds;

  AutoImportSettings copyWith({
    List<WatchedFolder>? folders,
    int? intervalHours,
    int? lastScanAtMs,
  }) =>
      AutoImportSettings(
        folders: folders ?? this.folders,
        intervalHours: intervalHours ?? this.intervalHours,
        lastScanAtMs: lastScanAtMs ?? this.lastScanAtMs,
      );
}

const _kFolders = 'autoimport.folders';
const _kInterval = 'autoimport.intervalHours';
const _kLastScan = 'autoimport.lastScanAt';

/// Auto-import configuration, mirrored into `shared_preferences`.
///
/// A device path means nothing to the vault, so this is device-local state and
/// stays out of the on-device mirror — the same rule [FolderMemoryController]
/// and `LibraryDisplayController` follow.
class AutoImportSettingsController extends Notifier<AutoImportSettings> {
  /// Set by the first mutation. A `_load()` still in flight at that point is
  /// older than what the user just did, and restoring over it would silently
  /// drop the folder they added.
  bool _touched = false;

  @override
  AutoImportSettings build() {
    Future<void>.microtask(_load);
    return const AutoImportSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_touched) return;
      final raw = prefs.getString(_kFolders);
      state = AutoImportSettings(
        folders: _decode(raw),
        intervalHours: prefs.getInt(_kInterval) ?? 12,
        lastScanAtMs: prefs.getInt(_kLastScan) ?? 0,
      );
    } catch (_) {
      // No storage available — the defaults are a fine starting point.
    }
  }

  static List<WatchedFolder> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?WatchedFolder.fromJson(item)];
    } catch (_) {
      return const []; // corrupt prefs must not brick the screen
    }
  }

  void addFolder(String path, String appId) {
    if (path.isEmpty) return;
    if (state.folders.any((f) => f.path == path)) return;
    _write(state.copyWith(
      folders: [...state.folders, WatchedFolder(path: path, appId: appId)],
    ));
  }

  void removeFolder(String path) => _write(state.copyWith(
        folders: state.folders.where((f) => f.path != path).toList(),
      ));

  void setAppId(String path, String appId) =>
      _update(path, (f) => f.copyWith(appId: appId));

  void setInterval(int hours) => _write(state.copyWith(intervalHours: hours));

  /// Record that [fileName] was imported from [path] and must not be picked up
  /// again. Called only after the commit succeeded.
  void markImported(String path, String fileName, int modifiedMs, DateTime at) =>
      _update(
        path,
        (f) => f.copyWith(
          lastFileName: fileName,
          lastModifiedMs: modifiedMs,
          lastImportedAtMs: at.millisecondsSinceEpoch,
        ),
      );

  void markScanned(DateTime at) =>
      _write(state.copyWith(lastScanAtMs: at.millisecondsSinceEpoch));

  void _update(String path, WatchedFolder Function(WatchedFolder) change) =>
      _write(state.copyWith(
        folders: [
          for (final f in state.folders) f.path == path ? change(f) : f,
        ],
      ));

  void _write(AutoImportSettings next) {
    _touched = true;
    state = next;
    _persist(next);
  }

  Future<void> _persist(AutoImportSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kFolders,
        jsonEncode([for (final f in settings.folders) f.toJson()]),
      );
      await prefs.setInt(_kInterval, settings.intervalHours);
      await prefs.setInt(_kLastScan, settings.lastScanAtMs);
    } catch (_) {
      // Best-effort: the in-memory settings are already updated.
    }
  }
}

final autoImportSettingsProvider =
    NotifierProvider<AutoImportSettingsController, AutoImportSettings>(
  AutoImportSettingsController.new,
);
