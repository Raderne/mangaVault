import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/library/library_models.dart';
import '../../data/stats/stats_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/archived_cover.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pressable.dart';
import '../../widgets/progress_ring.dart';
import '../library/library_screen.dart' show labelForStatus;
import 'dashboard_controller.dart';

/// Archive Dashboard (home): the `archive_dashboard` mockup's bento grid, fed
/// from `GET /stats/*`. Cells stack in one column on the phone and fade up in
/// sequence; pull down to re-fetch the whole snapshot.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MangaVault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh stats',
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: switch (async) {
          AsyncData(:final value) => _DashboardBody(data: value),
          AsyncError() => _ErrorState(
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
          _ => const _LoadingState(),
        },
      ),
    );
  }
}

/// Vertical padding shared by every dashboard scroll view (bottom clears the
/// floating glass nav bar).
const _listPadding = EdgeInsets.fromLTRB(
  AppDimens.gutter,
  0,
  AppDimens.gutter,
  120,
);

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;
    final cells = <Widget>[
      const _WelcomeBlock(),
      if (stats.isEmpty)
        const _EmptyArchiveCell()
      else ...[
        _TotalTitlesCell(stats: stats),
        // IntrinsicHeight so the paired cells match heights even when one
        // caption wraps — `stretch` alone can't size inside a ListView.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCell(
                  label: 'Chapters',
                  value: groupedNumber(stats.totalChapters),
                  caption: '${groupedNumber(stats.readChapters)} read',
                  icon: Icons.format_list_numbered,
                ),
              ),
              const SizedBox(width: AppDimens.gutter),
              Expanded(
                child: _StatCell(
                  label: 'Covers',
                  value: groupedNumber(stats.coversArchived),
                  caption: stats.coversFailed > 0
                      ? '${stats.coversFailed} failed'
                      : 'of ${groupedNumber(stats.totalTitles)} titles',
                  icon: Icons.image_outlined,
                ),
              ),
            ],
          ),
        ),
        _ReadingProgressCell(stats: stats),
        _BackupHealthCell(health: data.health, stats: stats),
        if (data.resume.isNotEmpty) _ResumeShelf(items: data.resume),
        if (data.recent.isNotEmpty) _RecentShelf(items: data.recent),
        _VaultCell(stats: stats),
      ],
    ];

    return ListView.separated(
      padding: _listPadding,
      itemCount: cells.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gutter),
      itemBuilder: (context, index) => EntranceFade(
        delay: Duration(milliseconds: 70 * index),
        child: cells[index],
      ),
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CellLabel('Overview'),
        const SizedBox(height: 2),
        Text('Archive Master', style: Theme.of(context).textTheme.headlineLarge),
      ],
    );
  }
}

