import type { NormalizedManga } from '../../tachibk';
import { MergeableManga, MergeEngine } from './merge.engine';

const engine = new MergeEngine();

function incoming(over: Partial<NormalizedManga> = {}): NormalizedManga {
  return {
    key: { sourceId: '1', mangaUrl: '/a' },
    sourceName: 'Src',
    title: 'A',
    genres: [],
    status: 'ongoing',
    notes: '',
    favorite: true,
    dateAdded: 1000,
    lastModifiedAt: 2000,
    categoryNames: [],
    chapters: [],
    tracking: [],
    ...over,
  };
}

function existing(over: Partial<MergeableManga> = {}): MergeableManga {
  return engine.fromNormalized(
    incoming({ lastModifiedAt: 1000, ...(over as Partial<NormalizedManga>) }),
  );
}

describe('MergeEngine', () => {
  it('OR-merges favorite and never deletes chapters', () => {
    const base = existing({
      favorite: false,
      chapters: [chapter('/c1', { read: true, lastPageRead: 5 })],
    });
    const { merged } = engine.applyMerge(
      base,
      incoming({
        favorite: true,
        chapters: [normChapter('/c2')],
      }),
    );
    expect(merged.favorite).toBe(true);
    expect(merged.chapters.map((c) => c.url).sort()).toEqual(['/c1', '/c2']);
  });

  it('OR-merges read/bookmark and takes max progress per chapter url', () => {
    const base = existing({
      chapters: [
        chapter('/c1', {
          read: false,
          bookmark: true,
          lastPageRead: 3,
          readDuration: 10,
        }),
      ],
    });
    const { merged } = engine.applyMerge(
      base,
      incoming({
        chapters: [
          normChapter('/c1', {
            read: true,
            bookmark: false,
            lastPageRead: 9,
            readDuration: 4,
            lastReadAt: 500,
          }),
        ],
      }),
    );
    const c = merged.chapters.find((x) => x.url === '/c1')!;
    expect(c).toMatchObject({
      read: true,
      bookmark: true,
      lastPageRead: 9,
      readDuration: 10,
      lastReadAt: 500,
    });
  });

  it('never overwrites a non-empty scalar with an empty incoming one', () => {
    const base = existing({
      author: 'Chugong',
      updatedAt: 1000,
    });
    const { merged } = engine.applyMerge(
      base,
      incoming({ author: undefined, lastModifiedAt: 9999 }),
    );
    expect(merged.author).toBe('Chugong');
  });

  it('newer lastModifiedAt wins a genuine scalar conflict and reports it', () => {
    const base = existing({
      description: 'old',
      updatedAt: 1000,
    });
    const { merged, conflicts } = engine.applyMerge(
      base,
      incoming({ description: 'new', lastModifiedAt: 5000 }),
    );
    expect(merged.description).toBe('new');
    expect(conflicts).toContainEqual({
      field: 'description',
      kept: 'new',
      incoming: 'old',
    });
  });

  it('concatenates differing notes with a divider and flags a conflict', () => {
    const base = existing({ notes: 'first' });
    const { merged, conflicts } = engine.applyMerge(
      base,
      incoming({ notes: 'second' }),
    );
    expect(merged.notes).toContain('first');
    expect(merged.notes).toContain('second');
    expect(conflicts.some((c) => c.field === 'notes')).toBe(true);
  });

  it('unions genres and categories', () => {
    const base = existing({
      genres: ['Action'],
      categoryNames: ['Reading'],
    });
    const { merged } = engine.applyMerge(
      base,
      incoming({
        genres: ['Action', 'Fantasy'],
        categoryNames: ['Reading', 'Faves'],
      }),
    );
    expect(merged.genres).toEqual(['Action', 'Fantasy']);
    expect(merged.categoryNames).toEqual(['Reading', 'Faves']);
  });
});

function normChapter(
  url: string,
  over: Partial<import('../../tachibk').NormalizedChapter> = {},
) {
  return {
    url,
    name: url,
    chapterNumber: -1,
    read: false,
    bookmark: false,
    lastPageRead: 0,
    dateUpload: 0,
    dateFetch: 0,
    sourceOrder: 0,
    readDuration: 0,
    ...over,
  };
}
function chapter(
  url: string,
  over: Partial<import('../../tachibk').NormalizedChapter> = {},
) {
  return normChapter(url, over);
}
