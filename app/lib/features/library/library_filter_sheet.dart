import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import 'library_controller.dart';

/// Library branch index in the shell's bottom navigation.
const int kLibraryBranchIndex = 1;

/// Open the library's filter & sort sheet.
///
/// Lives outside `LibraryScreen` because it is also opened from [AppShell] when
/// the Library tab is re-tapped — it reads and writes `libraryControllerProvider`
/// directly, so it needs no screen state.
Future<void> showLibraryFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppDimens.cellRadius)),
    ),
    builder: (_) => const _LibraryFilterSheet(),
  );
}

/// True when the grid is showing anything other than its defaults — drives the
/// app bar's "filters active" dot, since the filters are no longer on screen.
bool hasActiveFilters(LibraryFilters f) =>
    f.status.isNotEmpty ||
    !f.favorite ||
    f.sortBy != 'title' ||
    f.sortDir != 'asc';

class _LibraryFilterSheet extends ConsumerWidget {
  const _LibraryFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final filters = state.filters;

    return SafeArea(
      // The sheet can grow past the viewport at large text scales, so it
      // scrolls rather than overflowing.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.cellPadding,
            0,
            AppDimens.cellPadding,
            AppDimens.cellPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Filter & sort',
                        style: theme.textTheme.titleMedium),
                  ),
                  if (state.status == LibraryStatus.ready)
                    Text(
                      '${groupedNumber(state.total)} titles',
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.unit * 2),

              const CellLabel('Status'),
              const SizedBox(height: AppDimens.unit),
              Wrap(
                spacing: AppDimens.unit,
                runSpacing: AppDimens.unit,
                children: [
                  for (final (label, value) in kStatusFilters)
                    _SheetChip(
                      label: label,
                      selected: filters.status == value,
                      onTap: () => controller.setStatus(value),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.unit * 2.5),

              const CellLabel('Show'),
              const SizedBox(height: AppDimens.unit),
              Wrap(
                spacing: AppDimens.unit,
                runSpacing: AppDimens.unit,
                children: [
                  _SheetChip(
                    label: 'Favorites',
                    icon: Icons.star_rounded,
                    selected: filters.favorite,
                    onTap: () => controller.setFavorite(true),
                  ),
                  _SheetChip(
                    label: 'Others',
                    icon: Icons.star_outline_rounded,
                    selected: !filters.favorite,
                    onTap: () => controller.setFavorite(false),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.unit * 2.5),

              const CellLabel('Sort by'),
              const SizedBox(height: AppDimens.unit / 2),
              for (final sort in kLibrarySorts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(sort.label, style: theme.textTheme.bodyMedium),
                  trailing: sort.matches(filters)
                      ? Icon(Icons.check, color: theme.colorScheme.secondary)
                      : null,
                  onTap: () => controller.setSort(sort),
                ),

              if (hasActiveFilters(filters)) ...[
                const SizedBox(height: AppDimens.unit),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: controller.resetFilters,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset to defaults'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill used for the sheet's status and show options.
class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label.toUpperCase(),
                style:
                    Theme.of(context).textTheme.labelSmall!.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
