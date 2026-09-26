import 'dart:convert';

import '../../../data/export/export_models.dart';

/// How one saved backup selection is written to Drive.
enum DriveOutputLayout { single, splitByApp, splitByFavorite }

/// The selection shared by manual and automatic Drive uploads.
class DriveBackupPlan {
  const DriveBackupPlan({
    this.scope = const ExportScope(),
    this.layout = DriveOutputLayout.single,
  });

  final ExportScope scope;
  final DriveOutputLayout layout;

  /// Stable across launches; a change means the last upload is a different backup.
  String get signature => jsonEncode(toJson());

  String get summary {
    final what = scope.mode == ExportMode.all && scope.filters.isEmpty
        ? 'Whole vault'
        : '${scope.filters.activeCount} '
              'filter${scope.filters.activeCount == 1 ? '' : 's'}';
    final how = switch (layout) {
      DriveOutputLayout.single => 'one file',
      DriveOutputLayout.splitByApp => 'one file per reading app',
      DriveOutputLayout.splitByFavorite => 'favorites and other titles split',
    };
    final partial = scope.includes.isLossless ? '' : ', partial contents';
    return '$what, $how$partial.';
  }

  Map<String, dynamic> toJson() => {
    'scope': scope.toJson(),
    'layout': layout.name,
  };

  static DriveBackupPlan fromJson(Object? json) {
    if (json is! Map) return const DriveBackupPlan();
    final scope = ExportScope.fromJson(json['scope']);
    // A hand-picked id list goes stale the moment the library changes.
    if (scope.mode == ExportMode.ids) return const DriveBackupPlan();
    return DriveBackupPlan(
      scope: scope,
      layout: switch (json['layout']) {
        'splitByApp' => DriveOutputLayout.splitByApp,
        'splitByFavorite' => DriveOutputLayout.splitByFavorite,
        _ => DriveOutputLayout.single,
      },
    );
  }
}

/// One file within a [DriveBackupPlan].
class DriveBackupPart {
  const DriveBackupPart({
    required this.scope,
    required this.suffix,
    required this.key,
  });

  final ExportScope scope;

  /// Inserted before `.tachibk`. Empty for a single file.
  final String suffix;

  /// Stable within a run. Retention uses it to recognise a complete set.
  final String key;
}

/// Expands a plan into the files it should produce.
///
/// [appIds] is every reading app currently in the vault, used only when
/// splitting by app without a narrower app selection. App provenance overlaps:
/// a title imported by two apps belongs in both files.
List<DriveBackupPart> expandDrivePlan(
  DriveBackupPlan plan, {
  List<String> appIds = const [],
}) {
  switch (plan.layout) {
    case DriveOutputLayout.single:
      return [DriveBackupPart(scope: plan.scope, suffix: '', key: 'all')];
    case DriveOutputLayout.splitByFavorite:
      final filters = plan.scope.filters.copyWith(clearFavorite: true);
      final base = plan.scope.copyWith(
        mode: ExportMode.filter,
        filters: filters,
      );
      return [
        DriveBackupPart(
          scope: base.copyWith(filters: filters.copyWith(favorite: true)),
          suffix: 'favorites',
          key: 'favorites',
        ),
        DriveBackupPart(
          scope: base.copyWith(filters: filters.copyWith(favorite: false)),
          suffix: 'not-favorites',
          key: 'not-favorites',
        ),
      ];
    case DriveOutputLayout.splitByApp:
      final selected = plan.scope.filters.sourceApps.toList()..sort();
      final apps = selected.isNotEmpty ? selected : (appIds.toList()..sort());
      return [
        for (final id in apps)
          DriveBackupPart(
            scope: plan.scope.copyWith(
              mode: ExportMode.filter,
              filters: plan.scope.filters.copyWith(sourceApps: {id}),
            ),
            suffix: 'from-${_fileToken(id)}',
            key: 'app:$id',
          ),
      ];
  }
}

/// Keeps the server's `app_date` prefix so a restore still attributes the file.
String driveObjectName(String fileName, String suffix) {
  if (suffix.isEmpty) return fileName;
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '${fileName}_$suffix';
  return '${fileName.substring(0, dot)}_$suffix${fileName.substring(dot)}';
}

String _fileToken(String raw) =>
    raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
