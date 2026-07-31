import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/library/library_models.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/archived_cover.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pressable.dart';
import '../covers/cover_archive_controller.dart';
import '../sync/sync_controller.dart';
import 'library_controller.dart';
import 'library_display.dart';
import 'library_filter_sheet.dart';
import 'library_selection.dart';

/// Library Archive: an infinite-scroll cover grid with filters, sort, display
/// options and multi-select — the `library_archive` mockup, reading the
/// on-device mirror.
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
    // First run has an empty mirror and nothing to show, so fill it. A no-op
    // once a cursor exists — later syncs are import-driven or pull-to-refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncControllerProvider.notifier).bootstrap();
    });
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final display = ref.watch(libraryDisplayProvider);
    final selection = ref.watch(librarySelectionProvider);

    return PopScope(
      // In selection mode, back exits the selection rather than the screen —
      // the same expectation as every gallery/file manager.
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).exit();
      },
      child: Scaffold(
        appBar: selection.active
            ? _selectionAppBar(context, state, selection)
            : _defaultAppBar(context, state),
        body: RefreshIndicator(
          // Pull-to-refresh pulls server changes into the mirror; the grid then
          // re-reads locally when the sync bumps the revision.
          onRefresh: () => ref.read(syncControllerProvider.notifier).run(),
          child: CustomScrollView(
            controller: _scrollController,
            // Always scrollable, so the pull gesture works on a short or empty
            // library too.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_searchOpen)
                SliverToBoxAdapter(child: _buildSearchField(context)),
              SliverToBoxAdapter(child: _MetaLine(state: state)),
              const SliverToBoxAdapter(child: _SyncBanner()),
              const SliverToBoxAdapter(child: _CoverBanner()),
              ..._buildContent(context, state, display, selection),
              SliverToBoxAdapter(child: _Footer(state: state)),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _defaultAppBar(BuildContext context, LibraryState state) {
    final coverArchive = ref.watch(coverArchiveControllerProvider);
    final filtersActive = hasActiveFilters(state.filters);
    return AppBar(
      title: const Text('Library'),
      actions: [
        // Filters live in a bottom sheet (also reachable by re-tapping the
        // Library tab). Since they're off-screen, a dot marks non-defaults.
        IconButton(
          icon: Badge(
            isLabelVisible: filtersActive,
            smallSize: 8,
            child: const Icon(Icons.tune),
          ),
          onPressed: () => showLibraryFilterSheet(context),
          tooltip: 'Filter, sort & display',
        ),
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
              : () => ref.read(coverArchiveControllerProvider.notifier).start(),
          tooltip: 'Download covers',
        ),
        IconButton(
          icon: Icon(_searchOpen ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
          tooltip: _searchOpen ? 'Close search' : 'Search',
        ),
        // Deleted titles are blocked from every future import, so the list has
        // to be reachable — but it's a rare destination, hence the overflow.
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (value) {
            if (value == 'deleted') context.push('/library/deleted');
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'deleted',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('Deleted titles'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Contextual bar shown while titles are selected: it replaces the normal one
  /// so the destructive action can never be reached by accident, and the count
  /// is always in view.
  AppBar _selectionAppBar(
    BuildContext context,
    LibraryState state,
    LibrarySelection selection,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(librarySelectionProvider.notifier);
    final loaded = state.items.map((i) => i.id).toList();
    final allSelected =
        loaded.isNotEmpty && loaded.every(selection.contains);

    return AppBar(
      backgroundColor: scheme.surfaceContainerHigh,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: selection.busy ? null : notifier.exit,
      ),
      title: Text('${groupedNumber(selection.count)} selected'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Select none' : 'Select all loaded',
          onPressed: selection.busy
              ? null
              : () => allSelected
                  ? notifier.clear()
                  : notifier.selectAll(loaded),
        ),
        if (selection.busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete selected',
            color: scheme.error,
            onPressed:
                selection.count == 0 ? null : () => _confirmDelete(selection),
          ),
      ],
    );
  }

  /// Ask before deleting — this removes chapters, progress and covers from the
  /// server, and there is nothing to undo it with.
  Future<void> _confirmDelete(LibrarySelection selection) async {
    final count = selection.count;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(count == 1 ? 'Delete this title?' : 'Delete $count titles?'),
          content: Text(
            count == 1
                ? 'Its chapters, reading progress and archived cover are '
                    'removed from the vault. This cannot be undone.'
                : 'Their chapters, reading progress and archived covers are '
                    'removed from the vault. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      final deleted = await ref
          .read(librarySelectionProvider.notifier)
          .deleteSelected();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(
          deleted == 1 ? 'Title deleted' : '$deleted titles deleted',
        ),
      ));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't delete — ${_shortError(e)}"),
      ));
    }
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

  // (filters, sort and display options live in the bottom sheet —
  // see library_filter_sheet.dart)

  List<Widget> _buildContent(
    BuildContext context,
    LibraryState state,
    LibraryDisplay display,
    LibrarySelection selection,
  ) {
    if (state.status == LibraryStatus.loading) {
      return [_gridPadding(_skeleton(display))];
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

    Widget itemAt(BuildContext context, int index) {
      final item = state.items[index];
      final firstTime = _animated.add(item.id);
      return EntranceFade(
        // Stagger only the first screenful; later cards reveal on scroll.
        delay: firstTime
            ? Duration(milliseconds: 40 * (index % 8))
            : Duration.zero,
        duration: Duration(milliseconds: firstTime ? 420 : 0),
        child: _LibraryTile(
          item: item,
          display: display,
          selectionActive: selection.active,
          selected: selection.contains(item.id),
          onTap: () => _onTileTap(item, selection),
          onLongPress: () =>
              ref.read(librarySelectionProvider.notifier).begin(item.id),
        ),
      );
    }

    if (display.layout == LibraryLayout.list) {
      return [
        _gridPadding(
          SliverList.separated(
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppDimens.unit),
            itemBuilder: itemAt,
          ),
        ),
      ];
    }

    return [
      _gridPadding(
        SliverGrid(
          gridDelegate: _gridDelegate(display),
          delegate: SliverChildBuilderDelegate(
            itemAt,
            childCount: state.items.length,
          ),
        ),
      ),
    ];
  }

  /// Tap opens the title normally, but toggles it while selecting — the
  /// standard gesture pairing for a multi-select grid.
  void _onTileTap(MangaListItem item, LibrarySelection selection) {
    if (selection.active) {
      ref.read(librarySelectionProvider.notifier).toggle(item.id);
    } else {
      context.push('/library/title/${item.id}');
    }
  }

  SliverGridDelegate _gridDelegate(LibraryDisplay display) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: display.columns,
        mainAxisSpacing: AppDimens.gutter,
        crossAxisSpacing: AppDimens.gutter,
        // Compact cells are almost pure cover; comfortable ones carry three
        // overlaid lines and need the extra height.
        childAspectRatio:
            display.layout == LibraryLayout.compact ? 0.66 : 0.7,
      );

  Widget _gridPadding(Widget sliver) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter, AppDimens.unit, AppDimens.gutter, 120),
        sliver: sliver,
      );

  Widget _skeleton(LibraryDisplay display) {
    if (display.layout == LibraryLayout.list) {
      return SliverList.separated(
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: AppDimens.unit),
        itemBuilder: (_, _) => const SizedBox(height: 96, child: _SkeletonCard()),
      );
    }
    return SliverGrid(
      gridDelegate: _gridDelegate(display),
      delegate: SliverChildBuilderDelegate(
        (context, index) => const _SkeletonCard(),
        childCount: display.columns * 3,
      ),
    );
  }
}

