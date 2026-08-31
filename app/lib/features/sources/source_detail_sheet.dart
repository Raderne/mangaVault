import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/sources/source_models.dart';
import '../../data/sources/source_repository.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/selectable_chip.dart';
import 'source_health_controller.dart';
import 'sources_screen.dart' show HealthChip;

/// Details for one source, and the entry point to migrating off it.
Future<void> showSourceDetailSheet(
  BuildContext context,
  VaultSource source,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppDimens.cellRadius),
      ),
    ),
    builder: (_) => _SourceDetailSheet(source: source),
  );
}

class _SourceDetailSheet extends ConsumerWidget {
  const _SourceDetailSheet({required this.source});

  final VaultSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter,
          0,
          AppDimens.gutter,
          AppDimens.gutter,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                source.name.isEmpty ? source.sourceId : source.name,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppDimens.unit),
              Row(
                children: [
                  HealthChip(health: source.health, compact: false),
                  const SizedBox(width: AppDimens.unit * 2),
                  Text(
                    '${groupedNumber(source.titleCount)} titles',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (source.healthNote != null) ...[
                const SizedBox(height: AppDimens.unit),
                Text(
                  source.healthNote!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.unit * 2),

              _FactsCell(source: source),

              if (source.registryState != SourceRegistryState.listed) ...[
                const SizedBox(height: AppDimens.unit * 1.5),
                _NotPublishedCell(source: source),
              ],

              const SizedBox(height: AppDimens.unit * 2),
              _MigrateAction(source: source),
              const SizedBox(height: AppDimens.unit),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactsCell extends StatelessWidget {
  const _FactsCell({required this.source});

  final VaultSource source;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      tone: BentoTone.low,
      padding: const EdgeInsets.all(AppDimens.unit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('DETAILS'),
          const SizedBox(height: AppDimens.unit),
          _Fact(label: 'Source id', value: source.sourceId),
          if (source.lang.isNotEmpty)
            _Fact(label: 'Language', value: source.lang.toUpperCase()),
          if (source.homeUrl != null)
            _Fact(label: 'Website', value: source.homeUrl!),
          if (source.repoName != null)
            _Fact(label: 'Repository', value: source.repoName!),
          if (source.packageName != null)
            _Fact(label: 'Extension', value: source.packageName!),
          if (source.coverFailedCount > 0)
            _Fact(
              label: 'Covers failed',
              value: groupedNumber(source.coverFailedCount),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when no repository publishes this source any more.
///
/// The suggestions are the point. An extension that is renamed or re-published
/// gets brand-new source ids — the id is derived from the name — so a library
/// full of "Comick" titles is stranded on an id nothing serves, with the
/// successor sitting right there under a slightly different name.
class _NotPublishedCell extends StatelessWidget {
  const _NotPublishedCell({required this.source});

  final VaultSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delisted = source.registryState == SourceRegistryState.delisted;

    return BentoCell(
      tone: BentoTone.low,
      accent: VaultAccent.amber,
      padding: const EdgeInsets.all(AppDimens.unit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('NOT PUBLISHED'),
          const SizedBox(height: AppDimens.unit),
          Text(
            delisted
                ? 'This source was withdrawn from its extension repository, so '
                    'it can no longer be installed in a reading app.'
                : 'No extension repository lists this source, so there is no '
                    'extension to install for it any more.',
            style: theme.textTheme.bodySmall,
          ),
          if (source.suggestedReplacements.isNotEmpty) ...[
            const SizedBox(height: AppDimens.unit * 1.5),
            Text(
              'It may have been re-published under a new name:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.unit),
            Wrap(
              spacing: AppDimens.unit,
              runSpacing: AppDimens.unit,
              children: [
                for (final s in source.suggestedReplacements)
                  SelectableChip(
                    label: s.lang.isEmpty
                        ? s.name
                        : '${s.name} · ${s.lang.toUpperCase()}',
                    selected: false,
                    onTap: () {},
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The button that starts a migration, plus its target picker.
class _MigrateAction extends ConsumerStatefulWidget {
  const _MigrateAction({required this.source});

  final VaultSource source;

  @override
  ConsumerState<_MigrateAction> createState() => _MigrateActionState();
}

class _MigrateActionState extends ConsumerState<_MigrateAction> {
  bool _busy = false;

  Future<void> _start() async {
    final sources = ref.read(vaultSourcesProvider).value ?? const [];
    final targets = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.cellRadius),
        ),
      ),
      builder: (_) => _TargetPicker(
        from: widget.source,
        // Anything that still works is a candidate, plus the successors the
        // registry suggested for this source specifically.
        options: [
          ...widget.source.suggestedReplacements.map(
            (s) => VaultSource(
              sourceId: s.sourceId,
              name: s.name,
              lang: s.lang,
              titleCount: s.titleCount,
              iconUrl: s.iconUrl,
              homeUrl: s.homeUrl,
              registryState: SourceRegistryState.listed,
              health: SourceHealth.ok,
            ),
          ),
          ...sources.where(
            (s) =>
                s.sourceId != widget.source.sourceId &&
                !s.health.needsAttention &&
                !widget.source.suggestedReplacements
                    .any((r) => r.sourceId == s.sourceId),
          ),
        ],
      ),
    );
    if (targets == null || targets.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final job = await ref.read(sourceRepositoryProvider).planMigration(
            fromSourceId: widget.source.sourceId,
            toSourceIds: targets,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      router.push('/library/sources/migrate/${job.jobId}');
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(_shortError(err))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.source.titleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: PillButton(
            label: _busy
                ? 'Preparing…'
                : 'Migrate ${groupedNumber(count)} '
                    '${count == 1 ? 'title' : 'titles'}',
            icon: Icons.swap_horiz,
            accent: VaultAccent.violet,
            onPressed: _busy || count == 0 ? null : _start,
          ),
        ),
        const SizedBox(height: AppDimens.unit),
        Text(
          'Nothing changes until you review the matches.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Choose where the titles should go, in preference order.
class _TargetPicker extends StatefulWidget {
  const _TargetPicker({required this.from, required this.options});

  final VaultSource from;
  final List<VaultSource> options;

  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  /// Ordered: the list is the search priority, so first pick wins ties.
  final List<String> _selected = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter,
          0,
          AppDimens.gutter,
          AppDimens.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Migrate to', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppDimens.unit),
            Text(
              'Pick one or more sources to look for these titles on. The order '
              'you pick them is the order they are tried.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.unit * 2),
            if (widget.options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimens.gutter * 2,
                ),
                child: Text(
                  'No healthy source to migrate to yet. Run a health check, or '
                  'import a backup from a source that still works.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppDimens.unit,
                    runSpacing: AppDimens.unit,
                    children: [
                      for (final option in widget.options)
                        SelectableChip(
                          label: option.lang.isEmpty
                              ? option.name
                              : '${option.name} · ${option.lang.toUpperCase()}',
                          selected: _selected.contains(option.sourceId),
                          // The number is the search order, not a count —
                          // first pick is tried first.
                          trailing: _selected.contains(option.sourceId)
                              ? '${_selected.indexOf(option.sourceId) + 1}'
                              : null,
                          onTap: () => setState(() {
                            if (!_selected.remove(option.sourceId)) {
                              _selected.add(option.sourceId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.unit * 2),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: 'Find matches',
                icon: Icons.search,
                accent: VaultAccent.violet,
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortError(Object err) =>
    err.toString().replaceFirst('Exception: ', '').split('\n').first;
