import 'package:flutter/material.dart';

import '../theme/app_accents.dart';

/// Low-contrast capsule for genres/tags/status, per the design system:
/// background only slightly more saturated than the surface it sits on.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.emphasized = false,
    this.onTap,
    this.selected = false,
    this.accent,
  });

  final String label;

  /// Emphasized chips (e.g. the MERGED badge) use the primary container tone.
  final bool emphasized;

  /// When set the chip becomes a toggle — used for the import review's
  /// new/merged/skipped counts, which filter the list below them.
  final VoidCallback? onTap;

  /// Active state of a tappable chip. Reads as *chosen*, so it outranks
  /// [emphasized] and carries a ring the flat tones can't provide.
  final bool selected;

  /// Hue for chips whose label carries an outcome (NEW / MERGED / SKIPPED).
  /// Ranks below [selected]: a chip the user has actively chosen must still
  /// read as chosen, whatever it means.
  final VaultAccent? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = this.accent;
    final Color background;
    final Color foreground;
    if (selected) {
      background = scheme.secondaryContainer;
      foreground = scheme.onSecondaryContainer;
    } else if (accent != null) {
      background = accent.color.withValues(alpha: AccentAlpha.fill);
      foreground = accent.color;
    } else if (emphasized) {
      background = scheme.primaryContainer;
      foreground = scheme.primary;
    } else {
      background = scheme.surfaceContainerHigh;
      foreground = scheme.onSurfaceVariant;
    }

    final content = Padding(
      // Tappable chips are taller: a 24pt pill is a poor touch target.
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: onTap == null ? 6 : 9,
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: foreground),
      ),
    );

    // An accent chip is a translucent fill, so it needs the hairline to hold
    // its shape against a cell that may already be washed in another hue.
    final side = selected
        ? BorderSide(color: scheme.secondary, width: 1.5)
        : accent != null
            ? BorderSide(color: accent.color.withValues(alpha: AccentAlpha.border))
            : BorderSide.none;

    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: side == BorderSide.none ? null : Border.fromBorderSide(side),
        ),
        child: content,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        shape: StadiumBorder(side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
