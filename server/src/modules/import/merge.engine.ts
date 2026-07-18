import type {
  NormalizedChapter,
  NormalizedManga,
  NormalizedTracking,
  PublicationStatus,
} from '../../tachibk';

/**
 * A title reduced to the fields that participate in merging. The import service
 * projects a MangaEntity (+children) into this shape, merges, then writes the
 * result back — keeping the merge rules pure and unit-testable, free of TypeORM.
 */
export interface MergeableManga {
  title: string;
  author?: string;
  artist?: string;
  description?: string;
  thumbnailUrl?: string;
  status: PublicationStatus;
  genres: string[];
  favorite: boolean;
  notes: string;
  dateAdded: number;
  updatedAt: number; // source lastModifiedAt of whatever last set the scalars
  categoryNames: string[];
  chapters: MergeableChapter[];
  tracking: NormalizedTracking[];
}

export type MergeableChapter = NormalizedChapter;

export interface FieldConflict {
  field: string;
  kept: unknown;
  incoming: unknown;
}

export interface MergeOutcome {
  merged: MergeableManga;
  conflicts: FieldConflict[];
}

const NOTES_DIVIDER = '\n\n---\n\n';

/**
 * Merge logic for deduplicating a title across backups (docs/phase-1 §2 rules):
 * archival semantics — nothing is ever deleted, a non-empty value is never
 * overwritten by an empty one, read state only accumulates.
 */
export class MergeEngine {
  /** Build a fresh MergeableManga from a normalized import (the "created" case). */
  fromNormalized(m: NormalizedManga): MergeableManga {
    return {
      title: m.title,
      author: m.author,
      artist: m.artist,
      description: m.description,
      thumbnailUrl: m.thumbnailUrl,
      status: m.status,
      genres: [...m.genres],
      favorite: m.favorite,
      notes: m.notes,
      dateAdded: m.dateAdded,
      updatedAt: m.lastModifiedAt || m.dateAdded,
      categoryNames: [...m.categoryNames],
      chapters: m.chapters.map((c) => ({ ...c })),
      tracking: m.tracking.map((t) => ({ ...t })),
    };
  }

  /**
   * Merge an incoming normalized title into the existing one. Returns the merged
   * result plus any conflicts worth surfacing in the import-review UI.
   */
  applyMerge(
    existing: MergeableManga,
    incoming: NormalizedManga,
  ): MergeOutcome {
    const conflicts: FieldConflict[] = [];
    // Newer wins for scalars, but never overwrite a non-empty value with empty.
    const incomingNewer = (incoming.lastModifiedAt || 0) >= existing.updatedAt;

    const merged: MergeableManga = {
      title:
        pickScalar(
          'title',
          existing.title,
          incoming.title,
          incomingNewer,
          conflicts,
        ) ?? existing.title,
      author: pickScalar(
        'author',
        existing.author,
        incoming.author,
        incomingNewer,
        conflicts,
      ),
      artist: pickScalar(
        'artist',
        existing.artist,
        incoming.artist,
        incomingNewer,
        conflicts,
      ),
      description: pickScalar(
        'description',
        existing.description,
        incoming.description,
        incomingNewer,
        conflicts,
      ),
      thumbnailUrl: pickScalar(
        'thumbnailUrl',
        existing.thumbnailUrl,
        incoming.thumbnailUrl,
        incomingNewer,
        conflicts,
      ),
      status:
        incomingNewer && incoming.status !== 'unknown'
          ? incoming.status
          : existing.status,
      genres: unionStrings(existing.genres, incoming.genres),
      favorite: existing.favorite || incoming.favorite, // OR
      notes: mergeNotes(existing.notes, incoming.notes, conflicts),
      dateAdded: minPositive(existing.dateAdded, incoming.dateAdded), // earliest known
      updatedAt: Math.max(existing.updatedAt, incoming.lastModifiedAt || 0),
      categoryNames: unionStrings(
        existing.categoryNames,
        incoming.categoryNames,
      ),
      chapters: mergeChapters(existing.chapters, incoming.chapters),
      tracking: mergeTracking(existing.tracking, incoming.tracking),
    };

    return { merged, conflicts };
  }
}

