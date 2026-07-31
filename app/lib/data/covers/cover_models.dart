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

/// A cover-archiving run: `GET /covers/jobs/:jobId`, `GET /covers/jobs/active`,
/// and each entry of `GET /covers/jobs`.
///
/// Runs are durable on the server, so one can be in progress that this client
/// never started — kicked off by an import, or resumed after a server restart.
class CoverJobStatus {
  const CoverJobStatus({
    required this.jobId,
    required this.status,
    required this.trigger,
    required this.total,
    required this.done,
    required this.archived,
    required this.failed,
    required this.skipped,
    required this.finished,
    required this.cancelRequested,
    required this.error,
  });

  final String jobId;

  /// `running` | `finished` | `cancelled` | `failed` | `interrupted`.
  final String status;

  /// What started the run: `manual` | `import` | `resume`.
  final String trigger;
  final int total;
  final int done;
  final int archived;
  final int failed;
  final int skipped;
  final bool finished;

  /// A cancel was requested; downloads already in flight are draining.
  final bool cancelRequested;

  /// Why the run itself failed (not an individual cover).
  final String? error;

  bool get cancelled => status == 'cancelled';
  bool get startedByImport => trigger == 'import';

  double get fraction => total == 0 ? 1 : (done / total).clamp(0.0, 1.0);

  factory CoverJobStatus.fromJson(Map<String, dynamic> j) => CoverJobStatus(
        jobId: j['jobId'] as String,
        status: (j['status'] as String?) ?? 'running',
        trigger: (j['trigger'] as String?) ?? 'manual',
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        archived: (j['archived'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        finished: j['finished'] as bool? ?? false,
        cancelRequested: j['cancelRequested'] as bool? ?? false,
        error: j['error'] as String?,
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
