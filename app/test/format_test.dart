import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/format.dart';

void main() {
  group('groupedNumber', () {
    test('groups thousands', () {
      expect(groupedNumber(0), '0');
      expect(groupedNumber(999), '999');
      expect(groupedNumber(1000), '1,000');
      expect(groupedNumber(1284), '1,284');
      expect(groupedNumber(124567), '124,567');
      expect(groupedNumber(-1284), '-1,284');
    });
  });

  group('formatBytes', () {
    test('scales through the unit tiers', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('drops the decimal once the figure reaches three digits', () {
      expect(formatBytes(220 * 1024 * 1024), '220 MB');
    });
  });

  group('chapterNumberLabel', () {
    test('drops the .0 on whole chapters', () {
      expect(chapterNumberLabel(52), '52');
      expect(chapterNumberLabel(0), '0');
    });

    test('rounds away float32 noise from imported numbers', () {
      expect(chapterNumberLabel(0.10000000149011612), '0.1');
      expect(chapterNumberLabel(12.5), '12.5');
    });

    test('is null for an unnumbered chapter', () {
      expect(chapterNumberLabel(-1), isNull);
    });
  });

  group('relativeDate', () {
    test('is empty for a missing timestamp', () {
      expect(relativeDate(0), '');
    });

    test('reports recent times relatively', () {
      final now = DateTime.now();
      expect(relativeDate(now.millisecondsSinceEpoch), 'just now');
      expect(
        relativeDate(
            now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch),
        '5m ago',
      );
      expect(
        relativeDate(
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch),
        '3h ago',
      );
      expect(
        relativeDate(
            now.subtract(const Duration(days: 3)).millisecondsSinceEpoch),
        '3d ago',
      );
    });

    test('falls back to an absolute date past a week', () {
      final old = DateTime(2026, 3, 14, 12);
      expect(relativeDate(old.millisecondsSinceEpoch), 'Mar 14, 2026');
    });
  });
}
