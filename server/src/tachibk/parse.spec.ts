import { BackupParseError } from './errors';
import { BackupParser } from './parse';
import { encodeBackup, encodeBackupGzip } from './test-util';

describe('BackupParser', () => {
  const parser = new BackupParser();

  it('parses a gzip+protobuf backup and extracts the source app from the filename', async () => {
    const bytes = encodeBackupGzip({
      backupManga: [{ source: '123', url: '/manga/1', title: 'Solo Leveling' }],
      backupCategories: [{ name: 'Reading', order: '0' }],
    });
    const result = await parser.parse(
      bytes,
      'app.mihon_2026-07-18_10-30.tachibk',
    );

    expect(result.container).toBe('gzip-proto');
    expect(result.sourceApp).toBe('app.mihon');
    expect(result.wire.backupManga).toHaveLength(1);
    expect(result.wire.backupManga![0]).toMatchObject({
      source: '123', // int64 kept as decimal string
      url: '/manga/1',
      title: 'Solo Leveling',
    });
  });

  it('parses raw (non-gzipped) protobuf', async () => {
    const bytes = encodeBackup({
      backupManga: [{ source: '9', url: '/x', title: 'X' }],
    });
    const result = await parser.parse(bytes, 'weird.tachibk');
    expect(result.container).toBe('raw-proto');
    expect(result.sourceApp).toBe(''); // filename does not match the convention
    expect(result.wire.backupManga![0].title).toBe('X');
  });

  describe('source-app extraction from the filename', () => {
    // The prefix is the only identifier of the producing fork, and forks vary
    // the timestamp tail — so the match is anchored on the ISO date, not on
    // Mihon's exact `_yyyy-MM-dd_HH-mm`.
    const cases: [name: string, expected: string][] = [
      ['app.mihon_2026-07-16.tachibk', 'app.mihon'], // date only
      ['app.mihon_2026-07-16_10-30.tachibk', 'app.mihon'], // Mihon's own format
      ['app.komikku_2026-07-16_10-30-15.tachibk', 'app.komikku'], // with seconds
      ['eu.kanade.tachiyomi_2026-07-16_10-30.tachibk', 'eu.kanade.tachiyomi'],
      ['tachiyomi_2026-01-01.json', 'tachiyomi'], // legacy JSON carries it too
      ['APP.MIHON_2026-07-16.TACHIBK', 'app.mihon'], // normalized to lower case
      ['/sdcard/backups/app.mihon_2026-07-16.tachibk', 'app.mihon'], // path stripped
      ['weird.tachibk', ''], // no date to anchor on
      ['library-backup.tachibk', ''],
      ['my library_2026-07-16.tachibk', ''], // prefix can't be an application id
      ['_2026-07-16.tachibk', ''], // empty prefix
    ];

    it.each(cases)('%s → "%s"', async (fileName, expected) => {
      const bytes = encodeBackupGzip({
        backupManga: [{ source: '1', url: '/a', title: 'A' }],
      });
      const result = await parser.parse(bytes, fileName);
      expect(result.sourceApp).toBe(expected);
    });
  });

  it('tracks favorite presence: absent stays undefined, explicit false is preserved', async () => {
    const bytes = encodeBackup({
      backupManga: [
        { source: '1', url: '/a', title: 'A' }, // favorite omitted
        { source: '1', url: '/b', title: 'B', favorite: false },
      ],
    });
    const result = await parser.parse(bytes, 'x.tachibk');
    expect(result.wire.backupManga![0].favorite).toBeUndefined();
    expect(result.wire.backupManga![1].favorite).toBe(false);
  });

  it('preserves int64 source ids beyond 2^53 as exact strings', async () => {
    const big = '9223372036854775807'; // int64 max
    const bytes = encodeBackup({
      backupManga: [{ source: big, url: '/a', title: 'A' }],
    });
    const result = await parser.parse(bytes, 'x.tachibk');
    expect(result.wire.backupManga![0].source).toBe(big);
  });

  it('throws a staged BackupParseError on corrupt gzip', async () => {
    const bad = new Uint8Array([0x1f, 0x8b, 0x00, 0x00, 0x00]);
    await expect(parser.parse(bad, 'x.tachibk')).rejects.toMatchObject({
      name: 'BackupParseError',
      stage: 'gunzip',
    });
    await expect(parser.parse(bad, 'x.tachibk')).rejects.toBeInstanceOf(
      BackupParseError,
    );
  });
});
