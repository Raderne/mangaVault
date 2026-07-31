import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/import/import_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/status_chip.dart';
import 'import_controller.dart';

/// Backup & Sources: import hub per the `backup_sources` mockup. Upload
/// `.tachibk`/`.json` backups, review the staged merge, watch the import stream
/// in real time, and browse import history.
class BackupsScreen extends ConsumerWidget {
  const BackupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final busy = state is ImportStaging || state is ImportCommitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Backups & Sources')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          _ImportCtaCell(busy: busy),
          const SizedBox(height: AppDimens.gutter),
          ..._stateCells(context, ref, state),
          const _HistoryCell(),
        ],
      ),
    );
  }

  List<Widget> _stateCells(BuildContext context, WidgetRef ref, ImportState state) {
    return switch (state) {
      ImportStaging(:final fileName) => [
          _BusyCell(label: 'Reading $fileName…'),
          const SizedBox(height: AppDimens.gutter),
        ],
      ImportReview(:final queue) => [
          _ReviewCell(queue: queue),
          const SizedBox(height: AppDimens.gutter),
        ],
      ImportCommitting() => [
          _CommittingCell(state: state),
          const SizedBox(height: AppDimens.gutter),
        ],
      ImportDone(:final records) => [
          _DoneCell(records: records),
          const SizedBox(height: AppDimens.gutter),
        ],
      ImportFailed(:final message) => [
          _FailedCell(message: message),
          const SizedBox(height: AppDimens.gutter),
        ],
      ImportIdle() => const [],
    };
  }
}

class _ImportCtaCell extends ConsumerWidget {
  const _ImportCtaCell({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return BentoCell(
      tone: BentoTone.high,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CellLabel('Initialization')),
              const AccentIconWell(icon: Icons.upload_file),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text('Import Backup', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Restore your library, reading progress, and collections from a '
            '.tachibk or legacy .json backup exported by Mihon or its forks.',
            style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          PillButton(
            label: 'Select Local File',
            icon: Icons.upload_file,
            onPressed: busy ? null : () => ref.read(importControllerProvider.notifier).pickAndStage(),
          ),
        ],
      ),
    );
  }
}

