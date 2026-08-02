import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/library/library_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/selectable_chip.dart';
import 'library_controller.dart';
import 'library_display.dart';

/// Library branch index in the shell's bottom navigation.
const int kLibraryBranchIndex = 1;

/// Below this many sources the list is short enough to scan; above it, the
/// sheet offers a filter box so a 25-source library stays usable.
const int _kSourceSearchThreshold = 8;

/// Open the library's filter / sort / display sheet.
///
/// Lives outside `LibraryScreen` because it is also opened from [AppShell] when
/// the Library tab is re-tapped — it reads and writes the library providers
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
    builder: (_) => const LibraryOptionsSheet(),
  );
}

/// True when the grid is showing anything other than its default *data* — drives
/// the app bar's badge. Display options are deliberately excluded: they change
/// how titles look, not which titles you're looking at.
bool hasActiveFilters(LibraryFilters f) =>
    f.status.isNotEmpty ||
    f.sourceIds.isNotEmpty ||
    f.sourceApps.isNotEmpty ||
    !f.favorite ||
    f.sortBy != 'title' ||
    f.sortDir != 'asc';

/// The library's options sheet: three tabs over one scroll surface.
///
/// Everything that shapes the grid used to be an inline bar, which overflowed;
/// then a single scrolling column, which grew too long once sources and display
/// options joined. Tabs keep each decision one screenful and let the sheet hold
/// a 25-row source list without burying the sort options under it.
class LibraryOptionsSheet extends ConsumerStatefulWidget {
  const LibraryOptionsSheet({super.key});

  @override
  ConsumerState<LibraryOptionsSheet> createState() =>
      _LibraryOptionsSheetState();
}

