/// The reading apps a backup can come from.
///
/// Backups are named `<applicationId>_<timestamp>.tachibk`, so the filename
/// usually says which app produced it. This registry is what turns that id into
/// a name, offers a list when the filename doesn't say, and labels the library's
/// "from app" filter.
///
/// Manual `fromJson`, like every other DTO in the app — codegen is scoped to the
/// drift layer.
library;

/// Bucket id for backups whose producing app was never identified. Mirrors the
/// server's `COALESCE(NULLIF(source_app, ''), 'unknown')`.
const String kUnknownSourceApp = 'unknown';

class BackupApp {
  const BackupApp({
    required this.id,
    required this.displayName,
    this.accent,
    this.curated = false,
    this.importCount = 0,
    this.titleCount = 0,
    this.lastImportAt = 0,
  });

  /// Android application id, e.g. `app.mihon`.
  final String id;
  final String displayName;

  /// Hex accent for this app's chip; null falls back to the theme.
  final String? accent;

  /// Shipped by the server rather than added by the user — can't be deleted.
  final bool curated;

  /// Imports recorded against this app; 0 means "never imported from".
  final int importCount;
  final int titleCount;
  final int lastImportAt;

  bool get used => importCount > 0;

  factory BackupApp.fromJson(Map<String, dynamic> j) => BackupApp(
        id: (j['id'] as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        accent: j['accent'] as String?,
        curated: (j['curated'] as bool?) ?? false,
        importCount: (j['importCount'] as num?)?.toInt() ?? 0,
        titleCount: (j['titleCount'] as num?)?.toInt() ?? 0,
        lastImportAt: (j['lastImportAt'] as num?)?.toInt() ?? 0,
      );
}

/// A source app as the library filter sees it: how it should read, and how many
/// titles it accounts for. Derived from the mirror, so it only ever lists apps
/// the vault actually holds titles from.
class SourceAppOption {
  const SourceAppOption({
    required this.id,
    required this.label,
    required this.count,
  });

  final String id;
  final String label;
  final int count;
}

/// Display name for an app id, falling back to the id itself.
///
/// Several code paths need this — the picker, the filter chips, the Backups
/// history and Title Details — and an unresolvable id must still render as
/// *something*, or a backup from an app the registry never learned shows a
/// blank chip.
String backupAppLabel(String id, {String? displayName}) {
  if (displayName != null && displayName.trim().isNotEmpty) {
    return displayName;
  }
  if (id.trim().isEmpty || id == kUnknownSourceApp) return 'Unknown app';
  return id;
}
