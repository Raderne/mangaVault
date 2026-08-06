import type {
  NormalizedBackup,
  NormalizedChapter,
  NormalizedManga,
  NormalizedTracking,
  PublicationStatus,
} from './domain';
import type {
  WireBackup,
  WireChapter,
  WireHistory,
  WireManga,
  WireTracking,
} from './wire';

/** Domain status -> SManga status int. Exact inverse of the normalizer's map. */
const STATUS_INT: Record<PublicationStatus, number> = {
  unknown: 0,
  ongoing: 1,
  completed: 2,
  licensed: 3,
  publishing_finished: 4,
  cancelled: 5,
  on_hiatus: 6,
};

/** Domain TrackerId -> tracker syncId. Exact inverse of the normalizer's map. */
const TRACKER_SYNC_ID: Record<string, number> = {
  myanimelist: 1,
  anilist: 2,
  kitsu: 3,
  shikimori: 4,
  bangumi: 5,
  komga: 6,
  mangaupdates: 7,
};

/**
 * A tracker we couldn't name on the way in was stored as `unknown:<syncId>`, so
 * the original id is recoverable and the round-trip stays lossless. Anything
 * else (a tracker id we invented) has no wire representation and is dropped.
 */
const UNKNOWN_TRACKER_RE = /^unknown:(\d+)$/;

/**
 * Turns the normalized domain model back into the `.tachibk` wire model — the
 * exact inverse of {@link BackupNormalizer}, and the first half of export
 * (`domain -> wire -> bytes`, mirroring `bytes -> wire -> domain`).
 *
 * Pure and deterministic: no clock, no I/O, no ids. Two rules shape it:
 *
 * - **Write what Mihon reads.** Fields MangaVault doesn't model (reader flags,
 *   `updateStrategy`, row versions) are emitted as proto3 zero values rather
 *   than omitted, so a restoring app applies its own defaults instead of
 *   tripping over a sparse message.
 * - **Never invent identity.** Category linkage travels as `order` values, the
 *   same indirection the parser resolves on the way in; vault uuids never leave.
 */
export class BackupDenormalizer {
  denormalize(backup: NormalizedBackup): WireBackup {
    // name -> order, so each manga's categoryNames become the int64 order list
    // BackupManga.categories actually carries. Names are the only category
    // identity that survives a round-trip through a backup.
    const orderByName = new Map<string, number>();
    for (const c of backup.categories) orderByName.set(c.name, c.order);

    return {
      backupManga: backup.manga.map((m) =>
        this.denormalizeManga(m, orderByName),
      ),
      backupCategories: backup.categories.map((c) => ({
        name: c.name,
        order: String(c.order),
        // Mihon keys restores off `order`; `id` is written to match so a backup
        // read by an app that prefers the id lands on the same category.
        id: String(c.order),
        flags: '0',
      })),
      backupSources: backup.sources.map((s) => ({
        name: s.name,
        sourceId: s.sourceId,
      })),
    };
  }

  private denormalizeManga(
    m: NormalizedManga,
    orderByName: Map<string, number>,
  ): WireManga {
    const categories = m.categoryNames
      .map((name) => orderByName.get(name))
      .filter((order): order is number => order !== undefined)
      .map(String);

    return {
      source: m.key.sourceId,
      url: m.key.mangaUrl,
      title: m.title,
      artist: m.artist ?? '',
      author: m.author ?? '',
      description: m.description ?? '',
      genre: m.genres,
      status: STATUS_INT[m.status] ?? 0,
      thumbnailUrl: m.thumbnailUrl ?? '',
      dateAdded: String(m.dateAdded),
      chapters: m.chapters.map((c) => this.denormalizeChapter(c)),
      categories,
      tracking: m.tracking
        .map((t) => this.denormalizeTracking(t))
        .filter((t): t is WireTracking => t !== null),
      // Written explicitly, never left absent: absent means TRUE to every
      // reader, which would silently re-favorite a title exported as not-favorite.
      favorite: m.favorite,
      history: this.buildHistory(m.chapters),
      lastModifiedAt: String(m.lastModifiedAt),
      excludedScanlators: [],
      notes: m.notes,
      // "Details have been fetched" — true exactly when we hold the metadata a
      // fetch would have produced, so a restoring app doesn't re-scrape titles
      // the archive already describes.
      initialized: m.description !== undefined || m.thumbnailUrl !== undefined,
      viewer: 0,
      chapterFlags: 0,
      viewer_flags: 0,
      updateStrategy: 0, // ALWAYS_UPDATE
      favoriteModifiedAt: '0',
      version: '0',
    };
  }

  private denormalizeChapter(c: NormalizedChapter): WireChapter {
    return {
      url: c.url,
      name: c.name,
      scanlator: c.scanlator ?? '',
      read: c.read,
      bookmark: c.bookmark,
      lastPageRead: String(c.lastPageRead),
      dateFetch: String(c.dateFetch),
      dateUpload: String(c.dateUpload),
      chapterNumber: c.chapterNumber,
      sourceOrder: String(c.sourceOrder),
      lastModifiedAt: '0',
      version: '0',
    };
  }

  /**
   * Rebuild `BackupHistory` from the chapters it was folded into on the way in.
   *
   * The fold is lossy in one direction only — many history rows per url collapse
   * to `max(lastRead)` / `sum(readDuration)` — so unfolding emits **one** row per
   * chapter that has any reading history. Re-normalizing that yields the same
   * numbers, which is what makes the round-trip stable.
   */
  private buildHistory(chapters: NormalizedChapter[]): WireHistory[] {
    const history: WireHistory[] = [];
    for (const c of chapters) {
      const lastRead = c.lastReadAt ?? 0;
      if (lastRead <= 0 && c.readDuration <= 0) continue;
      history.push({
        url: c.url,
        lastRead: String(lastRead),
        readDuration: String(c.readDuration),
      });
    }
    return history;
  }

  private denormalizeTracking(t: NormalizedTracking): WireTracking | null {
    const syncId =
      TRACKER_SYNC_ID[t.tracker] ??
      Number(UNKNOWN_TRACKER_RE.exec(t.tracker)?.[1] ?? Number.NaN);
    if (!Number.isFinite(syncId)) return null;

    return {
      syncId,
      libraryId: '0',
      // Left at 0 on purpose: it is the deprecated 32-bit field, and the
      // normalizer only falls back to it when non-zero. Writing the id solely
      // to the int64 `mediaId` keeps ids above 2^31 intact.
      mediaIdInt: 0,
      trackingUrl: t.trackingUrl,
      title: t.title,
      lastChapterRead: t.lastChapterRead,
      totalChapters: t.totalChapters,
      score: t.score,
      status: t.status,
      startedReadingDate: String(t.startedAt ?? 0),
      finishedReadingDate: String(t.finishedAt ?? 0),
      private: false,
      mediaId: t.remoteId,
    };
  }
}
