import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/library/library_models.dart';

void main() {
  test('LibraryPage.fromJson parses items and paging metadata', () {
    final page = LibraryPage.fromJson({
      'items': [
        {
          'id': 'a',
          'title': 'Alpha',
          'author': 'Author One',
          'status': 'ongoing',
          'coverPath': null,
          'coverState': 'none',
          'sourceName': 'MangaDex',
          'sourceId': '123',
          'chapterCount': 12,
          'unreadCount': 3,
          'lastReadAt': 1700000000000,
        },
      ],
      'total': 42,
      'offset': 0,
      'limit': 40,
    });

    expect(page.total, 42);
    expect(page.items, hasLength(1));
    final item = page.items.single;
    expect(item.title, 'Alpha');
    expect(item.chapterCount, 12);
    expect(item.unreadCount, 3);
    expect(item.lastReadAt, 1700000000000);
    expect(item.coverState, 'none');
  });

  test('MangaListItem tolerates missing optionals', () {
    final item = MangaListItem.fromJson({'id': 'x', 'title': 'Y'});
    expect(item.author, isNull);
    expect(item.lastReadAt, isNull);
    expect(item.chapterCount, 0);
    expect(item.status, 'unknown');
  });

  test('VaultManga.fromJson parses nested refs and computes readFraction', () {
    final manga = VaultManga.fromJson({
      'id': 'm1',
      'sourceName': 'MangaDex',
      'title': 'Alpha Archivist',
      'author': 'Author One',
      'artist': null,
      'description': 'A tale.',
      'genres': ['Action', 'Fantasy'],
      'status': 'ongoing',
      'coverPath': null,
      'coverState': 'none',
      'notes': '',
      'dateAdded': 1700000000000,
      'chapterCount': 10,
      'readCount': 4,
      'unreadCount': 6,
      'lastReadChapter': {'name': 'Chapter 4', 'number': 4},
      'nextChapter': {'name': 'Chapter 5', 'number': 5},
      'categories': [
        {'id': 'c1', 'name': 'Favorites'},
      ],
      'archive': [
        {
          'id': 'imp1',
          'fileName': 'app.mihon_x.tachibk',
          'sourceApp': 'app.mihon',
          'container': 'gzip-proto',
          'importedAt': 1700000000000,
        },
      ],
    });

    expect(manga.genres, ['Action', 'Fantasy']);
    expect(manga.readFraction, closeTo(0.4, 1e-9));
    expect(manga.lastReadChapter!.name, 'Chapter 4');
    expect(manga.nextChapter!.number, 5);
    expect(manga.categories.single.name, 'Favorites');
    expect(manga.archive.single.sourceApp, 'app.mihon');
  });

  test('readFraction is 0 when there are no chapters', () {
    final manga = VaultManga.fromJson({
      'id': 'm2',
      'title': 'Empty',
      'chapterCount': 0,
      'readCount': 0,
    });
    expect(manga.readFraction, 0);
  });
}
