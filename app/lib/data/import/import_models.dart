// Dart mirrors of the server's import DTOs (server/src/modules/import/import.dto.ts)
// and the SSE `ImportEvent` union. Manual `fromJson` — the set is small and
// read-only; the Library DTOs (M3) can adopt json_serializable if they grow.

class ImportFileMeta {
  const ImportFileMeta({
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.sourceApp,
    required this.container,
  });

  final String fileName;
  final int fileSize;
  final String sha256;
  final String sourceApp;
  final String container;

  factory ImportFileMeta.fromJson(Map<String, dynamic> j) => ImportFileMeta(
        fileName: j['fileName'] as String,
        fileSize: (j['fileSize'] as num).toInt(),
        sha256: j['sha256'] as String,
        sourceApp: (j['sourceApp'] as String?) ?? '',
        container: j['container'] as String,
      );
}

class ImportSummary {
  const ImportSummary({
    required this.titlesTotal,
    required this.titlesNew,
    required this.titlesMerged,
    this.titlesSkipped = 0,
    required this.chaptersTotal,
    required this.categoriesTotal,
    required this.warnings,
  });

  final int titlesTotal;
  final int titlesNew;
  final int titlesMerged;

  /// Left out because the title is in the deletion registry — the user deleted
  /// it, so a backup must not silently bring it back.
  final int titlesSkipped;
  final int chaptersTotal;
  final int categoriesTotal;
  final List<String> warnings;

  factory ImportSummary.fromJson(Map<String, dynamic> j) => ImportSummary(
        titlesTotal: (j['titlesTotal'] as num?)?.toInt() ?? 0,
        titlesNew: (j['titlesNew'] as num?)?.toInt() ?? 0,
        titlesMerged: (j['titlesMerged'] as num?)?.toInt() ?? 0,
        titlesSkipped: (j['titlesSkipped'] as num?)?.toInt() ?? 0,
        chaptersTotal: (j['chaptersTotal'] as num?)?.toInt() ?? 0,
        categoriesTotal: (j['categoriesTotal'] as num?)?.toInt() ?? 0,
        warnings: ((j['warnings'] as List?) ?? const []).map((e) => e as String).toList(),
      );
}

class FieldConflict {
  const FieldConflict({required this.field, required this.kept, required this.incoming});

  final String field;
  final String kept;
  final String incoming;

  factory FieldConflict.fromJson(Map<String, dynamic> j) => FieldConflict(
        field: j['field'] as String,
        kept: '${j['kept'] ?? ''}',
        incoming: '${j['incoming'] ?? ''}',
      );
}

class MergeResult {
  const MergeResult({
    required this.title,
    required this.action,
    required this.conflicts,
  });

  final String title;

  /// 'created', 'merged', or 'skipped' (blocked by the deletion registry).
  final String action;
  final List<FieldConflict> conflicts;

  bool get isMerged => action == 'merged';
  bool get isSkipped => action == 'skipped';

  factory MergeResult.fromJson(Map<String, dynamic> j) => MergeResult(
        title: (j['title'] as String?) ?? '',
        action: j['action'] as String,
        conflicts: ((j['conflicts'] as List?) ?? const [])
            .map((e) => FieldConflict.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ImportRecord {
  const ImportRecord({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.sourceApp,
    required this.container,
    required this.importedAt,
    required this.stats,
  });

  final String id;
  final String fileName;
  final int fileSize;
  final String sourceApp;
  final String container;
  final int importedAt;
  final ImportSummary stats;

  factory ImportRecord.fromJson(Map<String, dynamic> j) => ImportRecord(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        sourceApp: (j['sourceApp'] as String?) ?? '',
        container: (j['container'] as String?) ?? '',
        importedAt: (j['importedAt'] as num?)?.toInt() ?? 0,
        stats: ImportSummary.fromJson((j['stats'] as Map<String, dynamic>?) ?? const {}),
      );
}

class StagedImport {
  const StagedImport({
    required this.id,
    required this.fileMeta,
    required this.summary,
    required this.preview,
    required this.expiresAt,
    this.duplicateOf,
  });

  final String id;
  final ImportFileMeta fileMeta;
  final ImportSummary summary;
  final List<MergeResult> preview;
  final int expiresAt;
  final ImportRecord? duplicateOf;

  bool get isDuplicate => duplicateOf != null;

  factory StagedImport.fromJson(Map<String, dynamic> j) => StagedImport(
        id: j['id'] as String,
        fileMeta: ImportFileMeta.fromJson(j['fileMeta'] as Map<String, dynamic>),
        summary: ImportSummary.fromJson(j['summary'] as Map<String, dynamic>),
        preview: ((j['preview'] as List?) ?? const [])
            .map((e) => MergeResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        expiresAt: (j['expiresAt'] as num?)?.toInt() ?? 0,
        duplicateOf: j['duplicateOf'] == null
            ? null
            : ImportRecord.fromJson(j['duplicateOf'] as Map<String, dynamic>),
      );
}

// ---- streamed commit events ----

/// One real-time commit progress event. Mirrors the server `ImportEvent` union;
/// `ImportEvent.fromJson` switches on the `type` discriminator.
sealed class ImportEvent {
  const ImportEvent();

  factory ImportEvent.fromJson(Map<String, dynamic> j) {
    switch (j['type'] as String) {
      case 'start':
        return StartEvent(
          fileName: (j['fileName'] as String?) ?? '',
          total: (j['total'] as num?)?.toInt() ?? 0,
        );
      case 'phase':
        return PhaseEvent(phase: j['phase'] as String, detail: j['detail'] as String?);
      case 'manga':
        return MangaEvent(
          title: (j['title'] as String?) ?? '',
          action: j['action'] as String,
          processed: (j['processed'] as num?)?.toInt() ?? 0,
          total: (j['total'] as num?)?.toInt() ?? 0,
        );
      case 'batch':
        return BatchEvent(
          committed: (j['committed'] as num?)?.toInt() ?? 0,
          total: (j['total'] as num?)?.toInt() ?? 0,
        );
      case 'done':
        return DoneEvent(ImportRecord.fromJson(j['record'] as Map<String, dynamic>));
      case 'error':
        return ErrorEvent(
          message: (j['message'] as String?) ?? 'import failed',
          processed: (j['processed'] as num?)?.toInt() ?? 0,
        );
      default:
        return const UnknownEvent();
    }
  }
}

class StartEvent extends ImportEvent {
  const StartEvent({required this.fileName, required this.total});
  final String fileName;
  final int total;
}

class PhaseEvent extends ImportEvent {
  const PhaseEvent({required this.phase, this.detail});
  final String phase;
  final String? detail;
}

class MangaEvent extends ImportEvent {
  const MangaEvent({
    required this.title,
    required this.action,
    required this.processed,
    required this.total,
  });
  final String title;
  final String action; // 'created' | 'merged' | 'skipped'
  final int processed;
  final int total;

  bool get isMerged => action == 'merged';
  bool get isSkipped => action == 'skipped';
}

class BatchEvent extends ImportEvent {
  const BatchEvent({required this.committed, required this.total});
  final int committed;
  final int total;
}

class DoneEvent extends ImportEvent {
  const DoneEvent(this.record);
  final ImportRecord record;
}

class ErrorEvent extends ImportEvent {
  const ErrorEvent({required this.message, required this.processed});
  final String message;
  final int processed;
}

class UnknownEvent extends ImportEvent {
  const UnknownEvent();
}
