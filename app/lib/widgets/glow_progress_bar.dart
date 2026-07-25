import 'package:flutter/material.dart';

/// Thin 4px reading-progress track with a subtle glow on the filled portion.
/// The fill animates implicitly to each new [value], so it both reveals softly
/// on first paint and glides between live updates (e.g. streamed imports).
class GlowProgressBar extends StatelessWidget {
  const GlowProgressBar({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 600),
  });

  /// Progress in [0, 1].
  final double value;

  /// How long the fill takes to animate to a new [value].
  final Duration duration;

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
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: clamped),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, fraction, _) => Container(
              height: 4,
              width: constraints.maxWidth * fraction,
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
          ),
        );
      },
    );
  }
}
