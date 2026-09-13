import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/google/google_account.dart';
import '../../../data/drive/drive_store.dart';
import '../../../theme/app_accents.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/entrance_fade.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/selectable_chip.dart';
import 'drive_backup_controller.dart';
import 'drive_backup_settings.dart';

/// The Google account, and when backups go to it.
///
/// Reached from the Backups hub. Device-local like auto-import: which Google
/// account a phone uses means nothing to the vault.
class DriveBackupScreen extends ConsumerWidget {
  const DriveBackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(googleAccountProvider).connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          const EntranceFade(child: _AccountCell()),
          if (connected) ...[
            const SizedBox(height: AppDimens.gutter),
            const EntranceFade(
              delay: Duration(milliseconds: 60),
              child: _UploadsCell(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountCell extends ConsumerWidget {
  const _AccountCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium!
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
    final account = ref.watch(googleAccountProvider);
    final controller = ref.read(googleAccountProvider.notifier);

    return BentoCell(
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: CellLabel('ACCOUNT')),
              AccentIconWell(
                icon: Icons.cloud_outlined,
                accent: VaultAccent.violet,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          if (!account.available)
            Text(
              "Google Drive isn't set up in this build of Manga Vault.",
              style: muted,
            )
          else if (account.connected) ...[
            Text(account.email!, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.unit),
            Text(
              'Backups go to the “$kDriveFolderName” folder. Manga Vault can '
              'only see files it created there.',
              style: muted,
            ),
            const SizedBox(height: AppDimens.unit),
            TextButton.icon(
              onPressed: controller.disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Disconnect'),
            ),
          ] else ...[
            Text(
              'Keep copies of your backups in your own Google Drive. Manga '
              'Vault can only see the files it creates.',
              style: muted,
            ),
            const SizedBox(height: AppDimens.unit * 2),
            PillButton(
              label: 'Connect Google',
              icon: Icons.login,
              accent: VaultAccent.violet,
              onPressed: account.busy ? null : controller.connect,
            ),
          ],
          if (account.error != null) ...[
            const SizedBox(height: AppDimens.unit),
            Text(
              account.error!,
              style: theme.textTheme.bodySmall!
                  .copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _UploadsCell extends ConsumerWidget {
  const _UploadsCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
    final settings = ref.watch(driveBackupSettingsProvider);
    final settingsController = ref.read(driveBackupSettingsProvider.notifier);
    final drive = ref.watch(driveBackupProvider);

    return BentoCell(
      accent: VaultAccent.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('UPLOADS'),
          const SizedBox(height: AppDimens.unit * 1.5),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            children: [
              SelectableChip(
                label: 'Manual',
                selected: !settings.isAutomatic,
                onTap: () => settingsController.setMode(DriveUploadMode.manual),
              ),
              SelectableChip(
                label: 'Automatic',
                selected: settings.isAutomatic,
                onTap: () {
                  if (settings.isAutomatic) return;
                  settingsController.setMode(DriveUploadMode.automatic);
                  // Visible proof the switch did something, instead of
                  // waiting for the next resume. Still skips an unchanged
                  // vault.
                  ref.read(driveBackupProvider.notifier).check();
                },
              ),
            ],
          ),
          if (settings.isAutomatic) ...[
            const SizedBox(height: AppDimens.unit * 1.5),
            Wrap(
              spacing: AppDimens.unit,
              runSpacing: AppDimens.unit,
              children: [
                for (final hours in kDriveIntervals)
                  SelectableChip(
                    label: 'Every ${hours}h',
                    selected: settings.intervalHours == hours,
                    onTap: () => settingsController.setInterval(hours),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              value: settings.afterImport,
              onChanged: settingsController.setAfterImport,
              contentPadding: EdgeInsets.zero,
              title: Text('Also after each import',
                  style: theme.textTheme.bodyLarge),
            ),
          ],
          const SizedBox(height: AppDimens.unit),
          // The honest version, as on auto-import: Android won't wake the app
          // on a schedule, so "every 12 hours" would be a promise it can't keep.
          Text(
            settings.isAutomatic
                ? 'The whole vault is uploaded when you open Manga Vault, at '
                    'most once every ${settings.intervalHours} hours, and only '
                    'if something changed. The newest $kDriveKeepAutomatic are '
                    'kept.'
                : 'Send a backup from Create Backup, or upload the whole vault '
                    'below. Nothing is uploaded on its own.',
            style: muted,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  drive.working
                      ? 'Working…'
                      : drive.message ??
                          (settings.lastUploadAtMs == 0
                              ? 'Nothing uploaded yet.'
                              : 'Last upload '
                                  '${relativeDate(settings.lastUploadAtMs)}.'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppDimens.unit),
              PillButton(
                label: 'Upload now',
                icon: Icons.cloud_upload_outlined,
                accent: VaultAccent.cyan,
                onPressed: drive.working
                    ? null
                    : () => ref.read(driveBackupProvider.notifier).check(
                          force: true,
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
