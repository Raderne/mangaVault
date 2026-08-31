/**
 * Normalized model of an extension repository index.
 *
 * Two wire formats exist and both are still in the wild, so everything above
 * this file speaks only these types:
 *
 *   * **v2** — what Mihon 0.20.1+ reads. Discovered through `repo.json`, which
 *     points at a protobuf `index_v2`; repositories publish a JSON mirror of the
 *     same data at `index.json`.
 *   * **legacy** — the flat `index.min.json` array Mihon <= 0.20.0 read. Still
 *     served by older/self-hosted repos.
 *
 * Source ids are Mihon's 64-bit ids and stay **decimal strings** end to end, the
 * same discipline the rest of the vault uses for `manga.source_id` (see
 * `common/transformers.ts`). They are read from the index verbatim and never
 * recomputed — see `generateSourceId` for why.
 */

/** Repository-declared content rating for an extension. */
export type ContentWarning = 'safe' | 'mixed' | 'nsfw';

/** Which wire format an index was read from. */
export type RepoIndexFormat = 'v2' | 'legacy';

/** Repository identity, from `repo.json`. */
export interface RepoMeta {
  /** Index base url, without a trailing slash. */
  baseUrl: string;
  name: string;
  shortName: string | null;
  website: string;
  /**
   * SHA-256 of the APK signing certificate every extension in this repo is
   * signed with. Mihon uses it to decide whether an extension is trusted; we
   * only store it, but a *change* to it means the repo changed hands, which is
   * worth surfacing rather than silently accepting.
   */
  signingKeyFingerprint: string | null;
  /** Present on v2 repos: url of the protobuf index. */
  indexV2Url: string | null;
}

/** One source (a site, in one language) published by an extension. */
export interface IndexedSource {
  /** Mihon 64-bit source id as a decimal string. Matches `manga.source_id`. */
  sourceId: string;
  name: string;
  /** BCP-47-ish language tag as the repo writes it (`en`, `pt-BR`, `all`). */
  lang: string;
  /** Site home page, e.g. `https://mangadex.org`. */
  homeUrl: string;
  /** Alternate domains the extension also accepts (v2 only). */
  mirrorUrls: string[];
  /** Owning extension — the key adapters bind to, since one package can
   *  publish dozens of ids (MangaDex ships 61, one per language). */
  packageName: string;
}

/** One installable extension. */
export interface IndexedExtension {
  packageName: string;
  name: string;
  versionName: string;
  versionCode: number;
  /** extensions-lib API level (`1.4`, `1.6`), as published. */
  extensionLib: string;
  contentWarning: ContentWarning;
  apkUrl: string;
  iconUrl: string;
  sourceIds: string[];
}

/** A parsed index, ready to be reconciled against the registry tables. */
export interface ParsedRepoIndex {
  format: RepoIndexFormat;
  extensions: IndexedExtension[];
  sources: IndexedSource[];
  /**
   * Non-fatal oddities (an entry with no sources, a duplicate id, …). Collected
   * rather than thrown, exactly like `BackupParser`'s warnings: a single bad
   * entry must never cost us the other 1,379.
   */
  warnings: string[];
}
