import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_models.dart';
import '../../data/covers/cover_repository.dart';
import '../library/library_controller.dart';

enum CoverArchivePhase { idle, running, done, error }

/// Progress of a cover-archiving run, driven by polling the server job.
class CoverArchiveState {
  const CoverArchiveState({
    this.phase = CoverArchivePhase.idle,
    this.total = 0,
    this.done = 0,
    this.archived = 0,
    this.failed = 0,
    this.skipped = 0,
    this.error,
  });

  final CoverArchivePhase phase;
  final int total;
  final int done;
  final int archived;
  final int failed;
  final int skipped;
  final Object? error;

  bool get isRunning => phase == CoverArchivePhase.running;
  bool get isDone => phase == CoverArchivePhase.done;
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  CoverArchiveState copyWith({
    CoverArchivePhase? phase,
    int? total,
    int? done,
    int? archived,
    int? failed,
    int? skipped,
    Object? error,
  }) =>
      CoverArchiveState(
        phase: phase ?? this.phase,
        total: total ?? this.total,
        done: done ?? this.done,
        archived: archived ?? this.archived,
        failed: failed ?? this.failed,
        skipped: skipped ?? this.skipped,
        error: error,
      );
}

/// Drives `POST /covers/archive-missing`, then polls the job to completion,
/// reloading the library grid as covers land so they appear progressively.
class CoverArchiveController extends Notifier<CoverArchiveState> {
  static const _pollInterval = Duration(seconds: 1);

  bool _disposed = false;

  CoverRepository get _repo => ref.read(coverRepositoryProvider);

  @override
  CoverArchiveState build() {
    ref.onDispose(() => _disposed = true);
    return const CoverArchiveState();
  }

  /// Start (or join) a run. No-op if one is already in progress.
  Future<void> start() async {
    if (state.isRunning) return;
    state = const CoverArchiveState(phase: CoverArchivePhase.running);
    try {
      final started = await _repo.archiveMissing();
      if (started.total == 0) {
        state = state.copyWith(phase: CoverArchivePhase.done, total: 0);
        return;
      }
      state = state.copyWith(total: started.total);
      unawaited(_poll(started.jobId));
    } catch (e) {
      state = state.copyWith(phase: CoverArchivePhase.error, error: e);
    }
  }

  /// Dismiss a finished/failed banner back to idle.
  void dismiss() {
    if (state.isRunning) return;
    state = const CoverArchiveState();
  }

  Future<void> _poll(String jobId) async {
    var lastDone = -1;
    while (!_disposed) {
      await Future<void>.delayed(_pollInterval);
      if (_disposed) return;
      CoverJobStatus status;
      try {
        status = await _repo.jobStatus(jobId);
      } catch (e) {
        state = state.copyWith(phase: CoverArchivePhase.error, error: e);
        return;
      }
      if (_disposed) return;
      state = state.copyWith(
        total: status.total,
        done: status.done,
        archived: status.archived,
        failed: status.failed,
        skipped: status.skipped,
        phase:
            status.finished ? CoverArchivePhase.done : CoverArchivePhase.running,
      );
      // Reveal newly archived covers without a skeleton flash.
      if (status.archived > 0 && status.done != lastDone) {
        lastDone = status.done;
        unawaited(ref.read(libraryControllerProvider.notifier).reload());
      }
      if (status.finished) return;
    }
  }
}

final coverArchiveControllerProvider =
    NotifierProvider<CoverArchiveController, CoverArchiveState>(
  CoverArchiveController.new,
);
