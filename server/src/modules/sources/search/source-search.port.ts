import type { MatchCandidate } from '../match/title-match';

/**
 * A source we can actually query, as the registry knows it.
 *
 * `packageName` is what an adapter binds to, never the source id: one package
 * publishes a source id per language (MangaDex ships 61, Comick 18), so binding
 * to ids would mean enumerating dozens of constants that change whenever an
 * extension adds a language. `lang` then picks which of them we are serving.
 */
export interface SearchableSource {
  sourceId: string;
  packageName: string;
  name: string;
  lang: string;
  homeUrl: string | null;
}

/** A search hit, in the shape the matcher scores and the migration applies. */
export interface SourceCandidate extends MatchCandidate {
  /** Where it came from, for the review list. */
  via: 'adapter' | 'vault' | 'manual';
}

/**
 * Live title lookup against one family of sources.
 *
 * **Why this is a port with only a few implementations.** Mihon searches a
 * source by loading that source's extension — an Android APK of compiled Kotlin
 * — and calling into it. A Node server cannot do that at any price, and the
 * alternative (a JVM sidecar running the real extensions) needs about as much
 * memory as this whole server is allowed on the deployment box. So instead of
 * pretending to cover all 2,156 sources, we implement the handful that publish
 * a usable public API and are honest about the rest: a source with no adapter
 * still migrates, using titles already in the vault or a url the user pastes.
 *
 * The port exists so that stays a *configuration* fact rather than an
 * architectural one — a future adapter, including one that proxies to an
 * external extension runner, plugs in here without touching the migration flow.
 */
export interface SourceSearchAdapter {
  /** Extension package this adapter speaks for. */
  readonly packageName: string;
  /** Shown in the app as the reason a source can be searched automatically. */
  readonly displayName: string;
  /**
   * Best candidates for `query` on `source`, unranked — scoring is the
   * matcher's job. Must resolve to `[]` rather than throw for "no results",
   * and must honour `signal` so a cancelled migration plan stops promptly.
   */
  search(
    source: SearchableSource,
    query: string,
    signal?: AbortSignal,
  ): Promise<SourceCandidate[]>;
}

/** Thrown when a source's API answers, but with something unusable. */
export class SourceSearchError extends Error {
  constructor(
    readonly packageName: string,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'SourceSearchError';
  }
}