String _shortError(Object e) =>
    e.toString().replaceFirst('Exception: ', '').split('\n').first;

/// One title, rendered per the active layout, with the selection affordances
/// layered on top.
class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.display,
    required this.selectionActive,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final MangaListItem item;
  final LibraryDisplay display;
  final bool selectionActive;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = display.layout == LibraryLayout.list
        ? _LibraryRow(item: item, display: display, selected: selected)
        : _LibraryCard(item: item, display: display, selected: selected);

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.cellRadius),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        // Inset the content so the selection ring reads as a frame around the
        // card rather than a border drawn on it.
        padding: const EdgeInsets.all(2),
        child: Stack(
          children: [
            child,
            if (selectionActive)
              Positioned(
                top: 6,
                right: 6,
                child: _SelectionCheck(selected: selected),
              ),
          ],
        ),
      ),
    );
  }
}

/// The archive card: cover fills the cell with a gradient scrim and the title,
/// status, and chapter/source meta overlaid — matching the mockup grid cells.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.item,
    required this.display,
    required this.selected,
  });

  final MangaListItem item;
  final LibraryDisplay display;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = display.layout == LibraryLayout.compact;

    return Container(
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
          if (selected)
            ColoredBox(
              color: scheme.primary.withValues(alpha: 0.18),
              child: const SizedBox.expand(),
            ),
          Padding(
            padding: const EdgeInsets.all(AppDimens.unit * 1.5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact) ...[
                  _StatusPill(status: item.status),
                  const SizedBox(height: AppDimens.unit),
                ],
                Text(
                  item.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? theme.textTheme.bodyMedium!
                          : theme.textTheme.bodyLarge!)
                      .copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    metaLineFor(item, display),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall!
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (display.showUnreadBadge && item.unreadCount > 0)
            Positioned(
              top: 6,
              left: 6,
              child: _UnreadBadge(count: item.unreadCount),
            ),
        ],
      ),
    );
  }
}

