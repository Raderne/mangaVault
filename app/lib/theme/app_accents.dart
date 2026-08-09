import 'package:flutter/material.dart';

/// The "manga neon" accent set layered over Minimalist Slate.
///
/// The base scheme is deliberately monochrome — and `secondary` and `tertiary`
/// carry the *same* hex, so the whole app had exactly one accent hue. That
/// reads flat on a bento grid, where the point of the layout is that each cell
/// is its own compartment. These five hues give every cell an identity while
/// the slate surfaces underneath stay unchanged, so cover art still dominates.
///
/// Each accent carries two colors rather than one, and the split is load
/// bearing:
///
/// * [AccentSwatch.color] is the **foreground** — numbers, icons, dots, arcs.
///   Lightened until it clears WCAG AA (4.5:1) against the most hostile
///   surface it can land on, which is a [BentoTone.high] cell already carrying
///   its own 12% wash.
/// * [AccentSwatch.wash] is the **tint** — the saturated form, used only at
///   low alpha for the cell gradient. A single color can't do both jobs: the
///   foreground has to be light enough to read, and a 12% veil of that same
///   light color reads grey instead of coloured.
///
/// Verified: every accent-on-washed-surface pairing is ≥ 5.30:1, and body
/// (`onSurface`) / muted (`onSurfaceVariant`) text stays ≥ 7.1:1 on every
/// washed cell.
enum VaultAccent {
  /// Titles, the archive hero, and the import way-in. The anchor hue — closest
  /// to the scheme's own lavender, so nothing pre-existing clashes with it.
  violet(Color(0xFFA79CFF), Color(0xFF6D5BF0)),

  /// Chapters and the "recently added" shelf.
  cyan(Color(0xFF4CC9E8), Color(0xFF14A5C7)),

  /// Covers, storage, and import history.
  amber(Color(0xFFF5A524), Color(0xFFE08700)),

  /// Reading progress, completion, successful outcomes.
  emerald(Color(0xFF35D0A5), Color(0xFF12A87F)),

  /// Attention: stale backups, cancelled titles, failures.
  rose(Color(0xFFFF7E99), Color(0xFFF0426A));

  const VaultAccent(this.color, this.wash);

  /// Contrast-safe foreground for text, icons and indicators.
  final Color color;

  /// Saturated hue for low-alpha surface tints. Never use as a foreground.
  final Color wash;
}

/// Alpha values the accent system paints with. Kept in one place because a
/// bento grid only holds together if every cell tints by the same amount — one
/// cell washed at 0.2 next to one at 0.12 reads as a bug, not a highlight.
abstract final class AccentAlpha {
  /// Peak opacity of a cell's gradient wash, at the top-left corner.
  static const double wash = 0.12;

  /// Cell border tint. Stronger than the plain `outlineVariant` hairline so
  /// the accent traces the cell's whole edge, not just its corner.
  static const double border = 0.28;

  /// Fill behind an accented icon, chip or nested well.
  static const double fill = 0.16;

  /// Glow bloom around progress fills.
  static const double glow = 0.45;
}

/// The cell wash: accent at [AccentAlpha.wash] in the top-left, fading out
/// diagonally so the bottom of a tall cell is untinted slate. A flat fill at
/// this alpha would just look like a slightly wrong surface color; the fade is
/// what makes it read as light falling on the cell.
LinearGradient accentWash(VaultAccent accent) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accent.wash.withValues(alpha: AccentAlpha.wash),
        accent.wash.withValues(alpha: AccentAlpha.wash * 0.35),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
