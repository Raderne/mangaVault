import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/migration_models.dart';
import '../../data/sources/source_repository.dart';
import '../sync/sync_controller.dart';

/// State of the review screen for one migration plan.
class MigrationPlanState {
  const MigrationPlanState({
    this.plan,
    this.selected = const {},
    this.loading = true,
    this.applying = false,
    this.result,
    this.error,
  });

  final MigrationPlan? plan;

  /// Manga ids the user has ticked — exactly what `apply` will be given.
  final Set<String> selected;
  final bool loading;
  final bool applying;
  final MigrationApplyResult? result;
  final Object? error;

  bool get isPlanning => plan?.job.isPlanning ?? false;

  List<MigrationItem> get items => plan?.items ?? const [];

  MigrationPlanState copyWith({
    MigrationPlan? plan,
    Set<String>? selected,
    bool? loading,
    bool? applying,
    MigrationApplyResult? result,
    Object? error,
    bool clearResult = false,
    bool clearError = false,
  }) =>
      MigrationPlanState(
        plan: plan ?? this.plan,
        selected: selected ?? this.selected,
        loading: loading ?? this.loading,
        applying: applying ?? this.applying,
        result: clearResult ? null : (result ?? this.result),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives one migration plan: polls while the server searches, tracks which
/// titles the user has ticked, and applies exactly those.
///
/// The selection is deliberately client-side and explicit. The server will
/// happily apply a plan on its own, but only for matches it is confident
/// about; anything in between — a 0.7 that might be the right book — has to be
/// a human decision, and the only honest place to make it is a list the user
/// can see.
class MigrationPlanController extends Notifier<MigrationPlanState> {
  bool _disposed = false;
  bool _polling = false;
  String? _jobId;

  SourceRepository get _repo => ref.read(sourceRepositoryProvider);

  @override
  MigrationPlanState build() {
    ref.onDispose(() => _disposed = true);
    return const MigrationPlanState();
  }

  /// Point the controller at a plan. Safe to call on every rebuild of the
  /// screen: re-opening the plan already loaded is a no-op, so a hot reload or
  /// an orientation change does not restart the poll.
  Future<void> open(String jobId) async {
    if (_jobId == jobId) return;
    _jobId = jobId;
    state = const MigrationPlanState();
    await _load(initial: true);
  }

  Future<void> refresh() => _load();

  Future<void> _load({bool initial = false}) async {
    if (_jobId == null) return;
    try {
      final plan = await _repo.plan(_jobId!);
      if (_disposed) return;

      state = state.copyWith(
        plan: plan,
        loading: false,
        clearError: true,
        // Pre-tick only what the server would apply by itself. Everything else
        // stays unticked until the user looks at it.
        selected: initial || state.selected.isEmpty
            ? plan.items
                .where((i) => i.confidentAt(plan.autoAcceptScore))
                .map((i) => i.mangaId)
                .toSet()
            : state.selected,
      );

      if (plan.job.isPlanning && !_polling) {
        unawaited(_poll());
      }
    } catch (err) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: err);
    }
  }

  Future<void> _poll() async {
    _polling = true;
    try {
      while (!_disposed) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_disposed) return;
        final plan = await _repo.plan(_jobId!);
        if (_disposed) return;
        state = state.copyWith(
          plan: plan,
          selected: plan.items
              .where((i) => i.confidentAt(plan.autoAcceptScore))
              .map((i) => i.mangaId)
              .toSet(),
        );
        if (!plan.job.isPlanning) return;
      }
    } catch (err) {
      if (!_disposed) state = state.copyWith(error: err);
    } finally {
      _polling = false;
    }
  }

  void toggle(String mangaId) {
    final next = {...state.selected};
    if (!next.remove(mangaId)) next.add(mangaId);
    state = state.copyWith(selected: next);
  }

  void selectAllMatched() {
    state = state.copyWith(
      selected: state.items
          .where((i) => i.hasMatch)
          .map((i) => i.mangaId)
          .toSet(),
    );
  }

  void selectNone() => state = state.copyWith(selected: const {});

  Future<void> chooseCandidate(String mangaId, int index) async {
    await _repo.chooseCandidate(
      jobId: _jobId!,
      mangaId: mangaId,
      candidateIndex: index,
    );
    if (_disposed) return;
    // Choosing a match by hand is a decision, so it ticks the row.
    state = state.copyWith(selected: {...state.selected, mangaId});
    await _load();
  }

  Future<void> setManual(
    String mangaId,
    String toSourceId,
    String toMangaUrl,
  ) async {
    await _repo.setManualTarget(
      jobId: _jobId!,
      mangaId: mangaId,
      toSourceId: toSourceId,
      toMangaUrl: toMangaUrl,
    );
    if (_disposed) return;
    state = state.copyWith(selected: {...state.selected, mangaId});
    await _load();
  }

  Future<void> skip(String mangaId) async {
    await _repo.skipItem(jobId: _jobId!, mangaId: mangaId);
    if (_disposed) return;
    final next = {...state.selected}..remove(mangaId);
    state = state.copyWith(selected: next);
    await _load();
  }

  Future<void> cancelPlanning() async {
    await _repo.cancelPlan(_jobId!);
    if (!_disposed) await _load();
  }

  /// Apply the ticked titles, then pull the library so the grid reflects it.
  Future<void> apply() async {
    if (state.selected.isEmpty || state.applying) return;
    state = state.copyWith(applying: true, clearError: true);
    try {
      final result = await _repo.apply(
        jobId: _jobId!,
        mangaIds: state.selected.toList(),
      );
      if (_disposed) return;
      state = state.copyWith(applying: false, result: result);
      await _load();
      // The migrated rows carry new `row_version`s, so a sync brings the new
      // source names into the mirror the library grid reads.
      await ref.read(syncControllerProvider.notifier).run();
    } catch (err) {
      if (_disposed) return;
      state = state.copyWith(applying: false, error: err);
    }
  }

  Future<void> undo(String itemId) async {
    await _repo.undo(itemId);
    if (_disposed) return;
    await _load();
    await ref.read(syncControllerProvider.notifier).run();
  }

  Future<void> mergeConflict(String itemId) async {
    await _repo.mergeConflict(itemId);
    if (_disposed) return;
    await _load();
    await ref.read(syncControllerProvider.notifier).run();
  }
}

/// Only one plan is ever on screen — the server allows a single migration at a
/// time — so this is a plain provider rather than a family.
final migrationPlanControllerProvider =
    NotifierProvider<MigrationPlanController, MigrationPlanState>(
  MigrationPlanController.new,
);
