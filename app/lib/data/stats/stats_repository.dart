import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/sync/sync_controller.dart';
import '../library/library_models.dart';
import '../local/local_library_dao.dart';
import 'stats_models.dart';

/// The dashboard read surface. An interface for the same reason as
/// `LibraryRepository`: the backing store is an implementation detail.
abstract class StatsRepository {
  /// Archive-wide counters (titles, chapters, covers, vault size).
  Future<LibraryStats> libraryStats();

  /// Backup freshness per source app, newest import first.
  Future<List<BackupHealth>> backupHealth();

  /// Newest titles in the archive.
  Future<List<MangaListItem>> recentlyAdded({int limit});

  /// Titles with reading progress and an unread chapter left.
  Future<List<ResumeItem>> resumeReading({int limit});
}

/// Dashboard aggregates computed from the **on-device mirror**.
///
/// The server derives these on read from Postgres; the mirror stores the same
/// per-title counters, so the identical figures fall out of a local `SUM` /
/// `GROUP BY`. The one exception is `vaultSizeBytes` — Postgres size plus the
/// server's `storage/` directory — which arrives with `/sync/meta` and is read
/// back from the sync bookkeeping row.
class LocalStatsRepository implements StatsRepository {
  LocalStatsRepository(this._dao);

  final LocalLibraryDao _dao;

  @override
  Future<LibraryStats> libraryStats() => _dao.libraryStats();

  @override
  Future<List<BackupHealth>> backupHealth() => _dao.backupHealth();

  @override
  Future<List<MangaListItem>> recentlyAdded({int limit = 10}) =>
      _dao.recentlyAdded(limit);

  @override
  Future<List<ResumeItem>> resumeReading({int limit = 10}) =>
      _dao.resumeReading(limit);
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => LocalStatsRepository(ref.watch(localLibraryDaoProvider)),
);
