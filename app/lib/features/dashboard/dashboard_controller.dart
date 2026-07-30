import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_models.dart';
import '../../data/stats/stats_models.dart';
import '../../data/stats/stats_repository.dart';

/// Everything the dashboard renders, fetched as one snapshot so the bento grid
/// appears in a single pass instead of cell-by-cell.
class DashboardData {
  const DashboardData({
    required this.stats,
    required this.health,
    required this.resume,
    required this.recent,
  });

  final LibraryStats stats;
  final List<BackupHealth> health;
  final List<ResumeItem> resume;
  final List<MangaListItem> recent;

  /// The freshest source app, which drives the health cell's headline.
  BackupHealth? get newestBackup => health.isEmpty ? null : health.first;
}

/// Shelf length — enough to scroll a little, small enough to stay cheap.
const int kShelfLimit = 12;

/// The dashboard snapshot. `ref.invalidate` (pull-to-refresh) re-runs all four
/// requests in parallel.
final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final repo = ref.watch(statsRepositoryProvider);
  final (stats, health, resume, recent) = await (
    repo.libraryStats(),
    repo.backupHealth(),
    repo.resumeReading(limit: kShelfLimit),
    repo.recentlyAdded(limit: kShelfLimit),
  ).wait;
  return DashboardData(
    stats: stats,
    health: health,
    resume: resume,
    recent: recent,
  );
});
