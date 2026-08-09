import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/config/server_config.dart';
import '../../core/config/server_config_controller.dart';
import '../../core/format.dart';
import '../../data/updates/update_models.dart';
import '../../router.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/status_chip.dart';
import '../updates/changelog_view.dart';
import '../updates/update_card.dart';
import '../updates/update_controller.dart';

/// About & Updates — the app's own identity page.
///
/// Not a settings screen: Manga Vault deliberately has no in-app settings (the
/// server is compiled in). This is the one place that talks about the *app*
/// rather than the library — what version is installed, what changed, and how
/// to get the next one.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opening this screen is an explicit "tell me about updates", so it always
    // checks — the six-hour throttle governs the silent launch check, not this.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateControllerProvider.notifier).check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the "install unknown apps" Settings screen is the only
    // way that grant can change, and Android gives no callback for it. Re-check
    // on resume so the card drops its permission warning by itself.
    if (state == AppLifecycleState.resumed) {
      ref.read(updateControllerProvider.notifier).recheckPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedAppProvider);
    final history = ref.watch(releaseHistoryProvider);

    final cells = <Widget>[
      _IdentityCell(installed: installed.value),
      _ServerCell(config: ref.watch(serverConfigProvider)),
      const UpdateCard(),
      _HistoryCell(
        history: history,
        installed: installed.value,
        onRetry: () => ref.invalidate(releaseHistoryProvider),
      ),
      _TechnicalCell(installed: installed.value),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(releaseHistoryProvider);
          await ref.read(updateControllerProvider.notifier).check();
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            0,
            AppDimens.gutter,
            120,
          ),
          itemCount: cells.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gutter),
          itemBuilder: (context, index) => EntranceFade(
            delay: Duration(milliseconds: 70 * index),
            child: cells[index],
          ),
        ),
      ),
    );
  }
}

/// The wordmark cell. Sets the app's name in the display face, which is the
/// only place in the product that does — an about page is allowed one moment
/// of brand.
class _IdentityCell extends StatelessWidget {
  const _IdentityCell({required this.installed});

