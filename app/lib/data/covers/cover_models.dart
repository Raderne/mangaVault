// Dart mirrors of the server's cover DTOs
// (server/src/modules/covers/cover.dto.ts). Manual `fromJson`, matching the
// import/library models — small, read-only, no codegen.

/// Response from `POST /covers/archive-missing`.
class CoverArchiveStarted {
  const CoverArchiveStarted({
    required this.jobId,
    required this.total,
    required this.alreadyRunning,
  });

  final String jobId;
  final int total;
  final bool alreadyRunning;

  factory CoverArchiveStarted.fromJson(Map<String, dynamic> j) =>
      CoverArchiveStarted(
        jobId: j['jobId'] as String,
        total: (j['total'] as num?)?.toInt() ?? 0,
        alreadyRunning: j['alreadyRunning'] as bool? ?? false,
      );
}

/// Poll response from `GET /covers/jobs/:jobId`.
class CoverJobStatus {
  const CoverJobStatus({
    required this.jobId,
    required this.total,
    required this.done,
    required this.archived,
    required this.failed,
    required this.skipped,
    required this.finished,
  });

  final String jobId;
  final int total;
  final int done;
  final int archived;
  final int failed;
  final int skipped;
  final bool finished;

  double get fraction => total == 0 ? 1 : (done / total).clamp(0.0, 1.0);

  factory CoverJobStatus.fromJson(Map<String, dynamic> j) => CoverJobStatus(
        jobId: j['jobId'] as String,
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        archived: (j['archived'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        finished: j['finished'] as bool? ?? false,
      );
}

/// Result of archiving a single cover (`POST /covers/:id/retry`).
class CoverResult {
  const CoverResult({
    required this.mangaId,
    required this.outcome,
    required this.coverState,
    required this.error,
  });

  final String mangaId;
  final String outcome; // 'archived' | 'failed' | 'skipped'
  final String coverState;
  final String? error;

  bool get archived => outcome == 'archived';

  factory CoverResult.fromJson(Map<String, dynamic> j) => CoverResult(
        mangaId: j['mangaId'] as String,
        outcome: (j['outcome'] as String?) ?? 'failed',
        coverState: (j['coverState'] as String?) ?? 'failed',
        error: j['error'] as String?,
      );
}
