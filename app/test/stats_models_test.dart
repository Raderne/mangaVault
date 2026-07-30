import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/stats/stats_models.dart';

void main() {
  test('LibraryStats parses counters and derives fractions', () {
    final s = LibraryStats.fromJson({
      'totalTitles': 1228,
      'favoriteTitles': 1200,
      'totalChapters': 124000,
      'readChapters': 31000,
      'addedLast7Days': 12,
      'sourceCount': 7,
      'bySourceApp': {'app.mihon': 1228},
      'byStatus': {'ongoing': 900, 'completed': 328, 'cancelled': 0},
      'coversArchived': 614,
      'coversFailed': 3,
      'importCount': 2,
      'lastImportAt': 1770000000000,
      'vaultSizeBytes': 3221225472,
    });

    expect(s.totalTitles, 1228);
    expect(s.bySourceApp['app.mihon'], 1228);
    expect(s.byStatus['completed'], 328);
    expect(s.readFraction, closeTo(0.25, 0.001));
    expect(s.coverFraction, closeTo(0.5, 0.001));
    expect(s.isEmpty, isFalse);
  });

  test('LibraryStats tolerates a sparse payload and an empty archive', () {
    final s = LibraryStats.fromJson(const {});

    expect(s.totalTitles, 0);
    expect(s.lastImportAt, isNull);
    expect(s.bySourceApp, isEmpty);
    // No chapters must not divide by zero.
    expect(s.readFraction, 0);
    expect(s.coverFraction, 0);
    expect(s.isEmpty, isTrue);
  });

  test('BackupHealth maps the staleness band, defaulting to stale', () {
    final fresh = BackupHealth.fromJson({
      'sourceApp': 'app.mihon',
      'lastImportAt': 1770000000000,
      'importCount': 3,
      'titleCount': 1228,
      'staleness': 'fresh',
    });
    expect(fresh.sourceApp, 'app.mihon');
    expect(fresh.staleness, Staleness.fresh);

    expect(
      BackupHealth.fromJson(const {'staleness': 'aging'}).staleness,
      Staleness.aging,
    );
    // An unknown/missing band is treated as stale, never as fresh.
    expect(
      BackupHealth.fromJson(const {}).staleness,
      Staleness.stale,
    );
  });

  test('ResumeItem wraps the list row and its next chapter', () {
    final item = ResumeItem.fromJson({
      'id': 'm1',
      'title': 'Vagabond',
      'status': 'ongoing',
      'coverState': 'archived',
      'sourceName': 'MangaDex',
      'sourceId': '9',
      'chapterCount': 327,
      'unreadCount': 27,
      'readCount': 300,
      'lastReadAt': 1770000000000,
      'nextChapter': {'name': 'Chapter 301', 'number': 301},
    });

    expect(item.manga.title, 'Vagabond');
    expect(item.manga.coverState, 'archived');
    expect(item.nextChapter.name, 'Chapter 301');
    expect(item.nextChapter.number, 301);
    expect(item.readFraction, closeTo(300 / 327, 0.001));
  });
}
