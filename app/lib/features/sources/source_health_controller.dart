import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/source_models.dart';
import '../../data/sources/source_repository.dart';

enum SourceHealthPhase { idle, running, done, error }

/// Progress of a source health run, driven by polling the server job.
class SourceHealthState {
  const SourceHealthState({
    this.phase = SourceHealthPhase.idle,
    this.total = 0,
    this.done = 0,
    this.ok = 0,
    this.degraded = 0,
    this.unhealthy = 0,
    this.cancelling = false,
    this.cancelled = false,
    this.error,
  });

  final SourceHealthPhase phase;
  final int total;
  final int done;
  final int ok;
  final int degraded;
  final int unhealthy;
  final bool cancelling;
  final bool cancelled;
  final Object? error;

  bool get isRunning => phase == SourceHealthPhase.running;
  bool get isDone => phase == SourceHealthPhase.done;
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  SourceHealthState copyWith({
    SourceHealthPhase? phase,
    int? total,
    int? done,
    int? ok,
    int? degraded,
    int? unhealthy,
    bool? cancelling,
    bool? cancelled,
    Object? error,
  }) =>
      SourceHealthState(
        phase: phase ?? this.phase,
        total: total ?? this.total,
        done: done ?? this.done,
        ok: ok ?? this.ok,
        degraded: degraded ?? this.degraded,
        unhealthy: unhealthy ?? this.unhealthy,
        cancelling: cancelling ?? this.cancelling,
        cancelled: cancelled ?? this.cancelled,
        error: error,
      );
}

/// Drives `POST /sources/health-check`, then polls the job to completion.
///
/// Deliberately the same shape as `CoverArchiveController`: the run lives on
/// the server, so [adopt] attaches to one already in progress — the daily
/// scheduled pass, or one resumed after a restart — and the screen shows real
/// progress for work this client never asked for.
class SourceHealthController extends Notifier<SourceHealthState> {
  bool _disposed = false;
  String? _pollingJobId;

  SourceRepository get _repo => ref.read(sourceRepositoryProvider);

  @override
  SourceHealthState build() {
    ref.onDispose(() => _disposed = true);
    return const SourceHealthState();
  }

  /// Start a run, unless one is already going.
  Future<void> start() async {
    if (state.isRunning) return;
    state = const SourceHealthState(phase: SourceHealthPhase.running);
    try {
      final job = await _repo.checkHealth();
      if (_disposed) return;
      state = state.copyWith(total: job.total);
      if (job.finished) {
        state = state.copyWith(phase: SourceHealthPhase.done);
        return;
      }
      unawaited(_poll(job.jobId));
    } catch (err) {
      if (_disposed) return;
      state = state.copyWith(phase: SourceHealthPhase.error, error: err);
    }
  }

  /// Attach to a run already in progress on the server, if there is one.
  Future<void> adopt() async {
    if (state.isRunning) return;
    try {
      final job = await _repo.activeHealthJob();
      if (_disposed || job == null || job.finished) return;
      state = SourceHealthState(
        phase: SourceHealthPhase.running,
        total: job.total,
        done: job.done,
        ok: job.ok,
        degraded: job.degraded,
        unhealthy: job.unhealthy,
      );
      unawaited(_poll(job.jobId));
    } catch (_) {
      // Adoption is opportunistic — a server that cannot answer just means no
      // banner, never an error on a screen the user did not ask to refresh.
    }
  }

  Future<void> cancel() async {
    final jobId = _pollingJobId;
    if (jobId == null) return;
    state = state.copyWith(cancelling: true);
    try {
      await _repo.cancelHealthJob(jobId);
    } catch (_) {
      // The poll below will observe the real outcome either way.
    }
  }

  /// Dismiss a finished run's summary.
  void dismiss() {
    if (state.isRunning) return;
    state = const SourceHealthState();
  }

  Future<void> _poll(String jobId) async {
    if (_pollingJobId == jobId) return;
    _pollingJobId = jobId;
    try {
      while (!_disposed) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_disposed) return;
        final job = await _repo.healthJob(jobId);
        if (_disposed) return;

        state = state.copyWith(
          total: job.total,
          done: job.done,
          ok: job.ok,
          degraded: job.degraded,
          unhealthy: job.unhealthy,
          cancelling: job.cancelRequested && !job.finished,
        );

        if (job.finished) {
          state = state.copyWith(
            phase: job.error != null
                ? SourceHealthPhase.error
                : SourceHealthPhase.done,
            cancelling: false,
            cancelled: job.status == 'cancelled',
            error: job.error,
          );
          return;
        }
      }
    } catch (err) {
      if (_disposed) return;
      state = state.copyWith(phase: SourceHealthPhase.error, error: err);
    } finally {
      if (_pollingJobId == jobId) _pollingJobId = null;
    }
  }
}

final sourceHealthControllerProvider =
    NotifierProvider<SourceHealthController, SourceHealthState>(
  SourceHealthController.new,
);

/// The source list, from the server so replacement suggestions come with it.
///
/// Falls back to the mirror when the server cannot be reached, which is the
/// whole reason the registry is mirrored at all: the screen still names every
/// source and shows its last known verdict on a train.
final vaultSourcesProvider =
    FutureProvider.autoDispose<List<VaultSource>>((ref) async {
  try {
    return await ref.watch(sourceRepositoryProvider).sources();
  } catch (_) {
    return ref.watch(localSourceRepositoryProvider).sources();
  }
});
