import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_accents.dart';
import 'entrance_fade.dart';

/// The mockup's circular progress ring: a track plus a rounded, glowing arc
/// that sweeps clockwise from 12 o'clock, with [center] laid over it. The sweep
/// animates implicitly to each new [value] (and snaps under reduce-motion).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.center,
    this.size = 128,
    this.strokeWidth = 8,
    this.color,
    this.accent,
    this.duration = const Duration(milliseconds: 900),
  });

  /// Progress in [0, 1].
  final double value;
  final Widget center;
  final double size;
  final double strokeWidth;

  /// Arc color; defaults to the scheme's secondary (indigo).
  final Color? color;

  /// Accent hue for the arc. Outranks [color] and adds the matching bloom.
  final VaultAccent? accent;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final arc = accent?.color ?? color ?? scheme.secondary;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: reduceMotion ? Duration.zero : duration,
        curve: kEntranceCurve,
        builder: (context, fraction, _) => CustomPaint(
          painter: _RingPainter(
            fraction: fraction,
            strokeWidth: strokeWidth,
            track: scheme.surfaceContainerHighest,
            arc: arc,
            // The ring is the dashboard's single largest accent surface, so it
            // carries the same bloom as GlowProgressBar rather than reading as
            // a flat stroke next to one.
            glow: accent != null,
          ),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.strokeWidth,
    required this.track,
    required this.arc,
    this.glow = false,
  });

  final double fraction;
  final double strokeWidth;
  final Color track;
  final Color arc;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = rect.center;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (fraction <= 0) return;
    final box = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * fraction;

    // Blurred underlay first, so the crisp arc sits on top of its own bloom.
    if (glow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = arc.withValues(alpha: AccentAlpha.glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawArc(box, -math.pi / 2, sweep, false, glowPaint);
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = arc;
    canvas.drawArc(box, -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.strokeWidth != strokeWidth ||
      old.track != track ||
      old.arc != arc ||
      old.glow != glow;
}
