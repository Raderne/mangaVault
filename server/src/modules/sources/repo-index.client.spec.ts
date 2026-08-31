import { RepoIndexClient } from './repo-index.client';

const BASE = 'https://repo.test/extensions';

/** Minimal v2 index with one real source. */
const v2Index = {
  name: 'Test Repo',
  extensionList: {
    extensions: [
      {
        name: 'MangaDex',
        packageName: 'eu.kanade.tachiyomi.extension.all.mangadex',
        resources: { apkUrl: 'a.apk', iconUrl: 'a.png', jarUrl: 'a.jar' },
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
          },
        ],
      },
    ],
  },
};

/** The stub a v2 repo now serves at the legacy path. */
const placeholder = [
  {
    name: 'Outdated App',
    pkg: 'eu.kanade.tachiyomi.extension.all.keiyoushi',
    apk: 'x.apk',
    lang: 'all',
    code: 1,
    version: '1.4.1',
    nsfw: 0,
    sources: [
      { name: 'Outdated App', lang: 'all', id: '1', baseUrl: 'https://k.test' },
    ],
  },
];

interface Reply {
  status?: number;
  body?: unknown;
  headers?: Record<string, string>;
}

/** Install a fetch stub that answers per-url, recording what was requested. */
function stubFetch(routes: Record<string, Reply | Reply[]>) {
  const calls: Array<{ url: string; headers: Record<string, string> }> = [];
  const remaining = new Map<string, Reply[]>(
    Object.entries(routes).map(([url, reply]) => [
      url,
      Array.isArray(reply) ? [...reply] : [reply],
    ]),
  );

  global.fetch = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({
      url,
      headers: (init?.headers ?? {}) as Record<string, string>,
    });
    const queue = remaining.get(url);
    const reply = queue && queue.length > 0 ? (queue.shift() as Reply) : null;
    if (!reply) {
      return new Response('not found', { status: 404 });
    }
    const status = reply.status ?? 200;
    return new Response(status === 304 ? null : JSON.stringify(reply.body), {
      status,
      headers: reply.headers,
    });
  }) as unknown as typeof fetch;

  return calls;
}

describe('RepoIndexClient', () => {
  const realFetch = global.fetch;
  let client: RepoIndexClient;

  beforeEach(() => {
    client = new RepoIndexClient({ timeoutMs: 1_000 });
  });

  afterAll(() => {
    global.fetch = realFetch;
  });

  describe('fetchMeta', () => {
    it('reads repo.json', async () => {
      stubFetch({
        [`${BASE}/repo.json`]: {
          body: {
            index_v2: `${BASE}/index.pb`,
            meta: {
              name: 'Test Repo',
              website: 'https://repo.test',
              signingKeyFingerprint: 'ff',
            },
          },
        },
      });

      await expect(client.fetchMeta(BASE)).resolves.toMatchObject({
        name: 'Test Repo',
        signingKeyFingerprint: 'ff',
        indexV2Url: `${BASE}/index.pb`,
      });
    });

    it('reports the status when repo.json is missing', async () => {
      stubFetch({});
      await expect(client.fetchMeta(BASE)).rejects.toThrow(/HTTP 404/);
    });
  });

  describe('fetchIndex', () => {
    it('prefers index.json', async () => {
      const calls = stubFetch({ [`${BASE}/index.json`]: { body: v2Index } });

      const result = await client.fetchIndex(BASE);

      expect(result).toMatchObject({ kind: 'index', url: `${BASE}/index.json` });
      expect(calls.map((c) => c.url)).toEqual([`${BASE}/index.json`]);
    });

    it('falls back to index.min.json when index.json is absent', async () => {
      const calls = stubFetch({
        [`${BASE}/index.min.json`]: {
          body: [
            {
              name: 'Asura',
              pkg: 'x.asura',
              apk: 'a.apk',
              lang: 'en',
              code: 1,
              version: '1.4.1',
              nsfw: 0,
              sources: [
                {
                  id: '6247824327199706550',
                  lang: 'en',
                  name: 'Asura',
                  baseUrl: 'https://asura.test',
                },
              ],
            },
          ],
        },
      });

      const result = await client.fetchIndex(BASE);

      expect(result).toMatchObject({ kind: 'index' });
      if (result.kind === 'index') expect(result.index.format).toBe('legacy');
      expect(calls.map((c) => c.url)).toEqual([
        `${BASE}/index.json`,
        `${BASE}/index.min.json`,
      ]);
    });

    it('refuses the update-your-app placeholder rather than delisting everything', async () => {
      stubFetch({ [`${BASE}/index.min.json`]: { body: placeholder } });

      // Both candidates answer with something; neither is usable data, so the
      // sync fails loudly instead of wiping the registry.
      await expect(client.fetchIndex(BASE)).rejects.toThrow(
        /placeholder index/,
      );
    });

    it('sends the stored ETag and reports 304 as unchanged', async () => {
      const calls = stubFetch({
        [`${BASE}/index.json`]: { status: 304 },
      });

      const result = await client.fetchIndex(BASE, `${BASE}/index.json`, 'W/"v1"');

      expect(result).toEqual({ kind: 'unchanged' });
      expect(calls[0].headers['If-None-Match']).toBe('W/"v1"');
    });

    it('only sends the ETag to the url it came from', async () => {
      const calls = stubFetch({
        [`${BASE}/index.json`]: { status: 404 },
        [`${BASE}/index.min.json`]: { body: v2Index },
      });

      await client.fetchIndex(BASE, `${BASE}/index.json`, 'W/"v1"');

      expect(calls[0].headers['If-None-Match']).toBe('W/"v1"');
      expect(calls[1].headers['If-None-Match']).toBeUndefined();
    });

    it('returns the new ETag so the next sync can be conditional', async () => {
      stubFetch({
        [`${BASE}/index.json`]: { body: v2Index, headers: { etag: 'W/"v2"' } },
      });

      const result = await client.fetchIndex(BASE);
      expect(result).toMatchObject({ etag: 'W/"v2"' });
    });

    it('rejects an index that lists no sources at all', async () => {
      stubFetch({
        [`${BASE}/index.json`]: { body: { extensionList: { extensions: [] } } },
      });
      await expect(client.fetchIndex(BASE)).rejects.toThrow(/lists no sources/);
    });
  });
});
