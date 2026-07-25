import { CoverFetcher, CoverFetchError } from './cover.fetcher';

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(32),
]);

const imageResponse = (bytes = PNG, headers: Record<string, string> = {}) =>
  new Response(bytes, {
    status: 200,
    headers: { 'content-type': 'image/png', ...headers },
  });

describe('CoverFetcher', () => {
  let fetchMock: jest.Mock;
  // Near-zero backoff so the retry paths don't slow the suite.
  const fetcher = new CoverFetcher({ baseBackoffMs: 1, maxAttempts: 3 });

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock;
  });

  it('sends the mobile UA + site-origin Referer and returns sniffed bytes', async () => {
    fetchMock.mockResolvedValueOnce(imageResponse());

    // Sub-domain host: Referer should point at the registrable site, not the CDN.
    const result = await fetcher.fetch('https://gg.asuracomic.net/a/cover.png');

    expect(result.mime).toBe('image/png');
    expect(result.bytes.length).toBe(PNG.length);
    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers['User-Agent']).toContain('Mobile'); // Mihon's mobile UA
    expect(headers['Referer']).toBe('https://asuracomic.net/');
    expect(headers['Sec-Fetch-Dest']).toBe('image');
  });

  it('uses the thumbnail origin as Referer for a bare domain', async () => {
    fetchMock.mockResolvedValueOnce(imageResponse());
    await fetcher.fetch('https://mangadex.org/covers/x.png');
    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect((init.headers as Record<string, string>)['Referer']).toBe(
      'https://mangadex.org/',
    );
  });

  it('applies per-source header overrides', async () => {
    fetchMock.mockResolvedValueOnce(imageResponse());

    await fetcher.fetch('https://cdn.example.com/x.png', {
      referer: 'https://reader.example.org/',
      userAgent: 'CustomAgent/1.0',
    });

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers['Referer']).toBe('https://reader.example.org/');
    expect(headers['User-Agent']).toBe('CustomAgent/1.0');
  });

  it('retries a transient 503 then succeeds', async () => {
    fetchMock
      .mockResolvedValueOnce(new Response('busy', { status: 503 }))
      .mockResolvedValueOnce(imageResponse());

    const result = await fetcher.fetch('https://cdn.example.com/x.png');

    expect(result.mime).toBe('image/png');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('retries a network error then succeeds', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('ECONNRESET'))
      .mockResolvedValueOnce(imageResponse());

    const result = await fetcher.fetch('https://cdn.example.com/x.png');

    expect(result.bytes.length).toBe(PNG.length);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not retry a hard 403 and surfaces the status', async () => {
    fetchMock.mockResolvedValue(new Response('denied', { status: 403 }));

    await expect(
      fetcher.fetch('https://cdn.example.com/x.png'),
    ).rejects.toMatchObject({ status: 403 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('rejects a non-image body (host lied in content-type)', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response('<html>error</html>', {
        status: 200,
        headers: { 'content-type': 'image/jpeg' },
      }),
    );

    await expect(
      fetcher.fetch('https://cdn.example.com/x.png'),
    ).rejects.toBeInstanceOf(CoverFetchError);
    expect(fetchMock).toHaveBeenCalledTimes(1); // not retried
  });

  it('rejects an oversized cover by content-length', async () => {
    const small = new CoverFetcher({ maxBytes: 100, maxAttempts: 1 });
    fetchMock.mockResolvedValueOnce(
      imageResponse(PNG, { 'content-length': '999999' }),
    );

    await expect(
      small.fetch('https://cdn.example.com/x.png'),
    ).rejects.toBeInstanceOf(CoverFetchError);
  });

  it('throws a non-retriable error for an invalid URL', async () => {
    await expect(fetcher.fetch('not-a-url')).rejects.toBeInstanceOf(
      CoverFetchError,
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
