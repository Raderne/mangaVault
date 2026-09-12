import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/files/file_access.dart';
import '../../core/files/vault_file_system.dart';
import '../../core/files/watched_folders.dart';
import 'import_controller.dart';

/// The newest backup in [entries] that [folder] hasn't already imported.
///
/// Only the newest is offered, never a backlog: a `.tachibk` is a *full
/// snapshot*, not a delta, so an older one carries nothing the newest doesn't.
/// Mihon keeps only its last 4 auto-backups anyway.
///
/// Pulled out as a plain function because it is the whole decision worth
/// testing, and it needs neither a container nor a filesystem to exercise.
FileEntry? newestUnseen(List<FileEntry> entries, WatchedFolder folder) {
  // Unseen first, newest second — not the other way round. Picking the newest
  // and *then* asking whether it was seen drops a sibling written in the same
  // second as the last import: the tie-break puts the already-imported one
  // first, and the new one never gets looked at.
  final fresh = entries.where((e) => e.isBackup && !folder.hasSeen(e)).toList();
  if (fresh.isEmpty) return null;
  return sortEntries(fresh, FileSort.modified).first;
}

/// What the Backups screen shows about the watcher. Deliberately thin — the
/// import itself is reported by the states [ImportController] already drives.
@immutable
class AutoImportState {
  const AutoImportState({this.scanning = false, this.message});

  final bool scanning;

  /// The last run's outcome, or null if it had nothing to say.
  final String? message;
}

/// Watches the configured folders and imports what it finds.
///
/// **Foreground only.** It runs at launch and on every resume, throttled by the
/// chosen interval; nothing happens while the app is closed. That is a
/// deliberate trade — the alternative is WorkManager, which needs the server
/// URL and token re-read from the keystore in a headless isolate and is
/// throttled unpredictably by OEM battery managers anyway.
class AutoImportController extends Notifier<AutoImportState> {
  AppLifecycleListener? _lifecycle;

  @override
  AutoImportState build() {
    _lifecycle = AppLifecycleListener(onResume: scan);
    ref.onDispose(() => _lifecycle?.dispose());
    Future<void>.microtask(scan);
    return const AutoImportState();
  }

  AutoImportSettingsController get _settings =>
      ref.read(autoImportSettingsProvider.notifier);

  /// Scan every watched folder, importing the newest unseen backup from each.
  ///
  /// [force] runs regardless of the interval and of it being switched off —
  /// that is the "Scan now" button, which must always do something visible.
  Future<void> scan({bool force = false}) async {
    if (state.scanning) return;

    final settings = ref.read(autoImportSettingsProvider);
    if (settings.folders.isEmpty) return;
    if (!force && !settings.isDue(DateTime.now())) return;

    // On a cold start the permission's first read hasn't landed yet, so the
    // status is still `unknown` and a naive check would skip the launch scan
    // every time.
    if (ref.read(fileAccessProvider) == FileAccessStatus.unknown) {
      await ref.read(fileAccessProvider.notifier).refresh();
    }
    if (!ref.read(fileAccessProvider).isGranted) {
      state = const AutoImportState(message: 'Needs all-files access to scan.');
      return;
    }

    state = const AutoImportState(scanning: true);
    final fs = ref.read(vaultFileSystemProvider);
    final importer = ref.read(importControllerProvider.notifier);
    var imported = 0;
    String? problem;

    for (final folder in ref.read(autoImportSettingsProvider).folders) {
      // The user's own import outranks the watcher's: never stomp a staged
      // queue awaiting review, a question being answered, or a live commit.
      if (ref.read(importControllerProvider).isBusy) {
        problem = 'Paused — an import is already in progress.';
        break;
      }

      final FileEntry? candidate;
      try {
        candidate = newestUnseen(await fs.list(folder.path), folder);
      } on FileAccessException catch (e) {
        problem = '${_name(folder.path)}: ${e.message}';
        continue;
      }
      if (candidate == null) continue;

      final failure = await importer.autoImport(candidate.path, folder.appId);
      if (failure != null) {
        problem = '${candidate.name}: $failure';
        break;
      }
      // Only now, so a failed commit is retried on the next scan instead of
      // being silently burned.
      _settings.markImported(
        folder.path,
        candidate.name,
        candidate.modifiedMillis,
        DateTime.now(),
      );
      imported++;
    }

    _settings.markScanned(DateTime.now());
    state = AutoImportState(
      message: problem ??
          (imported == 0
              ? 'No new backups found.'
              : 'Imported $imported new backup${imported == 1 ? '' : 's'}.'),
    );
  }

  static String _name(String path) =>
      path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
}

final autoImportProvider =
    NotifierProvider<AutoImportController, AutoImportState>(
  AutoImportController.new,
);
