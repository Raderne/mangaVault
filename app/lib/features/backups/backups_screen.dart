import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Initialization'),
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
          for (final staged in queue) _StagedFileSection(staged: staged),
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

class _StagedFileSection extends StatelessWidget {
  const _StagedFileSection({required this.staged});
  final StagedImport staged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = staged.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(staged.fileMeta.fileName, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppDimens.unit),
        Wrap(
          spacing: AppDimens.unit,
          runSpacing: AppDimens.unit,
          children: [
            StatusChip('${s.titlesNew} new'),
            StatusChip('${s.titlesMerged} merged', emphasized: true),
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
        const SizedBox(height: AppDimens.unit),
        // Builder-based, bounded height list — smooth at 1000+ titles.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: staged.preview.length,
            itemBuilder: (context, i) => _MergeRow(result: staged.preview[i]),
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
    final badge = StatusChip(result.isMerged ? 'MERGED' : 'NEW', emphasized: result.isMerged);
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
                      StatusChip(m.isMerged ? 'MERGED' : 'NEW', emphasized: m.isMerged),
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
    final titlesMerged = records.fold<int>(0, (n, r) => n + r.stats.titlesMerged);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.secondary),
              const SizedBox(width: AppDimens.unit),
              Text('Import complete', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text('$titlesNew new · $titlesMerged merged across ${records.length} file(s).',
              style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
          const CellLabel('Import history'),
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
                : Column(children: [for (final r in records) _HistoryRow(record: r)]),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
                  '${s.titlesNew} new · ${s.titlesMerged} merged · ${_relativeDate(record.importedAt)}',
                  style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
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
