import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/updates/update_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/glow_progress_bar.dart';
import '../../widgets/pill_button.dart';
import 'changelog_view.dart';
import 'update_controller.dart';

/// The updater's whole lifecycle in one bento cell.
///
/// Hue carries the state so it is legible before it is read: violet is the way
/// forward (checking, available, downloading — the same hue the archive hero
/// and the import way-in use), emerald is a good resting place (up to date,
/// downloaded), amber is "you need to do something first", rose is a failure.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key, this.showChangelog = true});

  /// The About screen shows the incoming release's notes inline; the dashboard
  /// banner does not.
  final bool showChangelog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);

    return switch (state) {
      UpdateIdle() => _CheckPrompt(onCheck: () => controller.check()),
      UpdateChecking() => const _CheckingCell(),
      UpdateUpToDate(:final checkedAt) => _UpToDateCell(
          checkedAt: checkedAt,
          onCheck: () => controller.check(),
        ),
      UpdateAvailable(:final available) => _AvailableCell(
          release: available,
          showChangelog: showChangelog,
          skipped: controller.isSkipped,
          onDownload: controller.download,
          onSkip: controller.skipCurrent,
        ),
      UpdateDownloading() => _DownloadingCell(
          state: state,
          onCancel: controller.cancelDownload,
        ),
      UpdateReady(:final available, :final needsPermission) => _ReadyCell(
          release: available,
          needsPermission: needsPermission,
          onInstall: controller.install,
          onOpenSettings: () async {
            final opened = await controller.openInstallSettings();
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Open Settings › Apps › Manga Vault › Install unknown apps.',
                  ),
                ),
              );
            }
          },
          onDiscard: controller.discardDownload,
        ),
      UpdateFailed(:final message, :final isOffline) => _FailedCell(
          message: message,
          isOffline: isOffline,
          onRetry: () => controller.check(),
        ),
    };
  }
}

/// Shared header: icon well, uppercase state label, and a headline.
class _UpdateHeader extends StatelessWidget {
  const _UpdateHeader({
    required this.icon,
    required this.label,
    required this.title,
    required this.accent,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String title;
  final VaultAccent accent;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccentIconWell(icon: icon, accent: accent),
        const SizedBox(width: AppDimens.unit * 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall!
                    .copyWith(color: accent.color),
              ),
              const SizedBox(height: 2),
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _CheckPrompt extends StatelessWidget {
  const _CheckPrompt({required this.onCheck});

  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _UpdateHeader(
            icon: Icons.system_update_alt,
            label: 'Updates',
            title: 'Check for a new version',
            subtitle: 'Manga Vault updates from GitHub Releases.',
            accent: VaultAccent.violet,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          PillButton(
            label: 'Check now',
            icon: Icons.refresh,
            accent: VaultAccent.violet,
            onPressed: onCheck,
          ),
        ],
      ),
    );
  }
}

class _CheckingCell extends StatelessWidget {
  const _CheckingCell();

