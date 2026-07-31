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
    this.trigger = 'manual',
    this.cancelling = false,
    this.cancelled = false,
    this.error,
  });

  final CoverArchivePhase phase;
  final int total;
  final int done;
  final int archived;
  final int failed;
  final int skipped;

  /// What started the run — the banner says so when it wasn't the user.
  final String trigger;

  /// A cancel was requested and the run is still draining.
  final bool cancelling;

  /// The finished run ended because it was cancelled.
  final bool cancelled;
  final Object? error;

  bool get isRunning => phase == CoverArchivePhase.running;
  bool get isDone => phase == CoverArchivePhase.done;
  bool get startedByServer => trigger != 'manual';
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  CoverArchiveState copyWith({
    CoverArchivePhase? phase,
    int? total,
    int? done,
    int? archived,
    int? failed,
    int? skipped,
    String? trigger,
    bool? cancelling,
    bool? cancelled,
    Object? error,
  }) =>
      CoverArchiveState(
        phase: phase ?? this.phase,
        total: total ?? this.total,
        done: done ?? this.done,
        archived: archived ?? this.archived,
        failed: failed ?? this.failed,
        skipped: skipped ?? this.skipped,
        trigger: trigger ?? this.trigger,
        cancelling: cancelling ?? this.cancelling,
        cancelled: cancelled ?? this.cancelled,
        error: error,
      );
}

/// Drives `POST /covers/archive-missing`, then polls the job to completion,
/// reloading the library grid as covers land so they appear progressively.
///
/// Runs live on the server, not here: [adopt] picks up one that is already in
/// progress (started by an import, or resumed after a server restart) so the
/// banner reflects work this client never asked for, and [cancel] stops a run
/// that is taking too long.
class CoverArchiveController extends Notifier<CoverArchiveState> {
  static const _pollInterval = Duration(seconds: 1);

  bool _disposed = false;

  /// Job currently being polled — guards against two poll loops at once.
  String? _pollingJobId;

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

  /// Attach to a run already in progress on the server, if there is one.
  /// Silent when there isn't (and on failure) — this is opportunistic, so it
  /// must never put an error banner in front of someone who just opened a
  /// screen.
  Future<void> adopt() async {
    if (state.isRunning) return;
    CoverJobStatus? job;
    try {
      job = await _repo.activeJob();
    } catch (_) {
      return;
    }
    if (job == null || job.finished || _disposed) return;
    state = CoverArchiveState(
      phase: CoverArchivePhase.running,
      total: job.total,
      done: job.done,
      archived: job.archived,
      failed: job.failed,
      skipped: job.skipped,
      trigger: job.trigger,
      cancelling: job.cancelRequested,
    );
    unawaited(_poll(job.jobId));
  }

  /// Ask the running job to stop. Downloads in flight finish first, so the
  /// banner shows "Stopping…" until the server reports the run cancelled.
  Future<void> cancel() async {
    final jobId = _pollingJobId;
    if (jobId == null || !state.isRunning) return;
    state = state.copyWith(cancelling: true);
    try {
      await _repo.cancelJob(jobId);
    } catch (e) {
      state = state.copyWith(cancelling: false, error: e);
    }
  }

  /// Dismiss a finished/failed banner back to idle.
  void dismiss() {
    if (state.isRunning) return;
    state = const CoverArchiveState();
  }

  Future<void> _poll(String jobId) async {
    if (_pollingJobId == jobId) return;
    _pollingJobId = jobId;
    var lastDone = -1;
    try {
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
          trigger: status.trigger,
          cancelling: status.cancelRequested && !status.finished,
          cancelled: status.cancelled,
          phase: status.finished
              ? CoverArchivePhase.done
              : CoverArchivePhase.running,
        );
        // Reveal newly archived covers without a skeleton flash.
        if (status.archived > 0 && status.done != lastDone) {
          lastDone = status.done;
          unawaited(ref.read(libraryControllerProvider.notifier).reload());
        }
        if (status.finished) return;
      }
    } finally {
      if (_pollingJobId == jobId) _pollingJobId = null;
    }
  }
}

final coverArchiveControllerProvider =
    NotifierProvider<CoverArchiveController, CoverArchiveState>(
  CoverArchiveController.new,
);