  final InstalledApp? installed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      tone: BentoTone.high,
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccentIconWell(
            icon: Icons.inventory_2_outlined,
            accent: VaultAccent.violet,
            size: 48,
            iconSize: 24,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          Text(
            'Manga\nVault',
            style: theme.textTheme.headlineLarge!.copyWith(height: 1.05),
          ),
          const SizedBox(height: AppDimens.unit + 4),
          Row(
            children: [
              StatusChip(
                installed?.display ?? 'Version unknown',
                accent: VaultAccent.violet,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit + 4),
          Text(
            'A personal archive for your manga and manhwa library. Backups '
            'from Mihon and its forks are consolidated into one vault that '
            'outlives the apps they came from.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Every published release, newest first. The installed one is expanded by
/// default and badged — so "what's new in the version I'm running" and "what
/// changed before that" are the same list, not two competing sections.
class _HistoryCell extends StatelessWidget {
  const _HistoryCell({
    required this.history,
    required this.installed,
    required this.onRetry,
  });

  final AsyncValue<List<AppRelease>> history;
  final InstalledApp? installed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCell(
      accent: VaultAccent.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AccentIconWell(
                icon: Icons.history_edu_outlined,
                accent: VaultAccent.cyan,
              ),
              const SizedBox(width: AppDimens.unit * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CellLabel('Changelog'),
                    const SizedBox(height: 2),
                    Text('Release history',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit * 2),
          switch (history) {
            AsyncData(:final value) when value.isEmpty => Text(
                'No releases published yet.',
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            AsyncData(:final value) => Column(
                children: [
                  for (final release in value)
                    _ReleaseTile(
                      release: release,
                      isInstalled: installed != null &&
                          release.version == installed!.version,
                      initiallyExpanded: installed != null &&
                          release.version == installed!.version,
                    ),
                ],
              ),
            AsyncError() => Row(
                children: [
                  Expanded(
                    child: Text(
                      'Could not load the changelog.',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppDimens.unit * 2),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          },
        ],
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.isInstalled,
    required this.initiallyExpanded,
  });

  final AppRelease release;
  final bool isInstalled;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = release.publishedAt;
    final subtitle = [
      if (published != null) relativeDate(published.millisecondsSinceEpoch),
      if (release.notes.changeCount > 0)
        '${release.notes.changeCount} '
            '${release.notes.changeCount == 1 ? 'change' : 'changes'}',
    ].join(' · ');

    return Theme(
      // ExpansionTile draws its own dividers and a Material-default indigo
      // header; strip both so it reads as part of the cell, not a list item
      // pasted into one.
      data: theme.copyWith(
        dividerColor: Colors.transparent,
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 0,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(
          bottom: AppDimens.unit * 2,
          right: AppDimens.unit,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: theme.colorScheme.onSurfaceVariant,
        collapsedIconColor: theme.colorScheme.onSurfaceVariant,
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Version ${release.version.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge!
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (isInstalled) ...[
              const SizedBox(width: AppDimens.unit),
              const StatusChip('Installed', accent: VaultAccent.emerald),
            ],
          ],
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
        children: [ChangelogView(notes: release.notes)],
      ),
    );
  }
}

/// The server this device is connected to, and the two ways off it.
///
/// Manga Vault has no account, so this cell is the whole of "who am I signed
/// in as". It names the server and nothing else — the token is a credential
/// and is never rendered, not even masked.
class _ServerCell extends ConsumerWidget {
  const _ServerCell({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return BentoCell(
      accent: VaultAccent.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AccentIconWell(
                icon: Icons.dns_outlined,
                accent: VaultAccent.emerald,
              ),
              const SizedBox(width: AppDimens.unit * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CellLabel('Connected to'),
                    const SizedBox(height: 2),
                    Text(
                      config.displayHost,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.unit + 4),
          Text(
            'Your library lives on this server. Manga Vault has no cloud and '
            'no account — the app only ever talks to the address you gave it.',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.unit * 2),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillButton(
                label: 'Change server',
                icon: Icons.swap_horiz,
                accent: VaultAccent.emerald,
                onPressed: () => context.go(kChangeServerRoute),
              ),
              TextButton(
                onPressed: () => _confirmDisconnect(context, ref),
                child: Text(
                  'Disconnect',
                  style: TextStyle(color: VaultAccent.rose.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect from this server?'),
        // Say plainly what is and isn't destroyed. "Disconnect" next to a
        // library is alarming, and the alarming reading is the wrong one.
        content: const Text(
          'This device will forget the address and token, and the offline copy '
          'of your library will be deleted from the phone.\n\n'
          'Nothing on the server is touched — reconnect and it all comes back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Disconnect',
              style: TextStyle(color: VaultAccent.rose.color),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The router guard sees `isConfigured` go false and moves to setup.
    await ref.read(serverConfigProvider.notifier).clear();
  }
}

/// Build facts, plus the links off-app.
class _TechnicalCell extends StatelessWidget {
  const _TechnicalCell({required this.installed});

  final InstalledApp? installed;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      accent: VaultAccent.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CellLabel('Build'),
          const SizedBox(height: AppDimens.unit + 4),
          // Version deliberately isn't repeated here — the identity cell at the
          // top of this same screen already states it, and saying it twice
          // invites the two to disagree.
          _InfoRow(
            label: 'Package',
            value: installed?.packageName ?? 'dev.mangavault.mangavault',
          ),
          _InfoRow(
            label: 'Build',
            value: installed?.buildNumber ?? 'unknown',
          ),
          const SizedBox(height: AppDimens.unit * 2),
          const Divider(height: 1),
          const SizedBox(height: AppDimens.unit),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _open(context, AppConfig.releasesPageUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('All releases on GitHub'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.unit),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
