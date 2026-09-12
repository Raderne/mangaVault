import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/files/file_access.dart';
import '../../core/files/storage_roots.dart';
import '../../core/files/watched_folders.dart';
import '../../data/backup_apps/backup_app_models.dart';
import '../../data/backup_apps/backup_apps_repository.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/selectable_chip.dart';
import '../files/file_access_gate.dart';
import '../files/file_browser_route.dart';
import 'auto_import_controller.dart';
import 'source_app_sheet.dart';

/// Where the watcher looks, and how often.
///
/// Reached from the Backups hub. Everything here is device-local — a path on
/// this phone means nothing to the vault — so none of it syncs.
class AutoImportScreen extends ConsumerWidget {
  const AutoImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(fileAccessProvider).isGranted;

    return Scaffold(
      appBar: AppBar(title: const Text('Auto-import')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          const EntranceFade(child: _ScheduleCell()),
          const SizedBox(height: AppDimens.gutter),
          if (!granted) ...[
            const FileAccessGate(),
            const SizedBox(height: AppDimens.gutter),
          ],
          const EntranceFade(
            delay: Duration(milliseconds: 60),
            child: _FoldersCell(),
          ),
          const SizedBox(height: AppDimens.gutter),
          const EntranceFade(
            delay: Duration(milliseconds: 120),
            child: _AddFolderCell(),
          ),
        ],
      ),
    );
  }
}

/// The interval, the last run, and the manual escape hatch.
class _ScheduleCell extends ConsumerWidget {
  const _ScheduleCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(autoImportSettingsProvider);
    final auto = ref.watch(autoImportProvider);

    return BentoCell(
      accent: VaultAccent.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('CHECK FOR NEW BACKUPS'),
          const SizedBox(height: AppDimens.unit * 1.5),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            children: [
              for (final hours in kAutoImportIntervals)
                SelectableChip(
                  label: hours == 0 ? 'Off' : 'Every ${hours}h',
                  selected: settings.intervalHours == hours,
                  onTap: () => ref
                      .read(autoImportSettingsProvider.notifier)
                      .setInterval(hours),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          // The honest version of what this does. An Android app cannot wake
          // itself on a schedule without background work, and promising "every
          // 12 hours" when the real trigger is a resume would be a lie the user
          // only discovers when a backup goes missing.
          Text(
            settings.intervalHours == 0
                ? 'Scanning only when you tap below.'
                : 'Checked when you open Manga Vault, at most once every '
                    '${settings.intervalHours} hours.',
            style: theme.textTheme.bodySmall!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  auto.scanning
                      ? 'Scanning…'
                      : auto.message ?? _lastScan(settings.lastScanAt),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppDimens.unit),
              PillButton(
                label: 'Scan now',
                icon: Icons.sync,
                accent: VaultAccent.cyan,
                onPressed: auto.scanning || settings.folders.isEmpty
                    ? null
                    : () => ref.read(autoImportProvider.notifier).scan(force: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _lastScan(DateTime? at) {
    if (at == null) return 'Not scanned yet.';
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'Last checked just now.';
    if (ago.inHours < 1) return 'Last checked ${ago.inMinutes}m ago.';
    if (ago.inDays < 1) return 'Last checked ${ago.inHours}h ago.';
    return 'Last checked ${ago.inDays}d ago.';
  }
}

/// The watched folders, each with the app it is attributed to.
class _FoldersCell extends ConsumerWidget {
  const _FoldersCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(autoImportSettingsProvider).folders;

    return BentoCell(
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('WATCHED FOLDERS'),
          const SizedBox(height: AppDimens.unit * 1.5),
          if (folders.isEmpty)
            Text(
              'No folders yet. Add the one your reading app writes its '
              'automatic backups into — usually Mihon/autobackup.',
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            for (final folder in folders) ...[
              _FolderRow(folder: folder),
              if (folder != folders.last)
                const SizedBox(height: AppDimens.unit),
            ],
        ],
      ),
    );
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({required this.folder});

  final WatchedFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final names = ref.watch(backupAppNamesProvider).value ?? const {};

    return NestedWell(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _shortPath(folder.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(folder, names),
                  maxLines: 2,
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.label_outline, size: 20),
            tooltip: 'Change app',
            onPressed: () async {
              final picked = await showSourceAppSheet(
                context,
                fileName: _shortPath(folder.path),
                current: folder.appId.isEmpty ? null : folder.appId,
              );
              if (picked == null) return;
              ref
                  .read(autoImportSettingsProvider.notifier)
                  .setAppId(folder.path, picked);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Stop watching',
            onPressed: () => ref
                .read(autoImportSettingsProvider.notifier)
                .removeFolder(folder.path),
          ),
        ],
      ),
    );
  }

  /// The app tag matters enough to show even when nothing has imported yet: it
  /// is the answer to a question nobody will be around to be asked.
  static String _subtitle(WatchedFolder folder, Map<String, String> names) {
    final app = folder.appId.isEmpty
        ? 'Unknown app'
        : backupAppLabel(folder.appId, displayName: names[folder.appId]);
    if (folder.lastFileName.isEmpty) return '$app · nothing imported yet';
    return '$app · last: ${folder.lastFileName}';
  }
}

/// Suggestions first, browser second.
class _AddFolderCell extends ConsumerWidget {
  const _AddFolderCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = {
      for (final f in ref.watch(autoImportSettingsProvider).folders) f.path,
    };
    final suggestions = ref
            .watch(autoBackupFoldersProvider)
            .value
            ?.where((f) => !watched.contains(f.path))
            .toList() ??
        const [];

    return BentoCell(
      accent: VaultAccent.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('ADD A FOLDER'),
          const SizedBox(height: AppDimens.unit * 1.5),
          if (suggestions.isNotEmpty) ...[
            Wrap(
              spacing: AppDimens.unit,
              runSpacing: AppDimens.unit,
              children: [
                for (final folder in suggestions)
                  SelectableChip(
                    label: folder.label,
                    selected: false,
                    icon: Icons.folder_outlined,
                    onTap: () => _add(context, ref, folder.path),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.unit * 1.5),
          ],
          PillButton(
            label: 'Browse…',
            icon: Icons.folder_open,
            accent: VaultAccent.emerald,
            onPressed: () async {
              final path = await openFolderBrowser(context);
              if (path == null || !context.mounted) return;
              await _add(context, ref, path);
            },
          ),
        ],
      ),
    );
  }

  /// Always asks which app owns the folder rather than inferring it from the
  /// folder's name. A wrong id silently fails to match real backups, and the
  /// filename usually answers this anyway — the tag is only the fallback, so
  /// dismissing the sheet (leaving it unknown) is a perfectly good answer.
  Future<void> _add(BuildContext context, WidgetRef ref, String path) async {
    final appId = await showSourceAppSheet(context, fileName: _shortPath(path));
    ref.read(autoImportSettingsProvider.notifier).addFolder(path, appId ?? '');
  }
}

/// `/storage/emulated/0/Mihon/autobackup` → `Mihon/autobackup`. The volume root
/// is the same on every row and eats the width the folder name needs.
String _shortPath(String path) {
  final parts = p.posix.split(path).where((s) => s.isNotEmpty).toList();
  return parts.length <= 2 ? path : parts.sublist(parts.length - 2).join('/');
}
