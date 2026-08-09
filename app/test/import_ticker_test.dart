import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/import/import_models.dart';
import 'package:mangavault/features/backups/import_ticker.dart';
import 'package:mangavault/theme/app_accents.dart';
import 'package:mangavault/theme/app_theme.dart';
import 'package:mangavault/widgets/status_chip.dart';

MangaEvent _event(String title, {String action = 'created', int at = 1}) =>
    MangaEvent(title: title, action: action, processed: at, total: 100);

/// The controller keeps `recent` newest-first; these helpers mirror that.
List<MangaEvent> _newestFirst(List<String> titles) => [
      for (var i = titles.length - 1; i >= 0; i--) _event(titles[i], at: i + 1),
    ];

Future<void> _pumpTicker(WidgetTester tester, List<MangaEvent> recent) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        // Column, not Center: the ticker must report its own height, and a
        // loose parent would let it size to whatever it likes.
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ImportTicker(recent: recent),
            // A badge laid out with room to breathe, so a test can tell "the
            // slot fits the badge" from "the slot squashed the badge". Under a
            // too-short slot the chip is simply constrained down rather than
            // painting outside it, so no rect ever lands out of bounds.
            // Accented, like the real badges: an accent chip carries a hairline
            // the plain one doesn't, which is 2pt of height.
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusChip('REFERENCE', accent: VaultAccent.emerald),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lets the throttle release every queued row.
Future<void> _settleTicker(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 160));
  }
}

void main() {
  testWidgets('the well keeps one height from empty to overflowing',
      (tester) async {
    await _pumpTicker(tester, const []);
    final empty = tester.getSize(find.byType(ImportTicker)).height;
    expect(empty, greaterThan(0));
    expect(find.text('Waiting for the first title…'), findsOneWidget);

    await _pumpTicker(tester, _newestFirst(['A']));
    await tester.pump();
    expect(tester.getSize(find.byType(ImportTicker)).height, empty);

    // Far more titles than there are slots — the old list grew here.
    for (var i = 0; i < 20; i++) {
      await _pumpTicker(tester, _newestFirst([for (var n = 0; n <= i; n++) 'T$n']));
      await _settleTicker(tester);
      expect(
        tester.getSize(find.byType(ImportTicker)).height,
        empty,
        reason: 'the card must not grow as titles stream in (title ${i + 1})',
      );
    }
  });

  testWidgets('only the newest handful of titles stay in the tree',
      (tester) async {
    await _pumpTicker(tester, _newestFirst(['T0']));
    for (var i = 1; i < 12; i++) {
      await _pumpTicker(tester, _newestFirst([for (var n = 0; n <= i; n++) 'T$n']));
      await _settleTicker(tester);
    }

    // Four visible depths plus the invisible exit slot the oldest row fades
    // into; everything older is dropped, not merely scrolled out of sight.
    expect(find.text('T11'), findsOneWidget);
    expect(find.text('T7'), findsOneWidget);
    expect(find.text('T6'), findsNothing);
    expect(find.text('T0'), findsNothing);
  });

  testWidgets('older rows are dimmer, and the oldest is fading out',
      (tester) async {
    await _pumpTicker(tester, _newestFirst(['T0']));
    for (var i = 1; i < 6; i++) {
      await _pumpTicker(tester, _newestFirst([for (var n = 0; n <= i; n++) 'T$n']));
      await _settleTicker(tester);
    }

    double opacityOf(String title) {
      final fades = tester.widgetList<AnimatedOpacity>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      // The depth fade is the outermost AnimatedOpacity above the row.
      return fades.last.opacity;
    }

    expect(opacityOf('T5'), 1.0);
    expect(opacityOf('T4'), lessThan(opacityOf('T5')));
    expect(opacityOf('T3'), lessThan(opacityOf('T4')));
    expect(opacityOf('T2'), lessThan(opacityOf('T3')));
    expect(opacityOf('T1'), 0.0); // exit slot: present, invisible
  });

  testWidgets('a burst is sampled rather than strobed', (tester) async {
    // A real 1,200-title backup lands events far faster than any transition.
    await _pumpTicker(tester, _newestFirst(['T0']));
    await tester.pump();
    expect(find.text('T0'), findsOneWidget);

    // Five more arrive within the same beat.
    for (var i = 1; i <= 5; i++) {
      await _pumpTicker(tester, _newestFirst([for (var n = 0; n <= i; n++) 'T$n']));
      await tester.pump(const Duration(milliseconds: 5));
    }

    // None of them has been admitted yet — the cooldown from T0 is still open.
    expect(find.text('T1'), findsNothing);
    expect(find.text('T5'), findsNothing);

    // The next beat takes the newest, dropping the four it overtook. Losing
    // them is the point: this is ambient feedback, not a log.
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('T5'), findsOneWidget);
    expect(find.text('T1'), findsNothing);
    expect(find.text('T3'), findsNothing);
  });

  testWidgets('survives an enlarged system font without clipping',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // Fed one at a time: the ticker reads only the head of `recent`, so a list
    // handed over in one go would show its newest entry and nothing else.
    await _pumpTicker(tester, _newestFirst(['T0']));
    for (var i = 1; i < 4; i++) {
      await _pumpTicker(tester, _newestFirst([for (var n = 0; n <= i; n++) 'T$n']));
      await _settleTicker(tester);
    }

    final well = tester.getRect(find.byType(ImportTicker));
    final natural = tester.getSize(find.ancestor(
      of: find.text('REFERENCE'),
      matching: find.byType(StatusChip),
    ));

    // Assert on the *badge*, not the title text: it is the taller of the two,
    // so it is what a slot sized from the title alone gets wrong. And assert on
    // its height rather than its position — a slot that is too short squashes
    // the chip to fit instead of letting it paint out of bounds, so a
    // bounds check would pass while the label is being clipped.
    Rect badgeIn(String title) {
      final row =
          find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
      return tester
          .getRect(find.descendant(of: row, matching: find.byType(StatusChip)));
    }

    for (final title in ['T3', 'T2', 'T1']) {
      // Taller than natural is fine (the badge just centres in its slot);
      // shorter means the slot squashed it, which is the bug.
      expect(badgeIn(title).height, greaterThanOrEqualTo(natural.height - 0.5),
          reason: "$title's badge is squashed by its slot at text scale 1.6");
      expect(badgeIn(title).bottom, lessThanOrEqualTo(well.bottom + 0.5),
          reason: "$title's badge falls outside the well at text scale 1.6");
    }
    expect(badgeIn('T3').top, greaterThanOrEqualTo(well.top - 0.5));
  });

  test('badge label and hue agree with the review chips', () {
    expect(importActionLabel('merged'), 'MERGED');
    expect(importActionLabel('skipped'), 'SKIPPED');
    expect(importActionLabel('created'), 'NEW');
    expect(importActionAccent('merged'), isNot(importActionAccent('created')));
  });
}
