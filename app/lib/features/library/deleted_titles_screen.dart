import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/library/deleted_models.dart';
import '../../data/library/library_models.dart';
import '../../data/library/library_write_repository.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../sync/sync_controller.dart';

/// The deletion registry, straight from the server.
///
/// Not mirrored in SQLite: it is small, rarely opened, and every action on it
/// needs the server anyway — so a drift table would only buy a schema bump.
final deletedTitlesProvider =
    FutureProvider.autoDispose<List<DeletedTitle>>((ref) {
  return ref.watch(libraryWriteRepositoryProvider).deletedTitles();
});

/// Titles the user deleted — the list every import now skips.
///
/// The whole point of the screen is choosing, so it is in multi-select from the
/// first tap: no long-press, and the two actions sit in a persistent bar.
class DeletedTitlesScreen extends ConsumerStatefulWidget {
  const DeletedTitlesScreen({super.key});

  @override
  ConsumerState<DeletedTitlesScreen> createState() =>
      _DeletedTitlesScreenState();
}

class _DeletedTitlesScreenState extends ConsumerState<DeletedTitlesScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deletedTitlesProvider);
    final entries = async.value ?? const <DeletedTitle>[];
    // Selections can outlive a refresh that removed their rows.
    final selected = _selected.where((id) => entries.any((e) => e.id == id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deleted titles'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: Icon(_selected.length == entries.length
                  ? Icons.deselect
                  : Icons.select_all),
              tooltip: _selected.length == entries.length
                  ? 'Select none'
                  : 'Select all',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        if (_selected.length == entries.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(entries.map((e) => e.id));
                        }
                      }),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(deletedTitlesProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: e.toString().replaceFirst('Exception: ', ''),
            onRetry: () => ref.invalidate(deletedTitlesProvider),
          ),
          data: (all) => all.isEmpty
              ? const _EmptyState()
              : _List(
                  entries: all,
                  selected: _selected,
                  onToggle: (id) => setState(() {
                    if (!_selected.remove(id)) _selected.add(id);
                  }),
                ),
        ),
      ),
      bottomNavigationBar: selected.isEmpty
          ? null
          : _ActionBar(
              count: selected.length,
              busy: _busy,
              onRestore: () => _run(restore: true),
              onForget: () => _run(restore: false),
            ),
    );
  }

  /// Restore (put the titles back) or forget (drop the block) the selection.
  Future<void> _run({required bool restore}) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    if (!restore) {
      final confirmed = await _confirmForget(ids.length);
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(libraryWriteRepositoryProvider);
      final String message;
      if (restore) {
        final result = await repo.restore(ids);
        message = result.skipped == 0
            ? '${result.restored} restored'
            : '${result.restored} restored · ${result.skipped} skipped';
        // Restored titles are new rows on the server; the mirror only learns
        // about them on the next delta.
        await ref.read(syncControllerProvider.notifier).run();
      } else {
        final purged = await repo.purgeDeleted(ids);
        message = '$purged removed from the list';
      }
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _busy = false;
      });
      ref.invalidate(deletedTitlesProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(
          "Couldn't ${restore ? 'restore' : 'update the list'} — "
          '${e.toString().replaceFirst('Exception: ', '').split('\n').first}',
        ),
      ));
    }
  }

  Future<bool?> _confirmForget(int count) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(count == 1
              ? 'Remove this entry?'
              : 'Remove $count entries?'),
          content: const Text(
            'The titles stay deleted, but they are no longer blocked — a '
            'future backup import will add them again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
}

class _List extends StatelessWidget {
  const _List({
    required this.entries,
    required this.selected,
    required this.onToggle,
  });

  final List<DeletedTitle> entries;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, AppDimens.unit, AppDimens.gutter, 120),
      // +1 for the explainer that leads the list.
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.unit),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(
                bottom: AppDimens.unit, left: 4, right: 4),
            child: Text(
              'These titles are skipped by every backup import. Restore the '
              'ones you want back — with their reading progress.',
              style: theme.textTheme.bodySmall!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        final entry = entries[index - 1];
        return EntranceFade(
          delay: Duration(milliseconds: 30 * (index.clamp(0, 8))),
          child: _DeletedRow(
            entry: entry,
            selected: selected.contains(entry.id),
            onTap: () => onToggle(entry.id),
          ),
        );
      },
    );
  }
}

class _DeletedRow extends StatelessWidget {
  const _DeletedRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final DeletedTitle entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return BentoCell(
      tone: selected ? BentoTone.high : BentoTone.mid,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.unit * 2, vertical: AppDimens.unit * 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppDimens.unit * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sourceLabel(entry.sourceName, entry.sourceId)}  ·  '
                  '${entry.chapterCount} ch  ·  ${entry.readCount} read',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppDimens.unit / 2),
                Wrap(
                  spacing: AppDimens.unit,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'deleted ${relativeDate(entry.deletedAt)}',
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    // The signal that matters when choosing: a backup you
                    // imported since still contains this title.
                    if (entry.seenSinceDelete) _SeenChip(entry: entry),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeenChip extends StatelessWidget {
  const _SeenChip({required this.entry});
  final DeletedTitle entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = entry.seenCount == 1
        ? 'in 1 backup since'
        : 'in ${entry.seenCount} backups since';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall!
            .copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

/// Persistent action bar: restore is the primary path, forgetting is secondary.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.busy,
    required this.onRestore,
    required this.onForget,
  });

  final int count;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppDimens.gutter, AppDimens.unit,
            AppDimens.gutter, AppDimens.unit * 2),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onForget,
                icon: const Icon(Icons.playlist_remove, size: 18),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: busy ? null : onRestore,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore, size: 18),
                label: Text('Restore $count'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so pull-to-refresh still works on an empty list.
    return ListView(
      padding: const EdgeInsets.all(AppDimens.cellPadding),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.delete_outline,
            size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppDimens.unit * 2),
        Center(
          child: Text('Nothing deleted', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppDimens.unit),
        Text(
          'Titles you delete are listed here, and skipped by future imports '
          'until you restore them.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium!
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppDimens.cellPadding),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.cloud_off_outlined,
            size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppDimens.unit * 2),
        Center(
          child: Text("Couldn't load the list",
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppDimens.unit),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall!
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppDimens.unit * 2),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
