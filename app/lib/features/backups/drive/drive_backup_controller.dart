import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config_controller.dart';
import '../../../core/google/google_account.dart';
import '../../../data/drive/drive_store.dart';
import '../../../data/export/export_models.dart';
import '../../../data/export/export_repository.dart';
import '../../../data/sync/sync_repository.dart';
import '../import_controller.dart';
import 'drive_backup_settings.dart';

@immutable
class DriveBackupState {
  const DriveBackupState({
    this.working = false,
    this.message,
  });

  final bool working;

  /// The last run's outcome, or null if it had nothing to say.
  final String? message;
}

/// Uploads a full-vault backup to Google Drive.
///
/// **Foreground only**, exactly like `AutoImportController`: at launch, on every
/// resume (throttled by the interval), and after an import commits. The same
/// reasons apply — a headless WorkManager isolate has no Riverpod graph, so the
/// server config and the export call would have to be re-plumbed outside it.
///
/// Manual uploads from the export wizard don't come through here: they carry
/// the wizard's own scope, and `ExportController.buildAndUpload` owns them.
class DriveBackupController extends Notifier<DriveBackupState> {
  AppLifecycleListener? _lifecycle;

  @override
  DriveBackupState build() {
    _lifecycle = AppLifecycleListener(onResume: check);
    ref.onDispose(() => _lifecycle?.dispose());

    // Listening rather than being called from ImportController keeps the
    // importer ignorant of Drive — and catches manual and unattended imports
    // alike, since both end in the same ImportDone.
    ref.listen(importControllerProvider, (previous, next) {
      if (next is ImportDone && previous is! ImportDone) {
        check(afterImport: true);
      }
    });

    Future<void>.microtask(check);
    return const DriveBackupState();
  }

  /// Run an automatic upload if one is owed.
  ///
  /// [force] is "Upload now": it ignores the mode, the interval and the
  /// nothing-changed check, and may show Google's sign-in UI. [now] exists for
  /// tests.
  Future<void> check({
    bool force = false,
    bool afterImport = false,
    DateTime? now,
  }) async {
    if (state.working) return;
    if (!ref.read(isConfiguredProvider)) return;

    final settingsController = ref.read(driveBackupSettingsProvider.notifier);
    await settingsController.ready;
    final settings = ref.read(driveBackupSettingsProvider);
    final at = now ?? DateTime.now();

    if (!force) {
      if (!settings.isAutomatic) return;
      if (afterImport ? !settings.afterImport : !settings.isDue(at)) return;
      // An import in flight changes the vault under us; its ImportDone brings
      // us back when it's finished.
      if (ref.read(importControllerProvider).isBusy) return;
    }

    state = const DriveBackupState(working: true);
    try {
      // Before building anything: a multi-MB export of an unchanged vault
      // would cost the server a full build and Drive a duplicate file.
      final meta = await ref.read(syncRepositoryProvider).meta();
      if (!force && !settings.changedSince(meta.serverEpoch, meta.cursor)) {
        settingsController.markChecked(at);
        state = const DriveBackupState(
          message: 'Nothing changed since the last upload.',
        );
        return;
      }

      final store = await ref.read(driveOpenerProvider)(interactive: force);
      if (store == null) {
        state = force
            ? const DriveBackupState(message: 'Google sign-in was cancelled.')
            : const DriveBackupState(
                message: 'Tap Upload now to reconnect Google Drive.',
              );
        return;
      }

      try {
        // The default scope is the whole vault with every include on.
        final built =
            await ref.read(exportRepositoryProvider).build(const ExportScope());
        await store.upload(built.fileName, built.bytes, automatic: true);
        await _prune(store);
        // Only now, so a failed upload is retried rather than recorded.
        settingsController.markUploaded(
          built.fileName,
          at,
          epoch: meta.serverEpoch,
          cursor: meta.cursor,
        );
        state = DriveBackupState(message: 'Uploaded ${built.fileName}.');
      } finally {
        store.close();
      }
    } catch (e) {
      state = DriveBackupState(message: _message(e));
    }
  }

  /// Keep the newest [kDriveKeepAutomatic] automatic uploads.
  Future<void> _prune(DriveStore store) async {
    try {
      final stale = (await store.automaticBackupIds()).skip(kDriveKeepAutomatic);
      for (final id in stale) {
        await store.delete(id);
      }
    } catch (_) {
      // Housekeeping: a failed prune must not turn a good upload into an
      // error. The next successful run tries again.
    }
  }

  static String _message(Object e) {
    final drive = describeDriveError(e);
    if (drive != null) return drive;
    if (e is DioException && e.type == DioExceptionType.connectionError) {
      return "Couldn't reach the server.";
    }
    return e.toString().replaceFirst('Exception: ', '');
  }
}

final driveBackupProvider =
    NotifierProvider<DriveBackupController, DriveBackupState>(
  DriveBackupController.new,
);