  @override
  Widget build(BuildContext context) {
    return const BentoCell(
      accent: VaultAccent.violet,
      child: _UpdateHeader(
        icon: Icons.system_update_alt,
        label: 'Updates',
        title: 'Checking for updates…',
        accent: VaultAccent.violet,
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _UpToDateCell extends StatelessWidget {
  const _UpToDateCell({required this.checkedAt, required this.onCheck});

  final DateTime checkedAt;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return BentoCell(
      accent: VaultAccent.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateHeader(
            icon: Icons.verified_outlined,
            label: 'Up to date',
            title: 'You have the latest version',
            subtitle:
                'Checked ${relativeDate(checkedAt.millisecondsSinceEpoch)}.',
            accent: VaultAccent.emerald,
          ),
          const SizedBox(height: AppDimens.unit),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCheck,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Check again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableCell extends StatelessWidget {
  const _AvailableCell({
    required this.release,
    required this.showChangelog,
    required this.skipped,
    required this.onDownload,
    required this.onSkip,
  });

  final AppRelease release;
  final bool showChangelog;
  final bool skipped;
  final VoidCallback onDownload;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (release.apkBytes > 0) formatBytes(release.apkBytes),
      if (release.publishedAt != null)
        relativeDate(release.publishedAt!.millisecondsSinceEpoch),
    ].join(' · ');

    return BentoCell(
      tone: BentoTone.high,
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateHeader(
            icon: Icons.download_for_offline_outlined,
            label: skipped ? 'Update skipped' : 'Update available',
            title: 'Version ${release.version.name}',
            subtitle: meta.isEmpty ? null : meta,
            accent: VaultAccent.violet,
          ),
          if (showChangelog && !release.notes.isEmpty) ...[
            const SizedBox(height: AppDimens.unit * 2),
            const Divider(height: 1),
            const SizedBox(height: AppDimens.unit * 2),
            const CellLabel("What's new"),
            const SizedBox(height: AppDimens.unit + 4),
            ChangelogView(notes: release.notes),
          ],
          const SizedBox(height: AppDimens.unit * 2.5),
          if (!release.isInstallable)
            Text(
              'This release has no APK attached. Open it on GitHub to '
              'download manually.',
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: VaultAccent.amber.color),
            )
          else
            Wrap(
              spacing: AppDimens.unit,
              runSpacing: AppDimens.unit,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillButton(
                  label: 'Download update',
                  icon: Icons.download,
                  accent: VaultAccent.violet,
                  onPressed: onDownload,
                ),
                if (!skipped)
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Skip this version'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DownloadingCell extends StatelessWidget {
  const _DownloadingCell({required this.state, required this.onCancel});

  final UpdateDownloading state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = state.fraction;
    final percent = fraction == null ? null : (fraction * 100).round();
    // One single-line Text, never a Row of pieces: a lone Text cannot overflow,
    // and the byte counts change width on every frame of the download.
    final progressLine = state.total > 0
        ? '${formatBytes(state.received)} of ${formatBytes(state.total)}'
            '${percent == null ? '' : '  ·  $percent%'}'
        : '${formatBytes(state.received)} downloaded';

    return BentoCell(
      tone: BentoTone.high,
      accent: VaultAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateHeader(
            icon: Icons.downloading,
            label: 'Downloading',
            title: 'Version ${state.available.version.name}',
            accent: VaultAccent.violet,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          // An unknown content length gets an indeterminate bar rather than one
          // frozen at zero, which reads as a stall.
          if (fraction == null)
            const LinearProgressIndicator(minHeight: 4)
          else
            GlowProgressBar(
              value: fraction,
              accent: VaultAccent.violet,
              // Fast: the bar is following real bytes, not easing into a
              // finished number, so a long tween would lag behind the truth.
              duration: const Duration(milliseconds: 220),
            ),
          const SizedBox(height: AppDimens.unit + 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  progressLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadyCell extends StatelessWidget {
  const _ReadyCell({
    required this.release,
    required this.needsPermission,
    required this.onInstall,
    required this.onOpenSettings,
    required this.onDiscard,
  });

  final AppRelease release;
  final bool needsPermission;
  final VoidCallback onInstall;
  final VoidCallback onOpenSettings;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = needsPermission ? VaultAccent.amber : VaultAccent.emerald;

    return BentoCell(
      tone: BentoTone.high,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateHeader(
            icon: needsPermission
                ? Icons.lock_open_outlined
                : Icons.task_alt_outlined,
            label: needsPermission ? 'Permission needed' : 'Ready to install',
            title: 'Version ${release.version.name}',
            subtitle: needsPermission
                ? null
                : 'Downloaded and ready. Android will ask you to confirm.',
            accent: accent,
          ),
          if (needsPermission) ...[
            const SizedBox(height: AppDimens.unit * 2),
            NestedWell(
              accent: VaultAccent.amber,
              child: Text(
                'Android blocks apps from installing other apps until you '
                'allow it. Turn on "Install unknown apps" for Manga Vault, '
                'then come back and tap Install.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppDimens.unit * 2.5),
          Wrap(
            spacing: AppDimens.unit,
            runSpacing: AppDimens.unit,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (needsPermission)
                PillButton(
                  label: 'Open settings',
                  icon: Icons.settings_outlined,
                  accent: VaultAccent.amber,
                  onPressed: onOpenSettings,
                ),
              PillButton(
                label: needsPermission ? 'Try again' : 'Install now',
                icon: needsPermission ? Icons.refresh : Icons.install_mobile,
                accent: needsPermission ? null : VaultAccent.emerald,
                onPressed: onInstall,
              ),
              TextButton(onPressed: onDiscard, child: const Text('Discard')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FailedCell extends StatelessWidget {
  const _FailedCell({
    required this.message,
    required this.isOffline,
    required this.onRetry,
  });

  final String message;

  /// Offline is a condition, not a fault — it gets amber, not the rose the
  /// design reserves for things that actually went wrong.
  final bool isOffline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = isOffline ? VaultAccent.amber : VaultAccent.rose;
    return BentoCell(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateHeader(
            icon: isOffline ? Icons.cloud_off_outlined : Icons.error_outline,
            label: isOffline ? 'Offline' : 'Update check failed',
            // The message goes in the subtitle: it is a full sentence, and a
            // sentence set at title size wraps into a heading-shaped block.
            title: isOffline ? "Can't reach GitHub" : 'Something went wrong',
            subtitle: message,
            accent: accent,
          ),
          const SizedBox(height: AppDimens.unit * 2),
          PillButton(
            label: 'Try again',
            icon: Icons.refresh,
            accent: accent,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
