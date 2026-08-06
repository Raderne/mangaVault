import { gunzipSync } from 'node:zlib';

import { BackupDenormalizer } from './denormalize';
import { ContainerDetector } from './detect';
import type { NormalizedBackup, NormalizedManga } from './domain';
import { BackupEncoder, buildBackupFileName } from './encode';
import { BackupNormalizer } from './normalize';
import { BackupParser } from './parse';

const encoder = new BackupEncoder();
const denormalizer = new BackupDenormalizer();
const parser = new BackupParser();
const normalizer = new BackupNormalizer();

/**
 * The property the whole export path rests on: writing the domain model and
 * reading it back must be the identity. Anything the encoder drops or the
 * decoder misreads shows up here as a diff.
 */
async function roundTrip(backup: NormalizedBackup): Promise<NormalizedBackup> {
  const bytes = await encoder.encode(denormalizer.denormalize(backup));
  const parsed = await parser.parse(
    bytes,
    'app.mihon_2026-08-06_14-30.tachibk',
  );
  return normalizer.normalize(parsed);
}

const manga = (over: Partial<NormalizedManga> = {}): NormalizedManga => ({
  key: { sourceId: '2499283573021220255', mangaUrl: '/manga/solo-leveling' },
  sourceName: 'MangaDex',
  title: 'Solo Leveling',
  author: 'Chugong',
  artist: 'Jang Sung-rak',
  description: 'The weakest hunter of all mankind.',
  genres: ['Action', 'Fantasy'],
  status: 'completed',
  thumbnailUrl: 'https://example.test/cover.jpg',
  notes: 'reread later',
  favorite: true,
  dateAdded: 1_700_000_000_000,
  lastModifiedAt: 1_750_000_000_000,
  categoryNames: ['Reading'],
  chapters: [
    {
      url: '/chapter/1',
      name: 'Chapter 1',
      chapterNumber: 1,
      scanlator: 'Team A',
      read: true,
      bookmark: false,
      lastPageRead: 12,
      dateUpload: 1_690_000_000_000,
      dateFetch: 1_690_000_100_000,
      sourceOrder: 0,
      lastReadAt: 1_710_000_000_000,
      readDuration: 45_000,
    },
    {
      url: '/chapter/2',
      name: 'Chapter 2',
      chapterNumber: 2,
      read: false,
      bookmark: true,
      lastPageRead: 0,
      dateUpload: 1_690_100_000_000,
      dateFetch: 1_690_100_100_000,
      sourceOrder: 1,
      readDuration: 0,
    },
  ],
  tracking: [
    {
      tracker: 'anilist',
      remoteId: '105398',
      trackingUrl: 'https://anilist.co/manga/105398',
      title: 'Solo Leveling',
      lastChapterRead: 179,
      totalChapters: 179,
      score: 9.5,
      status: 2,
      startedAt: 1_600_000_000_000,
      finishedAt: 1_650_000_000_000,
    },
  ],
  ...over,
});

const backup = (over: Partial<NormalizedBackup> = {}): NormalizedBackup => ({
  manga: [manga()],
  categories: [
    { name: 'Reading', order: 0 },
    { name: 'Completed', order: 1 },
  ],
  sources: [{ sourceId: '2499283573021220255', name: 'MangaDex' }],
  ...over,
});

