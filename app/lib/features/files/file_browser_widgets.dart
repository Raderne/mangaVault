import 'package:flutter/material.dart';

import '../../core/files/storage_roots.dart';
import '../../core/files/vault_file_system.dart';
import '../../core/format.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/selectable_chip.dart';
import 'file_browser_controller.dart';

/// Minimum tap target for a list row, independent of text scale.
const double kFileRowMinHeight = 48;

/// Where you are, as tappable segments, plus the volume switcher.
///
/// Horizontally scrollable and reversed-aligned so a deep path shows its *tail*
/// first — the folder you are in matters more than the volume you started from,
/// and a deep path would otherwise scroll the useful end off screen.
class BrowserLocationCell extends StatelessWidget {
  const BrowserLocationCell({
    super.key,
    required this.state,
    required this.accent,
    required this.onJumpToCrumb,
    required this.onSwitchVolume,
  });

  final FileBrowserState state;
  final VaultAccent accent;
  final ValueChanged<int> onJumpToCrumb;
  final ValueChanged<StorageVolume> onSwitchVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crumbs = state.crumbs;
    final volume = state.volume;

    return BentoCell(
      tone: BentoTone.high,
      accent: accent,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.unit * 2,
        vertical: AppDimens.unit * 1.5,
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 18, color: accent.color),
          const SizedBox(width: AppDimens.unit),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _Crumb(
                    label: volume?.label ?? 'Storage',
                    // The volume itself is only "current" when nothing is below
                    // it; otherwise it's a jump target like any other segment.
                    isCurrent: crumbs.isEmpty,
                    accent: accent,
                    onTap: () => onJumpToCrumb(0),
                  ),
                  for (var i = 0; i < crumbs.length; i++) ...[
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    _Crumb(
                      label: crumbs[i],
                      isCurrent: i == crumbs.length - 1,
                      accent: accent,
                      onTap: () => onJumpToCrumb(i + 1),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (state.volumes.length > 1) ...[
            const SizedBox(width: AppDimens.unit),
            PopupMenuButton<StorageVolume>(
              tooltip: 'Switch storage',
              icon: Icon(Icons.sd_storage_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              onSelected: onSwitchVolume,
              itemBuilder: (_) => [
                for (final v in state.volumes)
                  PopupMenuItem(value: v, child: Text(v.label)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.isCurrent,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VaultAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: isCurrent ? null : onTap,
      borderRadius: BorderRadius.circular(AppDimens.unit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium!.copyWith(
            color: isCurrent ? accent.color : theme.colorScheme.onSurfaceVariant,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// One-tap destinations: Downloads, detected reading-app backup folders, and
/// folders the user has used before.
class QuickAccessRow extends StatelessWidget {
  const QuickAccessRow({
    super.key,
    required this.folders,
    required this.current,
    required this.onTap,
  });

  final List<QuickFolder> folders;
  final String current;
  final ValueChanged<QuickFolder> onTap;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.gutter),
        itemCount: folders.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppDimens.unit),
        itemBuilder: (context, i) {
          final folder = folders[i];
          return SelectableChip(
            label: folder.label,
            icon: folder.isRecent ? Icons.history : Icons.folder_outlined,
            selected: folder.path == current,
            onTap: () => onTap(folder),
          );
        },
      ),
    );
  }
}

/// Sort control, "show all files" toggle and the name filter.
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({
    super.key,
    required this.state,
    required this.onSort,
    required this.onSearch,
    required this.onToggleShowAll,
  });

  final FileBrowserState state;
  final ValueChanged<FileSort> onSort;
  final ValueChanged<String> onSearch;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter this folder',
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        ),
        const SizedBox(width: AppDimens.unit),
        PopupMenuButton<FileSort>(
          tooltip: 'Sort',
          initialValue: state.sort,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final sort in FileSort.values)
              PopupMenuItem(value: sort, child: Text(sort.label)),
          ],
          child: _ToolbarAffordance(
            icon: Icons.swap_vert,
            label: state.sort.label,
            active: state.sort != FileSort.modified,
          ),
        ),
        const SizedBox(width: AppDimens.unit),
        InkWell(
          onTap: onToggleShowAll,
          borderRadius: BorderRadius.circular(AppDimens.coverRadius),
          child: _ToolbarAffordance(
            icon: state.showAllFiles
                ? Icons.visibility
                : Icons.visibility_off_outlined,
            label: 'All',
            active: state.showAllFiles,
          ),
        ),
      ],
    );
  }
}

class _ToolbarAffordance extends StatelessWidget {
  const _ToolbarAffordance({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Container(
      // 44 tall so it clears the touch-target floor next to the search field.
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.unit * 1.5),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall!.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// One folder or file. Folders navigate; backups select; anything else is
/// context only — visible so the folder doesn't look wrong, muted and inert so
/// it never reads as a thing you failed to tap.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.selectable,
    required this.accent,
    required this.onTap,
  });

  final FileEntry entry;
  final bool selected;
  final bool selectable;
  final VaultAccent accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final interactive = onTap != null;
    final tinted = entry.isDirectory || selectable;

    return Semantics(
      button: interactive,
      selected: selectable ? selected : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.unit),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimens.coverRadius),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kFileRowMinHeight),
              child: NestedWell(
                accent: selected ? accent : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.unit * 1.5,
                  vertical: AppDimens.unit * 1.5,
                ),
                child: Row(
                  children: [
                    AccentIconWell(
                      icon: entry.isDirectory
                          ? Icons.folder_rounded
                          : Icons.description_outlined,
                      size: 32,
                      iconSize: 16,
                      accent: tinted ? accent : null,
                    ),
                    const SizedBox(width: AppDimens.unit * 1.5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: tinted
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (!entry.isDirectory) ...[
                            const SizedBox(height: 2),
                            Text(
                              _meta(entry),
                              style: theme.textTheme.labelSmall!
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.unit),
                    if (entry.isDirectory)
                      Icon(Icons.chevron_right,
                          size: 18, color: scheme.onSurfaceVariant)
                    else if (selectable)
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color:
                            selected ? accent.color : scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _meta(FileEntry entry) {
    final date = relativeDate(entry.modifiedMillis);
    final size = formatBytes(entry.sizeBytes);
    return date.isEmpty ? size : '$size · $date';
  }
}
