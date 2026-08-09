import 'package:flutter/material.dart';

import '../theme/app_accents.dart';

/// Primary action button: pill-shaped, indigo fill, per the design system.
///
/// With an [accent] it takes that hue instead — a solid fill, since a call to
/// action is the one place in a cell that should out-shout the cell's own
/// wash. Text is drawn on the slate background color rather than white, which
/// is what keeps a saturated pill from glaring on a dark screen.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.accent,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final VaultAccent? accent;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    final style = accent == null
        ? null
        : FilledButton.styleFrom(
            backgroundColor: accent.color,
            foregroundColor: Theme.of(context).colorScheme.surface,
            disabledBackgroundColor:
                accent.color.withValues(alpha: AccentAlpha.fill),
            disabledForegroundColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
          );
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }
}
