import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/library/library_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/archived_cover.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pressable.dart';
import '../covers/cover_archive_controller.dart';
import 'library_controller.dart';

/// Library Archive: an infinite-scroll cover grid with status filters, sort,
/// and search — the `library_archive` mockup, wired to `GET /library`.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searchOpen = false;

  /// Cover ids that have already played their entrance, so scrolling back up
  /// doesn't re-animate them (content reveals once as you scroll down).
  final Set<String> _animated = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      ref.read(libraryControllerProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(libraryControllerProvider.notifier).setSearch(value);
    });
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen && _searchController.text.isNotEmpty) {
      _searchController.clear();
      ref.read(libraryControllerProvider.notifier).setSearch('');
    }
  }

  Future<void> _openSortSheet(LibraryFilters filters) async {
    final selected = await showModalBottomSheet<LibrarySort>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppDimens.cellRadius)),
      ),
      builder: (context) => _SortSheet(current: filters),
    );
    if (selected != null) {
      ref.read(libraryControllerProvider.notifier).setSort(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final coverArchive = ref.watch(coverArchiveControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: coverArchive.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            onPressed: coverArchive.isRunning
                ? null
                : () =>
                    ref.read(coverArchiveControllerProvider.notifier).start(),
            tooltip: 'Download covers',
          ),
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            tooltip: _searchOpen ? 'Close search' : 'Search',
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (_searchOpen)
            SliverToBoxAdapter(child: _buildSearchField(context)),
          SliverToBoxAdapter(child: _buildFilterBar(context, state)),
          const SliverToBoxAdapter(child: _CoverBanner()),
          ..._buildContent(context, state),
          SliverToBoxAdapter(
            child: _Footer(state: state),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, AppDimens.unit, AppDimens.gutter, 0),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search titles and authors',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, LibraryState state) {
    final controller = ref.read(libraryControllerProvider.notifier);
    final current = kLibrarySorts.firstWhere(
      (s) => s.matches(state.filters),
      orElse: () => kLibrarySorts.first,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, AppDimens.unit, AppDimens.gutter, AppDimens.unit),
      child: BentoCell(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.unit * 2, vertical: AppDimens.unit * 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (label, value) in kStatusFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: AppDimens.unit),
                      child: _FilterChipButton(
                        label: label,
                        selected: state.filters.status == value,
                        onTap: () => controller.setStatus(value),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.unit),
            Row(
              children: [
                Text(
                  'SORT',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(width: AppDimens.unit),
                _SortPill(
                  label: current.label,
                  onTap: () => _openSortSheet(state.filters),
                ),
                const Spacer(),
                if (state.status == LibraryStatus.ready)
                  Text(
                    '${state.total}',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, LibraryState state) {
    if (state.status == LibraryStatus.loading) {
      return [_gridPadding(_skeletonGrid())];
    }
    if (state.status == LibraryStatus.error) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorState(
            onRetry: () => ref.read(libraryControllerProvider.notifier).refresh(),
          ),
        ),
      ];
    }
    if (state.isEmpty) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: _EmptyState()),
      ];
    }
    return [
      _gridPadding(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppDimens.gutter,
            crossAxisSpacing: AppDimens.gutter,
            childAspectRatio: 0.7,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = state.items[index];
              final firstTime = _animated.add(item.id);
              return EntranceFade(
                // Stagger only the first screenful; later cards reveal on scroll.
                delay: firstTime
                    ? Duration(milliseconds: 40 * (index % 8))
                    : Duration.zero,
                duration: Duration(milliseconds: firstTime ? 420 : 0),
                child: _LibraryCard(
                  item: item,
                  onTap: () => context.push('/library/title/${item.id}'),
                ),
              );
            },
            childCount: state.items.length,
          ),
        ),
      ),
    ];
  }

  Widget _gridPadding(Widget sliver) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter, AppDimens.unit, AppDimens.gutter, 120),
        sliver: sliver,
      );

  Widget _skeletonGrid() => SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppDimens.gutter,
          crossAxisSpacing: AppDimens.gutter,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => const _SkeletonCard(),
          childCount: 6,
        ),
      );
}

