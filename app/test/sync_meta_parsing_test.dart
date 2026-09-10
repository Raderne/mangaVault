import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/sync/sync_models.dart';

/// `/sync/meta` is fetched before the first delta page, so anything that throws
/// while parsing it aborts the whole sync — and after a `schemaVersion` bump has
/// just dropped the mirror, that leaves the user with no library at all and no
/// way to refill it. It has to survive whatever the server sends.
void main() {
  Map<String, dynamic> meta(Object? healthCheckedAt) => {
        'serverEpoch': 'e',
        'cursor': '10',
        'totalTitles': 1,
        'categories': <dynamic>[],
        'imports': <dynamic>[],
        'backupApps': <dynamic>[],
        'sources': [
          {
            'sourceId': '1',
            'name': 'MangaDex',
            'lang': 'en',
            'healthCheckedAt': healthCheckedAt,
            'titleCount': 3,
          },
        ],
        'vaultSizeBytes': 0,
      };

  test('an int8 epoch sent as a string still parses', () {
    // What node-postgres actually returns for a BIGINT column. A hard
    // `as num?` cast on this wiped the library in 1.0.2.
    final parsed = SyncMetaSnapshot.fromJson(meta('1788208072894'));
    expect(parsed.sources.single.healthCheckedAt, 1788208072894);
  });

  test('a numeric epoch still parses', () {
    final parsed = SyncMetaSnapshot.fromJson(meta(1788208072894));
    expect(parsed.sources.single.healthCheckedAt, 1788208072894);
  });

  test('a null or unparseable epoch is not fatal', () {
    expect(SyncMetaSnapshot.fromJson(meta(null)).sources.single.healthCheckedAt,
        isNull);
    expect(SyncMetaSnapshot.fromJson(meta('nonsense')).sources.single
        .healthCheckedAt, isNull);
  });

  test('a source list the server never sent is empty, not a crash', () {
    final body = meta(null)..remove('sources');
    expect(SyncMetaSnapshot.fromJson(body).sources, isEmpty);
  });
}
