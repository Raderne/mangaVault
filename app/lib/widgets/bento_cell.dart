import 'package:flutter/material.dart';

import '../theme/app_accents.dart';
import '../theme/app_dimens.dart';

/// Surface tier for a [BentoCell] — tonal layering per Minimalist Slate.
enum BentoTone {
  /// `surfaceContainerLow` — nested wells inside a mid cell.
  low,

  /// `surfaceContainer` — default module layer.
  mid,

  /// `surfaceContainerHigh` — hero / emphasis cells.
  high,
}

/// The core layout container of the Minimalist Slate design: a rounded,
/// bordered surface cell of the bento grid.
class BentoCell extends StatelessWidget {
  const BentoCell({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppDimens.cellPadding),
    this.tone = BentoTone.mid,
    this.accent,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Surface elevation within the slate ladder. Defaults to [BentoTone.mid].
  final BentoTone tone;

  /// Hue this cell is identified by. When set, the cell gains a diagonal
  /// [accentWash] over its slate surface and an accent-tinted border; when
  /// null the cell renders exactly as it always did.
  final VaultAccent? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      BentoTone.low => scheme.surfaceContainerLow,
      BentoTone.mid => scheme.surfaceContainer,
      BentoTone.high => scheme.surfaceContainerHigh,
    };
    final accent = this.accent;
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.cellRadius),
        side: BorderSide(
          color: accent == null
              ? scheme.outlineVariant.withValues(alpha: 0.3)
              : accent.color.withValues(alpha: AccentAlpha.border),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // `Ink`, not a `DecoratedBox`: Ink paints its decoration onto the
      // Material itself, so the InkWell's splash still renders *above* the
      // wash. A DecoratedBox between the two would swallow every ripple.
      child: Ink(
        decoration: accent == null
            ? null
            : BoxDecoration(gradient: accentWash(accent)),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Uppercase micro-label used above cell content ("STATUS: COMPLETED" style).
class CellLabel extends StatelessWidget {
  const CellLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall!
          .copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Nested low-tone well used inside a mid [BentoCell] (mockup source cards).
class NestedWell extends StatelessWidget {
  const NestedWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimens.unit * 2),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Tints the well's fill and border. Used for rows that carry their own
  /// meaning inside a cell — a stale backup, a completed import.
  final VaultAccent? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = this.accent;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.surfaceContainerLow
            : Color.alphaBlend(
                accent.wash.withValues(alpha: AccentAlpha.wash),
                scheme.surfaceContainerLow,
              ),
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        border: Border.all(
          color: accent == null
              ? scheme.outlineVariant.withValues(alpha: 0.3)
              : accent.color.withValues(alpha: AccentAlpha.border),
        ),
      ),
      child: child,
    );
  }
}

/// 40×40 icon box — the mockup's accent well on source tiles and archive rows.
/// Without an [accent] it keeps the original `primaryContainer` lavender; with
/// one it becomes the cell's hue, which is what gives each bento cell a
/// recognisable badge at a glance.
class AccentIconWell extends StatelessWidget {
  const AccentIconWell({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.accent,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VaultAccent? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = this.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.primaryContainer
            : accent.color.withValues(alpha: AccentAlpha.fill),
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        border: accent == null
            ? null
            : Border.all(
                color: accent.color.withValues(alpha: AccentAlpha.border),
              ),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: accent?.color ?? scheme.primary,
      ),
    );
  }
}
