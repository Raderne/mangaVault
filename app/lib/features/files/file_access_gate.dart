import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/files/file_access.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pill_button.dart';

/// Shown wherever the browser would be, when the app can't read storage yet.
///
/// Amber, not rose: nothing has failed, the flow is waiting on the user — the
/// same reading `_NeedsAppCell` gets on the Backups hub.
///
/// It always offers the system picker as a way through. An archive tool whose
/// import button opens a wall is worse than one that looks less polished, and
/// the `FilePicker` path is still there and still works.
class FileAccessGate extends ConsumerWidget {
  const FileAccessGate({
    super.key,
    this.onUseSystemPicker,
    this.systemPickerLabel = 'Use the system picker instead',
  });

  /// Falls back to the platform dialog. Null hides the escape hatch (used where
  /// the caller has no fallback to offer).
  final VoidCallback? onUseSystemPicker;
  final String systemPickerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(fileAccessProvider);
    final blocked = status == FileAccessStatus.permanentlyDenied;

    return BentoCell(
      accent: VaultAccent.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: CellLabel('File access')),
              AccentIconWell(
                icon: Icons.folder_open_outlined,
                accent: VaultAccent.amber,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          Text(
            'Let MangaVault browse your files',
            style: theme.textTheme.titleMedium!
                .copyWith(color: VaultAccent.amber.color),
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            blocked
                ? 'File access was turned off for MangaVault. Switch it back on '
                    'in the app settings to browse for backups here.'
                : 'A .tachibk is not a photo or a document, so Android only '
                    'hands it over with full file access. Granting it lets '
                    'MangaVault open the folder your reading app writes backups '
                    'to, and save new ones back beside them.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.gutter),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillButton(
                label: blocked ? 'Open app settings' : 'Grant file access',
                icon: blocked ? Icons.settings : Icons.lock_open,
                accent: VaultAccent.amber,
                onPressed: () => blocked
                    ? openFileAccessSettings()
                    : ref.read(fileAccessProvider.notifier).request(),
              ),
              if (onUseSystemPicker != null)
                TextButton(
                  onPressed: onUseSystemPicker,
                  child: Text(
                    systemPickerLabel,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            // Android drops the user on a settings page rather than a dialog,
            // and coming back is the step people miss.
            'Android opens its own settings screen for this. Flip the switch, '
            'then come back — this will update on its own.',
            style: theme.textTheme.labelSmall!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
