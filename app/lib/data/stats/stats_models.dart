// Dart mirrors of the server's stats DTOs
// (server/src/modules/stats/stats.dto.ts). Manual `fromJson`, same style as the
// library and cover models — small, read-only, no codegen.

import '../library/library_models.dart';

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
