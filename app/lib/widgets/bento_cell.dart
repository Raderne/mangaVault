import 'package:flutter/material.dart';

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
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Surface elevation within the slate ladder. Defaults to [BentoTone.mid].
  final BentoTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      BentoTone.low => scheme.surfaceContainerLow,
      BentoTone.mid => scheme.surfaceContainer,
      BentoTone.high => scheme.surfaceContainerHigh,
    };
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.cellRadius),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }
}

/// 40×40 `primaryContainer` icon box — the mockup's accent well on source
/// tiles and archive rows. Keeps indigo/lavender sparse so covers dominate.
class AccentIconWell extends StatelessWidget {
  const AccentIconWell({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
      ),
      child: Icon(icon, size: iconSize, color: scheme.primary),
    );
  }
}
