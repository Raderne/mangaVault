import { generateSourceId } from './generate-id';
import {
  detectIndexFormat,
  isPlaceholderIndex,
  parseIndexLegacy,
  parseIndexV2,
  parseRepoIndex,
  parseRepoMeta,
  resolveIndexUrls,
} from './parse';

const BASE = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo';

const v2Body = (extensions: unknown[]) => ({
  name: 'Keiyoushi',
  badgeLabel: 'KEI',
  signingKey: 'abc',
  extensionList: { extensions },
});

const v2Entry = () => ({
  name: 'MangaDex',
  packageName: 'eu.kanade.tachiyomi.extension.all.mangadex',
  resources: {
    apkUrl: 'https://example.test/mangadex.apk',
    iconUrl: 'https://example.test/mangadex.png',
    jarUrl: 'https://example.test/mangadex.jar',
  },
  extensionLib: '1.4',
  versionCode: '212',
  versionName: '1.4.212',
  contentWarning: 'CONTENT_WARNING_MIXED',
  sources: [
    {
      id: '2499283573021220255',
      name: 'MangaDex',
      language: 'en',
      homeUrl: 'https://mangadex.org',
      mirrorUrls: ['https://mangadex.dev'],
    },
    {
      id: '3339599426223341161',
      name: 'MangaDex',
      language: 'ar',
      homeUrl: 'https://mangadex.org',
    },
  ],
});

describe('parseRepoMeta', () => {
  it('reads meta and the v2 index pointer', () => {
    const meta = parseRepoMeta(`${BASE}/`, {
      index_v2: `${BASE}/index.pb`,
      meta: {
        name: 'Keiyoushi',
        website: 'https://keiyoushi.github.io',
        signingKeyFingerprint: '9add655a',
      },
    });
    expect(meta).toEqual({
      // The trailing slash is dropped so url building stays predictable.
      baseUrl: BASE,
      name: 'Keiyoushi',
      shortName: null,
      website: 'https://keiyoushi.github.io',
      signingKeyFingerprint: '9add655a',
      indexV2Url: `${BASE}/index.pb`,
    });
  });

  it('accepts a legacy repo that publishes only meta', () => {
    const meta = parseRepoMeta(BASE, {
      meta: { name: 'Some Repo', website: 'https://example.test' },
    });
    expect(meta.indexV2Url).toBeNull();
    expect(meta.signingKeyFingerprint).toBeNull();
  });

  it('rejects a body that is not a repository descriptor', () => {
    expect(() => parseRepoMeta(BASE, { hello: 'world' })).toThrow(
      /no "meta" object/,
    );
    expect(() => parseRepoMeta(BASE, [1, 2, 3])).toThrow(/not a JSON object/);
  });
});

describe('resolveIndexUrls', () => {
  it('prefers the v2 JSON mirror over the legacy index', () => {
    expect(resolveIndexUrls(`${BASE}/`)).toEqual([
      `${BASE}/index.json`,
      `${BASE}/index.min.json`,
    ]);
  });
});

describe('detectIndexFormat', () => {
  it('tells the two wire formats apart', () => {
    expect(detectIndexFormat(v2Body([]))).toBe('v2');
    expect(detectIndexFormat([])).toBe('legacy');
    expect(detectIndexFormat({ nope: true })).toBeNull();
  });
});

describe('parseIndexV2', () => {
  it('normalizes an extension and its per-language sources', () => {
    const parsed = parseIndexV2(BASE, v2Body([v2Entry()]));

    expect(parsed.format).toBe('v2');
    expect(parsed.warnings).toEqual([]);
    expect(parsed.extensions).toEqual([
      {
        packageName: 'eu.kanade.tachiyomi.extension.all.mangadex',
        name: 'MangaDex',
        versionName: '1.4.212',
        versionCode: 212,
        extensionLib: '1.4',
        contentWarning: 'mixed',
        apkUrl: 'https://example.test/mangadex.apk',
        iconUrl: 'https://example.test/mangadex.png',
        sourceIds: ['2499283573021220255', '3339599426223341161'],
      },
    ]);
    expect(parsed.sources[0]).toEqual({
      sourceId: '2499283573021220255',
      name: 'MangaDex',
      lang: 'en',
      homeUrl: 'https://mangadex.org',
      mirrorUrls: ['https://mangadex.dev'],
      packageName: 'eu.kanade.tachiyomi.extension.all.mangadex',
    });
  });

  it('keeps ids past 2^53 exact', () => {
    const id = '9127464796236242233';
    const entry = {
      ...v2Entry(),
      sources: [{ id, name: 'X', language: 'az' }],
    };
    const parsed = parseIndexV2(BASE, v2Body([entry]));

    expect(parsed.sources[0].sourceId).toBe(id);
    // The reason we never let one of these become a JS number.
    expect(String(Number(id))).not.toBe(id);
  });

  it('skips a broken entry instead of losing the rest', () => {
    const parsed = parseIndexV2(
      BASE,
      v2Body([{ name: 'No package' }, v2Entry()]),
    );
    expect(parsed.extensions).toHaveLength(1);
    expect(parsed.warnings).toEqual([
      'v2 entry without packageName or name; skipped',
    ]);
  });

  it('warns when two packages claim one source id, keeping the first', () => {
    const other = {
      ...v2Entry(),
      packageName: 'eu.kanade.tachiyomi.extension.all.impostor',
      sources: [
        { id: '2499283573021220255', name: 'Impostor', language: 'en' },
      ],
    };
    const parsed = parseIndexV2(BASE, v2Body([v2Entry(), other]));

    expect(parsed.sources).toHaveLength(2);
    expect(
      parsed.sources.find((s) => s.sourceId === '2499283573021220255')?.name,
    ).toBe('MangaDex');
    expect(parsed.warnings[0]).toMatch(/claimed by both/);
  });

  it('defaults an unknown content warning to safe', () => {
    const entry = { ...v2Entry(), contentWarning: 'CONTENT_WARNING_FUTURE' };
    expect(
      parseIndexV2(BASE, v2Body([entry])).extensions[0].contentWarning,
    ).toBe('safe');
  });
});

