import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/import/import_models.dart';
import '../../data/import/import_repository.dart';

/// Keep only the most recent manga records in the live view (perf at 1000+).
const _recentCap = 50;

// ---- state ----

sealed class ImportState {
  const ImportState();
}

class ImportIdle extends ImportState {
  const ImportIdle();
}

class ImportStaging extends ImportState {
  const ImportStaging(this.fileName);
  final String fileName;
}

/// One or more files staged and awaiting the user's commit/discard decision.
class ImportReview extends ImportState {
  const ImportReview(this.queue);
  final List<StagedImport> queue;
}

/// A commit is streaming. Holds live progress for the current file.
class ImportCommitting extends ImportState {
  const ImportCommitting({
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.processed,
    required this.total,
    required this.phaseLabel,
    required this.recent,
  });

  final String fileName;
  final int fileIndex; // 1-based
  final int fileCount;
  final int processed;
  final int total;
  final String phaseLabel;
  final List<MangaEvent> recent; // newest first, capped

  double get fraction => total == 0 ? 0 : (processed / total).clamp(0.0, 1.0);

  ImportCommitting copyWith({
    int? processed,
    int? total,
    String? phaseLabel,
    List<MangaEvent>? recent,
  }) =>
      ImportCommitting(
        fileName: fileName,
        fileIndex: fileIndex,
        fileCount: fileCount,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        phaseLabel: phaseLabel ?? this.phaseLabel,
        recent: recent ?? this.recent,
      );
}

class ImportDone extends ImportState {
  const ImportDone(this.records);
  final List<ImportRecord> records;
}

class ImportFailed extends ImportState {
  const ImportFailed(this.message, {this.partial = const []});
  final String message;
  final List<ImportRecord> partial;
}

// ---- controller ----

class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportIdle();

  ImportRepository get _repo => ref.read(importRepositoryProvider);

  /// Pick one or more backups and stage each; move to the review queue.
  ///
  /// Uses [FileType.any] (not a custom-extension filter): `.tachibk` has no
  /// registered MIME type, so Android's document picker greys those files out
  /// under `FileType.custom`. We filter by extension ourselves instead.
  Future<void> pickAndStage() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return; // user cancelled

    final accepted = result.files.where(_isBackupFile).toList();
    if (accepted.isEmpty) {
      state = const ImportFailed('Select a .tachibk or .json backup file.');
      return;
    }

    final existing = state is ImportReview ? [...(state as ImportReview).queue] : <StagedImport>[];
    for (final file in accepted) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      state = ImportStaging(file.name);
      try {
        existing.add(await _repo.stage(file.name, bytes));
      } catch (e) {
        state = ImportFailed(_message(e));
        return;
      }
    }
    state = existing.isEmpty ? const ImportIdle() : ImportReview(existing);
  }

  static bool _isBackupFile(PlatformFile f) {
    final name = f.name.toLowerCase();
    return name.endsWith('.tachibk') || name.endsWith('.json');
  }

  /// Commit every staged import sequentially, folding SSE events into state.
  Future<void> commitAll() async {
    final current = state;
    if (current is! ImportReview) return;
    final queue = current.queue.where((s) => !s.isDuplicate).toList();
    final records = <ImportRecord>[];

    for (var i = 0; i < queue.length; i++) {
      final staged = queue[i];
      state = ImportCommitting(
        fileName: staged.fileMeta.fileName,
        fileIndex: i + 1,
        fileCount: queue.length,
        processed: 0,
        total: staged.summary.titlesTotal,
        phaseLabel: 'Starting…',
        recent: const [],
      );

      try {
        final jobId = await _repo.commit(staged.id);
        await for (final event in _repo.streamEvents(jobId)) {
          final done = _apply(event);
          if (done != null) records.add(done);
        }
      } catch (e) {
        state = ImportFailed(_message(e), partial: records);
        return;
      }
    }

    ref.invalidate(importHistoryProvider);
    state = ImportDone(records);
  }

  /// Fold one event into the committing state; returns a record on `done`.
  ImportRecord? _apply(ImportEvent event) {
    final s = state;
    if (s is! ImportCommitting) return null;
    switch (event) {
      case StartEvent(:final total):
        state = s.copyWith(total: total, phaseLabel: 'Preparing…');
      case PhaseEvent(:final phase, :final detail):
        state = s.copyWith(phaseLabel: detail ?? _phaseLabel(phase));
      case MangaEvent():
        state = s.copyWith(
          processed: event.processed,
          phaseLabel: 'Importing titles… ${event.processed} / ${event.total}',
          recent: [event, ...s.recent].take(_recentCap).toList(),
        );
      case BatchEvent():
        break; // progress already reflected by manga events
      case DoneEvent(:final record):
        return record;
      case ErrorEvent(:final message):
        throw Exception(message);
      case UnknownEvent():
        break;
    }
    return null;
  }

  /// Discard all staged imports and return to idle.
  Future<void> discardAll() async {
    final current = state;
    if (current is ImportReview) {
      for (final s in current.queue) {
        try {
          await _repo.discard(s.id);
        } catch (_) {
          // best-effort; server evicts staged imports on TTL anyway
        }
      }
    }
    state = const ImportIdle();
  }

  void reset() => state = const ImportIdle();

  String _phaseLabel(String phase) => switch (phase) {
        'categories' => 'Applying categories…',
        'sources' => 'Registering sources…',
        'manga' => 'Importing titles…',
        'archiving' => 'Archiving file…',
        'done' => 'Finishing…',
        _ => 'Working…',
      };

  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);

final importHistoryProvider = FutureProvider<List<ImportRecord>>(
  (ref) => ref.watch(importRepositoryProvider).history(),
);
