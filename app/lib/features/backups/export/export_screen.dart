import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/entrance_fade.dart';
import '../../../widgets/glow_progress_bar.dart';
import '../../../widgets/pill_button.dart';
import 'export_controller.dart';
import 'export_options_step.dart';
import 'export_review_step.dart';
import 'export_scope_step.dart';
import 'export_widgets.dart';

/// Create a `.tachibk` backup out of the vault — the inverse of the import hub.
///
/// A three-step funnel (select → options → review) rather than one long form:
/// the scope builder alone is a screenful of chips, and stacking the include
/// switches and the review under it would bury the numbers that make the
/// selection legible. A persistent summary bar carries the live counts across
/// every step, so the effect of any choice is visible without going back.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Backup'),
        actions: [
          if (state.status == ExportStatus.editing &&
              state.step != ExportStep.select)
            IconButton(
              onPressed: controller.reset,
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Start over',
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (state.status) {
          ExportStatus.building => _BuildingBody(state: state),
          ExportStatus.saved => _SavedBody(state: state),
          ExportStatus.failed => _FailedBody(state: state),
          ExportStatus.editing => _EditingBody(state: state),
        },
      ),
    );
  }
}

/// The wizard proper: step bar, the current step's body, and the action bar.
class _EditingBody extends ConsumerWidget {
  const _EditingBody({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(exportControllerProvider.notifier);

    return Column(
      children: [
        ExportStepBar(current: state.step, onTap: controller.goTo),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: kEntranceCurve,
            // Out faster than in, so the incoming step never waits on the
            // outgoing one — the flow reads as forward motion, not a swap.
            switchOutCurve: Curves.easeIn,
            reverseDuration: const Duration(milliseconds: 140),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(state.step),
              child: switch (state.step) {
                ExportStep.select => const ExportScopeStep(),
                ExportStep.options => const ExportOptionsStep(),
                ExportStep.review => const ExportReviewStep(),
              },
            ),
          ),
        ),
        _ActionBar(state: state),
      ],
    );
  }
}

/// The persistent footer: what the scope covers right now, and how to move on.
///
/// Pinned rather than scrolled with the content — on the select step the list
/// of chips is long, and a count that scrolls off is a count nobody reads.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(exportControllerProvider.notifier);
    final last = state.step == ExportStep.last;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            AppDimens.unit * 1.5,
            AppDimens.gutter,
            AppDimens.unit * 1.5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExportScopeSummary(preview: state.preview),
              const SizedBox(height: AppDimens.unit * 1.5),
              Row(
                children: [
                  if (state.step != ExportStep.select)
                    TextButton.icon(
                      onPressed: controller.back,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  if (last)
                    PillButton(
                      label: 'Create backup',
                      icon: Icons.download,
                      onPressed: state.canBuild ? controller.buildAndSave : null,
                    )
                  else
                    PillButton(
                      label: 'Next',
                      icon: Icons.arrow_forward,
                      onPressed: state.canAdvance ? controller.next : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildingBody extends StatelessWidget {
  const _BuildingBody({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = state.preview.value;

    return ListView(
      padding: const EdgeInsets.all(AppDimens.gutter),
      children: [
        BentoCell(
          tone: BentoTone.high,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CellLabel('Creating backup'),
              const SizedBox(height: AppDimens.unit),
              Text(
                preview?.fileName ?? 'Building…',
                style: theme.textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppDimens.unit * 2),
              GlowProgressBar(value: state.progress ?? 0),
              const SizedBox(height: AppDimens.unit),
              Text(
                state.progress == null
                    // The server has to assemble and compress the whole file
                    // before the first byte ships, so there is genuinely
                    // nothing to report until then. Say so rather than
                    // animating a bar that means nothing.
                    ? 'Reading the vault and compressing…'
                    : 'Downloading — ${(state.progress! * 100).round()}%',
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedBody extends ConsumerWidget {
  const _SavedBody({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(exportControllerProvider.notifier);
    final result = state.result!;

    return ListView(
      padding: const EdgeInsets.all(AppDimens.gutter),
      children: [
        EntranceFade(
          child: BentoCell(
            tone: BentoTone.high,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NestedWell(
                  child: Row(
                    children: [
                      const AccentIconWell(icon: Icons.check_circle_outline),
                      const SizedBox(width: AppDimens.unit * 1.5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Backup created',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              '${groupedNumber(result.titles)} '
                              '${result.titles == 1 ? 'title' : 'titles'} · '
                              '${formatBytes(result.sizeBytes)}',
                              style: theme.textTheme.bodyMedium!
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimens.gutter),
                const CellLabel('Saved to'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  result.path,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimens.gutter),
                Text(
                  'Restore it from your reading app: Settings → Data and '
                  'storage → Restore backup.',
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppDimens.gutter),
                PillButton(
                  label: 'Create another',
                  icon: Icons.add,
                  onPressed: controller.reset,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FailedBody extends ConsumerWidget {
  const _FailedBody({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(exportControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.gutter),
      children: [
        BentoCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: AppDimens.unit),
                  Text('Backup failed', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: AppDimens.unit),
              Text(
                state.error ?? 'Something went wrong.',
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppDimens.gutter),
              Row(
                children: [
                  PillButton(
                    label: 'Try again',
                    icon: Icons.refresh,
                    onPressed: controller.buildAndSave,
                  ),
                  const SizedBox(width: AppDimens.unit),
                  TextButton(
                    // Keeps the scope: a failed build must not cost the user
                    // the selection they just built.
                    onPressed: controller.dismissError,
                    child: Text(
                      'Back to review',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
