import { Injectable, Logger } from '@nestjs/common';

import {
  isPlaceholderIndex,
  parseRepoIndex,
  parseRepoMeta,
  resolveIndexUrls,
  RepoIndexError,
  type ParsedRepoIndex,
  type RepoMeta,
} from '../../extrepo';

export interface RepoIndexClientOptions {
  timeoutMs: number;
  /** Refuse a body larger than this. The real index is ~1.4 MB. */
  maxBytes: number;
  userAgent: string;
}

const DEFAULTS: RepoIndexClientOptions = {
  timeoutMs: 30_000,
  maxBytes: 32 * 1024 * 1024,
  userAgent: 'MangaVault/1.0 (+https://github.com/mangavault)',
};

/** Outcome of one index fetch. */
export type IndexFetch =
  | { kind: 'unchanged' }
  | { kind: 'index'; index: ParsedRepoIndex; url: string; etag: string | null };

/**
 * Fetches and decodes extension-repository documents.
 *
 * The only network-facing half of the registry; parsing lives in the pure
 * `extrepo` lib. Two behaviours matter here:
 *
 *   * **Conditional requests.** The index is ~1.4 MB and changes maybe daily.
 *     Passing the stored ETag back turns almost every scheduled sync into a 304
 *     with no body — which is what makes a daily refresh free on a 1-OCPU box.
 *   * **Placeholder refusal.** A repository that has moved to the v2 index keeps
 *     serving `index.min.json`, but its contents are now a two-entry "update
 *     your app" stub. Ingesting that would delist every source in the vault, so
 *     a placeholder is treated as "this url is not the index" and the next
 *     candidate is tried.
 */
@Injectable()
export class RepoIndexClient {
  private readonly logger = new Logger(RepoIndexClient.name);
  private readonly opts: RepoIndexClientOptions;

  constructor(opts: Partial<RepoIndexClientOptions> = {}) {
    this.opts = { ...DEFAULTS, ...opts };
  }

  /** `GET {baseUrl}/repo.json` → repository identity. */
  async fetchMeta(baseUrl: string): Promise<RepoMeta> {
    const url = `${baseUrl}/repo.json`;
    const res = await this.get(url);
    if (!res.ok) {
      throw new RepoIndexError(
        'repo-meta',
        `${url} answered HTTP ${res.status}`,
      );
    }
    return parseRepoMeta(baseUrl, await this.json(res, url));
  }

  /**
   * Fetch the index, preferring `preferredUrl` (whatever answered last time).
   *
   * `etag` is sent on the preferred url only: a 304 is only meaningful for the
   * document the tag came from.
   */
  async fetchIndex(
    baseUrl: string,
    preferredUrl?: string | null,
    etag?: string | null,
  ): Promise<IndexFetch> {
    const candidates = resolveIndexUrls(baseUrl);
    const urls = preferredUrl
      ? [preferredUrl, ...candidates.filter((u) => u !== preferredUrl)]
      : candidates;

    const failures: string[] = [];
    for (const url of urls) {
      const conditional = url === preferredUrl ? etag : null;
      const res = await this.get(url, conditional);

      if (res.status === 304) return { kind: 'unchanged' };
      if (!res.ok) {
        failures.push(`${url}: HTTP ${res.status}`);
        continue;
      }

      let index: ParsedRepoIndex;
      try {
        index = parseRepoIndex(baseUrl, await this.json(res, url));
      } catch (err) {
        failures.push(
          `${url}: ${err instanceof Error ? err.message : String(err)}`,
        );
        continue;
      }

      if (isPlaceholderIndex(index)) {
        // Not an error — just the wrong document on a repo that has moved on.
        this.logger.debug(`${url} is an update-your-app placeholder; skipping`);
        failures.push(`${url}: placeholder index`);
        continue;
      }
      if (index.sources.length === 0) {
        failures.push(`${url}: index lists no sources`);
        continue;
      }

      return { kind: 'index', index, url, etag: res.headers.get('etag') };
    }

    throw new RepoIndexError(
      'index-parse',
      `no usable index at ${baseUrl} (${failures.join('; ')})`,
    );
  }

  // ---- internals ----

  private async get(url: string, etag?: string | null): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.opts.timeoutMs);
    try {
      return await fetch(url, {
        headers: {
          'User-Agent': this.opts.userAgent,
          Accept: 'application/json,*/*;q=0.8',
          ...(etag ? { 'If-None-Match': etag } : {}),
        },
        redirect: 'follow',
        signal: controller.signal,
      });
    } catch (err) {
      throw new RepoIndexError(
        'index-parse',
        `${url} unreachable (${err instanceof Error ? err.message : String(err)})`,
        err,
      );
    } finally {
      clearTimeout(timer);
    }
  }

  /** Read a JSON body, refusing anything implausibly large. */
  private async json(res: Response, url: string): Promise<unknown> {
    const declared = Number(res.headers.get('content-length'));
    if (Number.isFinite(declared) && declared > this.opts.maxBytes) {
      throw new RepoIndexError(
        'index-parse',
        `${url} is ${declared} bytes, over the ${this.opts.maxBytes} limit`,
      );
    }
    const text = await res.text();
    if (text.length > this.opts.maxBytes) {
      throw new RepoIndexError('index-parse', `${url} body over size limit`);
    }
    try {
      return JSON.parse(text) as unknown;
    } catch (err) {
      throw new RepoIndexError('index-parse', `${url} is not valid JSON`, err);
    }
  }
}
