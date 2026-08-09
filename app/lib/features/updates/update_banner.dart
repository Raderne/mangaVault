import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/pressable.dart';
import 'update_controller.dart';

/// Route of the About & Updates screen. Nested under the Dashboard branch so
/// opening it keeps the Dashboard tab selected and back returns to it.
const String kAboutRoute = '/about';

/// App-bar entry point to [kAboutRoute], badged when an update is waiting.
///
/// The badge is the whole reason this is a widget rather than a plain
/// `IconButton`: the About screen is otherwise easy to forget, and an update
/// nobody notices is an update nobody installs.
class AboutAction extends ConsumerWidget {
  const AboutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final hasUpdate = switch (ref.read(updateControllerProvider)) {
      UpdateAvailable() || UpdateReady() => !controller.isSkipped,
      _ => false,
    };

    return IconButton(
      tooltip: hasUpdate ? 'Update available' : 'About Manga Vault',
      onPressed: () => context.go(kAboutRoute),
      icon: Badge(
        isLabelVisible: hasUpdate,
        backgroundColor: VaultAccent.violet.color,
        smallSize: 8,
        child: const Icon(Icons.info_outline),
      ),
    );
  }
}

/// Slim dashboard banner announcing a waiting update.
///
/// Mirrors the cover-archive and sync banners: it slides in above the grid
/// rather than covering it, and it is dismissible — this is an archive tool,
/// not a storefront, so the update never blocks the library behind it.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final show = controller.shouldPromptBanner;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              // Top-only: the banner rides inside the dashboard's first list
              // slot, and the list's own separator supplies the gap below. A
              // bottom pad here would leave a double gutter when it collapses.
              padding: const EdgeInsets.only(top: AppDimens.gutter),
              child: _BannerBody(
                version: state.release?.version.name ?? '',
                isReady: state is UpdateReady,
                onOpen: () => context.go(kAboutRoute),
                onDismiss: controller.dismissBanner,
              ),
            ),
    );
  }
}

class _BannerBody extends StatelessWidget {
  const _BannerBody({
    required this.version,
    required this.isReady,
    required this.onOpen,
    required this.onDismiss,
  });

  final String version;
  final bool isReady;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = VaultAccent.violet;

    return Pressable(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.unit * 2,
          AppDimens.unit + 4,
          AppDimens.unit,
          AppDimens.unit + 4,
        ),
        decoration: BoxDecoration(
          gradient: accentWash(accent),
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppDimens.coverRadius),
          border: Border.all(
            color: accent.color.withValues(alpha: AccentAlpha.border),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isReady ? Icons.install_mobile : Icons.download_for_offline,
              size: 20,
              color: accent.color,
            ),
            const SizedBox(width: AppDimens.unit + 4),
            Expanded(
              // Single Text: the row also holds two icons, and a two-part
              // label would be the thing that overflows at a large text scale.
              child: Text(
                isReady
                    ? 'Version $version is ready to install'
                    : 'Version $version is available',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              icon: Icon(
                Icons.close,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
