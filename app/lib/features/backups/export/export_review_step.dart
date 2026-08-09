import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/export/export_models.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/status_chip.dart';
import 'export_controller.dart';
import 'export_widgets.dart';

/// Step 3 — **the readout before the write**.
///
/// Everything the file will and will not contain, stated once, in full. The
/// exclusions get as much room as the counts: the failure mode of an archive
/// tool is a backup that looks complete and isn't.
class ExportReviewStep extends ConsumerWidget {
  const ExportReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.gutter,
        AppDimens.unit,
        AppDimens.gutter,
        AppDimens.gutter,
      ),
      children: [
        state.preview.when(
          loading: () => const _ReviewLoading(),
          error: (e, _) => _ReviewError(message: '$e'),
          data: (preview) => Column(
            children: [
              _SummaryCell(preview: preview, scope: state.scope),
              const SizedBox(height: AppDimens.gutter),
              if (!state.scope.includes.isLossless)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.gutter),
                  child: _ExclusionsCell(
                    includes: state.scope.includes,
                    onEdit: () =>
                        ref.read(exportControllerProvider.notifier).goTo(
                              ExportStep.options,
                            ),
                  ),
                ),
              if (preview.sample.isNotEmpty)
                _SampleCell(preview: preview),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gutter),
        Text(
          'The file is built on the server and saved wherever you choose. '
          'Nothing is kept server-side.',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall!
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ReviewLoading extends StatelessWidget {
  const _ReviewLoading();

  @override
  Widget build(BuildContext context) => const BentoCell(
        tone: BentoTone.high,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppDimens.gutter),
            Text('Working out what this covers…'),
          ],
        ),
      );
}

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: AppDimens.unit),
              Text('Could not size this export',
                  style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            message,
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.preview, required this.scope});

  final ExportPreview preview;
  final ExportScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final includes = scope.includes;

    return BentoCell(
      tone: BentoTone.high,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CellLabel('Ready to create')),
              const AccentIconWell(icon: Icons.archive_outlined),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          Text(preview.fileName, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppDimens.unit),
          Text(
            'About ${formatBytes(preview.estimatedBytes)} · '
            'gzipped protobuf, readable by Mihon and its forks.',
            style:
                theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.gutter),
          NestedWell(
            padding: const EdgeInsets.all(AppDimens.unit * 2),
            child: Wrap(
              spacing: AppDimens.gutter * 2,
              runSpacing: AppDimens.gutter,
              children: [
                ExportStat(
                  label: 'Titles',
                  value: groupedNumber(preview.titles),
                ),
                ExportStat(
                  label: 'Chapters',
                  value: includes.chapters
                      ? groupedNumber(preview.chapters)
                      : 'Excluded',
                  muted: !includes.chapters,
                ),
                ExportStat(
                  label: 'Read',
                  value: includes.chapters && includes.readProgress
                      ? groupedNumber(preview.readChapters)
                      : 'Excluded',
                  muted: !(includes.chapters && includes.readProgress),
                ),
                ExportStat(
                  label: 'Categories',
                  value: includes.categories
                      ? groupedNumber(preview.categories)
                      : 'Excluded',
                  muted: !includes.categories,
                ),
                ExportStat(
                  label: 'Tracked',
                  value: includes.tracking
                      ? groupedNumber(preview.trackedTitles)
                      : 'Excluded',
                  muted: !includes.tracking,
                ),
                ExportStat(
                  label: 'Sources',
                  value: groupedNumber(preview.sources),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What this backup will *not* contain, with a way straight back to change it.
class _ExclusionsCell extends StatelessWidget {
  const _ExclusionsCell({required this.includes, required this.onEdit});

  final ExportIncludes includes;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final missing = <String>[
      if (!includes.chapters) 'chapter lists',
      if (includes.chapters && !includes.readProgress) 'reading progress',
      if (!includes.categories) 'categories',
      if (!includes.tracking) 'tracker links',
    ];

    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: AppDimens.unit),
              Expanded(
                child: Text('This is a partial backup',
                    style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            'It will not contain ${_joinWords(missing)}. Restoring it into a '
            'reading app will not bring those back.',
            style:
                theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Change what is included'),
            ),
          ),
        ],
      ),
    );
  }

  static String _joinWords(List<String> words) => switch (words.length) {
        0 => 'anything',
        1 => words.first,
        2 => '${words[0]} or ${words[1]}',
        _ =>
          '${words.sublist(0, words.length - 1).join(', ')} or ${words.last}',
      };
}

class _SampleCell extends StatelessWidget {
  const _SampleCell({required this.preview});

  final ExportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final more = preview.titles - preview.sample.length;

    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Included titles'),
          const SizedBox(height: AppDimens.unit * 1.5),
          for (var i = 0; i < preview.sample.length; i++) ...[
            if (i > 0) const SizedBox(height: AppDimens.unit),
            _SampleRow(item: preview.sample[i]),
          ],
          if (more > 0) ...[
            const SizedBox(height: AppDimens.unit * 1.5),
            Text(
              '…and ${groupedNumber(more)} more',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.item});

  final ExportPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          item.favorite ? Icons.favorite : Icons.book_outlined,
          size: 14,
          color: item.favorite ? scheme.secondary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppDimens.unit),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (item.sourceName.isNotEmpty)
                Text(
                  item.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppDimens.unit),
        StatusChip('${item.readCount}/${item.chapterCount}'),
      ],
    );
  }
}
