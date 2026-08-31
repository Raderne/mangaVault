import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/sources/source_models.dart';
import '../../data/sources/source_repository.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pressable.dart';
import '../../widgets/status_chip.dart';

/// Everything the extension repositories publish — about 1,380 entries.
///
/// Deliberately **not** mirrored to the device: it is not vault data, it
/// changes daily, and this screen is opened rarely. So it pages over the
/// server and shows an honest empty state when offline, rather than a stale
/// snapshot pretending to be current.
///
/// The app cannot install any of these — they are Android APKs of compiled
/// Kotlin, and MangaVault is a Flutter client talking to a Node server. What it
/// can do is tell you which ones your library depends on and hand you the
/// download link to install in a reading app yourself.
class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  static const _pageSize = 40;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ExtensionEntry> _items = [];
  Timer? _debounce;
  String _query = '';
  bool _includeNsfw = false;
  bool _loading = false;
  bool _hasMore = true;
  int _total = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      unawaited(_load());
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim();
      unawaited(_load(reset: true));
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final page = await ref.read(sourceRepositoryProvider).extensions(
            query: _query,
            includeNsfw: _includeNsfw,
            offset: reset ? 0 : _items.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _total = page.total;
        _hasMore = _items.length < page.total;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            icon: Icon(
              _includeNsfw ? Icons.visibility : Icons.visibility_off_outlined,
            ),
            tooltip: _includeNsfw ? 'Hide adult sources' : 'Show adult sources',
            onPressed: () {
              setState(() => _includeNsfw = !_includeNsfw);
              unawaited(_load(reset: true));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.gutter,
              AppDimens.unit,
              AppDimens.gutter,
              AppDimens.unit,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search extensions',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.gutter,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${groupedNumber(_total)} extensions',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't reach the server",
        body: 'The extension list lives on your server and is not stored on '
            'this device.',
        actionLabel: 'Retry',
        onAction: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        title: 'Nothing matches',
        body: _query.isEmpty
            ? 'No repository has been synced yet. Pull to refresh your sources '
                'and try again.'
            : 'No extension called "$_query".',
        actionLabel: 'Clear search',
        onAction: () {
          _searchController.clear();
          _onQueryChanged('');
        },
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.gutter,
        AppDimens.unit,
        AppDimens.gutter,
        AppDimens.gutter * 2,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.unit + 4),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(AppDimens.gutter),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entry = _items[index];
        return _ExtensionRow(key: ValueKey(entry.packageName), entry: entry);
      },
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  const _ExtensionRow({super.key, required this.entry});

  final ExtensionEntry entry;

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: entry.apkUrl));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Download link copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only extensions the library actually depends on get an accent, so the
    // list reads as "yours" versus "everything else" at a glance.
    final inUse = entry.titleCount > 0;

    return Pressable(
      onTap: entry.apkUrl.isEmpty ? null : () => _copyLink(context),
      child: BentoCell(
        accent: inUse ? VaultAccent.violet : null,
        padding: const EdgeInsets.all(AppDimens.unit * 2),
        child: Row(
          children: [
            _ExtensionIcon(entry: entry),
            const SizedBox(width: AppDimens.unit * 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${entry.versionName} · ${entry.sourceCount} '
                    '${entry.sourceCount == 1 ? 'source' : 'sources'}'
                    '${inUse ? ' · ${groupedNumber(entry.titleCount)} of your titles' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.isNsfw) ...[
                    const SizedBox(height: 6),
                    const StatusChip('ADULT', accent: VaultAccent.rose),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            Icon(
              Icons.copy_all_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtensionIcon extends StatelessWidget {
  const _ExtensionIcon({required this.entry});

  final ExtensionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.extension_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: entry.iconUrl.isEmpty
            ? fallback
            : Image.network(
                entry.iconUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gutter * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppDimens.unit * 2),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.unit),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.unit * 2),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
