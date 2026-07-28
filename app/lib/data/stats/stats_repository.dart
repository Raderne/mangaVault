import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../library/library_models.dart';
import 'stats_models.dart';

/// Talks to the server's `/stats/*` endpoints — the dashboard aggregates (M5).
class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  /// Archive-wide counters (titles, chapters, covers, vault size).
  Future<LibraryStats> libraryStats() async {
    final res = await _dio.get<Map<String, dynamic>>('/stats/library');
    return LibraryStats.fromJson(res.data!);
  }

  /// Backup freshness per source app, newest import first.
  Future<List<BackupHealth>> backupHealth() async {
    final res = await _dio.get<List<dynamic>>('/stats/backup-health');
    return (res.data ?? const [])
        .map((e) => BackupHealth.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Newest titles in the archive.
  Future<List<MangaListItem>> recentlyAdded({int limit = 10}) async {
    final res = await _dio.get<List<dynamic>>(
      '/stats/recently-added',
      queryParameters: {'limit': limit},
    );
    return (res.data ?? const [])
        .map((e) => MangaListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Titles with reading progress and an unread chapter left.
  Future<List<ResumeItem>> resumeReading({int limit = 10}) async {
    final res = await _dio.get<List<dynamic>>(
      '/stats/resume-reading',
      queryParameters: {'limit': limit},
    );
    return (res.data ?? const [])
        .map((e) => ResumeItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(apiClientProvider)),
);
