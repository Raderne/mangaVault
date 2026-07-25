import { BackupNormalizer } from './normalize';
import { BackupParser } from './parse';

describe('legacy JSON import', () => {
  it('parses an object-keyed legacy backup into the normalized model', async () => {
    const legacy = {
      version: 2,
      categories: [{ name: 'Reading', order: 0 }],
      mangas: [
        {
          manga: {
            source: '2499283573021220255', // quoted: only way int64 survives JSON
            url: '/manga/solo-leveling',
            title: 'Solo Leveling',
            author: 'Chugong',
            status: 2,
            thumbnail_url: 'https://example.com/c.jpg',
            genre: ['Action', 'Fantasy'],
            favorite: true,
          },
          chapters: [
            { url: '/c/1', name: 'Chapter 1', read: true, last_page_read: 12 },
          ],
          categories: [0],
          history: [{ url: '/c/1', last_read: 5000, read_duration: 60 }],
        },
      ],
    };
    const bytes = new TextEncoder().encode(JSON.stringify(legacy));

    const parsed = await new BackupParser().parse(bytes, 'backup.json');
    expect(parsed.container).toBe('legacy-json');

    const normalized = new BackupNormalizer().normalize(parsed);
    const m = normalized.manga[0];
    expect(m.key.sourceId).toBe('2499283573021220255'); // int64 preserved as string
    expect(m).toMatchObject({
      title: 'Solo Leveling',
      author: 'Chugong',
      status: 'completed',
    });
    expect(m.genres).toEqual(['Action', 'Fantasy']);
    expect(m.categoryNames).toEqual(['Reading']);
    expect(m.chapters[0]).toMatchObject({
      name: 'Chapter 1',
      read: true,
      lastReadAt: 5000,
      readDuration: 60,
    });
  });

  it('throws a JSON-stage error on malformed JSON', async () => {
    const bytes = new TextEncoder().encode('{ not valid json ');
    await expect(
      new BackupParser().parse(bytes, 'x.json'),
    ).rejects.toMatchObject({
      name: 'BackupParseError',
      stage: 'json',
    });
  });
});