class _LibraryOptionsSheetState extends ConsumerState<LibraryOptionsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String _sourceQuery = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(libraryControllerProvider);

    // A fixed body height keeps the sheet from resizing as you switch tabs
    // (the source list is far taller than the sort list). Capped so it never
    // swallows the whole screen, floored so it isn't a letterbox on a small one.
    final bodyHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(300.0, 520.0);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.cellPadding),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text('Library view', style: theme.textTheme.titleMedium),
                ),
                if (state.status == LibraryStatus.ready)
                  Text(
                    '${groupedNumber(state.total)} titles',
                    style: theme.textTheme.labelSmall!
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.unit),
          TabBar(
            controller: _tabs,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: scheme.onSurface,
            unselectedLabelColor: scheme.onSurfaceVariant,
            labelStyle: theme.textTheme.labelSmall!
                .copyWith(fontWeight: FontWeight.w600),
            unselectedLabelStyle: theme.textTheme.labelSmall,
            tabs: const [
              Tab(text: 'FILTER'),
              Tab(text: 'SORT'),
              Tab(text: 'DISPLAY'),
            ],
          ),
          SizedBox(
            height: bodyHeight,
            child: TabBarView(
              controller: _tabs,
              children: [
                _FilterTab(
                  query: _sourceQuery,
                  onQueryChanged: (q) => setState(() => _sourceQuery = q),
                ),
                const _SortTab(),
                const _DisplayTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared scroll padding for a tab body.
const _tabPadding = EdgeInsets.fromLTRB(
  AppDimens.cellPadding,
  AppDimens.unit * 2,
  AppDimens.cellPadding,
  AppDimens.cellPadding,
);

// ---------------------------------------------------------------- filter tab

class _FilterTab extends ConsumerWidget {
  const _FilterTab({required this.query, required this.onQueryChanged});

  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(libraryControllerProvider).filters;
    final controller = ref.read(libraryControllerProvider.notifier);
    final sources = ref.watch(librarySourcesProvider);
    final apps = ref.watch(libraryAppsProvider);

    return ListView(
      padding: _tabPadding,
      children: [
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

        // Which reading app a title came from. Chips rather than the searchable
        // source list: there are a handful of apps against 25+ sources. A title
        // merged from two apps' backups appears under both.
        Row(
          children: [
            const Expanded(child: CellLabel('From app')),
            if (filters.sourceApps.isNotEmpty)
              TextButton(
                onPressed: () => controller.setSourceApps(const []),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Clear (${filters.sourceApps.length})'),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.unit),
        apps.when(
          loading: () => const SizedBox(height: AppDimens.unit * 4),
          error: (_, _) => Text(
            "Couldn't read backup apps",
            style: theme.textTheme.bodySmall!
                .copyWith(color: theme.colorScheme.error),
          ),
          data: (all) => all.isEmpty
              ? Text(
                  'Nothing imported yet.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: AppDimens.unit,
                  runSpacing: AppDimens.unit,
                  children: [
                    for (final app in all)
                      _SheetChip(
                        label: app.label,
                        trailing: groupedNumber(app.count),
                        selected: filters.sourceApps.contains(app.id),
                        onTap: () => controller.toggleSourceApp(app.id),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppDimens.unit * 2.5),

        Row(
          children: [
            const Expanded(child: CellLabel('Sources')),
            if (filters.sourceIds.isNotEmpty)
              TextButton(
                onPressed: () => controller.setSources(const []),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Clear (${filters.sourceIds.length})'),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.unit),
        sources.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDimens.unit * 2),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Text(
            "Couldn't read sources",
            style: theme.textTheme.bodySmall!
                .copyWith(color: theme.colorScheme.error),
          ),
          data: (all) => _SourceList(
            sources: all,
            selected: filters.sourceIds,
            query: query,
            onQueryChanged: onQueryChanged,
            onToggle: controller.toggleSource,
          ),
        ),

        if (hasActiveFilters(filters)) ...[
          const SizedBox(height: AppDimens.unit * 2),
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
    );
  }
}

/// The source picker: an optional filter box plus one selectable row per
/// source, showing how many titles it accounts for.
class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.sources,
    required this.selected,
    required this.query,
    required this.onQueryChanged,
    required this.onToggle,
  });

  final List<SourceOption> sources;
  final List<String> selected;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (sources.isEmpty) {
      return Text(
        'No sources yet — import a backup.',
        style: theme.textTheme.bodySmall!
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final needle = query.trim().toLowerCase();
    final shown = needle.isEmpty
        ? sources
        : sources
            .where((s) => s.label.toLowerCase().contains(needle))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sources.length > _kSourceSearchThreshold) ...[
          TextField(
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Find a source',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          const SizedBox(height: AppDimens.unit),
        ],
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.unit),
            child: Text(
              'No source matches "$query"',
              style: theme.textTheme.bodySmall!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final source in shown)
          _SourceRow(
            key: ValueKey(source.id),
            source: source,
            selected: selected.contains(source.id),
            onTap: () => onToggle(source.id),
          ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final SourceOption source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Sources whose backup carried no name show their numeric id in a monospace
    // tone, so it reads as an identifier rather than a title.
    final unnamed = source.name.trim().isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.unit * 1.5),
      child: Padding(
        // 44pt minimum touch target even at the default text size.
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.unit, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppDimens.unit * 1.5),
            Expanded(
              child: Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: unnamed ? scheme.onSurfaceVariant : scheme.onSurface,
                  fontFeatures: unnamed
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            Text(
              groupedNumber(source.count),
              style: theme.textTheme.labelSmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sort tab

class _SortTab extends ConsumerWidget {
  const _SortTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filters = ref.watch(libraryControllerProvider).filters;
    final controller = ref.read(libraryControllerProvider.notifier);

    return ListView(
      padding: _tabPadding,
      children: [
        const CellLabel('Sort by'),
        const SizedBox(height: AppDimens.unit / 2),
        for (final sort in kLibrarySorts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text(sort.label, style: theme.textTheme.bodyMedium),
            // The active row carries the direction, and tapping it flips —
            // so every field can be read either way without extra controls.
            trailing: sort.isActive(filters)
                ? Icon(
                    filters.sortDir == 'asc'
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 18,
                    color: scheme.secondary,
                  )
                : null,
            onTap: () => controller.setSort(sort),
          ),
        const SizedBox(height: AppDimens.unit),
        Text(
          'Tap the active sort to reverse it.',
          style: theme.textTheme.labelSmall!
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- display tab

class _DisplayTab extends ConsumerWidget {
  const _DisplayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(libraryDisplayProvider);
    final controller = ref.read(libraryDisplayProvider.notifier);

    return ListView(
      padding: _tabPadding,
      children: [
        const CellLabel('Layout'),
        const SizedBox(height: AppDimens.unit),
        Wrap(
          spacing: AppDimens.unit,
          runSpacing: AppDimens.unit,
          children: [
            _SheetChip(
              label: 'Comfortable',
              icon: Icons.grid_view_rounded,
              selected: display.layout == LibraryLayout.comfortable,
              onTap: () => controller.setLayout(LibraryLayout.comfortable),
            ),
            _SheetChip(
              label: 'Compact',
              icon: Icons.apps_rounded,
              selected: display.layout == LibraryLayout.compact,
              onTap: () => controller.setLayout(LibraryLayout.compact),
            ),
            _SheetChip(
              label: 'List',
              icon: Icons.view_list_rounded,
              selected: display.layout == LibraryLayout.list,
              onTap: () => controller.setLayout(LibraryLayout.list),
            ),
          ],
        ),

        if (display.isGrid) ...[
          const SizedBox(height: AppDimens.unit * 2.5),
          const CellLabel('Columns'),
          const SizedBox(height: AppDimens.unit),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            children: [
              for (final n in display.columnOptions)
                _SheetChip(
                  label: '$n',
                  selected: display.columns == n,
                  onTap: () => controller.setColumns(n),
                ),
            ],
          ),
        ],

        const SizedBox(height: AppDimens.unit * 2),
        const CellLabel('On each title'),
        const SizedBox(height: AppDimens.unit / 2),
        _ToggleRow(
          label: 'Unread count',
          subtitle: 'Badge with unread chapters',
          value: display.showUnreadBadge,
          onChanged: controller.setShowUnreadBadge,
        ),
        _ToggleRow(
          label: 'Source name',
          subtitle: 'Where the title came from',
          value: display.showSourceName,
          onChanged: controller.setShowSourceName,
        ),

        if (!display.isDefault) ...[
          const SizedBox(height: AppDimens.unit),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.reset,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset display'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(label, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.labelSmall!
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The sheet's chip-style option. Moved to `widgets/selectable_chip.dart` so
/// the import flow's source-app picker renders the same control.
typedef _SheetChip = SelectableChip;