describe('parseIndexLegacy', () => {
  const legacyEntry = {
    name: 'Tachiyomi: Asura Scans',
    pkg: 'eu.kanade.tachiyomi.extension.en.asurascans',
    apk: 'tachiyomi-en.asurascans-v1.4.23.apk',
    lang: 'en',
    code: 23,
    version: '1.4.23',
    nsfw: 0,
    sources: [
      {
        id: '6247824327199706550',
        lang: 'en',
        name: 'Asura Scans',
        baseUrl: 'https://asuracomic.net',
      },
    ],
  };

  it('derives apk and icon urls from the repository layout', () => {
    const parsed = parseIndexLegacy(`${BASE}/`, [legacyEntry]);

    expect(parsed.format).toBe('legacy');
    expect(parsed.extensions[0]).toMatchObject({
      // The "Tachiyomi: " prefix is stripped, as Mihon does.
      name: 'Asura Scans',
      versionCode: 23,
      extensionLib: '1.4',
      contentWarning: 'safe',
      apkUrl: `${BASE}/apk/tachiyomi-en.asurascans-v1.4.23.apk`,
      iconUrl: `${BASE}/icon/eu.kanade.tachiyomi.extension.en.asurascans.png`,
    });
    expect(parsed.sources[0].homeUrl).toBe('https://asuracomic.net');
  });

  it('maps the nsfw flag onto the content warning', () => {
    const parsed = parseIndexLegacy(BASE, [{ ...legacyEntry, nsfw: 1 }]);
    expect(parsed.extensions[0].contentWarning).toBe('nsfw');
  });

  it('drops a source whose id already lost precision in JSON', () => {
    // What `JSON.parse` leaves behind for an unquoted 64-bit id.
    const parsed = parseIndexLegacy(BASE, [
      { ...legacyEntry, sources: [{ id: 6247824327199259000, lang: 'en' }] },
    ]);
    expect(parsed.sources).toHaveLength(0);
    expect(parsed.warnings[0]).toMatch(/lost precision/);
  });
});

describe('isPlaceholderIndex', () => {
  it('recognises the stub a v2 repo serves at index.min.json', () => {
    // Verbatim shape of the current keiyoushi index.min.json.
    const stub = parseIndexLegacy(BASE, [
      {
        name: 'Outdated App',
        pkg: 'eu.kanade.tachiyomi.extension.all.keiyoushi',
        apk: 'tachiyomi-all.keiyoushi-v1.4.1.apk',
        lang: 'all',
        code: 1,
        version: '1.4.1',
        nsfw: 0,
        sources: [
          {
            name: 'Outdated App',
            lang: 'all',
            id: '1',
            baseUrl: 'https://keiyoushi.github.io',
          },
        ],
      },
      {
        name: 'Update to Mihon 0.20.1+',
        pkg: 'eu.kanade.tachiyomi.extension.all.mihon',
        apk: 'tachiyomi-all.mihon-v1.4.1.apk',
        lang: 'all',
        code: 1,
        version: '1.4.1',
        nsfw: 0,
        sources: [
          {
            name: 'Update to Mihon 0.20.1+',
            lang: 'all',
            id: '1',
            baseUrl: 'https://mihon.app',
          },
        ],
      },
    ]);

    expect(isPlaceholderIndex(stub)).toBe(true);
  });

  it('does not mistake a small real repo for the stub', () => {
    expect(isPlaceholderIndex(parseIndexV2(BASE, v2Body([v2Entry()])))).toBe(
      false,
    );
  });

  it('is false for an empty index (nothing to conclude)', () => {
    expect(isPlaceholderIndex(parseIndexV2(BASE, v2Body([])))).toBe(false);
  });
});

describe('parseRepoIndex', () => {
  it('dispatches on the detected format', () => {
    expect(parseRepoIndex(BASE, v2Body([v2Entry()])).format).toBe('v2');
    expect(parseRepoIndex(BASE, []).format).toBe('legacy');
    expect(() => parseRepoIndex(BASE, { nope: 1 })).toThrow(/neither a v2/);
  });
});

describe('generateSourceId', () => {
  // Mihon: MD5 of "name.lowercase()/lang/versionId", first 8 bytes BE, sign
  // bit cleared. These are live ids from the keiyoushi index.
  it.each([
    ['MangaDex', 'en', 1, '2499283573021220255'],
    ['Weeb Central', 'en', 1, '2131019126180322627'],
  ])('reproduces %s (%s)', (name, lang, versionId, expected) => {
    expect(generateSourceId(name, lang, versionId)).toBe(expected);
  });

  it('lowercases the name, as Mihon does', () => {
    expect(generateSourceId('MANGADEX', 'en', 1)).toBe(
      generateSourceId('mangadex', 'en', 1),
    );
  });

  it('always clears the sign bit', () => {
    for (let i = 0; i < 200; i++) {
      const id = BigInt(generateSourceId(`source ${i}`, 'en', 0));
      expect(id).toBeLessThanOrEqual(0x7fffffffffffffffn);
      expect(id).toBeGreaterThanOrEqual(0n);
    }
  });
});
