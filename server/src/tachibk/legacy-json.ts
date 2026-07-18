import { BackupParseError } from './errors';
import type {
  WireBackup,
  WireCategory,
  WireChapter,
  WireHistory,
  WireManga,
  WireTracking,
} from './wire';

/**
 * Best-effort importer for legacy Tachiyomi JSON backups. Mihon itself rejects
 * these, so MangaVault handles them instead — but the legacy format has many
 * historical variants, so this targets the object-keyed shape (named fields per
 * manga) and records a warning for anything it cannot map. Protobuf `.tachibk`
 * is the primary path; this is a compatibility seam.
 *
 * Adapts into the same {@link WireBackup} shape the protobuf decoder emits, so
 * the normalizer downstream is format-agnostic. int64-typed wire fields are
 * emitted as decimal strings to match the protobuf path.
 */
export function parseLegacyJson(
  file: Uint8Array,
  warnings: string[],
): WireBackup {
  let root: unknown;
  try {
    root = JSON.parse(Buffer.from(file).toString('utf8'));
  } catch (cause) {
    throw new BackupParseError(
      'json',
      'failed to parse legacy JSON backup',
      'legacy-json',
      cause,
    );
  }
  if (!isRecord(root)) {
    throw new BackupParseError(
      'json',
      'legacy JSON root is not an object',
      'legacy-json',
    );
  }

  const mangas = asArray(root.mangas);
  if (mangas.length === 0) {
    warnings.push('legacy backup contained no "mangas" array');
  }

  const backupManga: WireManga[] = mangas.map((entry, i) =>
    mapManga(entry, i, warnings),
  );
  const backupCategories: WireCategory[] = asArray(root.categories).map(
    mapCategory,
  );

  return { backupManga, backupCategories, backupSources: [] };
}

function mapManga(
  entry: unknown,
  index: number,
  warnings: string[],
): WireManga {
  // Some exports nest the fields under a `manga` key; others inline them.
  const src = isRecord(entry) && isRecord(entry.manga) ? entry.manga : entry;
  if (!isRecord(src)) {
    warnings.push(
      `legacy manga #${index} was not an object; skipped its fields`,
    );
    return { url: '', title: '' };
  }
  const container = isRecord(entry) ? entry : {};

  // int64 source ids only survive legacy JSON if the export quoted them; a bare
  // JSON number > 2^53 is already mangled by JSON.parse before we see it.
  const rawSource = src.source ?? src.sourceId;
  if (typeof rawSource === 'number' && !Number.isSafeInteger(rawSource)) {
    warnings.push(
      `legacy manga #${index} ("${str(src.title)}") had an unquoted 64-bit source id; ` +
        `precision may be lost — dedup identity could be affected`,
    );
  }

  return {
    source: intStr(rawSource),
    url: str(src.url),
    title: str(src.title),
    artist: optStr(src.artist),
    author: optStr(src.author),
    description: optStr(src.description),
    genre: asStringArray(src.genre ?? src.genres),
    status: num(src.status),
    thumbnailUrl: optStr(src.thumbnail_url ?? src.thumbnailUrl),
    dateAdded: intStr(src.dateAdded ?? src.date_added),
    favorite: typeof src.favorite === 'boolean' ? src.favorite : undefined,
    lastModifiedAt: intStr(src.lastModifiedAt ?? src.last_modified_at),
    notes: optStr(src.notes),
    chapters: asArray(container.chapters ?? src.chapters).map(mapChapter),
    categories: asArray(container.categories ?? src.categories).map(
      (c) => intStr(c) ?? '0',
    ),
    history: asArray(container.history ?? src.history).map(mapHistory),
    tracking: asArray(
      container.track ?? container.tracking ?? src.tracking,
    ).map(mapTracking),
  };
}

function mapChapter(entry: unknown): WireChapter {
  const c = isRecord(entry) ? entry : {};
  return {
    url: str(c.url),
    name: str(c.name),
    scanlator: optStr(c.scanlator),
    read: Boolean(c.read),
    bookmark: Boolean(c.bookmark),
    lastPageRead: intStr(c.lastPageRead ?? c.last_page_read),
    dateFetch: intStr(c.dateFetch ?? c.date_fetch),
    dateUpload: intStr(c.dateUpload ?? c.date_upload),
    chapterNumber:
      typeof c.chapterNumber === 'number'
        ? c.chapterNumber
        : num(c.chapter_number, -1),
    sourceOrder: intStr(c.sourceOrder ?? c.source_order),
  };
}

function mapHistory(entry: unknown): WireHistory {
  const h = isRecord(entry) ? entry : {};
  return {
    url: str(h.url),
    lastRead: intStr(h.lastRead ?? h.last_read),
    readDuration: intStr(h.readDuration ?? h.time_read ?? h.read_duration),
  };
}

function mapTracking(entry: unknown): WireTracking {
  const t = isRecord(entry) ? entry : {};
  return {
    syncId: num(t.syncId ?? t.sync_id),
    mediaIdInt: num(t.mediaIdInt ?? t.media_id),
    mediaId: intStr(t.mediaId),
    trackingUrl: str(t.trackingUrl ?? t.tracking_url),
    title: str(t.title),
    lastChapterRead: num(t.lastChapterRead ?? t.last_chapter_read),
    totalChapters: num(t.totalChapters ?? t.total_chapters),
    score: num(t.score),
    status: num(t.status),
  };
}

function mapCategory(entry: unknown): WireCategory {
  const c = isRecord(entry) ? entry : {};
  return { name: str(c.name), order: intStr(c.order) };
}

// ---- coercion helpers (legacy JSON is loosely typed) ----

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}
function asStringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.map(primStr) : [];
}
/** Stringify only JSON primitives; objects/arrays/null become ''. */
function primStr(v: unknown): string {
  switch (typeof v) {
    case 'string':
      return v;
    case 'number':
    case 'boolean':
    case 'bigint':
      return String(v);
    default:
      return '';
  }
}
function str(v: unknown): string {
  return primStr(v);
}
function optStr(v: unknown): string | undefined {
  const s = primStr(v);
  return s === '' ? undefined : s;
}
function num(v: unknown, fallback = 0): number {
  const n = typeof v === 'number' ? v : Number(primStr(v));
  return Number.isFinite(n) ? n : fallback;
}
/** Coerce a numeric/string int64 into a decimal string, or undefined. */
function intStr(v: unknown): string | undefined {
  if (v == null || v === '') return undefined;
  if (typeof v === 'number')
    return Number.isFinite(v) ? String(Math.trunc(v)) : undefined;
  const s = primStr(v);
  return /^-?\d+$/.test(s) ? s : undefined;
}
