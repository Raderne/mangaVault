import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/import/import_models.dart';

void main() {
  group('ImportEvent.fromJson', () {
    test('decodes each event type by its discriminator', () {
      expect(ImportEvent.fromJson({'type': 'start', 'fileName': 'x.tachibk', 'total': 5}), isA<StartEvent>());
      expect(ImportEvent.fromJson({'type': 'phase', 'phase': 'categories'}), isA<PhaseEvent>());
      expect(ImportEvent.fromJson({'type': 'batch', 'committed': 2, 'total': 5}), isA<BatchEvent>());
      expect(ImportEvent.fromJson({'type': 'error', 'message': 'boom', 'processed': 3}), isA<ErrorEvent>());
      expect(ImportEvent.fromJson({'type': 'nonsense'}), isA<UnknownEvent>());
    });

    test('decodes a manga event with progress and action', () {
      final e = ImportEvent.fromJson({
        'type': 'manga',
        'title': 'Solo Leveling',
        'action': 'merged',
        'processed': 42,
        'total': 900,
      }) as MangaEvent;
      expect(e.title, 'Solo Leveling');
      expect(e.isMerged, true);
      expect(e.processed, 42);
      expect(e.total, 900);
    });

    test('decodes a done event carrying the import record', () {
      final e = ImportEvent.fromJson({
        'type': 'done',
        'record': {
          'id': 'r1',
          'fileName': 'app.mihon_x.tachibk',
          'fileSize': 1234,
          'sourceApp': 'app.mihon',
          'container': 'gzip-proto',
          'importedAt': 1700000000000,
          'stats': {'titlesNew': 3, 'titlesMerged': 1, 'chaptersTotal': 90},
        },
      }) as DoneEvent;
      expect(e.record.sourceApp, 'app.mihon');
      expect(e.record.stats.titlesNew, 3);
    });
  });

  test('StagedImport.fromJson parses preview + duplicate flag', () {
    final staged = StagedImport.fromJson({
      'id': 's1',
      'fileMeta': {
        'fileName': 'x.tachibk',
        'fileSize': 10,
        'sha256': 'abc',
        'sourceApp': 'app.mihon',
        'container': 'gzip-proto',
      },
      'summary': {'titlesTotal': 2, 'titlesNew': 1, 'titlesMerged': 1, 'chaptersTotal': 5, 'categoriesTotal': 1, 'warnings': []},
      'preview': [
        {'title': 'A', 'action': 'created', 'conflicts': []},
        {
          'title': 'B',
          'action': 'merged',
          'conflicts': [
            {'field': 'description', 'kept': 'new', 'incoming': 'old'}
          ],
        },
      ],
      'expiresAt': 123,
    });
    expect(staged.isDuplicate, false);
    expect(staged.preview[1].isMerged, true);
    expect(staged.preview[1].conflicts.single.field, 'description');
  });
}