/// The archive card: cover fills the cell with a gradient scrim and the title,
/// status, and chapter/source meta overlaid — matching the mockup grid cells.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.item, required this.onTap});

  final MangaListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppDimens.cellRadius),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'manga-cover-${item.id}',
              child: ArchivedCover(
                coverState: item.coverState,
                mangaId: item.id,
                placeholder: const _CoverPlaceholder(),
              ),
            ),
            // Bottom scrim so overlaid text stays legible on any cover.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xE6111415), Color(0x00111415)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimens.unit * 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusPill(status: item.status),
                  const SizedBox(height: AppDimens.unit),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLine(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall!
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine(MangaListItem item) {
    final chapters = '${item.chapterCount} ch';
    final source = item.sourceName.isNotEmpty ? item.sourceName : 'Unknown';
    return '$chapters • $source';
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.menu_book_outlined,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6), size: 34),
      ),
    );
  }
}

/// Small status capsule shown on cards (uppercase micro-label).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        labelForStatus(status),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// Human, uppercase label for a publication status enum value.
String labelForStatus(String status) => switch (status) {
      'ongoing' => 'ONGOING',
      'completed' => 'COMPLETED',
      'licensed' => 'LICENSED',
      'publishing_finished' => 'FINISHED',
      'cancelled' => 'CANCELLED',
      'on_hiatus' => 'HIATUS',
      _ => 'UNKNOWN',
    };

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppDimens.coverRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});
  final LibraryFilters current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.unit),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppDimens.cellPadding, AppDimens.unit, 0, AppDimens.unit),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CellLabel('Sort by'),
              ),
            ),
            for (final sort in kLibrarySorts)
              ListTile(
                title: Text(sort.label),
                trailing: sort.matches(current)
                    ? Icon(Icons.check, color: scheme.secondary)
                    : null,
                onTap: () => Navigator.of(context).pop(sort),
              ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});
  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    if (!state.loadingMore) return const SizedBox(height: 0);
    return const Padding(
      padding: EdgeInsets.only(bottom: 120, top: AppDimens.unit),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// A slim banner that expands in while covers are being archived (and reports
/// the result), driven by [coverArchiveControllerProvider]. Animates its height
/// so it slides in/out rather than popping.
class _CoverBanner extends ConsumerWidget {
  const _CoverBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(coverArchiveControllerProvider);
    final show = s.phase != CoverArchivePhase.idle;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: kEntranceCurve,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppDimens.gutter, 0, AppDimens.gutter, AppDimens.unit),
              child: BentoCell(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.unit * 2, vertical: AppDimens.unit * 1.5),
                child: _content(context, ref, s),
              ),
            ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, CoverArchiveState s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(coverArchiveControllerProvider.notifier);

    if (s.phase == CoverArchivePhase.error) {
      return Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.error),
          const SizedBox(width: AppDimens.unit),
          Expanded(
            child: Text("Couldn't download covers",
                style: theme.textTheme.bodyMedium),
          ),
          TextButton(onPressed: controller.start, child: const Text('Retry')),
          _closeButton(controller),
        ],
      );
    }

    if (s.phase == CoverArchivePhase.done) {
      final summary = s.total == 0
          ? 'All covers are already archived.'
          : '${s.archived} archived'
              '${s.failed > 0 ? ' · ${s.failed} failed' : ''}';
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: AppDimens.unit),
          Expanded(
            child: Text(summary, style: theme.textTheme.bodyMedium),
          ),
          _closeButton(controller),
        ],
      );
    }

    // Running.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Downloading covers', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              s.total == 0 ? '…' : '${s.done} / ${s.total}',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.unit),
        GlowProgressBar(value: s.fraction),
      ],
    );
  }

  Widget _closeButton(CoverArchiveController controller) => IconButton(
        icon: const Icon(Icons.close, size: 18),
        visualDensity: VisualDensity.compact,
        tooltip: 'Dismiss',
        onPressed: controller.dismiss,
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppDimens.unit * 2),
          Text('No titles match', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Try a different filter, or import a backup.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppDimens.unit * 2),
          Text("Couldn't load the library",
              style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.unit),
          Text(
            'Check that the server is reachable.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// A gently pulsing placeholder cell shown during the first load.
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
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
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppDimens.cellRadius),
        ),
      ),
    );
  }
}
