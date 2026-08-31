import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/sources/source_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pressable.dart';
import 'source_detail_sheet.dart';
import 'source_health_controller.dart';

/// Where the vault's titles actually come from, and whether those places still
/// work.
///
/// The screen exists because a `manga.source_id` is a 64-bit number and nothing
/// else: until the extension registry landed, a library could not tell you that
/// 366 of its titles sit on a site whose covers have all stopped loading. It
/// ranks by trouble rather than alphabetically, because the only reason to open
/// it is to find what needs moving.
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  @override
  void initState() {
    super.initState();
    // A daily health pass runs on the server; attach to one already going so
    // the screen shows live progress it never started.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sourceHealthControllerProvider.notifier).adopt();
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(vaultSourcesProvider);
    await ref.read(vaultSourcesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vaultSourcesProvider);
    final health = ref.watch(sourceHealthControllerProvider);

    // Re-read the list as verdicts land, so rows re-rank while the run goes.
    ref.listen(sourceHealthControllerProvider, (previous, next) {
      if (previous?.done != next.done || previous?.phase != next.phase) {
        ref.invalidate(vaultSourcesProvider);
      }
    });

    final sources = async.value ?? const <VaultSource>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: 'Browse extensions',
            onPressed: () => context.push('/library/extensions'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.gutter,
                AppDimens.gutter,
                AppDimens.gutter,
                AppDimens.unit,
              ),
              sliver: SliverToBoxAdapter(
                child: _SummaryCell(sources: sources, health: health),
              ),
            ),
            if (async.isLoading && sources.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (async.hasError && sources.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: "Couldn't load your sources",
                  body: 'The server is unreachable and nothing has been '
                      'mirrored to this device yet.',
                  actionLabel: 'Retry',
                  onAction: _refresh,
                ),
              )
            else if (sources.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.hub_outlined,
                  title: 'No sources yet',
                  body: 'Import a backup and the sources its titles came from '
                      'will be listed here.',
                  actionLabel: 'Go to Backups',
                  onAction: () => context.go('/backups'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.gutter,
                  0,
                  AppDimens.gutter,
                  AppDimens.gutter * 2,
                ),
                sliver: SliverList.separated(
                  itemCount: sources.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppDimens.unit + 4),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    return EntranceFade(
                      // Capped so a library with thirty sources does not make
                      // the last row wait two seconds to appear.
                      delay: Duration(milliseconds: 40 * (index.clamp(0, 8))),
                      child: _SourceRow(
                        key: ValueKey(source.sourceId),
                        source: source,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Header: what the library depends on, and the button that re-checks it.
class _SummaryCell extends ConsumerWidget {
  const _SummaryCell({required this.sources, required this.health});

  final List<VaultSource> sources;
  final SourceHealthState health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trouble = sources.where((s) => s.health.needsAttention).toList();
    final affected =
        trouble.fold<int>(0, (sum, s) => sum + s.titleCount);
    final accent = trouble.isEmpty ? VaultAccent.emerald : VaultAccent.amber;

    return BentoCell(
      tone: BentoTone.high,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('SOURCE HEALTH'),
          const SizedBox(height: AppDimens.unit),
          Text(
            trouble.isEmpty
                ? '${groupedNumber(sources.length)} sources, all working'
                : '${groupedNumber(trouble.length)} of '
                    '${groupedNumber(sources.length)} need attention',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            trouble.isEmpty
                ? 'Nothing in your library is stranded.'
                : '${groupedNumber(affected)} titles are on a source that is '
                    'blocked, unreachable or no longer published.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          if (health.isRunning) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    health.cancelling
                        ? 'Stopping…'
                        : 'Checking ${health.done} of ${health.total}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: health.cancelling
                      ? null
                      : () => ref
                          .read(sourceHealthControllerProvider.notifier)
                          .cancel(),
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.unit),
            GlowProgressBar(value: health.fraction, accent: accent),
          ] else if (health.isDone)
            Row(
              children: [
                Expanded(
                  child: Text(
                    health.cancelled
                        ? 'Check stopped after ${health.done} sources'
                        : '${health.ok} working · ${health.degraded} degraded '
                            '· ${health.unhealthy} not working',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss',
                  onPressed: () => ref
                      .read(sourceHealthControllerProvider.notifier)
                      .dismiss(),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                label: 'Check sources',
                icon: Icons.wifi_tethering,
                accent: accent,
                onPressed: () =>
                    ref.read(sourceHealthControllerProvider.notifier).start(),
              ),
            ),
        ],
      ),
    );
  }
}

/// One source: what it is, how many titles depend on it, and its verdict.
class _SourceRow extends StatelessWidget {
  const _SourceRow({super.key, required this.source});

  final VaultSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = source.health.accent;

    return Pressable(
      onTap: () => showSourceDetailSheet(context, source),
      child: BentoCell(
        accent: source.health.needsAttention ? accent : null,
        padding: const EdgeInsets.all(AppDimens.unit * 2),
        child: Row(
          children: [
            _SourceIcon(source: source),
            const SizedBox(width: AppDimens.unit * 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name.isEmpty ? source.sourceId : source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (source.lang.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          source.lang.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${groupedNumber(source.titleCount)} '
                    '${source.titleCount == 1 ? 'title' : 'titles'}'
                    '${source.healthNote == null ? '' : ' · ${source.healthNote}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            HealthChip(health: source.health),
          ],
        ),
      ),
    );
  }
}

/// Verdict badge. Icon **and** word, never colour alone.
class HealthChip extends StatelessWidget {
  const HealthChip({super.key, required this.health, this.compact = true});

  final SourceHealth health;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = health.accent;
    final color = accent?.color ?? theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(health.icon, size: 16, color: color),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(
            health.label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}

/// The extension's icon, falling back to its initial.
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.source});

  final VaultSource source;

  @override
  Widget build(BuildContext context) {
    final letter = source.name.trim().isEmpty
        ? '?'
        : source.name.trim().characters.first.toUpperCase();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: source.iconUrl == null
            ? _IconFallback(letter: letter)
            : Image.network(
                source.iconUrl!,
                fit: BoxFit.cover,
                // Repository icons come from a public CDN and are cosmetic —
                // a failure must never look like an error.
                errorBuilder: (_, _, _) => _IconFallback(letter: letter),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _IconFallback(letter: letter),
              ),
      ),
    );
  }
}

class _IconFallback extends StatelessWidget {
  const _IconFallback({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          letter,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
