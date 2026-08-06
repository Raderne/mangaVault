import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/export/export_models.dart';
import '../../../theme/app_dimens.dart';
import '../../../widgets/bento_cell.dart';
import '../../../widgets/entrance_fade.dart';
import '../../../widgets/pressable.dart';
import '../../../widgets/selectable_chip.dart';
import 'export_controller.dart';

/// Where the wizard is, and how far there is to go.
///
/// Steps are tappable *backwards* only: revisiting a decision you've made is
/// free, but skipping ahead past one you haven't is how a user ends up
/// exporting a scope they never looked at.
class ExportStepBar extends StatelessWidget {
  const ExportStepBar({
    super.key,
    required this.current,
    required this.onTap,
  });

  final ExportStep current;
  final ValueChanged<ExportStep> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.gutter,
        vertical: AppDimens.unit,
      ),
      child: Row(
        children: [
          for (final step in ExportStep.values) ...[
            if (step.index > 0) const SizedBox(width: AppDimens.unit),
            Expanded(
              child: _StepSegment(
                step: step,
                current: current,
                onTap: step.index < current.index ? () => onTap(step) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepSegment extends StatelessWidget {
  const _StepSegment({
    required this.step,
    required this.current,
    required this.onTap,
  });

  final ExportStep step;
  final ExportStep current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = step.index < current.index;
    final active = step == current;

    final rail = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: kEntranceCurve,
      height: 3,
      decoration: BoxDecoration(
        color: active || done ? scheme.secondary : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
    );

    final label = Row(
      children: [
        // A completed step gets a check as well as a color, so the state does
        // not rest on color alone.
        if (done) ...[
          Icon(Icons.check, size: 12, color: scheme.secondary),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            step.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall!.copyWith(
              color: active
                  ? scheme.onSurface
                  : done
                      ? scheme.secondary
                      : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    final content = Semantics(
      button: onTap != null,
      selected: active,
      label: '${step.label} step${done ? ', completed' : ''}',
      child: Padding(
        // Keeps the tap target ≥44dp tall even though the rail is 3dp.
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [rail, const SizedBox(height: AppDimens.unit), label],
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.unit),
      child: content,
    );
  }
}

/// A full-width scope preset: icon well, name, what it covers, and a radio mark.
///
/// A row rather than a tile grid on purpose — three tiles across a 375dp phone
/// leaves ~109dp each, which forces the counts (the thing being compared) into
/// two lines of 10pt text.
class ExportPresetTile extends StatelessWidget {
  const ExportPresetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: kEntranceCurve,
          padding: const EdgeInsets.all(AppDimens.unit * 2),
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer.withValues(alpha: 0.35)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppDimens.coverRadius),
            border: Border.all(
              color: selected
                  ? scheme.secondary
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AccentIconWell(icon: icon, size: 40, iconSize: 20),
              const SizedBox(width: AppDimens.unit * 1.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.unit),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? scheme.secondary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled block of selectable chips over one facet.
///
/// Long lists (sources, in a vault with 25+ of them) collapse to the first
/// [collapseAfter] entries, which are the highest-count ones — the server sorts
/// them that way, so the chips you actually want are the ones on screen.
class ExportFacetSection extends StatefulWidget {
  const ExportFacetSection({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.emptyHint,
    this.collapseAfter = 8,
  });

  final String label;
  final List<ExportFacetOption> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? emptyHint;
  final int collapseAfter;

  @override
  State<ExportFacetSection> createState() => _ExportFacetSectionState();
}

class _ExportFacetSectionState extends State<ExportFacetSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.options;

    if (all.isEmpty) {
      if (widget.emptyHint == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CellLabel(widget.label),
          const SizedBox(height: AppDimens.unit),
          Text(
            widget.emptyHint!,
            style: theme.textTheme.bodyMedium!
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    // A selected chip always stays visible, even if it sits past the cut — a
    // filter you can't see is a filter you can't remove.
    final hidden = all.length - widget.collapseAfter;
    final shown = _expanded || hidden <= 0
        ? all
        : [
            ...all.take(widget.collapseAfter),
            ...all
                .skip(widget.collapseAfter)
                .where((o) => widget.selected.contains(o.id)),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: CellLabel(widget.label)),
            if (widget.selected.isNotEmpty)
              Text(
                '${widget.selected.length} selected',
                style: theme.textTheme.labelSmall!
                    .copyWith(color: theme.colorScheme.secondary),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.unit * 1.5),
        Wrap(
          spacing: AppDimens.unit,
          runSpacing: AppDimens.unit,
          children: [
            for (final option in shown)
              SelectableChip(
                label: option.label,
                trailing: '${option.count}',
                selected: widget.selected.contains(option.id),
                onTap: () => widget.onToggle(option.id),
              ),
          ],
        ),
        if (hidden > 0) ...[
          const SizedBox(height: AppDimens.unit),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(_expanded ? 'Show less' : 'Show $hidden more'),
          ),
        ],
      ],
    );
  }
}

/// One number in the review grid.
class ExportStat extends StatelessWidget {
  const ExportStat({
    super.key,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;

  /// Dimmed when the option behind it is switched off — a zero that is a
  /// *choice* must not read like a zero that is a problem.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium!.copyWith(
            color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall!.copyWith(
            color: muted
                ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The persistent readout above the wizard's actions: what the current scope
/// would export, right now.
///
/// It is the reason the whole flow feels answerable — every chip tap moves this
/// number, so the effect of a filter is visible before committing to it.
class ExportScopeSummary extends StatelessWidget {
  const ExportScopeSummary({super.key, required this.preview});

  final AsyncValue<ExportPreview> preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return preview.when(
      loading: () => Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppDimens.unit),
          Text(
            'Counting…',
            style: theme.textTheme.bodyMedium!
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      error: (e, _) => Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.error),
          const SizedBox(width: AppDimens.unit),
          Expanded(
            child: Text(
              '$e',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium!.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
      data: (p) {
        if (p.isEmpty) {
          return Row(
            children: [
              Icon(Icons.filter_alt_off_outlined, size: 16, color: scheme.error),
              const SizedBox(width: AppDimens.unit),
              Expanded(
                child: Text(
                  'Nothing matches this selection',
                  style:
                      theme.textTheme.bodyMedium!.copyWith(color: scheme.error),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: groupedNumber(p.titles),
                      style: theme.textTheme.bodyLarge!
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: p.titles == 1 ? ' title' : ' titles',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (p.chapters > 0)
                      TextSpan(
                        text: ' · ${groupedNumber(p.chapters)} chapters',
                        style: theme.textTheme.bodyMedium!
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            Text(
              '~${formatBytes(p.estimatedBytes)}',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}
