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
  timeoutMs: 30_000, // matches Mihon's OkHttp connect/read timeout
  maxBytes: 15 * 1024 * 1024,
  maxAttempts: 3,
  baseBackoffMs: 500,
  // Mihon's own default User-Agent (NetworkPreferences.kt) — a **mobile** Android
  // Chrome. Source CDNs fingerprint this; a desktop UA gets 403'd/blocked by some.
  userAgent:
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
};

/** HTTP statuses worth a retry (transient/server-side/rate-limit). */
const RETRIABLE_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);

/**
 * Unwrap the useful bit of a thrown fetch error. Node's global `fetch` throws a
 * `TypeError: fetch failed` whose real reason (`ECONNRESET`, `UND_ERR_*`, TLS
 * failure, DNS, …) hides in `.cause` — surface it so failures are diagnosable
 * instead of a uniform "fetch failed".
 */
function describeCause(err: unknown): string {
  if (err instanceof Error) {
    const cause = (err as { cause?: unknown }).cause;
    if (cause instanceof Error) {
      const code = (cause as { code?: string }).code;
      return `${err.message}: ${code ?? cause.message}`;
    }
    return err.message;
  }
  return 'cover fetch failed';
}

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
 * Downloads a cover image the way Mihon would: its **mobile** default
 * User-Agent, browser-like image headers, and a `Referer` pointed at the
 * source's *site* origin (a browser loading an `<img>` sends the site, not the
 * CDN sub-domain — e.g. `gg.asuracomic.net` → `asuracomic.net`), with per-source
 * header overrides (`known_source.fetch_hint`), a bounded timeout, and
 * exponential-backoff retries on transient/connection failures. The response is
 * validated by **sniffing the bytes** — a host lying in its `Content-Type` won't
 * smuggle an HTML error page into the archive.
 *
 * Limitation: sources behind a Cloudflare JS/TLS challenge (AsuraScans et al.)
 * can still fail at the connection layer (`fetch failed`) — Mihon clears those
 * with an on-device WebView we can't replicate server-side.
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
    // Fragments (e.g. `#image-request`) are client-side only — strip so the URL
    // we request, and derive headers from, is clean.
    const cleanUrl = url.split('#')[0].trim();
    let parsed: URL;
    try {
      parsed = new URL(cleanUrl);
    } catch {
      throw new CoverFetchError(`invalid cover url: ${url}`);
    }

    const headers = this.buildHeaders(parsed, hint);

    let lastError: CoverFetchError | undefined;
    for (let attempt = 1; attempt <= this.opts.maxAttempts; attempt++) {
      try {
        return await this.attempt(cleanUrl, headers);
      } catch (err) {
        // A raw throw (network reset, abort/timeout) is transient → retriable.
        const e =
          err instanceof CoverFetchError
            ? err
            : new CoverFetchError(describeCause(err), undefined, true);
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

  /** Browser-like image request headers (Mihon UA + a plausible site Referer). */
  private buildHeaders(
    u: URL,
    hint?: CoverFetchHint | null,
  ): Record<string, string> {
    return {
      'User-Agent': hint?.userAgent ?? this.opts.userAgent,
      Accept:
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      Referer: this.resolveReferer(u, hint),
      // What a browser sends when loading an <img> cross-site.
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
    };
  }

  /**
   * Referer a browser on the source site would send. Prefer an explicit
   * per-source override, else the **registrable domain** of the thumbnail host
   * (so a CDN sub-domain like `gg.asuracomic.net` → `https://asuracomic.net/`),
   * else the thumbnail origin (IPs / bare domains).
   */
  private resolveReferer(u: URL, hint?: CoverFetchHint | null): string {
    if (hint?.referer) return hint.referer;
    const host = u.hostname;
    const isIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':');
    const labels = host.split('.');
    if (!isIp && labels.length > 2) {
      return `${u.protocol}//${labels.slice(-2).join('.')}/`;
    }
    return `${u.origin}/`;
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
