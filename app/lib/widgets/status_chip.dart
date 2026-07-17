import 'package:flutter/material.dart';

/// Low-contrast capsule for genres/tags/status, per the design system:
/// background only slightly more saturated than the surface it sits on.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.emphasized = false});

  final String label;

  /// Emphasized chips (e.g. active filter) use the primary container tone.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: emphasized ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: emphasized ? scheme.primary : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
