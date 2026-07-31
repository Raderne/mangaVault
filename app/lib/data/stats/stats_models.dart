// Dart mirrors of the server's stats DTOs
// (server/src/modules/stats/stats.dto.ts). Manual `fromJson`, same style as the
// library and cover models — small, read-only, no codegen.

import '../library/library_models.dart';

/// Where the vault's bytes live.
///
/// Kept as three parts rather than one total because they behave completely
/// differently: on a 2,000-title library the database is ~113 MB while the
/// cover images are ~613 MB, so "the vault is growing" nearly always means
/// covers — which one combined number hid.
class VaultStorage {
  const VaultStorage({
    this.databaseBytes = 0,
    this.coversBytes = 0,
    this.backupsBytes = 0,
    this.totalBytes = 0,
  });

  /// Postgres: every table, index and TOAST segment.
  final int databaseBytes;

  /// Archived cover images on the server's disk.
  final int coversBytes;

  /// The original `.tachibk` files, kept verbatim.
  final int backupsBytes;
  final int totalBytes;

  /// Share of the vault taken by covers, in [0, 1] — the headline ratio.
  double get coverFraction =>
      totalBytes == 0 ? 0 : (coversBytes / totalBytes).clamp(0.0, 1.0);

  bool get isEmpty => totalBytes == 0;

  factory VaultStorage.fromJson(Map<String, dynamic> j) => VaultStorage(
        databaseBytes: (j['databaseBytes'] as num?)?.toInt() ?? 0,
        coversBytes: (j['coversBytes'] as num?)?.toInt() ?? 0,
        backupsBytes: (j['backupsBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Headline archive figures behind the dashboard's stat cells.
class LibraryStats {
  const LibraryStats({
    required this.totalTitles,
    required this.favoriteTitles,
    required this.totalChapters,
    required this.readChapters,
    required this.addedLast7Days,
    required this.sourceCount,
    required this.bySourceApp,
    required this.byStatus,
    required this.coversArchived,
    required this.coversFailed,
    required this.importCount,
    required this.lastImportAt,
    required this.vaultSizeBytes,
    this.vaultStorage = const VaultStorage(),
  });

  final int totalTitles;
  final int favoriteTitles;
  final int totalChapters;
  final int readChapters;
  final int addedLast7Days;
  final int sourceCount;
  final Map<String, int> bySourceApp;
  final Map<String, int> byStatus;
  final int coversArchived;
  final int coversFailed;
  final int importCount;
  final int? lastImportAt;
  final int vaultSizeBytes;

  /// The same total, split by database / covers / backups.
  final VaultStorage vaultStorage;

  /// Read fraction of the whole archive, in [0, 1].
  double get readFraction =>
      totalChapters == 0 ? 0 : (readChapters / totalChapters).clamp(0.0, 1.0);

  /// Fraction of titles whose cover is archived, in [0, 1].
  double get coverFraction =>
      totalTitles == 0 ? 0 : (coversArchived / totalTitles).clamp(0.0, 1.0);

  /// True when nothing has been imported yet (drives the empty dashboard).
  bool get isEmpty => totalTitles == 0 && importCount == 0;

  factory LibraryStats.fromJson(Map<String, dynamic> j) => LibraryStats(
        totalTitles: (j['totalTitles'] as num?)?.toInt() ?? 0,
        favoriteTitles: (j['favoriteTitles'] as num?)?.toInt() ?? 0,
        totalChapters: (j['totalChapters'] as num?)?.toInt() ?? 0,
        readChapters: (j['readChapters'] as num?)?.toInt() ?? 0,
        addedLast7Days: (j['addedLast7Days'] as num?)?.toInt() ?? 0,
        sourceCount: (j['sourceCount'] as num?)?.toInt() ?? 0,
        bySourceApp: _countMap(j['bySourceApp']),
        byStatus: _countMap(j['byStatus']),
        coversArchived: (j['coversArchived'] as num?)?.toInt() ?? 0,
        coversFailed: (j['coversFailed'] as num?)?.toInt() ?? 0,
        importCount: (j['importCount'] as num?)?.toInt() ?? 0,
        lastImportAt: (j['lastImportAt'] as num?)?.toInt(),
        vaultSizeBytes: (j['vaultSizeBytes'] as num?)?.toInt() ?? 0,
        vaultStorage: VaultStorage.fromJson(
          (j['vaultStorage'] as Map<String, dynamic>?) ?? const {},
        ),
      );

  static Map<String, int> _countMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key as String: (entry.value as num?)?.toInt() ?? 0,
    };
  }
}

/// How stale the newest backup of one source app is.
enum Staleness { fresh, aging, stale }

/// Freshness of the backups contributed by one source app ("app.mihon", …).
class BackupHealth {
  const BackupHealth({
    required this.sourceApp,
    required this.lastImportAt,
    required this.importCount,
    required this.titleCount,
    required this.staleness,
  });

  final String sourceApp;
  final int lastImportAt;
  final int importCount;
  final int titleCount;
  final Staleness staleness;

  factory BackupHealth.fromJson(Map<String, dynamic> j) => BackupHealth(
        sourceApp: (j['sourceApp'] as String?) ?? 'unknown',
        lastImportAt: (j['lastImportAt'] as num?)?.toInt() ?? 0,
        importCount: (j['importCount'] as num?)?.toInt() ?? 0,
        titleCount: (j['titleCount'] as num?)?.toInt() ?? 0,
        staleness: switch (j['staleness'] as String?) {
          'fresh' => Staleness.fresh,
          'aging' => Staleness.aging,
          _ => Staleness.stale,
        },
      );
}

/// A title to pick back up: the grid row plus where to continue.
class ResumeItem {
  const ResumeItem({
    required this.manga,
    required this.readCount,
    required this.nextChapter,
  });

  final MangaListItem manga;
  final int readCount;
  final ChapterRef nextChapter;

  /// Read fraction of this title, in [0, 1].
  double get readFraction => manga.chapterCount == 0
      ? 0
      : (readCount / manga.chapterCount).clamp(0.0, 1.0);

  factory ResumeItem.fromJson(Map<String, dynamic> j) => ResumeItem(
        manga: MangaListItem.fromJson(j),
        readCount: (j['readCount'] as num?)?.toInt() ?? 0,
        nextChapter:
            ChapterRef.fromJson((j['nextChapter'] as Map<String, dynamic>?) ?? const {}),
      );
}
