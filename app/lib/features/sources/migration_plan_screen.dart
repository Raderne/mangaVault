import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/sources/migration_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pressable.dart';
import '../../widgets/status_chip.dart';
import 'migration_plan_controller.dart';

/// Review a migration before anything is written.
///
/// The screen is the safety mechanism, not decoration. Planning has already
/// searched every target source and scored what it found, but a score is a
/// guess: "Solo Leveling" and "Solo Leveling: Ragnarok" are different books
/// that score alike. So confident matches arrive pre-ticked, everything else
/// arrives untouched, and the only thing that writes to the vault is the button
/// at the bottom — which says exactly how many titles it will move.
class MigrationPlanScreen extends ConsumerStatefulWidget {
  const MigrationPlanScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<MigrationPlanScreen> createState() =>
      _MigrationPlanScreenState();
}

class _MigrationPlanScreenState extends ConsumerState<MigrationPlanScreen> {
  @override
  void initState() {
    super.initState();
    // Point the controller at this plan once the first frame is up, so the
    // load never runs during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(migrationPlanControllerProvider.notifier).open(widget.jobId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final jobId = widget.jobId;
    final state = ref.watch(migrationPlanControllerProvider);
    final controller =
        ref.read(migrationPlanControllerProvider.notifier);
    final plan = state.plan;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          plan == null ? 'Migration' : 'Move off ${plan.job.fromSourceName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (plan != null && !state.isPlanning)
            PopupMenuButton<String>(
              onSelected: (value) => switch (value) {
                'all' => controller.selectAllMatched(),
                'none' => controller.selectNone(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Select all matches')),
                PopupMenuItem(value: 'none', child: Text('Select none')),
              ],
            ),
        ],
      ),
      body: state.loading && plan == null
          ? const Center(child: CircularProgressIndicator())
          : plan == null
              ? _ErrorState(
                  error: state.error,
                  onRetry: controller.refresh,
                )
              : _PlanBody(jobId: jobId, state: state),
      bottomNavigationBar: plan == null || state.isPlanning
          ? null
          : _ApplyBar(jobId: jobId, state: state),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.jobId, required this.state});

  final String jobId;
  final MigrationPlanState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(migrationPlanControllerProvider.notifier);
    final plan = state.plan!;
    final items = plan.items;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            AppDimens.gutter,
            AppDimens.gutter,
            AppDimens.unit,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                _HeaderCell(state: state),
                if (plan.unsearchable.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.unit * 1.5),
                  _UnsearchableCell(targets: plan.unsearchable),
                ],
                if (state.result != null) ...[
                  const SizedBox(height: AppDimens.unit * 1.5),
                  _ResultCell(result: state.result!),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            0,
            AppDimens.gutter,
            AppDimens.gutter * 2,
          ),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppDimens.unit + 4),
            itemBuilder: (context, index) {
              final item = items[index];
              return _ItemRow(
                key: ValueKey(item.mangaId),
                item: item,
                selected: state.selected.contains(item.mangaId),
                autoAcceptScore: plan.autoAcceptScore,
                onToggle: () => controller.toggle(item.mangaId),
                onOpen: () => _openItemSheet(context, ref, jobId, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Plan progress, or its summary once the search is done.
class _HeaderCell extends ConsumerWidget {
  const _HeaderCell({required this.state});

  final MigrationPlanState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = state.plan!;
    final job = plan.job;
    final controller =
        ref.read(migrationPlanControllerProvider.notifier);

    if (job.isPlanning) {
      return BentoCell(
        tone: BentoTone.high,
        accent: VaultAccent.cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CellLabel('SEARCHING'),
            const SizedBox(height: AppDimens.unit),
            Text(
              'Looking for ${groupedNumber(job.total)} titles on the sources '
              'you picked',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppDimens.unit),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${job.planned} of ${job.total} · '
                    '${job.matched} matched so far',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: controller.cancelPlanning,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.unit),
            GlowProgressBar(value: job.fraction, accent: VaultAccent.cyan),
            const SizedBox(height: AppDimens.unit),
            Text(
              'Nothing has been changed yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final matched = plan.items.where((i) => i.hasMatch).length;
    final unmatched = plan.items
        .where((i) => i.state == MigrationItemState.unmatched)
        .length;

    return BentoCell(
      tone: BentoTone.high,
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('REVIEW'),
          const SizedBox(height: AppDimens.unit),
          Text(
            '$matched of ${groupedNumber(job.total)} titles matched',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            unmatched == 0
                ? 'Ticked titles are the ones that will move. Tap any row to '
                    'change its match.'
                : "$unmatched couldn't be found automatically — tap one to "
                    'search again or paste its address.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Target sources with no built-in search, and what that means.
class _UnsearchableCell extends StatelessWidget {
  const _UnsearchableCell({required this.targets});

  final List<UnsearchableTarget> targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      tone: BentoTone.low,
      accent: VaultAccent.amber,
      padding: const EdgeInsets.all(AppDimens.unit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('LIMITED SEARCH'),
          const SizedBox(height: AppDimens.unit),
          for (final target in targets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${target.name} — ${target.reason}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Matches for these come from titles already in your library, or '
            'from an address you paste.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCell extends StatelessWidget {
  const _ResultCell({required this.result});

  final MigrationApplyResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clean = result.conflicts == 0 && result.failed == 0;
    return BentoCell(
      tone: BentoTone.low,
      accent: clean ? VaultAccent.emerald : VaultAccent.amber,
      padding: const EdgeInsets.all(AppDimens.unit * 2),
      child: Row(
        children: [
          AccentIconWell(
            icon: clean ? Icons.check : Icons.warning_amber_rounded,
            accent: clean ? VaultAccent.emerald : VaultAccent.amber,
          ),
          const SizedBox(width: AppDimens.unit * 1.5),
          Expanded(
            child: Text(
              clean
                  ? '${groupedNumber(result.applied)} titles moved. Tap a '
                      'moved title to undo it.'
                  : '${groupedNumber(result.applied)} moved · '
                      '${result.conflicts} already in your library · '
                      '${result.failed} failed',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// One title: where it is now, where it would go, and how sure we are.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.selected,
    required this.autoAcceptScore,
    required this.onToggle,
    required this.onOpen,
  });

  final MigrationItem item;
  final bool selected;
  final double autoAcceptScore;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(item);
    final selectable = item.hasMatch;

    return Pressable(
      onTap: onOpen,
      child: BentoCell(
        accent: accent,
        padding: const EdgeInsets.all(AppDimens.unit * 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 48dp tap target of its own, so ticking a row never means opening
            // the sheet by accident.
            SizedBox(
              width: 48,
              height: 48,
              child: selectable
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => onToggle(),
                    )
                  : Center(
                      child: Icon(
                        _iconFor(item),
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: AppDimens.unit),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  _TargetLine(item: item),
                  if (item.reasons.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final reason in item.reasons)
                          StatusChip(reason),
                      ],
                    ),
                  ],
                  if (item.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            _ScoreBadge(item: item, autoAcceptScore: autoAcceptScore),
          ],
        ),
      ),
    );
  }

  static VaultAccent? _accentFor(MigrationItem item) => switch (item.state) {
        MigrationItemState.applied => VaultAccent.emerald,
        MigrationItemState.conflict => VaultAccent.amber,
        MigrationItemState.failed => VaultAccent.rose,
        _ => null,
      };

  static IconData _iconFor(MigrationItem item) => switch (item.state) {
        MigrationItemState.applied => Icons.check_circle_outline,
        MigrationItemState.undone => Icons.undo,
        MigrationItemState.skipped => Icons.remove_circle_outline,
        MigrationItemState.conflict => Icons.merge_type,
        MigrationItemState.failed => Icons.error_outline,
        MigrationItemState.unmatched => Icons.search_off,
        _ => Icons.hourglass_empty,
      };
}

class _TargetLine extends StatelessWidget {
  const _TargetLine({required this.item});

  final MigrationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return switch (item.state) {
      MigrationItemState.pending => Text('Searching…', style: muted),
      MigrationItemState.unmatched =>
        Text('No match found — tap to fix', style: muted),
      MigrationItemState.skipped => Text('Skipped', style: muted),
      MigrationItemState.undone => Text('Moved back', style: muted),
      MigrationItemState.conflict => Text(
          'Already in your library as "${item.conflictTitle ?? 'another title'}"',
          style: muted,
        ),
      _ => Row(
          children: [
            Icon(Icons.arrow_forward, size: 12, color: muted?.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${item.toSourceName ?? ''} · ${item.toTitle ?? item.toMangaUrl ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
          ],
        ),
    };
  }
}

/// Confidence, as a percentage with a word — never colour alone.
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.item, required this.autoAcceptScore});

  final MigrationItem item;
  final double autoAcceptScore;

  @override
  Widget build(BuildContext context) {
    if (!item.hasMatch) return const SizedBox.shrink();
    final theme = Theme.of(context);

    if (item.method == 'manual') {
      return StatusChip('BY HAND', accent: VaultAccent.cyan);
    }
    final score = item.score ?? 0;
    final confident = score >= autoAcceptScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${(score * 100).round()}%',
          style: theme.textTheme.titleSmall?.copyWith(
            color: confident
                ? VaultAccent.emerald.color
                : VaultAccent.amber.color,
          ),
        ),
        Text(
          confident ? 'likely' : 'check',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The apply bar. Says exactly what it will do, and confirms first.
class _ApplyBar extends ConsumerWidget {
  const _ApplyBar({required this.jobId, required this.state});

  final String jobId;
  final MigrationPlanState state;

  Future<void> _confirmAndApply(BuildContext context, WidgetRef ref) async {
    final count = state.selected.length;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move $count ${count == 1 ? 'title' : 'titles'}?'),
        content: const Text(
          'Each title keeps its chapters, reading progress, categories and '
          'archive history — only the source it points at changes. You can '
          'undo any of them afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(migrationPlanControllerProvider.notifier).apply();
    final result = ref.read(migrationPlanControllerProvider).result;
    if (result == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${result.applied} moved'
            '${result.conflicts > 0 ? ', ${result.conflicts} already in your library' : ''}'
            '${result.failed > 0 ? ', ${result.failed} failed' : ''}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = state.selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter,
          AppDimens.unit,
          AppDimens.gutter,
          AppDimens.unit,
        ),
        child: SizedBox(
          width: double.infinity,
          child: PillButton(
            label: state.applying
                ? 'Moving…'
                : count == 0
                    ? 'Nothing selected'
                    : 'Move $count ${count == 1 ? 'title' : 'titles'}',
            icon: Icons.swap_horiz,
            accent: VaultAccent.violet,
            onPressed: count == 0 || state.applying
                ? null
                : () => _confirmAndApply(context, ref),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gutter * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppDimens.unit * 2),
            Text("Couldn't load this migration",
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.unit),
            Text(
              error == null
                  ? 'The server did not answer.'
                  : error
                      .toString()
                      .replaceFirst('Exception: ', '')
                      .split('\n')
                      .first,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.unit * 2),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Per-title actions: switch match, paste an address, skip, undo, merge.
Future<void> _openItemSheet(
  BuildContext context,
  WidgetRef ref,
  String jobId,
  MigrationItem item,
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
    builder: (_) => _ItemSheet(jobId: jobId, item: item),
  );
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.jobId, required this.item});

  final String jobId;
  final MigrationItem item;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  final _urlController = TextEditingController();
  bool _busy = false;
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  MigrationPlanController get _controller =>
      ref.read(migrationPlanControllerProvider.notifier);

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            err.toString().replaceFirst('Exception: ', '').split('\n').first,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final plan = ref.watch(migrationPlanControllerProvider).plan;
    final targetSourceId = item.toSourceId ??
        plan?.items
            .firstWhere(
              (i) => i.toSourceId != null,
              orElse: () => item,
            )
            .toSourceId;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.gutter,
          right: AppDimens.gutter,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.gutter,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppDimens.unit * 2),

              if (item.state == MigrationItemState.applied && item.undoable)
                _ActionTile(
                  icon: Icons.undo,
                  label: 'Move back to the original source',
                  onTap: _busy ? null : () => _run(() => _controller.undo(item.id)),
                ),

              if (item.state == MigrationItemState.conflict) ...[
                Text(
                  'Your library already has this title on the target source. '
                  'Merging keeps the copy that is already there and carries '
                  'this one\'s reading progress over to it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimens.unit),
                _ActionTile(
                  icon: Icons.merge_type,
                  label: 'Merge into the copy I already have',
                  onTap: _busy
                      ? null
                      : () => _run(() => _controller.mergeConflict(item.id)),
                ),
              ],

              if (item.candidates.isNotEmpty) ...[
                const CellLabel('OTHER MATCHES'),
                const SizedBox(height: AppDimens.unit),
                for (var i = 0; i < item.candidates.length; i++)
                  _CandidateTile(
                    candidate: item.candidates[i],
                    chosen: item.candidates[i].url == item.toMangaUrl,
                    onTap: _busy
                        ? null
                        : () => _run(
                              () => _controller.chooseCandidate(item.mangaId, i),
                            ),
                  ),
                const SizedBox(height: AppDimens.unit * 2),
              ],

              const CellLabel('ENTER AN ADDRESS'),
              const SizedBox(height: AppDimens.unit),
              Text(
                'Paste the title\'s path on the target source, exactly as the '
                'reading app stores it (for example /manga/some-id).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDimens.unit),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Address on the new source',
                  hintText: '/manga/…',
                  // Errors sit with the field they belong to, never at the top.
                  errorText: _urlError,
                ),
                onSubmitted: (_) => _submitUrl(targetSourceId),
              ),
              const SizedBox(height: AppDimens.unit),
              Align(
                alignment: Alignment.centerLeft,
                child: PillButton(
                  label: 'Use this address',
                  icon: Icons.link,
                  accent: VaultAccent.cyan,
                  onPressed: _busy ? null : () => _submitUrl(targetSourceId),
                ),
              ),

              const SizedBox(height: AppDimens.unit * 2),
              if (item.state != MigrationItemState.applied)
                _ActionTile(
                  icon: Icons.remove_circle_outline,
                  label: 'Leave this title where it is',
                  onTap: _busy
                      ? null
                      : () => _run(() => _controller.skip(item.mangaId)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitUrl(String? targetSourceId) {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Enter an address first');
      return;
    }
    if (targetSourceId == null) {
      setState(() =>
          _urlError = 'No target source to attach this address to');
      return;
    }
    setState(() => _urlError = null);
    unawaitedRun(
      () => _controller.setManual(widget.item.mangaId, targetSourceId, url),
    );
  }

  void unawaitedRun(Future<void> Function() action) => _run(action);
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.chosen,
    required this.onTap,
  });

  final MigrationCandidate candidate;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.unit),
      child: NestedWell(
        accent: chosen ? VaultAccent.violet : null,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${candidate.sourceName} · '
                      '${candidate.method == 'vault' ? 'already in your library' : 'searched'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.unit),
              Text(
                '${(candidate.score * 100).round()}%',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.unit),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}
