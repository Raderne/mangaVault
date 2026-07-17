import 'package:flutter/material.dart';

/// Thin 4px reading-progress track with a subtle glow on the filled portion.
class GlowProgressBar extends StatelessWidget {
  const GlowProgressBar({super.key, required this.value});

  /// Progress in [0, 1].
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.centerLeft,
          child: Container(
            height: 4,
            width: constraints.maxWidth * clamped,
            decoration: BoxDecoration(
              color: scheme.secondary,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: scheme.secondary.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
