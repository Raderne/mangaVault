import 'package:flutter/material.dart';

import '../../data/updates/update_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';

/// Renders parsed release notes as colour-coded groups.
///
/// A changelog is the one screen in the app that is pure text, which on a dark
/// slate reads as a wall. The accent per [ChangeKind] is what breaks it up:
/// green additions, cyan fixes, rose removals — so "did anything get taken
/// away?" is answerable at a glance, before reading a word.
///
/// Colour is never the only signal. Every group also carries its name as an
/// uppercase micro-label, which is what a colour-blind reader (and every
/// screen reader) actually goes by.
class ChangelogView extends StatelessWidget {
  const ChangelogView({
    super.key,
    required this.notes,
    this.emptyLabel = 'No release notes for this version.',
  });

  final ReleaseNotes notes;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (notes.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium!
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notes.summary.isNotEmpty) ...[
          Text(notes.summary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppDimens.unit * 2),
        ],
        for (final group in notes.groups) ...[
          _ChangeGroupBlock(group: group),
          if (group != notes.groups.last)
            const SizedBox(height: AppDimens.unit * 2),
        ],
      ],
    );
  }
}

class _ChangeGroupBlock extends StatelessWidget {
  const _ChangeGroupBlock({required this.group});

  final ChangeGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = group.kind.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.label,
          style: theme.textTheme.labelSmall!.copyWith(color: accent.color),
        ),
        const SizedBox(height: AppDimens.unit),
        for (final item in group.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ChangeLine(text: item, accent: accent),
          ),
      ],
    );
  }
}

/// One bullet. The marker is a short accent rule rather than a dot — at 12px
/// the design's hairline vocabulary reads better than a bullet glyph, and it
/// gives the eye a left edge to run down.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.text, required this.accent});

  final String text;
  final VaultAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!;
    // Centre the marker on the first line of text at any text scale, so an
    // enlarged system font doesn't leave the rules floating.
    final firstLineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
            (style.height ?? 1.4);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: firstLineHeight,
          child: Center(
            child: Container(
              width: 10,
              height: 2,
              decoration: BoxDecoration(
                color: accent.color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimens.unit + 2),
        Expanded(
          child: Text(
            text,
            style: style.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
