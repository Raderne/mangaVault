import type {
  ContentWarning,
  IndexedExtension,
  IndexedSource,
  ParsedRepoIndex,
  RepoIndexFormat,
  RepoMeta,
} from './domain';
import { RepoIndexError } from './errors';

/** Max entries we will ingest from one repository (keiyoushi ships ~1,380). */
const MAX_ENTRIES = 20_000;

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

const str = (v: unknown): string => (typeof v === 'string' ? v : '');

/** Repos publish `versionCode` as a string in v2 and a number in legacy. */
const int = (v: unknown): number => {
  const n = typeof v === 'string' ? Number(v) : v;
  return typeof n === 'number' && Number.isFinite(n) ? Math.trunc(n) : 0;
};

/**
 * Source ids are int64 and MUST survive as exact decimal strings. v2 already
 * quotes them; a legacy index does not, so by the time `JSON.parse` has run the
 * low bits of a large id are already gone. We cannot repair that here — the
 * entry is dropped with a warning rather than admitted with a subtly wrong id
 * that would attach vault rows to the wrong source.
 */
const sourceId = (v: unknown): string | null => {
  if (typeof v === 'string' && /^\d{1,20}$/.test(v.trim())) return v.trim();
  if (typeof v === 'number' && Number.isSafeInteger(v)) return String(v);
  return null;
};

const trimSlash = (u: string): string => u.replace(/\/+$/, '');

const CONTENT_WARNINGS: Record<string, ContentWarning> = {
  CONTENT_WARNING_SAFE: 'safe',
  CONTENT_WARNING_MIXED: 'mixed',
  CONTENT_WARNING_NSFW: 'nsfw',
};

/**
 * Repository identity from `repo.json`.
 *
 * Shape (keiyoushi, current):
 *   { "index_v2": "https://.../index.pb",
 *     "meta": { name, shortName?, website, signingKeyFingerprint } }
 *
 * Older repos publish only `meta`. Both are accepted; a repo that answers with
 * neither is not a repository we can use.
 */
export function parseRepoMeta(baseUrl: string, body: unknown): RepoMeta {
  if (!isObject(body)) {
    throw new RepoIndexError('repo-meta', 'repo.json is not a JSON object');
  }
  const meta = isObject(body.meta) ? body.meta : null;
  if (!meta) {
    throw new RepoIndexError('repo-meta', 'repo.json has no "meta" object');
  }
  const name = str(meta.name).trim();
  if (!name) {
    throw new RepoIndexError('repo-meta', 'repo.json has no repository name');
  }
  return {
    baseUrl: trimSlash(baseUrl),
    name,
    shortName: str(meta.shortName).trim() || null,
    website: str(meta.website).trim(),
    signingKeyFingerprint: str(meta.signingKeyFingerprint).trim() || null,
    indexV2Url: str(body.index_v2).trim() || null,
  };
}

/**
 * Index urls to try, best first.
 *
 * We deliberately prefer `index.json` over the protobuf `index_v2` it mirrors:
 * decoding the protobuf needs a schema we would have to transcribe and keep in
 * lockstep with upstream, and this runs once a day in the background where
 * 1.4 MB of JSON costs nothing. `index.min.json` is last because on a repo that
 * has moved to v2 it is now a two-entry "update your app" stub rather than
 * data — see {@link isPlaceholderIndex}.
 */
export function resolveIndexUrls(baseUrl: string): string[] {
  const base = trimSlash(baseUrl);
  return [`${base}/index.json`, `${base}/index.min.json`];
}

/** Which format a decoded index body is in, or null when it is neither. */
export function detectIndexFormat(body: unknown): RepoIndexFormat | null {
  if (Array.isArray(body)) return 'legacy';
  if (isObject(body) && isObject(body.extensionList)) return 'v2';
  return null;
}

/**
 * A repo that has migrated to v2 keeps serving `index.min.json`, but its
 * contents are now a placeholder telling old clients to update — a couple of
 * entries whose only "source" has id `1`. Ingesting that would delist every
 * real source in the vault, so it is detected and refused.
 */
export function isPlaceholderIndex(parsed: ParsedRepoIndex): boolean {
  return (
    parsed.sources.length > 0 &&
    parsed.sources.length <= 4 &&
    parsed.sources.every((s) => s.sourceId === '1')
  );
}

/** Parse an index body in whichever format it is published in. */
export function parseRepoIndex(
  baseUrl: string,
  body: unknown,
): ParsedRepoIndex {
  const format = detectIndexFormat(body);
  if (format === null) {
    throw new RepoIndexError(
      'index-format',
      'index is neither a v2 object nor a legacy array',
    );
  }
  return format === 'v2'
    ? parseIndexV2(baseUrl, body as Json)
    : parseIndexLegacy(baseUrl, body as unknown[]);
}

/**
 * v2 (`index.json`) — Mihon 0.20.1+.
 *
 *   { name, badgeLabel, signingKey, contact,
 *     extensionList: { extensions: [ {
 *       name, packageName, extensionLib, versionCode, versionName,
 *       contentWarning, resources: { apkUrl, iconUrl, jarUrl },
 *       sources: [ { id, name, language, homeUrl, mirrorUrls? } ] } ] } }
 */
