import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_cache.dart';
import '../../data/covers/cover_repository.dart';
import '../../data/library/library_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/archived_cover.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/status_chip.dart';
import '../library/library_controller.dart';
import '../library/library_screen.dart' show labelForStatus;

/// Title Details: a stacked bento view fed from `GET /library/:id`. Cells fade
/// up in sequence, and the cover shares a Hero transition with the grid card.
class TitleDetailsScreen extends ConsumerWidget {
  const TitleDetailsScreen({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mangaDetailsProvider(titleId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          async.asData?.value.title ?? 'Title details',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Re-fetch cover',
            onPressed: () => _refetchCover(ref, context),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _DetailsError(
          onRetry: () => ref.invalidate(mangaDetailsProvider(titleId)),
        ),
        data: (manga) => _DetailsBody(manga: manga),
      ),
    );
  }

  /// Ask the server to (re)archive this title's cover, then refresh the view.
  Future<void> _refetchCover(WidgetRef ref, BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Fetching cover…')),
    );
    try {
      final result = await ref.read(coverRepositoryProvider).retry(titleId);
      // Drop any cached image (disk + memory) so the fresh cover shows — the
      // serve URL is stable, so a replaced cover would otherwise stay stale.
      final url = CoverRepository.coverUrl('archived', titleId);
      if (url != null) {
        await CoverCache.evict(titleId, url);
      }
      ref.invalidate(mangaDetailsProvider(titleId));
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(result.archived
            ? 'Cover archived'
            : 'Cover unavailable'
                '${result.error != null ? ' (${result.error})' : ''}'),
      ));
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover fetch failed')),
      );
    }
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    // Build the cells, then wrap each in a staggered entrance.
    final cells = <Widget>[
      _HeroCover(manga: manga),
      _SynopsisCell(manga: manga),
      _MetadataCell(manga: manga),
      _ProgressCell(manga: manga),
      _ArchiveCell(manga: manga),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, AppDimens.gutter, AppDimens.gutter, 120),
      itemCount: cells.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gutter),
      itemBuilder: (context, index) => EntranceFade(
        delay: Duration(milliseconds: 70 * index),
        child: cells[index],
      ),
    );
  }
}

class _HeroCover extends StatelessWidget {
  const _HeroCover({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.cellRadius),
      child: SizedBox(
        height: 380,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'manga-cover-${manga.id}',
              child: ArchivedCover(
                coverState: manga.coverState,
                mangaId: manga.id,
                placeholder: const _CoverFallback(),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xF2111415), Color(0x00111415)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimens.cellPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      labelForStatus(manga.status),
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ),
                  const SizedBox(height: AppDimens.unit + 4),
                  Text(
                    manga.title,
                    style: theme.textTheme.headlineMedium!
                        .copyWith(color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.menu_book_outlined,
            size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _SynopsisCell extends StatelessWidget {
  const _SynopsisCell({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = manga.description?.trim();
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Synopsis'),
          const SizedBox(height: AppDimens.unit + 4),
          Text(
            description == null || description.isEmpty
                ? 'No synopsis was included in this backup.'
                : description,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (manga.genres.isNotEmpty) ...[
            const SizedBox(height: AppDimens.unit * 2),
            Wrap(
              spacing: AppDimens.unit,
              runSpacing: AppDimens.unit,
              children:
                  manga.genres.map((g) => StatusChip(g)).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataCell extends StatelessWidget {
  const _MetadataCell({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(
            icon: Icons.person_outline,
            label: 'Author',
            value: manga.author?.trim().isNotEmpty == true
                ? manga.author!
                : 'Unknown',
          ),
          const SizedBox(height: AppDimens.gutter),
          _MetaRow(
            icon: Icons.format_list_numbered,
            label: 'Total chapters',
            value: '${manga.chapterCount}',
          ),
          const SizedBox(height: AppDimens.gutter),
          _MetaRow(
            icon: Icons.account_tree_outlined,
            label: 'Source',
            value: manga.sourceName.isNotEmpty ? manga.sourceName : 'Unknown',
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppDimens.unit),
            CellLabel(label),
          ],
        ),
        const SizedBox(height: AppDimens.unit),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppDimens.coverRadius),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Text(
            value,
            style: theme.textTheme.titleMedium!.copyWith(color: scheme.primary),
          ),
        ),
      ],
    );
  }
}

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasChapters = manga.chapterCount > 0;
    final caughtUp = hasChapters && manga.unreadCount == 0;
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppDimens.unit),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimens.coverRadius),
                ),
                child: Icon(Icons.auto_stories_outlined,
                    color: scheme.primary, size: 20),
              ),
              const SizedBox(width: AppDimens.unit + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reading progress',
                        style: theme.textTheme.titleMedium),
                    Text(
                      _subtitle(hasChapters, caughtUp),
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gutter),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const CellLabel('Progress'),
              Text(
                '${manga.readCount} / ${manga.chapterCount} read',
                style: theme.textTheme.labelSmall!
                    .copyWith(color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          GlowProgressBar(value: manga.readFraction),
          const SizedBox(height: AppDimens.gutter),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showReaderNotice(context),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(
                manga.nextChapter != null
                    ? 'Continue • ${manga.nextChapter!.name}'
                    : 'All chapters read',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(bool hasChapters, bool caughtUp) {
    if (!hasChapters) return 'No chapters in this backup.';
    if (caughtUp) return "You're all caught up!";
    final last = manga.lastReadChapter;
    return last != null ? 'Last read: ${last.name}' : 'Not started yet.';
  }

  void _showReaderNotice(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Reading in-app arrives in a later milestone — '
            'MangaVault archives your library and progress for now.'),
      ));
  }
}

class _ArchiveCell extends StatelessWidget {
  const _ArchiveCell({required this.manga});
  final VaultManga manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.backup_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppDimens.unit),
              Text('Archive history', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.gutter),
          if (manga.archive.isEmpty)
            Text(
              'No backup records for this title.',
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final entry in manga.archive)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.unit),
                child: _ArchiveRow(entry: entry),
              ),
        ],
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.entry});
  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.unit + 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_done_outlined,
                size: 18, color: scheme.primary),
          ),
          const SizedBox(width: AppDimens.unit + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (entry.sourceApp.isNotEmpty) entry.sourceApp,
                    relativeDate(entry.importedAt),
                  ].where((s) => s.isNotEmpty).join(' • '),
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppDimens.unit * 2),
          Text("Couldn't load this title", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.unit * 2),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact relative/absolute date for archive rows.
String relativeDate(int millis) {
  if (millis <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
