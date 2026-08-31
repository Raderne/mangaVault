// Dart mirrors of the server's migration DTOs
// (server/src/modules/sources/migration.dto.ts).

/// Per-title state within a plan.
enum MigrationItemState {
  pending,
  matched,
  unmatched,
  skipped,
  conflict,
  applied,
  failed,
  undone,
}

MigrationItemState _stateFrom(String? raw) => switch (raw) {
      'matched' => MigrationItemState.matched,
      'unmatched' => MigrationItemState.unmatched,
      'skipped' => MigrationItemState.skipped,
      'conflict' => MigrationItemState.conflict,
      'applied' => MigrationItemState.applied,
      'failed' => MigrationItemState.failed,
      'undone' => MigrationItemState.undone,
      _ => MigrationItemState.pending,
    };

/// An alternative target for a title, ranked by the server's matcher.
class MigrationCandidate {
  const MigrationCandidate({
    required this.sourceId,
    required this.sourceName,
    required this.url,
    required this.title,
    required this.score,
    required this.method,
    this.author,
    this.thumbnailUrl,
    this.reasons = const [],
  });

  final String sourceId;
  final String sourceName;
  final String url;
  final String title;
  final double score;

  /// `adapter` (searched live), `vault` (already in your library), `manual`.
  final String method;
  final String? author;
  final String? thumbnailUrl;
  final List<String> reasons;

  factory MigrationCandidate.fromJson(Map<String, dynamic> j) =>
      MigrationCandidate(
        sourceId: (j['sourceId'] as String?) ?? '',
        sourceName: (j['sourceName'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        score: ((j['score'] as num?) ?? 0).toDouble(),
        method: (j['method'] as String?) ?? 'adapter',
        author: j['author'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        reasons: ((j['reasons'] as List?) ?? const []).cast<String>(),
      );
}

/// One title in a migration plan.
class MigrationItem {
  const MigrationItem({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.state,
    this.toSourceId,
    this.toSourceName,
    this.toMangaUrl,
    this.toTitle,
    this.toThumbnailUrl,
    this.score,
    this.method,
    this.reasons = const [],
    this.candidates = const [],
    this.conflictMangaId,
    this.conflictTitle,
    this.error,
    this.undoable = false,
  });

  final String id;
  final String mangaId;
  final String title;
  final MigrationItemState state;
  final String? toSourceId;
  final String? toSourceName;
  final String? toMangaUrl;
  final String? toTitle;
  final String? toThumbnailUrl;

  /// 0..1, or null for a url entered by hand — nothing to score it against.
  final double? score;
  final String? method;
  final List<String> reasons;
  final List<MigrationCandidate> candidates;
  final String? conflictMangaId;
  final String? conflictTitle;
  final String? error;
  final bool undoable;

  bool get hasMatch => state == MigrationItemState.matched;

  /// True when the server considers this match safe to pre-select.
  bool confidentAt(double threshold) =>
      hasMatch && (method == 'manual' || (score ?? 0) >= threshold);

  factory MigrationItem.fromJson(Map<String, dynamic> j) => MigrationItem(
        id: (j['id'] as String?) ?? '',
        mangaId: (j['mangaId'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        state: _stateFrom(j['state'] as String?),
        toSourceId: j['toSourceId'] as String?,
        toSourceName: j['toSourceName'] as String?,
        toMangaUrl: j['toMangaUrl'] as String?,
        toTitle: j['toTitle'] as String?,
        toThumbnailUrl: j['toThumbnailUrl'] as String?,
        score: (j['score'] as num?)?.toDouble(),
        method: j['method'] as String?,
        reasons: ((j['reasons'] as List?) ?? const []).cast<String>(),
        candidates: ((j['candidates'] as List?) ?? const [])
            .map((e) => MigrationCandidate.fromJson(e as Map<String, dynamic>))
            .toList(),
        conflictMangaId: j['conflictMangaId'] as String?,
        conflictTitle: j['conflictTitle'] as String?,
        error: j['error'] as String?,
        undoable: (j['undoable'] as bool?) ?? false,
      );
}

/// The plan's own progress — polled while the server searches.
class MigrationJob {
  const MigrationJob({
    required this.jobId,
    required this.status,
    required this.fromSourceId,
    required this.fromSourceName,
    required this.total,
    required this.planned,
    required this.matched,
    required this.applied,
    required this.skipped,
    required this.failed,
    required this.finished,
    this.error,
  });

  final String jobId;

  /// `planning` / `ready` / `applying` / `applied` / `cancelled` / `failed`.
  final String status;
  final String fromSourceId;
  final String fromSourceName;
  final int total;
  final int planned;
  final int matched;
  final int applied;
  final int skipped;
  final int failed;
  final bool finished;
  final String? error;

  bool get isPlanning => status == 'planning';
  double get fraction =>
      total == 0 ? 0 : (planned / total).clamp(0, 1).toDouble();

  factory MigrationJob.fromJson(Map<String, dynamic> j) => MigrationJob(
        jobId: (j['jobId'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'planning',
        fromSourceId: (j['fromSourceId'] as String?) ?? '',
        fromSourceName: (j['fromSourceName'] as String?) ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        planned: (j['planned'] as num?)?.toInt() ?? 0,
        matched: (j['matched'] as num?)?.toInt() ?? 0,
        applied: (j['applied'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        finished: (j['finished'] as bool?) ?? false,
        error: j['error'] as String?,
      );
}

/// A target source the server could not search, and why.
class UnsearchableTarget {
  const UnsearchableTarget({
    required this.sourceId,
    required this.name,
    required this.reason,
  });

  final String sourceId;
  final String name;
  final String reason;

  factory UnsearchableTarget.fromJson(Map<String, dynamic> j) =>
      UnsearchableTarget(
        sourceId: (j['sourceId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        reason: (j['reason'] as String?) ?? '',
      );
}

/// A plan and every title in it.
class MigrationPlan {
  const MigrationPlan({
    required this.job,
    required this.items,
    this.unsearchable = const [],
    this.autoAcceptScore = 0.85,
  });

  final MigrationJob job;
  final List<MigrationItem> items;
  final List<UnsearchableTarget> unsearchable;

  /// The server's own bar for a confident match — used so the boxes we tick
  /// and the set the server would apply by default can never disagree.
  final double autoAcceptScore;

  factory MigrationPlan.fromJson(Map<String, dynamic> j) => MigrationPlan(
        job: MigrationJob.fromJson(j['job'] as Map<String, dynamic>),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => MigrationItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        unsearchable: ((j['unsearchable'] as List?) ?? const [])
            .map((e) => UnsearchableTarget.fromJson(e as Map<String, dynamic>))
            .toList(),
        autoAcceptScore:
            ((j['autoAcceptScore'] as num?) ?? 0.85).toDouble(),
      );
}

/// Outcome of applying a plan.
class MigrationApplyResult {
  const MigrationApplyResult({
    required this.applied,
    required this.conflicts,
    required this.failed,
  });

  final int applied;
  final int conflicts;
  final int failed;

  factory MigrationApplyResult.fromJson(Map<String, dynamic> j) =>
      MigrationApplyResult(
        applied: (j['applied'] as num?)?.toInt() ?? 0,
        conflicts: (j['conflicts'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
      );
}
