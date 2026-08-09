import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/backup_apps/backup_app_models.dart';
import '../../data/backup_apps/backup_apps_repository.dart';
import '../../data/import/import_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/status_chip.dart';
import 'import_controller.dart';
import 'source_app_sheet.dart';

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
          const _ExportCtaCell(),
          const SizedBox(height: AppDimens.gutter),
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
      ImportNeedsApp() => [
          _NeedsAppCell(state: state),
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
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CellLabel('Initialization')),
              const AccentIconWell(
                icon: Icons.upload_file,
                accent: VaultAccent.violet,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Import Backup',
            style: theme.textTheme.headlineMedium!
                .copyWith(color: VaultAccent.violet.color),
          ),
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
            accent: VaultAccent.violet,
            onPressed: busy ? null : () => ref.read(importControllerProvider.notifier).pickAndStage(),
          ),
        ],
      ),
    );
  }
}

/// The way out of the vault, sat directly opposite the way in.
///
/// The pairing is the point: an archive you can only put things into is a trap,
/// so "create a backup" lives at the same level as "import one" rather than
/// behind a settings menu.
class _ExportCtaCell extends StatelessWidget {
  const _ExportCtaCell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      // Emerald against the import cell's violet: the two CTAs sit opposite
      // each other by design, and different hues is what makes that read.
      accent: VaultAccent.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: CellLabel('Export')),
              AccentIconWell(
                icon: Icons.archive_outlined,
                accent: VaultAccent.emerald,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Create Backup',
            style: theme.textTheme.headlineMedium!
                .copyWith(color: VaultAccent.emerald.color),
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Write your library back out as a .tachibk file — everything, your '
            'favorites, or any slice by app, source or category. Restores into '
            'Mihon and its forks.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          PillButton(
            label: 'Create Backup',
            icon: Icons.download,
            accent: VaultAccent.emerald,
            onPressed: () => context.go('/backups/export'),
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
      accent: VaultAccent.cyan,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: VaultAccent.cyan.color,
            ),
          ),
          const SizedBox(width: AppDimens.gutter),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Asks which reading app a backup came from, when its filename didn't say.
///
/// The sheet opens on its own the moment this cell appears — the flow is
/// blocked on the answer, so making the user tap a button first is a wasted
/// step. Dismissing it leaves the cell in place with a button to reopen, so a
/// stray back-swipe can't strand the import.
class _NeedsAppCell extends ConsumerStatefulWidget {
  const _NeedsAppCell({required this.state});
  final ImportNeedsApp state;

  @override
  ConsumerState<_NeedsAppCell> createState() => _NeedsAppCellState();
}

