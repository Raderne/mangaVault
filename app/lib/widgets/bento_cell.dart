import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';

/// The core layout container of the Minimalist Slate design: a rounded,
/// bordered surface cell of the bento grid.
class BentoCell extends StatelessWidget {
  const BentoCell({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppDimens.cellPadding),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
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