export function parseIndexV2(baseUrl: string, body: Json): ParsedRepoIndex {
  const list = isObject(body.extensionList)
    ? body.extensionList.extensions
    : [];
  const entries = Array.isArray(list) ? list.slice(0, MAX_ENTRIES) : [];
  const acc = newAccumulator('v2', baseUrl);

  for (const raw of entries) {
    if (!isObject(raw)) continue;
    const packageName = str(raw.packageName).trim();
    const name = str(raw.name).trim();
    if (!packageName || !name) {
      acc.warnings.push('v2 entry without packageName or name; skipped');
      continue;
    }
    const resources = isObject(raw.resources) ? raw.resources : {};
    addExtension(acc, {
      packageName,
      name,
      versionName: str(raw.versionName).trim(),
      versionCode: int(raw.versionCode),
      extensionLib: str(raw.extensionLib).trim(),
      contentWarning: CONTENT_WARNINGS[str(raw.contentWarning)] ?? 'safe',
      apkUrl: str(resources.apkUrl).trim(),
      iconUrl: str(resources.iconUrl).trim(),
      sourceIds: [],
    });

    const sources = Array.isArray(raw.sources) ? raw.sources : [];
    for (const rawSource of sources) {
      if (!isObject(rawSource)) continue;
      const id = sourceId(rawSource.id);
      if (id === null) {
        acc.warnings.push(`${packageName}: source with unusable id; skipped`);
        continue;
      }
      addSource(acc, {
        sourceId: id,
        name: str(rawSource.name).trim() || name,
        lang: str(rawSource.language).trim(),
        homeUrl: str(rawSource.homeUrl).trim(),
        mirrorUrls: Array.isArray(rawSource.mirrorUrls)
          ? rawSource.mirrorUrls.filter(
              (m): m is string => typeof m === 'string',
            )
          : [],
        packageName,
      });
    }
  }
  return finish(acc);
}

/**
 * Legacy (`index.min.json`) — Mihon <= 0.20.0.
 *
 *   [ { name, pkg, apk, lang, code, version, nsfw,
 *       sources: [ { id, lang, name, baseUrl } ] } ]
 *
 * Unlike v2 the entry carries no urls, so apk and icon are derived from the
 * repository layout Mihon assumes: `$repo/apk/$apk` and `$repo/icon/$pkg.png`.
 */
export function parseIndexLegacy(
  baseUrl: string,
  entries: unknown[],
): ParsedRepoIndex {
  const base = trimSlash(baseUrl);
  const acc = newAccumulator('legacy', baseUrl);

  for (const raw of entries.slice(0, MAX_ENTRIES)) {
    if (!isObject(raw)) continue;
    const packageName = str(raw.pkg).trim();
    // Mihon strips this prefix off pre-fork extension names.
    const name = str(raw.name)
      .replace(/^Tachiyomi:\s*/, '')
      .trim();
    if (!packageName || !name) {
      acc.warnings.push('legacy entry without pkg or name; skipped');
      continue;
    }
    const version = str(raw.version).trim();
    const apk = str(raw.apk).trim();
    addExtension(acc, {
      packageName,
      name,
      versionName: version,
      versionCode: int(raw.code),
      // Mihon derives the lib level the same way: everything before the last dot.
      extensionLib: version.includes('.')
        ? version.slice(0, version.lastIndexOf('.'))
        : version,
      contentWarning: int(raw.nsfw) === 1 ? 'nsfw' : 'safe',
      apkUrl: apk ? `${base}/apk/${apk}` : '',
      iconUrl: `${base}/icon/${packageName}.png`,
      sourceIds: [],
    });

    const sources = Array.isArray(raw.sources) ? raw.sources : [];
    for (const rawSource of sources) {
      if (!isObject(rawSource)) continue;
      const id = sourceId(rawSource.id);
      if (id === null) {
        acc.warnings.push(
          `${packageName}: source id lost precision in JSON; skipped`,
        );
        continue;
      }
      addSource(acc, {
        sourceId: id,
        name: str(rawSource.name).trim() || name,
        lang: str(rawSource.lang).trim(),
        homeUrl: str(rawSource.baseUrl).trim(),
        mirrorUrls: [],
        packageName,
      });
    }
  }
  return finish(acc);
}

// ---- accumulator ----

interface Accumulator {
  format: RepoIndexFormat;
  baseUrl: string;
  extensions: IndexedExtension[];
  byPackage: Map<string, IndexedExtension>;
  sources: Map<string, IndexedSource>;
  warnings: string[];
}

function newAccumulator(format: RepoIndexFormat, baseUrl: string): Accumulator {
  return {
    format,
    baseUrl: trimSlash(baseUrl),
    extensions: [],
    byPackage: new Map(),
    sources: new Map(),
    warnings: [],
  };
}

function addExtension(acc: Accumulator, ext: IndexedExtension): void {
  if (acc.byPackage.has(ext.packageName)) {
    acc.warnings.push(`duplicate package ${ext.packageName}; kept the first`);
    return;
  }
  acc.byPackage.set(ext.packageName, ext);
  acc.extensions.push(ext);
}

function addSource(acc: Accumulator, source: IndexedSource): void {
  const existing = acc.sources.get(source.sourceId);
  if (existing) {
    // Two packages claiming one id is a repo-side mistake. Keep the first so a
    // sync is deterministic, and say so.
    if (existing.packageName !== source.packageName) {
      acc.warnings.push(
        `source ${source.sourceId} claimed by both ${existing.packageName} and ${source.packageName}; kept the first`,
      );
    }
    return;
  }
  acc.sources.set(source.sourceId, source);
  acc.byPackage.get(source.packageName)?.sourceIds.push(source.sourceId);
}

function finish(acc: Accumulator): ParsedRepoIndex {
  return {
    format: acc.format,
    extensions: acc.extensions,
    sources: [...acc.sources.values()],
    warnings: acc.warnings,
  };
}
