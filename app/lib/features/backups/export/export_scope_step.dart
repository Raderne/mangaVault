import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/export/export_models.dart';
import '../../../data/export/export_repository.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/selectable_chip.dart';
import 'export_controller.dart';
import 'export_widgets.dart';

/// Step 1 — **which titles**.
///
/// Three presets sit on top because they cover almost every real export, and
/// the full facet builder unfolds beneath only once the user asks for it. That
/// ordering is the whole design: "back up everything" must be one tap, while
/// "everything from Komikku that I've started and haven't finished" must still
/// be expressible.
class ExportScopeStep extends ConsumerWidget {
  const ExportScopeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);
    final facets = ref.watch(exportFacetsProvider);

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
              const CellLabel('What to back up'),
              const SizedBox(height: AppDimens.unit * 2),
              _Presets(state: state, controller: controller, facets: facets),
            ],
          ),
        ),
        if (state.scope.mode != ExportMode.all) ...[
          const SizedBox(height: AppDimens.gutter),
          facets.when(
            loading: () => const _FacetsLoading(),
            error: (e, _) => _FacetsError(message: '$e'),
            data: (data) => _FacetBuilder(
              facets: data,
              filters: state.scope.filters,
              controller: controller,
            ),
          ),
        ],
      ],
    );
  }
}

/// Which preset the current scope reads as. Derived rather than stored: the
/// user can arrive at "favorites only" either by tapping the preset or by
/// setting the facet by hand, and both must light the same tile.
enum _Preset { everything, favorites, custom }

_Preset _presetOf(ExportScope scope) {
  if (scope.mode == ExportMode.all) return _Preset.everything;
  final f = scope.filters;
  if (f.favorite == true && f.activeCount == 1) return _Preset.favorites;
  return _Preset.custom;
}

class _Presets extends StatelessWidget {
  const _Presets({
    required this.state,
    required this.controller,
    required this.facets,
  });

  final ExportState state;
  final ExportController controller;
  final AsyncValue<ExportFacets> facets;

  @override
  Widget build(BuildContext context) {
    final preset = _presetOf(state.scope);
    final data = facets.value;
    final total = data == null ? null : groupedNumber(data.totalTitles);
    final favorites = data == null ? null : groupedNumber(data.favoriteTitles);
    final active = state.scope.filters.activeCount;

    return Column(
      children: [
        ExportPresetTile(
          icon: Icons.all_inclusive,
          title: 'Everything',
          subtitle: total == null
              ? 'The whole vault'
              : '$total titles — the whole vault',
          selected: preset == _Preset.everything,
          onTap: controller.applyEverythingPreset,
        ),
        const SizedBox(height: AppDimens.unit),
        ExportPresetTile(
          icon: Icons.favorite_outline,
          title: 'Favorites only',
          subtitle: favorites == null
              ? 'Titles marked as favorite'
              : '$favorites titles marked as favorite',
          selected: preset == _Preset.favorites,
          onTap: controller.applyFavoritesPreset,
        ),
        const SizedBox(height: AppDimens.unit),
        ExportPresetTile(
          icon: Icons.tune,
          title: 'Custom selection',
          subtitle: preset == _Preset.custom && active > 0
              ? '$active filter${active == 1 ? '' : 's'} active'
              : 'Pick by app, source, category or status',
          selected: preset == _Preset.custom,
          onTap: controller.applyCustomPreset,
        ),
      ],
    );
  }
}

class _FacetsLoading extends StatelessWidget {
  const _FacetsLoading();

  @override
  Widget build(BuildContext context) => const BentoCell(
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppDimens.gutter),
            Text('Reading what the vault holds…'),
          ],
        ),
      );
}

class _FacetsError extends ConsumerWidget {
  const _FacetsError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: AppDimens.unit),
              Text('Could not load the filters',
                  style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            message,
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.gutter),
          TextButton.icon(
            onPressed: () => ref.invalidate(exportFacetsProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// The full facet builder: every axis the vault can be sliced along.
class _FacetBuilder extends StatelessWidget {
  const _FacetBuilder({
    required this.facets,
    required this.filters,
    required this.controller,
  });

  final ExportFacets facets;
  final ExportFilters filters;
  final ExportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        BentoCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: CellLabel('Narrow it down')),
                  if (filters.activeCount > 0)
                    TextButton(
                      onPressed: controller.clearFilters,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.unit),
              Text(
                'Filters combine: a title must match every group you use.',
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppDimens.gutter),
              _SearchField(
                initial: filters.text,
                onChanged: controller.setText,
              ),
              const Divider(height: AppDimens.gutter * 2),
              ExportFacetSection(
                label: 'From reading app',
                options: facets.apps,
                selected: filters.sourceApps,
                onToggle: controller.toggleApp,
                emptyHint: 'No imports are tagged with an app yet.',
              ),
              const Divider(height: AppDimens.gutter * 2),
              ExportFacetSection(
                label: 'From source',
                options: facets.sources,
                selected: filters.sourceIds,
                onToggle: controller.toggleSource,
                emptyHint: 'The vault is empty.',
              ),
              const Divider(height: AppDimens.gutter * 2),
              ExportFacetSection(
                label: 'Categories',
                options: facets.categories,
                selected: filters.categoryIds,
                onToggle: controller.toggleCategory,
                emptyHint: 'No categories in the vault.',
              ),
              const Divider(height: AppDimens.gutter * 2),
              ExportFacetSection(
                label: 'Publication status',
                options: facets.statuses
                    .map((s) => ExportFacetOption(
                          id: s.id,
                          label: _statusLabel(s.label),
                          count: s.count,
                        ))
                    .toList(),
                selected: filters.status,
                onToggle: controller.toggleStatus,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gutter),
        _ReadingStateCell(filters: filters, controller: controller),
      ],
    );
  }

  static String _statusLabel(String raw) => switch (raw) {
        'publishing_finished' => 'Publishing finished',
        'on_hiatus' => 'On hiatus',
        _ => raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1),
      };
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      // The wizard debounces before previewing, so typing stays responsive
      // without a second debounce here.
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: 'Title contains',
        hintText: 'e.g. Solo Leveling',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// Reading-state facets, kept apart from the "where did it come from" chips
/// because they answer a different question and pair with the tri-state
/// favorite control.
class _ReadingStateCell extends StatelessWidget {
  const _ReadingStateCell({required this.filters, required this.controller});

  final ExportFilters filters;
  final ExportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Reading state'),
          const SizedBox(height: AppDimens.unit * 1.5),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            children: [
              SelectableChip(
                label: 'Favorites',
                icon: Icons.favorite,
                selected: filters.favorite == true,
                onTap: () =>
                    controller.setFavorite(filters.favorite == true ? null : true),
              ),
              SelectableChip(
                label: 'Not favorites',
                icon: Icons.favorite_border,
                selected: filters.favorite == false,
                onTap: () => controller
                    .setFavorite(filters.favorite == false ? null : false),
              ),
              SelectableChip(
                label: 'Has unread',
                icon: Icons.mark_email_unread_outlined,
                selected: filters.unreadOnly,
                onTap: () => controller.setUnreadOnly(!filters.unreadOnly),
              ),
              SelectableChip(
                label: 'Started reading',
                icon: Icons.auto_stories_outlined,
                selected: filters.startedOnly,
                onTap: () => controller.setStartedOnly(!filters.startedOnly),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          Text(
            'Favorites and Not favorites are opposites — picking one clears the other.',
            style: theme.textTheme.labelSmall!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