/// The hero cell: total titles as a display-size figure, with the week's
/// additions and a live "archive is watched" footer.
class _TotalTitlesCell extends StatelessWidget {
  const _TotalTitlesCell({required this.stats});

  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BentoCell(
      child: Stack(
        children: [
          // Oversized watermark glyph, as in the mockup's large cell.
          Positioned(
            top: -12,
            right: -8,
            child: Icon(
              Icons.auto_stories,
              size: 96,
              color: scheme.onSurface.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CellLabel('Total titles'),
              const SizedBox(height: AppDimens.unit * 1.5),
              Text(
                groupedNumber(stats.totalTitles),
                style: theme.textTheme.displayLarge!
                    .copyWith(color: scheme.primary),
              ),
              const SizedBox(height: 2),
              Text(
                stats.addedLast7Days > 0
                    ? '+${stats.addedLast7Days} added this week'
                    : 'No new titles this week',
                style: theme.textTheme.bodyLarge!
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppDimens.unit * 2),
              Row(
                children: [
                  _PulseDot(color: scheme.secondary),
                  const SizedBox(width: AppDimens.unit),
                  Expanded(
                    child: Text(
                      '${groupedNumber(stats.favoriteTitles)} in library · '
                      '${stats.sourceCount} '
                      '${stats.sourceCount == 1 ? 'source' : 'sources'}',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact number cell for the paired row.
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BentoCell(
      padding: const EdgeInsets.all(AppDimens.unit * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CellLabel(label)),
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppDimens.unit),
          Text(value, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(
            caption,
            style: theme.textTheme.bodyMedium!
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Archive-wide reading progress as the mockup's ring, plus the status mix.
class _ReadingProgressCell extends StatelessWidget {
  const _ReadingProgressCell({required this.stats});

  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = (stats.readFraction * 100).round();
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Reading progress'),
          const SizedBox(height: AppDimens.unit * 2),
          Row(
            children: [
              ProgressRing(
                value: stats.readFraction,
                size: 104,
                center: Text('$percent%', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: AppDimens.cellPadding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${groupedNumber(stats.readChapters)} of '
                      '${groupedNumber(stats.totalChapters)} chapters read',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppDimens.unit),
                    for (final entry in _statusMix(stats))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${labelForStatus(entry.key)} · '
                          '${groupedNumber(entry.value)}',
                          style: theme.textTheme.labelSmall!
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The three largest non-empty status bands, biggest first.
  List<MapEntry<String, int>> _statusMix(LibraryStats stats) {
    final entries = stats.byStatus.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).toList();
  }
}

/// Per-source-app backup freshness — the archive's "is my data current" cell.
class _BackupHealthCell extends StatelessWidget {
  const _BackupHealthCell({required this.health, required this.stats});

  final List<BackupHealth> health;
  final LibraryStats stats;

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
              const Expanded(child: CellLabel('Backup health')),
              Text(
                '${stats.importCount} '
                '${stats.importCount == 1 ? 'backup' : 'backups'}',
                style: theme.textTheme.labelSmall!
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          if (health.isEmpty)
            Text(
              'No backups imported yet',
              style: theme.textTheme.bodyLarge,
            )
          else
            for (final row in health)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.unit),
                child: _HealthRow(row: row),
              ),
          const SizedBox(height: AppDimens.unit),
          PillButton(
            label: 'Import a backup',
            icon: Icons.upload_file,
            onPressed: () => context.go('/backups'),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.row});

  final BackupHealth row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (color, word) = switch (row.staleness) {
      Staleness.fresh => (scheme.secondary, 'Fresh'),
      Staleness.aging => (scheme.tertiary, 'Aging'),
      Staleness.stale => (scheme.error, 'Stale'),
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppDimens.unit * 1.5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.sourceApp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                '${groupedNumber(row.titleCount)} titles · '
                '${relativeDate(row.lastImportAt)}',
                style: theme.textTheme.labelSmall!
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Text(
          word.toUpperCase(),
          style: theme.textTheme.labelSmall!.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Horizontal shelf of titles with progress left to read.
class _ResumeShelf extends StatelessWidget {
  const _ResumeShelf({required this.items});

  final List<ResumeItem> items;

  @override
  Widget build(BuildContext context) {
    return _Shelf(
      label: 'Resume reading',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final number = chapterNumberLabel(item.nextChapter.number);
        return _ShelfCard(
          manga: item.manga,
          caption: number != null ? 'Ch. $number' : item.nextChapter.name,
          progress: item.readFraction,
        );
      },
    );
  }
}

/// Horizontal shelf of the newest titles in the archive.
class _RecentShelf extends StatelessWidget {
  const _RecentShelf({required this.items});

  final List<MangaListItem> items;

  @override
  Widget build(BuildContext context) {
    return _Shelf(
      label: 'Recently added',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ShelfCard(
          manga: item,
          caption: '${groupedNumber(item.chapterCount)} ch',
        );
      },
    );
  }
}

/// Shelf tile geometry: a 2:3 cover plus room for two title lines, the progress
/// bar and the caption.
const double _coverWidth = 108;
const double _coverHeight = 162;

/// 4px progress bar + the gap below it. Reserved on every tile, with or without
/// a bar, so captions line up across both shelves.
const double _progressBlock = 8;

/// Text block heights for a shelf tile, measured at the device's current text
/// scale. A horizontal shelf needs a fixed height, so it must be derived rather
/// than hardcoded — an enlarged system font overflows a constant (which it did:
/// 240px of tile in a 238px box at scale 1.1).
class _ShelfMetrics {
  const _ShelfMetrics({required this.titleBlock, required this.caption});

  /// Exactly two title lines, so every tile's caption sits at the same offset.
  final double titleBlock;
  final double caption;

  /// The theme sets an explicit `height` on both styles, so a line box is
  /// exactly `scaledFontSize * height` — no font metrics to guess at.
  factory _ShelfMetrics.of(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleLine = (scaler.scale(14) * (20 / 14)).ceilToDouble();
    final captionLine = (scaler.scale(12) * (16 / 12)).ceilToDouble();
    return _ShelfMetrics(titleBlock: titleLine * 2, caption: captionLine);
  }

  double get shelfHeight =>
      _coverHeight + AppDimens.unit + titleBlock + _progressBlock + caption;
}

/// A labelled, horizontally scrolling row of [_ShelfCard]s.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.label,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String label;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.unit * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimens.cellPadding),
            child: CellLabel(label),
          ),
          const SizedBox(height: AppDimens.unit * 1.5),
          SizedBox(
            height: _ShelfMetrics.of(context).shelfHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.cellPadding),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: AppDimens.unit),
              itemBuilder: itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}

/// A shelf tile: cover, title, one caption line and an optional progress bar.
/// Tapping switches to the Library tab with the title's details on top, so the
/// back gesture lands somewhere sensible.
class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    required this.manga,
    required this.caption,
    this.progress,
  });

  final MangaListItem manga;
  final String caption;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = _ShelfMetrics.of(context);
    return Pressable(
      onTap: () => context.go('/library/title/${manga.id}'),
      child: SizedBox(
        width: _coverWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.coverRadius),
              child: SizedBox(
                width: _coverWidth,
                height: _coverHeight,
                child: ArchivedCover(
                  coverState: manga.coverState,
                  mangaId: manga.id,
                  placeholder: ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: Center(
                      child: Icon(
                        Icons.menu_book_outlined,
                        size: 24,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.unit),
            // Both text blocks are pinned to the measured line heights the
            // shelf reserved, so the tile can never exceed its box.
            SizedBox(
              height: metrics.titleBlock,
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: _progressBlock,
              child: progress == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GlowProgressBar(value: progress!),
                    ),
            ),
            SizedBox(
              height: metrics.caption,
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall!
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Disk footprint and when the archive last received a backup.
class _VaultCell extends StatelessWidget {
  const _VaultCell({required this.stats});

  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = stats.lastImportAt;
    return BentoCell(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Vault on disk'),
                const SizedBox(height: 2),
                Text(
                  formatBytes(stats.vaultSizeBytes),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.cloud_done_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      last == null
                          ? 'Nothing imported yet'
                          : 'Last import ${relativeDate(last)}',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.storage, size: 28, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Shown before the first backup exists: nothing to count yet.
class _EmptyArchiveCell extends StatelessWidget {
  const _EmptyArchiveCell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Your vault is empty'),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Import a .tachibk backup and your titles, chapters and reading '
            'progress will be archived here.',
            style: theme.textTheme.bodyLarge!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          PillButton(
            label: 'Import a backup',
            icon: Icons.upload_file,
            onPressed: () => context.go('/backups'),
          ),
        ],
      ),
    );
  }
}

/// Pulsing status dot ("active monitoring" in the mockup).
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Pulsing placeholder cells while the first snapshot loads.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _listPadding,
      children: const [
        _SkeletonCell(height: 60),
        SizedBox(height: AppDimens.gutter),
        _SkeletonCell(height: 190),
        SizedBox(height: AppDimens.gutter),
        _SkeletonCell(height: 110),
        SizedBox(height: AppDimens.gutter),
        _SkeletonCell(height: 170),
      ],
    );
  }
}

class _SkeletonCell extends StatefulWidget {
  const _SkeletonCell({required this.height});

  final double height;

  @override
  State<_SkeletonCell> createState() => _SkeletonCellState();
}

class _SkeletonCellState extends State<_SkeletonCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.8).animate(_controller),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppDimens.cellRadius),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A scrollable so RefreshIndicator still works in the error state.
    return ListView(
      padding: _listPadding,
      children: [
        const SizedBox(height: 80),
        Icon(Icons.cloud_off_outlined,
            size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppDimens.unit * 2),
        Center(
          child: Text("Couldn't load your archive stats",
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppDimens.unit),
        Center(
          child: Text(
            'Check that the server is reachable.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppDimens.unit * 2),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
