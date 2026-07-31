import 'package:flutter/material.dart';

/// Low-contrast capsule for genres/tags/status, per the design system:
/// background only slightly more saturated than the surface it sits on.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.emphasized = false,
    this.onTap,
    this.selected = false,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.secondaryContainer
        : emphasized
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : emphasized
            ? scheme.primary
            : scheme.onSurfaceVariant;

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

    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: content,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: selected
              ? BorderSide(color: scheme.secondary, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
