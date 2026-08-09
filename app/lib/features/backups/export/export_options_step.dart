import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup_apps/backup_app_models.dart';
import '../../../data/backup_apps/backup_apps_repository.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/selectable_chip.dart';
import 'export_controller.dart';

/// Step 2 — **what travels with each title**, and which app the file is for.
///
/// Everything starts on. The switches exist for the narrower jobs (seeding a
/// second device with a clean library, handing someone a title list) and the
/// screen says plainly what each one costs, because "backup" and "silently
/// missing your reading progress" must never be the same tap.
class ExportOptionsStep extends ConsumerWidget {
  const ExportOptionsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);
    final includes = state.scope.includes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.gutter,
        AppDimens.unit,
        AppDimens.gutter,
        AppDimens.gutter,
      ),
      children: [
        BentoCell(
          tone: BentoTone.high,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: CellLabel('Include in the backup')),
                  if (includes.isLossless)
                    const _LosslessBadge()
                  else
                    const _PartialBadge(),
                ],
              ),
              const SizedBox(height: AppDimens.unit),
              _OptionSwitch(
                icon: Icons.menu_book_outlined,
                title: 'Chapters',
                subtitle: 'The chapter list for every title.',
                value: includes.chapters,
                onChanged: controller.setIncludeChapters,
              ),
              _OptionSwitch(
                icon: Icons.bookmark_added_outlined,
                title: 'Reading progress',
                subtitle: includes.chapters
                    ? 'Read markers, page position and reading history.'
                    : 'Needs chapters — progress lives on them.',
                value: includes.chapters && includes.readProgress,
                // Progress cannot outlive the chapters it hangs off, so the
                // switch goes inert rather than pretending to be available.
                onChanged:
                    includes.chapters ? controller.setIncludeReadProgress : null,
              ),
              _OptionSwitch(
                icon: Icons.folder_outlined,
                title: 'Categories',
                subtitle: 'Your collections and which titles are in them.',
                value: includes.categories,
                onChanged: controller.setIncludeCategories,
              ),
              _OptionSwitch(
                icon: Icons.sync_alt,
                title: 'Tracker links',
                subtitle: 'AniList, MyAnimeList and other tracker entries.',
                value: includes.tracking,
                onChanged: controller.setIncludeTracking,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gutter),
        const _CoverNote(),
        const SizedBox(height: AppDimens.gutter),
        _TargetAppCell(
          selected: state.scope.targetApp,
          fileName: state.preview.value?.fileName,
          onPick: controller.setTargetApp,
        ),
      ],
    );
  }
}

class _LosslessBadge extends StatelessWidget {
  const _LosslessBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: 14, color: scheme.secondary),
        const SizedBox(width: 4),
        Text(
          'COMPLETE',
          style: Theme.of(context)
              .textTheme
              .labelSmall!
              .copyWith(color: scheme.secondary),
        ),
      ],
    );
  }
}

class _PartialBadge extends StatelessWidget {
  const _PartialBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          'PARTIAL',
          style: Theme.of(context)
              .textTheme
              .labelSmall!
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the row entirely (no tap target, dimmed).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;
    final fg = enabled ? scheme.onSurface : scheme.onSurfaceVariant;

    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      // Keeps the whole row a single tap target rather than just the switch.
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: Icon(
        icon,
        size: 20,
        color: enabled ? scheme.onSurfaceVariant : scheme.outline,
      ),
      title: Text(title, style: theme.textTheme.bodyLarge!.copyWith(color: fg)),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: enabled
              ? scheme.onSurfaceVariant
              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// States plainly what a `.tachibk` cannot carry, so a missing cover after a
/// restore reads as the format's limit rather than as a failed backup.
class _CoverNote extends StatelessWidget {
  const _CoverNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BentoCell(
      tone: BentoTone.low,
      padding: const EdgeInsets.all(AppDimens.unit * 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppDimens.unit * 1.5),
          Expanded(
            child: Text(
              'Cover images stay in the vault. The .tachibk format stores only '
              'the cover URL, which is what every reading app re-downloads from.',
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Which app the file is named for.
///
/// This is not cosmetic: the filename is the only place a `.tachibk` records
/// which app produced it, so it decides how a future re-import into MangaVault
/// attributes these titles.
class _TargetAppCell extends ConsumerWidget {
  const _TargetAppCell({
    required this.selected,
    required this.fileName,
    required this.onPick,
  });

  final String selected;
  final String? fileName;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final apps = ref.watch(backupAppsProvider).value ?? const <BackupApp>[];

    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('File name'),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Name the backup for the app you plan to restore it into.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.gutter),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            children: [
              SelectableChip(
                label: 'MangaVault',
                icon: Icons.inventory_2_outlined,
                selected: selected.isEmpty,
                onTap: () => onPick(''),
              ),
              for (final app in apps)
                SelectableChip(
                  label: app.displayName,
                  icon: Icons.smartphone_rounded,
                  selected: selected == app.id,
                  onTap: () => onPick(app.id),
                ),
            ],
          ),
          if (fileName != null) ...[
            const SizedBox(height: AppDimens.gutter),
            NestedWell(
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppDimens.unit),
                  Expanded(
                    child: Text(
                      fileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