/** Newer-wins, but a non-empty existing value is never clobbered by an empty one. */
function pickScalar(
  field: string,
  existing: string | undefined,
  incoming: string | undefined,
  incomingNewer: boolean,
  conflicts: FieldConflict[],
): string | undefined {
  const inc = incoming?.trim() ? incoming : undefined;
  const exi = existing?.trim() ? existing : undefined;
  if (inc === undefined) return exi;
  if (exi === undefined) return inc;
  if (inc === exi) return exi;
  // Genuine disagreement between two non-empty values.
  if (incomingNewer) {
    conflicts.push({ field, kept: inc, incoming: exi });
    return inc;
  }
  conflicts.push({ field, kept: exi, incoming: inc });
  return exi;
}

function mergeNotes(
  existing: string,
  incoming: string,
  conflicts: FieldConflict[],
): string {
  const a = existing.trim();
  const b = incoming.trim();
  if (!a) return b;
  if (!b || a === b || a.includes(b)) return existing;
  conflicts.push({ field: 'notes', kept: a, incoming: b });
  return existing + NOTES_DIVIDER + incoming;
}

function unionStrings(a: string[], b: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const s of [...a, ...b]) {
    if (!seen.has(s)) {
      seen.add(s);
      out.push(s);
    }
  }
  return out;
}

function minPositive(a: number, b: number): number {
  const vals = [a, b].filter((v) => v > 0);
  return vals.length ? Math.min(...vals) : Math.max(a, b);
}

/** Union by chapter url; OR read/bookmark; max lastPageRead/lastReadAt/readDuration. */
function mergeChapters(
  existing: MergeableChapter[],
  incoming: NormalizedChapter[],
): MergeableChapter[] {
  const byUrl = new Map<string, MergeableChapter>();
  for (const c of existing) byUrl.set(c.url, { ...c });
  for (const inc of incoming) {
    const prev = byUrl.get(inc.url);
    if (!prev) {
      byUrl.set(inc.url, { ...inc });
      continue;
    }
    byUrl.set(inc.url, {
      ...prev,
      // Prefer non-empty metadata; keep whichever has the name/scanlator.
      name: inc.name || prev.name,
      chapterNumber:
        prev.chapterNumber >= 0 ? prev.chapterNumber : inc.chapterNumber,
      scanlator: prev.scanlator ?? inc.scanlator,
      read: prev.read || inc.read,
      bookmark: prev.bookmark || inc.bookmark,
      lastPageRead: Math.max(prev.lastPageRead, inc.lastPageRead),
      dateUpload: prev.dateUpload || inc.dateUpload,
      dateFetch: prev.dateFetch || inc.dateFetch,
      sourceOrder: inc.sourceOrder || prev.sourceOrder,
      lastReadAt: maxOptional(prev.lastReadAt, inc.lastReadAt),
      readDuration: Math.max(prev.readDuration, inc.readDuration),
    });
  }
  return [...byUrl.values()];
}

/** Union by tracker; take the higher progress, keep existing links when present. */
function mergeTracking(
  existing: NormalizedTracking[],
  incoming: NormalizedTracking[],
): NormalizedTracking[] {
  const byTracker = new Map<string, NormalizedTracking>();
  for (const t of existing) byTracker.set(t.tracker, { ...t });
  for (const inc of incoming) {
    const prev = byTracker.get(inc.tracker);
    if (!prev) {
      byTracker.set(inc.tracker, { ...inc });
      continue;
    }
    byTracker.set(inc.tracker, {
      ...prev,
      remoteId: prev.remoteId !== '0' ? prev.remoteId : inc.remoteId,
      trackingUrl: prev.trackingUrl || inc.trackingUrl,
      title: prev.title || inc.title,
      lastChapterRead: Math.max(prev.lastChapterRead, inc.lastChapterRead),
      totalChapters: Math.max(prev.totalChapters, inc.totalChapters),
      score: prev.score || inc.score,
      status: inc.status || prev.status,
      startedAt: minPositiveOptional(prev.startedAt, inc.startedAt),
      finishedAt: maxOptional(prev.finishedAt, inc.finishedAt),
    });
  }
  return [...byTracker.values()];
}

function maxOptional(
  a: number | undefined,
  b: number | undefined,
): number | undefined {
  if (a == null) return b;
  if (b == null) return a;
  return Math.max(a, b);
}
function minPositiveOptional(
  a: number | undefined,
  b: number | undefined,
): number | undefined {
  const vals = [a, b].filter((v): v is number => v != null && v > 0);
  return vals.length ? Math.min(...vals) : (a ?? b);
}
