import { Logger } from '@nestjs/common';

import type { CoverFetchHint } from '../../entities/known-source.entity';
import { sniffImage } from './image-sniff';

export interface FetchedCover {
  bytes: Buffer;
  mime: string;
}

export interface CoverFetcherOptions {
  /** Abort a single attempt after this long. */
  timeoutMs: number;
  /** Reject a body larger than this (bytes). */
  maxBytes: number;
  /** Total attempts before giving up (>=1). */
  maxAttempts: number;
  /** Base delay for exponential backoff between attempts. */
  baseBackoffMs: number;
  /** Fallback User-Agent when a source has no override. */
  userAgent: string;
}

export const DEFAULT_COVER_FETCHER_OPTIONS: CoverFetcherOptions = {
  timeoutMs: 20_000,
  maxBytes: 15 * 1024 * 1024,
  maxAttempts: 3,
  baseBackoffMs: 500,
  // A current desktop-Chrome UA: many manga source CDNs 403 default agents.
  userAgent:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
};

/** HTTP statuses worth a retry (transient/server-side/rate-limit). */
const RETRIABLE_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);

/**
 * Failure carrying the last HTTP status (if any) and whether another attempt
 * could plausibly help. Transient HTTP statuses and network/abort errors are
 * retriable; a 200 with a bad body (non-image, empty, oversized) is not — the
 * host answered, it just answered wrong.
 */
export class CoverFetchError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly retriable = false,
  ) {
    super(message);
    this.name = 'CoverFetchError';
  }
}

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));

/**
 * Downloads a cover image the way Mihon would: a browser-like User-Agent plus a
 * `Referer` derived from the thumbnail's own origin (many source CDNs 403
 * otherwise), with per-source header overrides, a bounded timeout, and
 * exponential-backoff retries on transient failures. The response is validated
 * by **sniffing the bytes** — a host lying in its `Content-Type` won't smuggle
 * an HTML error page into the archive.
 */
export class CoverFetcher {
  private readonly logger = new Logger(CoverFetcher.name);
  private readonly opts: CoverFetcherOptions;

  constructor(options?: Partial<CoverFetcherOptions>) {
    this.opts = { ...DEFAULT_COVER_FETCHER_OPTIONS, ...options };
  }

  async fetch(
    url: string,
    hint?: CoverFetchHint | null,
  ): Promise<FetchedCover> {
    let origin: string;
    try {
      origin = new URL(url).origin;
    } catch {
      throw new CoverFetchError(`invalid cover url: ${url}`);
    }

    const headers: Record<string, string> = {
      'User-Agent': hint?.userAgent ?? this.opts.userAgent,
      Referer: hint?.referer ?? `${origin}/`,
      Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };

    let lastError: CoverFetchError | undefined;
    for (let attempt = 1; attempt <= this.opts.maxAttempts; attempt++) {
      try {
        return await this.attempt(url, headers);
      } catch (err) {
        // A raw throw (network reset, abort/timeout) is transient → retriable.
        const e =
          err instanceof CoverFetchError
            ? err
            : new CoverFetchError(
                err instanceof Error ? err.message : 'cover fetch failed',
                undefined,
                true,
              );
        lastError = e;
        if (!e.retriable || attempt === this.opts.maxAttempts) break;
        const backoff =
          this.opts.baseBackoffMs * 2 ** (attempt - 1) +
          Math.floor(Math.random() * 200);
        this.logger.debug(
          `cover fetch ${url} attempt ${attempt} failed (${e.message}); retrying in ${backoff}ms`,
        );
        await sleep(backoff);
      }
    }
    throw lastError ?? new CoverFetchError('cover fetch failed');
  }

  private async attempt(
    url: string,
    headers: Record<string, string>,
  ): Promise<FetchedCover> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.opts.timeoutMs);
    try {
      const res = await fetch(url, {
        headers,
        redirect: 'follow',
        signal: controller.signal,
      });
      if (!res.ok) {
        throw new CoverFetchError(
          `HTTP ${res.status}`,
          res.status,
          RETRIABLE_STATUS.has(res.status),
        );
      }

      const declared = Number(res.headers.get('content-length'));
      if (Number.isFinite(declared) && declared > this.opts.maxBytes) {
        throw new CoverFetchError(
          `cover too large (${declared} bytes)`,
          res.status,
        );
      }

      const bytes = Buffer.from(await res.arrayBuffer());
      if (bytes.length === 0) {
        throw new CoverFetchError('empty cover response', res.status);
      }
      if (bytes.length > this.opts.maxBytes) {
        throw new CoverFetchError(
          `cover too large (${bytes.length} bytes)`,
          res.status,
        );
      }

      const sniffed = sniffImage(bytes);
      if (!sniffed) {
        const ct = res.headers.get('content-type') ?? 'unknown';
        throw new CoverFetchError(`response was not an image (${ct})`);
      }
      return { bytes, mime: sniffed.mime };
    } finally {
      clearTimeout(timer);
    }
  }
}