class _BusyCell extends StatelessWidget {
  const _BusyCell({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppDimens.gutter),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ReviewCell extends ConsumerWidget {
  const _ReviewCell({required this.queue});
  final List<StagedImport> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(importControllerProvider.notifier);
    final anyCommittable = queue.any((s) => !s.isDuplicate);

    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Review import'),
          const SizedBox(height: AppDimens.unit * 2),
          for (final staged in queue)
            // Keyed by file: each section owns its own chip filter, and a
            // reordered queue must not carry one file's filter to another.
            _StagedFileSection(key: ValueKey(staged.id), staged: staged),
          const SizedBox(height: AppDimens.gutter),
          Row(
            children: [
              PillButton(
                label: anyCommittable ? 'Commit import' : 'Nothing to import',
                icon: Icons.check,
                onPressed: anyCommittable ? controller.commitAll : null,
              ),
              const SizedBox(width: AppDimens.unit),
              TextButton(
                onPressed: controller.discardAll,
                child: Text('Discard', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StagedFileSection extends StatefulWidget {
  const _StagedFileSection({super.key, required this.staged});
  final StagedImport staged;

  @override
  State<_StagedFileSection> createState() => _StagedFileSectionState();
}

class _StagedFileSectionState extends State<_StagedFileSection> {
  /// Active count-chip filter: the `MergeResult.action` to show, or null for
  /// everything. Tapping the active chip again clears it.
  String? _filter;

  void _toggle(String action) => setState(
        () => _filter = _filter == action ? null : action,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = widget.staged;
    final s = staged.summary;
    final shown = _filter == null
        ? staged.preview
        : staged.preview.where((p) => p.action == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(staged.fileMeta.fileName, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppDimens.unit),
        Wrap(
          spacing: AppDimens.unit,
          runSpacing: AppDimens.unit,
          children: [
            // The three outcome counts double as filters over the list below —
            // on a 2,000-title backup, "which 3 were skipped?" is otherwise a
            // long scroll. A zero count stays inert: nothing to show.
            StatusChip(
              '${s.titlesNew} new',
              selected: _filter == 'created',
              onTap: s.titlesNew == 0 ? null : () => _toggle('created'),
            ),
            StatusChip(
              '${s.titlesMerged} merged',
              selected: _filter == 'merged',
              onTap: s.titlesMerged == 0 ? null : () => _toggle('merged'),
            ),
            // Deleted titles this backup will NOT bring back, stated before
            // the user commits rather than discovered afterwards.
            if (s.titlesSkipped > 0)
              StatusChip(
                '${s.titlesSkipped} skipped',
                selected: _filter == 'skipped',
                onTap: () => _toggle('skipped'),
              ),
            StatusChip('${s.chaptersTotal} chapters'),
            if (staged.isDuplicate) StatusChip('Already imported'),
          ],
        ),
        if (s.warnings.isNotEmpty) ...[
          const SizedBox(height: AppDimens.unit),
          Text(
            '${s.warnings.length} warning(s): ${s.warnings.first}',
            style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (_filter != null) ...[
          const SizedBox(height: AppDimens.unit),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing ${shown.length} of ${staged.preview.length}',
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _filter = null),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Show all'),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppDimens.unit),
        // Builder-based, bounded height list — smooth at 1000+ titles.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (context, i) => _MergeRow(result: shown[i]),
          ),
        ),
        const Divider(height: AppDimens.gutter * 2),
      ],
    );
  }
}

class _MergeRow extends StatelessWidget {
  const _MergeRow({required this.result});
  final MergeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = StatusChip(_actionLabel(result.action),
        emphasized: result.isMerged);
    final title = Expanded(
      child: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
    );

    if (result.conflicts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [title, const SizedBox(width: AppDimens.unit), badge]),
      );
    }
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppDimens.unit, bottom: AppDimens.unit),
        title: Row(children: [title, const SizedBox(width: AppDimens.unit), badge]),
        subtitle: Text('${result.conflicts.length} field conflict(s)',
            style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.error)),
        children: [
          for (final c in result.conflicts)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${c.field}: kept "${c.kept}" over "${c.incoming}"',
                  style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

class _CommittingCell extends StatelessWidget {
  const _CommittingCell({required this.state});
  final ImportCommitting state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CellLabel(state.fileCount > 1
              ? 'Importing (${state.fileIndex} of ${state.fileCount})'
              : 'Importing'),
          const SizedBox(height: AppDimens.unit),
          Text(state.fileName, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppDimens.unit * 2),
          GlowProgressBar(value: state.fraction),
          const SizedBox(height: AppDimens.unit),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(state.phaseLabel,
                    style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Text('${state.processed} / ${state.total}',
                  style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: AppDimens.gutter),
          // Live stream of the most recent records as they're written.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: state.recent.length,
              itemBuilder: (context, i) {
                final m = state.recent[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(m.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                      ),
                      const SizedBox(width: AppDimens.unit),
                      StatusChip(_actionLabel(m.action), emphasized: m.isMerged),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneCell extends ConsumerWidget {
  const _DoneCell({required this.records});
  final List<ImportRecord> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final titlesNew = records.fold<int>(0, (n, r) => n + r.stats.titlesNew);
    final titlesSkipped =
        records.fold<int>(0, (n, r) => n + r.stats.titlesSkipped);
    final titlesMerged = records.fold<int>(0, (n, r) => n + r.stats.titlesMerged);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NestedWell(
            child: Row(
              children: [
                const AccentIconWell(icon: Icons.check_circle_outline),
                const SizedBox(width: AppDimens.unit * 1.5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import complete', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '$titlesNew new · $titlesMerged merged'
                        '${titlesSkipped > 0 ? ' · $titlesSkipped skipped' : ''} '
                        'across ${records.length} file(s).',
                        style: theme.textTheme.bodyMedium!
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Skipped titles are the one outcome that needs a decision, so the
          // list is one tap away instead of buried under the Library tab.
          if (titlesSkipped > 0) ...[
            const SizedBox(height: AppDimens.unit),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/library/deleted'),
                icon: const Icon(Icons.restore, size: 18),
                label: Text(
                  titlesSkipped == 1
                      ? 'Review 1 skipped title'
                      : 'Review $titlesSkipped skipped titles',
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDimens.gutter),
          PillButton(
            label: 'Import another',
            icon: Icons.add,
            onPressed: () => ref.read(importControllerProvider.notifier).reset(),
          ),
        ],
      ),
    );
  }
}

class _FailedCell extends ConsumerWidget {
  const _FailedCell({required this.message});
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
              Text('Import failed', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(message, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppDimens.gutter),
          PillButton(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: () => ref.read(importControllerProvider.notifier).reset(),
          ),
        ],
      ),
    );
  }
}

class _HistoryCell extends ConsumerWidget {
  const _HistoryCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(importHistoryProvider);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: CellLabel('Import history')),
              AccentIconWell(icon: Icons.history, size: 32, iconSize: 16),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 2),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppDimens.unit),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text('Could not load history: $e',
                style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.error)),
            data: (records) => records.isEmpty
                ? Text('No imports yet.',
                    style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant))
                : Column(
                    children: [
                      for (var i = 0; i < records.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppDimens.unit),
                        NestedWell(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.unit * 1.5,
                            vertical: AppDimens.unit * 1.5,
                          ),
                          child: _HistoryRow(record: records[i]),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final ImportRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = record.stats;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                '${record.sourceApp.isEmpty ? 'unknown' : record.sourceApp} · '
                '${s.titlesNew} new · ${s.titlesMerged} merged'
                '${s.titlesSkipped > 0 ? ' · ${s.titlesSkipped} skipped' : ''}'
                ' · ${_relativeDate(record.importedAt)}',
                style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _relativeDate(int epochMillis) {
    if (epochMillis <= 0) return 'unknown';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMillis));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Badge text for a per-title import outcome.
String _actionLabel(String action) => switch (action) {
      'merged' => 'MERGED',
      'skipped' => 'SKIPPED',
      _ => 'NEW',
    };