/// The list layout's row: a small cover with the title, author and meta beside
/// it. Denser and far easier to scan by name than any grid.
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.item,
    required this.display,
    required this.selected,
  });

  final MangaListItem item;
  final LibraryDisplay display;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.28)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppDimens.cellRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(AppDimens.unit),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.coverRadius),
            child: SizedBox(
              width: 52,
              height: 78,
              child: Hero(
                tag: 'manga-cover-${item.id}',
                child: ArchivedCover(
                  coverState: item.coverState,
                  mangaId: item.id,
                  placeholder: const _CoverPlaceholder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDimens.unit * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  metaLineFor(item, display),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (display.showUnreadBadge && item.unreadCount > 0) ...[
            const SizedBox(width: AppDimens.unit),
            _UnreadBadge(count: item.unreadCount),
          ],
          const SizedBox(width: AppDimens.unit / 2),
        ],
      ),
    );
  }
}

/// Chapter count, status and (optionally) the source, in one line.
///
/// Sources whose backup carried no name fall back to their numeric id — a blank
/// segment would just read as missing data.
String metaLineFor(MangaListItem item, LibraryDisplay display) {
  final parts = <String>[
    '${item.chapterCount} ch',
    if (display.showSourceName) sourceLabel(item.sourceName, item.sourceId),
  ];
  return parts.join(' • ');
}

/// Unread-chapter count, shown on the cover corner.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        style: theme.textTheme.labelSmall!.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Filled tick when a tile is selected, hollow ring when it is selectable —
/// so selection mode is visible on every tile, not only the chosen ones.
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : scheme.scrim.withValues(alpha: 0.55),
        border: Border.all(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : null,
    );
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

/// One quiet line above the grid: how many titles match, how fresh the mirror
/// is, and which filters are active. It is a **single** [Text] on its own line —
/// the previous inline filter bar crammed these next to the sort and favourites
/// pills and overflowed horizontally on narrow phones and at large text scales.
class _MetaLine extends ConsumerWidget {
  const _MetaLine({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final syncedAt = ref.watch(lastSyncedAtProvider).value;
    final sources = state.filters.sourceIds.length;

    final parts = <String>[
      if (state.status == LibraryStatus.ready)
        '${groupedNumber(state.total)} '
            '${state.filters.favorite ? 'favorites' : 'others'}',
      if (state.filters.status.isNotEmpty)
        labelForStatus(state.filters.status).toLowerCase(),
      if (sources > 0) sources == 1 ? '1 source' : '$sources sources',
      if (syncedAt != null) 'synced ${relativeDate(syncedAt)}',
    ];
    if (parts.isEmpty) return const SizedBox(height: AppDimens.unit);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, AppDimens.unit, AppDimens.gutter, AppDimens.unit),
      child: Text(
        parts.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Mirrors [_CoverBanner] for library sync: shows progress while the mirror is
/// being filled from the server, and reports a failure without hiding whatever
/// the mirror already holds — an unreachable server degrades to stale data, not
/// an empty screen.
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(syncControllerProvider);
    // A completed sync needs no announcement — the titles simply appear.
    final show = state is SyncRunning || state is SyncFailed;

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
                    horizontal: AppDimens.unit * 2,
                    vertical: AppDimens.unit * 1.5),
                child: switch (state) {
                  SyncFailed(:final message) => Row(
                      children: [
                        Icon(Icons.sync_problem_outlined,
                            size: 18, color: scheme.error),
                        const SizedBox(width: AppDimens.unit),
                        Expanded(
                          child: Text(
                            "Couldn't reach the server — showing the last "
                            'synced library.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(syncControllerProvider.notifier).run(),
                          child: const Text('Retry'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: message,
                          onPressed:
                              ref.read(syncControllerProvider.notifier).dismiss,
                        ),
                      ],
                    ),
                  SyncRunning(
                    :final received,
                    :final total,
                    :final fraction
                  ) =>
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Syncing library',
                                style: theme.textTheme.titleSmall),
                            const Spacer(),
                            Text(
                              total == 0 ? '…' : '$received / $total',
                              style: theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimens.unit),
                        GlowProgressBar(value: fraction),
                      ],
                    ),
                  _ => const SizedBox.shrink(),
                },
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