class _NeedsAppCellState extends ConsumerState<_NeedsAppCell> {
  /// Staged ids the sheet has already been auto-opened for, so rebuilds (and
  /// the rebuild caused by dismissing it) don't reopen it in a loop.
  final _autoOpened = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
  }

  @override
  void didUpdateWidget(_NeedsAppCell old) {
    super.didUpdateWidget(old);
    if (old.state.current.id != widget.state.current.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
    }
  }

  void _maybeOpen() {
    if (!mounted) return;
    if (_autoOpened.add(widget.state.current.id)) _open();
  }

  Future<void> _open() async {
    final staged = widget.state.current;
    final picked = await showSourceAppSheet(
      context,
      fileName: staged.fileMeta.fileName,
      current: staged.fileMeta.sourceApp.isEmpty
          ? null
          : staged.fileMeta.sourceApp,
    );
    if (picked == null || !mounted) return; // dismissed — leave the cell up
    await ref
        .read(importControllerProvider.notifier)
        .setSourceApp(staged.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = widget.state.current;
    final remaining = widget.state.queue.length - widget.state.index - 1;

    return BentoCell(
      // Amber: the flow is blocked waiting on the user, which is a caution,
      // not a failure.
      accent: VaultAccent.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Identify backup'),
          const SizedBox(height: AppDimens.unit * 2),
          Text(staged.fileMeta.fileName, style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppDimens.unit),
          Text(
            "This filename doesn't say which app it came from. Pick one so the "
            'library can be filtered by it.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (remaining > 0) ...[
            const SizedBox(height: AppDimens.unit),
            Text(
              '$remaining more file(s) after this one.',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppDimens.gutter),
          Row(
            children: [
              PillButton(
                label: 'Choose app',
                icon: Icons.smartphone_rounded,
                accent: VaultAccent.amber,
                onPressed: _open,
              ),
              const SizedBox(width: AppDimens.unit),
              TextButton(
                onPressed: () => ref
                    .read(importControllerProvider.notifier)
                    .setSourceApp(staged.id, ''),
                child: Text(
                  'Skip',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
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
      accent: VaultAccent.cyan,
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
                accent: VaultAccent.cyan,
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

class _StagedFileSection extends ConsumerStatefulWidget {
  const _StagedFileSection({super.key, required this.staged});
  final StagedImport staged;

  @override
  ConsumerState<_StagedFileSection> createState() => _StagedFileSectionState();
}

class _StagedFileSectionState extends ConsumerState<_StagedFileSection> {
  /// Active count-chip filter: the `MergeResult.action` to show, or null for
  /// everything. Tapping the active chip again clears it.
  String? _filter;

  void _toggle(String action) => setState(
        () => _filter = _filter == action ? null : action,
      );

  /// Re-open the picker for a file that is already in the review queue — the
  /// filename-derived app can be wrong, and this is the last chance to fix it
  /// before the tag is written to the import record.
  Future<void> _retag() async {
    final staged = widget.staged;
    final picked = await showSourceAppSheet(
      context,
      fileName: staged.fileMeta.fileName,
      current: staged.fileMeta.sourceApp.isEmpty
          ? null
          : staged.fileMeta.sourceApp,
    );
    if (picked == null || !mounted) return;
    await ref
        .read(importControllerProvider.notifier)
        .retagStaged(staged.id, picked);
  }

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
            // Which app this backup is credited to, and a way to change it —
            // the same tag the library's "from app" filter will read.
            _SourceAppChip(
              sourceApp: staged.fileMeta.sourceApp,
              onTap: _retag,
            ),
            // The three outcome counts double as filters over the list below —
            // on a 2,000-title backup, "which 3 were skipped?" is otherwise a
            // long scroll. A zero count stays inert: nothing to show.
            StatusChip(
              '${s.titlesNew} new',
              selected: _filter == 'created',
              // A zero count is inert, and colouring it would advertise an
              // outcome that didn't happen.
              accent: s.titlesNew == 0 ? null : VaultAccent.emerald,
              onTap: s.titlesNew == 0 ? null : () => _toggle('created'),
            ),
            StatusChip(
              '${s.titlesMerged} merged',
              selected: _filter == 'merged',
              accent: s.titlesMerged == 0 ? null : VaultAccent.cyan,
              onTap: s.titlesMerged == 0 ? null : () => _toggle('merged'),
            ),
            // Deleted titles this backup will NOT bring back, stated before
            // the user commits rather than discovered afterwards.
            if (s.titlesSkipped > 0)
              StatusChip(
                '${s.titlesSkipped} skipped',
                selected: _filter == 'skipped',
                accent: VaultAccent.amber,
                onTap: () => _toggle('skipped'),
              ),
            StatusChip('${s.chaptersTotal} chapters'),
            if (staged.isDuplicate)
              StatusChip('Already imported', accent: VaultAccent.amber),
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

/// The app a backup is credited to. Renders the registry's display name, falling
/// back to the raw id, and reads "Unknown app" when nothing identified it.
class _SourceAppChip extends ConsumerWidget {
  const _SourceAppChip({required this.sourceApp, this.onTap});

  final String sourceApp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(backupAppNamesProvider).value ?? const {};
    final label = backupAppLabel(sourceApp, displayName: names[sourceApp]);
    // Violet, so the "which app" chip reads as a different *kind* of fact from
    // the emerald/cyan/amber outcome counts sitting next to it. An unidentified
    // backup stays grey — there's nothing to affirm.
    return StatusChip(
      label,
      accent: sourceApp.isEmpty ? null : VaultAccent.violet,
      onTap: onTap,
    );
  }
}

class _MergeRow extends StatelessWidget {
  const _MergeRow({required this.result});
  final MergeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = StatusChip(
      _actionLabel(result.action),
      accent: _actionAccent(result.action),
    );
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
      tone: BentoTone.high,
      accent: VaultAccent.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CellLabel(state.fileCount > 1
              ? 'Importing (${state.fileIndex} of ${state.fileCount})'
              : 'Importing'),
          const SizedBox(height: AppDimens.unit),
          Text(state.fileName, style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppDimens.unit * 2),
          GlowProgressBar(value: state.fraction, accent: VaultAccent.cyan),
          const SizedBox(height: AppDimens.unit),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(state.phaseLabel,
                    style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Text('${state.processed} / ${state.total}',
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: VaultAccent.cyan.color)),
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
                      StatusChip(
                        _actionLabel(m.action),
                        accent: _actionAccent(m.action),
                      ),
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
      accent: VaultAccent.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NestedWell(
            accent: VaultAccent.emerald,
            child: Row(
              children: [
                const AccentIconWell(
                  icon: Icons.check_circle_outline,
                  accent: VaultAccent.emerald,
                ),
                const SizedBox(width: AppDimens.unit * 1.5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import complete',
                        style: theme.textTheme.titleMedium!
                            .copyWith(color: VaultAccent.emerald.color),
                      ),
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
                style: TextButton.styleFrom(
                  foregroundColor: VaultAccent.amber.color,
                ),
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
            accent: VaultAccent.emerald,
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
      accent: VaultAccent.rose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AccentIconWell(
                icon: Icons.error_outline,
                accent: VaultAccent.rose,
              ),
              const SizedBox(width: AppDimens.unit * 1.5),
              Text(
                'Import failed',
                style: theme.textTheme.titleMedium!
                    .copyWith(color: VaultAccent.rose.color),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(message, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppDimens.gutter),
          PillButton(
            label: 'Try again',
            icon: Icons.refresh,
            accent: VaultAccent.rose,
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
      accent: VaultAccent.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: CellLabel('Import history')),
              AccentIconWell(
                icon: Icons.history,
                size: 32,
                iconSize: 16,
                accent: VaultAccent.amber,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 2),
          history.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.unit),
              child: LinearProgressIndicator(color: VaultAccent.amber.color),
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

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.record});
  final ImportRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = record.stats;
    final names = ref.watch(backupAppNamesProvider).value ?? const {};
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
                '${backupAppLabel(record.sourceApp, displayName: names[record.sourceApp])} · '
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

/// Hue for a per-title import outcome, matching the review chips above the
/// list so a badge and the count that filters to it read as the same thing.
VaultAccent _actionAccent(String action) => switch (action) {
      'merged' => VaultAccent.cyan,
      'skipped' => VaultAccent.amber,
      _ => VaultAccent.emerald,
    };
