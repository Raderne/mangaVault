import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/files/vault_file_system.dart';
import '../../../data/export/export_models.dart';
import '../../../data/export/export_repository.dart';

/// The wizard's three steps.
enum ExportStep {
  /// Which titles. Presets plus the full facet builder.
  select,

  /// What travels with them, and which app the file is named for.
  options,

  /// The final readout, then the button that writes the file.
  review;

  static const last = ExportStep.review;

  String get label => switch (this) {
        ExportStep.select => 'Select',
        ExportStep.options => 'Options',
        ExportStep.review => 'Review',
      };
}

enum ExportStatus { editing, building, saved, failed }

/// Where the finished file ended up.
@immutable
class ExportResult {
  const ExportResult({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.titles,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
  final int titles;
}

/// The whole wizard in one immutable value: what is selected, which step is
/// showing, what the server says it would produce, and how the build went.
///
/// A single state object rather than a sealed union (as the import flow uses)
/// because the scope has to survive every status — a failed build must return
/// the user to their selection intact, not to an empty form.
@immutable
class ExportState {
  const ExportState({
    this.scope = const ExportScope(),
    this.step = ExportStep.select,
    this.preview = const AsyncValue.loading(),
    this.status = ExportStatus.editing,
    this.progress,
    this.result,
    this.error,
  });

  final ExportScope scope;
  final ExportStep step;

  /// The server's answer for the current scope. Refreshed, debounced, on every
  /// change — the counts are the whole point of the builder.
  final AsyncValue<ExportPreview> preview;

  final ExportStatus status;

  /// 0..1 while the file downloads, or null when the server sent no length.
  final double? progress;
  final ExportResult? result;
  final String? error;

  bool get isBusy => status == ExportStatus.building;

  /// Whether the current step allows moving on. A scope that matches nothing
  /// can't be reviewed, let alone exported.
  bool get canAdvance =>
      step != ExportStep.last && !(preview.value?.isEmpty ?? false);

  bool get canBuild =>
      status != ExportStatus.building &&
      (preview.value?.titles ?? 0) > 0;

  ExportState copyWith({
    ExportScope? scope,
    ExportStep? step,
    AsyncValue<ExportPreview>? preview,
    ExportStatus? status,
    double? progress,
    bool clearProgress = false,
    ExportResult? result,
    String? error,
    bool clearError = false,
  }) =>
      ExportState(
        scope: scope ?? this.scope,
        step: step ?? this.step,
        preview: preview ?? this.preview,
        status: status ?? this.status,
        progress: clearProgress ? null : (progress ?? this.progress),
        result: result ?? this.result,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Debounce on scope edits. Chip taps arrive in bursts as the user builds a
/// selection; previewing each one would put a query per tap on the server and
/// make the counts flicker between stale answers.
const _previewDebounce = Duration(milliseconds: 300);

/// Drives the export wizard: holds the scope, keeps a live preview of it, then
/// builds the file and hands it to the platform's save dialog.
class ExportController extends Notifier<ExportState> {
  Timer? _debounce;
  CancelToken? _inFlight;

  /// Guards against a slow preview landing after a newer one. Riverpod gives no
  /// ordering guarantee across awaits, and an out-of-order response would show
  /// counts for a scope the user has already changed.
  int _requestSeq = 0;

  @override
  ExportState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _inFlight?.cancel();
    });
    // Kick off the first preview — the default scope is "everything", and the
    // user should land on a screen that already knows how big that is.
    scheduleMicrotask(_refreshPreview);
    return const ExportState();
  }

  // ---- scope edits ----

  void setMode(ExportMode mode) {
    // Presets are modes with a filter baked in, so switching to one clears
    // whatever the previous preset left behind rather than silently ANDing it.
    _edit(state.scope.copyWith(mode: mode));
  }

  /// "Favorites only" preset: still `filter` mode, but with one facet set.
  void applyFavoritesPreset() {
    _edit(
      state.scope.copyWith(
        mode: ExportMode.filter,
        filters: const ExportFilters(favorite: true),
      ),
    );
  }

  void applyEverythingPreset() {
    _edit(
      state.scope.copyWith(
        mode: ExportMode.all,
        filters: const ExportFilters(),
      ),
    );
  }

  void applyCustomPreset() {
    _edit(state.scope.copyWith(mode: ExportMode.filter));
  }

  void setText(String text) =>
      _editFilters(state.scope.filters.copyWith(text: text.trim()));

  void toggleApp(String id) => _editFilters(
        state.scope.filters
            .copyWith(sourceApps: _toggled(state.scope.filters.sourceApps, id)),
      );

  void toggleSource(String id) => _editFilters(
        state.scope.filters
            .copyWith(sourceIds: _toggled(state.scope.filters.sourceIds, id)),
      );

  void toggleCategory(String id) => _editFilters(
        state.scope.filters.copyWith(
          categoryIds: _toggled(state.scope.filters.categoryIds, id),
        ),
      );

  void toggleStatus(String id) => _editFilters(
        state.scope.filters
            .copyWith(status: _toggled(state.scope.filters.status, id)),
      );

  /// Tri-state: favorites → non-favorites → both, by tapping the same control.
  void setFavorite(bool? value) => _editFilters(
        value == null
            ? state.scope.filters.copyWith(clearFavorite: true)
            : state.scope.filters.copyWith(favorite: value),
      );

  void setUnreadOnly(bool value) =>
      _editFilters(state.scope.filters.copyWith(unreadOnly: value));

  void setStartedOnly(bool value) =>
      _editFilters(state.scope.filters.copyWith(startedOnly: value));

  void clearFilters() =>
      _editFilters(const ExportFilters(), mode: ExportMode.filter);

  // ---- options ----

  void setIncludeChapters(bool value) =>
      _edit(state.scope.copyWith(includes: state.scope.includes.copyWith(chapters: value)));

  void setIncludeReadProgress(bool value) => _edit(state.scope
      .copyWith(includes: state.scope.includes.copyWith(readProgress: value)));

  void setIncludeCategories(bool value) => _edit(state.scope
      .copyWith(includes: state.scope.includes.copyWith(categories: value)));

  void setIncludeTracking(bool value) =>
      _edit(state.scope.copyWith(includes: state.scope.includes.copyWith(tracking: value)));

  /// Which app the file is named for. Changing it changes the filename, which
  /// the preview shows, so it re-previews like any other edit.
  void setTargetApp(String appId) =>
      _edit(state.scope.copyWith(targetApp: appId));

  // ---- navigation ----

  void goTo(ExportStep step) => state = state.copyWith(step: step);

  void next() {
    final i = state.step.index;
    if (i < ExportStep.values.length - 1) {
      state = state.copyWith(step: ExportStep.values[i + 1]);
    }
  }

  void back() {
    final i = state.step.index;
    if (i > 0) state = state.copyWith(step: ExportStep.values[i - 1]);
  }

  // ---- build ----

  /// Build the backup and write it where the user says.
  ///
  /// The file lands in a folder they chose rather than in app storage: a backup
  /// they can't find is not a backup, and it has to survive uninstalling the
  /// app.
  ///
  /// [chooseDestination] is MangaVault's own save browser, supplied by the
  /// screen because a `Notifier` has no `BuildContext`. When it is given, *we*
  /// write the bytes; when it isn't — file access hasn't been granted — the
  /// platform save dialog does, and writes them itself.
  Future<void> buildAndSave({
    Future<String?> Function(String suggestedName)? chooseDestination,
  }) async {
    if (state.isBusy) return;
    _debounce?.cancel();
    state = state.copyWith(
      status: ExportStatus.building,
      clearError: true,
      clearProgress: true,
    );

    final cancel = CancelToken();
    try {
      final built = await ref.read(exportRepositoryProvider).build(
            state.scope,
            cancelToken: cancel,
            onProgress: (received, total) {
              if (total > 0) {
                state = state.copyWith(progress: received / total);
              }
            },
          );

      final String? path;
      if (chooseDestination != null) {
        path = await chooseDestination(built.fileName);
        if (path != null) {
          await ref.read(vaultFileSystemProvider).writeBytes(path, built.bytes);
        }
      } else {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save backup',
          fileName: built.fileName,
          bytes: built.bytes,
        );
      }

      if (path == null) {
        // Dismissed the save dialog — not an error. Drop straight back to the
        // review step with everything intact so they can try again.
        state = state.copyWith(
          status: ExportStatus.editing,
          clearProgress: true,
        );
        return;
      }

      state = state.copyWith(
        status: ExportStatus.saved,
        clearProgress: true,
        result: ExportResult(
          // The user can rename the file in the save browser, so the saved
          // name comes from the path, not from what the server suggested.
          fileName: p.posix.basename(path),
          path: path,
          sizeBytes: built.sizeBytes,
          titles: built.titles,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        status: ExportStatus.failed,
        clearProgress: true,
        error: _message(e),
      );
    }
  }

  /// Back to a fresh wizard, for "export another".
  void reset() {
    _debounce?.cancel();
    _inFlight?.cancel();
    state = const ExportState();
    _refreshPreview();
  }

  /// Return to the builder after a failure, keeping the scope.
  void dismissError() => state = state.copyWith(
        status: ExportStatus.editing,
        step: ExportStep.review,
        clearError: true,
      );

  // ---- internals ----

  Set<String> _toggled(Set<String> current, String id) {
    final next = {...current};
    if (!next.remove(id)) next.add(id);
    return next;
  }

  void _editFilters(ExportFilters filters, {ExportMode? mode}) {
    // Touching any facet means the user is building a custom scope; flipping
    // the mode for them saves a step and keeps "Everything" from silently
    // ignoring the chip they just tapped.
    _edit(
      state.scope.copyWith(mode: mode ?? ExportMode.filter, filters: filters),
    );
  }

  void _edit(ExportScope scope) {
    state = state.copyWith(scope: scope, clearError: true);
    _schedulePreview();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    // Show the pending state immediately so the counts read as "catching up"
    // rather than as a wrong answer the user might act on.
    state = state.copyWith(preview: const AsyncValue.loading());
    _debounce = Timer(_previewDebounce, _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    _inFlight?.cancel();
    final cancel = _inFlight = CancelToken();
    final seq = ++_requestSeq;
    final scope = state.scope;

    try {
      final preview = await ref
          .read(exportRepositoryProvider)
          .preview(scope, cancelToken: cancel);
      if (seq != _requestSeq) return; // superseded by a newer edit
      state = state.copyWith(preview: AsyncValue.data(preview));
    } catch (e, st) {
      if (cancel.isCancelled || seq != _requestSeq) return;
      state = state.copyWith(preview: AsyncValue.error(_message(e), st));
    }
  }

  static String _message(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      if (e.type == DioExceptionType.connectionError) {
        return "Couldn't reach the server.";
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'The server took too long to build the backup.';
      }
    }
    return e.toString().replaceFirst('Exception: ', '');
  }
}

final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
