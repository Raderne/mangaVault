import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/theme/app_accents.dart';
import 'package:mangavault/theme/app_colors.dart';
import 'package:mangavault/widgets/bento_cell.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The surface an accented cell actually presents: slate with its own wash
/// already blended in. This — not the bare slate token — is what accent text
/// has to be legible against, and it's the case that's easy to forget.
Color _washed(VaultAccent accent, Color surface) => Color.alphaBlend(
      accent.wash.withValues(alpha: AccentAlpha.wash),
      surface,
    );

void main() {
  const scheme = AppColors.colorScheme;

  // Every surface an accented cell or well can sit on.
  const surfaces = <String, Color>{
    'surfaceContainerLow': AppColors.surfaceContainerLow,
    'surfaceContainer': AppColors.surfaceContainer,
    'surfaceContainerHigh': AppColors.surfaceContainerHigh,
  };

  group('accent contrast', () {
    test('every accent clears AA as foreground on its own washed surface', () {
      for (final accent in VaultAccent.values) {
        for (final entry in surfaces.entries) {
          final ratio = _contrast(accent.color, _washed(accent, entry.value));
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${accent.name} on washed ${entry.key} is '
                '${ratio.toStringAsFixed(2)}:1, below WCAG AA (4.5:1). '
                'Lighten VaultAccent.${accent.name}.color.',
          );
        }
      }
    });

    test('a wash never costs body or muted text its legibility', () {
      for (final accent in VaultAccent.values) {
        for (final entry in surfaces.entries) {
          final washed = _washed(accent, entry.value);
          for (final (name, text) in [
            ('onSurface', scheme.onSurface),
            ('onSurfaceVariant', scheme.onSurfaceVariant),
          ]) {
            final ratio = _contrast(text, washed);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$name on ${accent.name}-washed ${entry.key} is '
                  '${ratio.toStringAsFixed(2)}:1. Lower AccentAlpha.wash.',
            );
          }
        }
      }
    });

    test('accents are actually distinguishable from each other', () {
      // A five-hue palette where two hues read the same defeats the point of
      // giving each cell its own identity.
      for (final a in VaultAccent.values) {
        for (final b in VaultAccent.values) {
          if (a == b) continue;
          final same = (a.color.r - b.color.r).abs() < 0.06 &&
              (a.color.g - b.color.g).abs() < 0.06 &&
              (a.color.b - b.color.b).abs() < 0.06;
          expect(same, isFalse,
              reason: '${a.name} and ${b.name} are near-identical colors');
        }
      }
    });
  });

  group('BentoCell accent', () {
    testWidgets('an accented cell paints a wash and tints its border',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: BentoCell(accent: VaultAccent.violet, child: Text('x')),
        ),
      ));

      final ink = tester.widget<Ink>(find.byType(Ink));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.gradient, isNotNull);

      final material = tester.widget<Material>(
        find.ancestor(of: find.byType(Ink), matching: find.byType(Material)).first,
      );
      final side = (material.shape! as RoundedRectangleBorder).side;
      expect(side.color.r, closeTo(VaultAccent.violet.color.r, 0.01));
      expect(side.color.a, closeTo(AccentAlpha.border, 0.01));
    });

    testWidgets('a cell without an accent is unchanged', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: BentoCell(child: Text('x'))),
      ));

      final ink = tester.widget<Ink>(find.byType(Ink));
      expect(ink.decoration, isNull);
    });
  });
}