describe('BackupEncoder', () => {
  it('writes a gzip container the detector recognizes', async () => {
    const bytes = await encoder.encode(denormalizer.denormalize(backup()));
    expect(new ContainerDetector().detect(bytes.subarray(0, 8))).toBe(
      'gzip-proto',
    );
    // Really gzip, not just the right magic bytes.
    expect(() => gunzipSync(bytes)).not.toThrow();
  });

  it('can write a raw (ungzipped) protobuf payload', async () => {
    const bytes = await encoder.encode(denormalizer.denormalize(backup()), {
      gzip: false,
    });
    expect(new ContainerDetector().detect(bytes.subarray(0, 8))).toBe(
      'raw-proto',
    );
  });

  it('round-trips a full backup unchanged', async () => {
    const original = backup();
    expect(await roundTrip(original)).toEqual(original);
  });

  it('preserves int64 source ids beyond 2^53', async () => {
    const big = '9223372036854775807'; // int64 max
    const out = await roundTrip(
      backup({
        manga: [manga({ key: { sourceId: big, mangaUrl: '/m/1' } })],
        sources: [{ sourceId: big, name: 'Huge Source' }],
      }),
    );
    expect(out.manga[0].key.sourceId).toBe(big);
    expect(out.sources[0].sourceId).toBe(big);
  });

  it('preserves favorite=false instead of defaulting it back to true', async () => {
    // The single most dangerous field in the format: absent means TRUE, so an
    // encoder that omits `false` silently re-favorites the whole export.
    const out = await roundTrip(
      backup({ manga: [manga({ favorite: false })] }),
    );
    expect(out.manga[0].favorite).toBe(false);
  });

  it('preserves favorite=true', async () => {
    const out = await roundTrip(backup({ manga: [manga({ favorite: true })] }));
    expect(out.manga[0].favorite).toBe(true);
  });

  it('rebuilds reading history so progress survives the trip', async () => {
    const out = await roundTrip(backup());
    const [read, unread] = out.manga[0].chapters;
    expect(read.read).toBe(true);
    expect(read.lastPageRead).toBe(12);
    expect(read.lastReadAt).toBe(1_710_000_000_000);
    expect(read.readDuration).toBe(45_000);
    // A chapter with no history must not gain a phantom entry.
    expect(unread.lastReadAt).toBeUndefined();
    expect(unread.readDuration).toBe(0);
    expect(unread.bookmark).toBe(true);
  });

  it('carries category membership across as order values', async () => {
    const out = await roundTrip(backup());
    expect(out.manga[0].categoryNames).toEqual(['Reading']);
    expect(out.categories).toEqual([
      { name: 'Reading', order: 0 },
      { name: 'Completed', order: 1 },
    ]);
  });

  it('drops a category reference the backup does not define', async () => {
    // Membership travels as an order value; a name with no category row has no
    // wire representation, so it must vanish rather than corrupt the list.
    const out = await roundTrip(
      backup({ manga: [manga({ categoryNames: ['Reading', 'Ghost'] })] }),
    );
    expect(out.manga[0].categoryNames).toEqual(['Reading']);
  });

  it('round-trips every publication status', async () => {
    const statuses = [
      'unknown',
      'ongoing',
      'completed',
      'licensed',
      'publishing_finished',
      'cancelled',
      'on_hiatus',
    ] as const;
    const out = await roundTrip(
      backup({
        manga: statuses.map((status, i) =>
          manga({ status, key: { sourceId: '1', mangaUrl: `/m/${i}` } }),
        ),
      }),
    );
    expect(out.manga.map((m) => m.status)).toEqual([...statuses]);
  });

  it('round-trips tracking, keeping remote ids above 2^31 intact', async () => {
    // mediaIdInt is a 32-bit field; ids must ride the int64 mediaId instead.
    const out = await roundTrip(
      backup({
        manga: [
          manga({
            tracking: [
              {
                tracker: 'myanimelist',
                remoteId: '4294967396',
                trackingUrl: 'https://myanimelist.net/manga/4294967396',
                title: 'Big Id',
                lastChapterRead: 3.5,
                totalChapters: 10,
                score: 8,
                status: 1,
              },
            ],
          }),
        ],
      }),
    );
    expect(out.manga[0].tracking[0]).toEqual({
      tracker: 'myanimelist',
      remoteId: '4294967396',
      trackingUrl: 'https://myanimelist.net/manga/4294967396',
      title: 'Big Id',
      lastChapterRead: 3.5,
      totalChapters: 10,
      score: 8,
      status: 1,
      startedAt: undefined,
      finishedAt: undefined,
    });
  });

  it('round-trips an unnamed tracker via its syncId', async () => {
    const out = await roundTrip(
      backup({
        manga: [
          manga({
            tracking: [
              {
                tracker: 'unknown:42',
                remoteId: '7',
                trackingUrl: '',
                title: '',
                lastChapterRead: 0,
                totalChapters: 0,
                score: 0,
                status: 0,
              },
            ],
          }),
        ],
      }),
    );
    expect(out.manga[0].tracking[0].tracker).toBe('unknown:42');
  });

  it('handles an empty backup', async () => {
    const empty: NormalizedBackup = { manga: [], categories: [], sources: [] };
    expect(await roundTrip(empty)).toEqual(empty);
  });

  it('round-trips titles with no optional metadata', async () => {
    const bare = manga({
      author: undefined,
      artist: undefined,
      description: undefined,
      thumbnailUrl: undefined,
      genres: [],
      notes: '',
      categoryNames: [],
      chapters: [],
      tracking: [],
    });
    const out = await roundTrip(backup({ manga: [bare] }));
    expect(out.manga[0]).toEqual(bare);
  });
});

describe('buildBackupFileName', () => {
  it("follows Mihon's <app>_yyyy-MM-dd_HH-mm.tachibk convention", () => {
    const at = new Date(2026, 7, 6, 14, 3); // local time, 6 Aug 2026 14:03
    expect(buildBackupFileName('app.mihon', at)).toBe(
      'app.mihon_2026-08-06_14-03.tachibk',
    );
  });

  it('falls back to the mangavault app id when none is given', () => {
    expect(buildBackupFileName('', new Date(2026, 0, 2, 3, 4))).toBe(
      'mangavault_2026-01-02_03-04.tachibk',
    );
  });

  it('produces a name the import path attributes back to the same app', async () => {
    const name = buildBackupFileName('app.komikku', new Date(2026, 7, 6, 9, 0));
    const bytes = await encoder.encode(denormalizer.denormalize(backup()));
    const parsed = await parser.parse(bytes, name);
    expect(parsed.sourceApp).toBe('app.komikku');
  });
});
