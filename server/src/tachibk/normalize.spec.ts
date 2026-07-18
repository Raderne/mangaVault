import { BackupNormalizer } from './normalize';
import { BackupParser } from './parse';
import { encodeBackup } from './test-util';

async function normalizeBytes(backup: Record<string, unknown>) {
  const parsed = await new BackupParser().parse(
    encodeBackup(backup),
    'x.tachibk',
  );
  return {
    normalized: new BackupNormalizer().normalize(parsed),
    warnings: parsed.warnings,
  };
}

describe('BackupNormalizer', () => {
  it('applies Mihon defaults (favorite=true when absent) and maps status', async () => {
    const { normalized } = await normalizeBytes({
      backupManga: [
        { source: '1', url: '/a', title: 'A', status: 2 }, // completed, favorite omitted
        { source: '1', url: '/b', title: 'B', favorite: false, status: 6 }, // on_hiatus
      ],
    });
    expect(normalized.manga[0]).toMatchObject({
      status: 'completed',
      favorite: true,
    });
    expect(normalized.manga[1]).toMatchObject({
      status: 'on_hiatus',
      favorite: false,
    });
  });

  it('resolves category orders to names', async () => {
    const { normalized } = await normalizeBytes({
      backupManga: [
        { source: '1', url: '/a', title: 'A', categories: ['0', '2'] },
      ],
      backupCategories: [
        { name: 'Reading', order: '0' },
        { name: 'Completed', order: '2' },
      ],
    });
    expect(normalized.manga[0].categoryNames).toEqual(['Reading', 'Completed']);
  });

  it('folds reading history into chapters (max lastRead, summed duration)', async () => {
    const { normalized } = await normalizeBytes({
      backupManga: [
        {
          source: '1',
          url: '/a',
          title: 'A',
          chapters: [{ url: '/a/c1', name: 'Ch 1', read: true }],
          history: [
            { url: '/a/c1', lastRead: '1000', readDuration: '30' },
            { url: '/a/c1', lastRead: '5000', readDuration: '45' },
          ],
        },
      ],
    });
    const ch = normalized.manga[0].chapters[0];
    expect(ch.lastReadAt).toBe(5000);
    expect(ch.readDuration).toBe(75);
  });

  it('maps trackers and prefers int64 mediaId over deprecated mediaIdInt', async () => {
    const { normalized } = await normalizeBytes({
      backupManga: [
        {
          source: '1',
          url: '/a',
          title: 'A',
          tracking: [
            { syncId: 2, mediaId: '105398' }, // anilist, mediaIdInt omitted
            { syncId: 99, mediaIdInt: 7 }, // unknown tracker, legacy int id
          ],
        },
      ],
    });
    expect(normalized.manga[0].tracking[0]).toMatchObject({
      tracker: 'anilist',
      remoteId: '105398',
    });
    expect(normalized.manga[0].tracking[1]).toMatchObject({
      tracker: 'unknown:99',
      remoteId: '7',
    });
  });

  it('skips a manga missing url/source and records a warning', async () => {
    const { normalized, warnings } = await normalizeBytes({
      backupManga: [{ source: '1', title: 'no url' }],
    });
    expect(normalized.manga).toHaveLength(0);
    expect(warnings.join(' ')).toMatch(/missing source\/url/);
  });
});
