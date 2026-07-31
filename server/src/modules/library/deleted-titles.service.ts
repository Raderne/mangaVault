import { Injectable, Logger } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, In, Repository } from 'typeorm';

import { withSyncLock } from '../../common/sync-lock';
import {
  CategoryEntity,
  ChapterEntity,
  DeletedMangaEntity,
  ImportRecordEntity,
  MangaEntity,
  TrackingEntity,
} from '../../entities';
import type {
  DeletedChapter,
  DeletedMangaScalars,
  DeletedMangaSnapshot,
  DeletedTracking,
} from '../../entities/deleted-manga.entity';
import type { DeletedTitlesPageDto, RestoreResultDto } from './library.dto';

/** Identity of a title within the Mihon ecosystem. */
export interface MangaKey {
  sourceId: string;
  mangaUrl: string;
}

/** Map/Set key for a [MangaKey]. `\0` can't occur in either field. */
export const mangaKeyOf = (sourceId: string, mangaUrl: string): string =>
  `${sourceId}\0${mangaUrl}`;

const mangaScalars = (m: MangaEntity): DeletedMangaScalars => ({
  sourceId: m.sourceId,
  mangaUrl: m.mangaUrl,
  sourceName: m.sourceName,
  title: m.title,
  author: m.author,
  artist: m.artist,
  description: m.description,
  genres: m.genres,
  status: m.status,
  thumbnailUrl: m.thumbnailUrl,
  coverPath: m.coverPath,
  coverState: m.coverState,
  coverFailedAt: m.coverFailedAt,
  notes: m.notes,
  favorite: m.favorite,
  dateAdded: m.dateAdded,
  updatedAt: m.updatedAt,
});

const chapterSnapshot = (c: ChapterEntity): DeletedChapter => ({
  url: c.url,
  name: c.name,
  chapterNumber: c.chapterNumber,
  scanlator: c.scanlator,
  read: c.read,
  bookmark: c.bookmark,
  lastPageRead: c.lastPageRead,
  dateUpload: c.dateUpload,
  dateFetch: c.dateFetch,
  sourceOrder: c.sourceOrder,
  lastReadAt: c.lastReadAt,
  readDuration: c.readDuration,
});

const trackingSnapshot = (t: TrackingEntity): DeletedTracking => ({
  tracker: t.tracker,
  remoteId: t.remoteId,
  trackingUrl: t.trackingUrl,
  title: t.title,
  lastChapterRead: t.lastChapterRead,
  totalChapters: t.totalChapters,
  score: t.score,
  status: t.status,
  startedAt: t.startedAt,
  finishedAt: t.finishedAt,
});

/**
 * The deletion registry: a recycle bin that doubles as an import block list.
 *
 * Without it a delete is undone by the next backup — the merge engine keys on
 * `(source_id, manga_url)`, finds nothing, and creates the title again. So a
 * delete records the title here with a full snapshot, imports skip registered
 * keys, and the user restores what they want explicitly.
 */
@Injectable()
export class DeletedTitlesService {
  private readonly logger = new Logger(DeletedTitlesService.name);

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(DeletedMangaEntity)
    private readonly repo: Repository<DeletedMangaEntity>,
  ) {}

  /**
   * Snapshot titles into the registry. Call **inside** the delete transaction,
   * before the rows go — this reads the very data that is about to cascade.
   *
   * A key already registered is refreshed rather than duplicated: the title
   * must have been restored and deleted again, and the newer snapshot wins.
   */
  async record(mgr: EntityManager, ids: string[]): Promise<number> {
    if (ids.length === 0) return 0;

    const rows = await mgr.find(MangaEntity, {
      where: { id: In(ids) },
      relations: {
        chapters: true,
        tracking: true,
        categories: true,
        imports: true,
      },
    });

    const now = Date.now();
    const entries = rows.map((m) => {
      const { chapters, tracking, categories, imports } = m;
      const snapshot: DeletedMangaSnapshot = {
        manga: mangaScalars(m),
        // Field lists are spelled out rather than spread-minus-keys: this JSON
        // is a *persisted format*, so it should change only deliberately, and
        // the Omit<> types make TypeScript flag anything left behind.
        chapters: chapters.map(chapterSnapshot),
        tracking: tracking.map(trackingSnapshot),
        categoryNames: categories.map((c) => c.name),
        importIds: imports.map((i) => i.id),
      };
      return {
        sourceId: m.sourceId,
        mangaUrl: m.mangaUrl,
        sourceName: m.sourceName,
        title: m.title,
        thumbnailUrl: m.thumbnailUrl,
        chapterCount: chapters.length,
        readCount: chapters.filter((c) => c.read).length,
        deletedAt: now,
        lastSeenAt: null,
        seenCount: 0,
        snapshot,
      };
    });

    await mgr
      .createQueryBuilder()
      .insert()
      .into(DeletedMangaEntity)
      .values(entries)
      .orUpdate(
        [
          'source_name',
          'title',
          'thumbnail_url',
          'chapter_count',
          'read_count',
          'deleted_at',
          'last_seen_at',
          'seen_count',
          'snapshot',
        ],
        ['source_id', 'manga_url'],
      )
      .execute();

    return entries.length;
  }

  /** Every registered key, for the import to check against. */
  async blockedKeys(): Promise<Set<string>> {
    const rows = await this.repo.find({
      select: { sourceId: true, mangaUrl: true },
    });
    return new Set(rows.map((r) => mangaKeyOf(r.sourceId, r.mangaUrl)));
  }

  /**
   * Note that an import offered these titles again. Purely informational — it
   * is what lets the restore list say "a backup wanted this back yesterday".
   */
  async noteSeen(keys: MangaKey[]): Promise<void> {
    if (keys.length === 0) return;
    await this.dataSource.query(
      `UPDATE deleted_manga d
          SET last_seen_at = $1,
              seen_count   = d.seen_count + 1
        FROM unnest($2::text[], $3::text[]) AS k(source_id, manga_url)
       WHERE d.source_id = k.source_id AND d.manga_url = k.manga_url`,
      [Date.now(), keys.map((k) => k.sourceId), keys.map((k) => k.mangaUrl)],
    );
  }

  /**
   * The recycle bin, most recently deleted first, with what it costs on disk.
   * Snapshots stay server-side — the list only carries what the screen renders.
   *
   * The size is a `pg_total_relation_size` catalog lookup, not a scan of the
   * rows: `pg_column_size` per row would have to touch every TOASTed snapshot.
   */
  async list(): Promise<DeletedTitlesPageDto> {
    const [rows, size] = await Promise.all([
      this.repo.find({ order: { deletedAt: 'DESC' } }),
      this.dataSource
        .query<{ bytes: string }[]>(
          `SELECT pg_total_relation_size('deleted_manga')::text AS bytes`,
        )
        .then((r) => Number(r[0]?.bytes ?? 0))
        // A size we can't read must not break the list itself.
        .catch(() => 0),
    ]);

    return {
      items: rows.map((r) => ({
        id: r.id,
        sourceId: r.sourceId,
        mangaUrl: r.mangaUrl,
        sourceName: r.sourceName,
        title: r.title,
        chapterCount: r.chapterCount,
        readCount: r.readCount,
        deletedAt: r.deletedAt,
        lastSeenAt: r.lastSeenAt,
        seenCount: r.seenCount,
      })),
      totalBytes: size,
    };
  }

  /**
   * Put titles back and drop their registry rows.
   *
   * Restored titles get **new** ids (the old ones are tombstoned and gone from
   * every mirror), and their covers come back as `none` — the archived image
   * was unlinked with the row, so it has to be re-fetched.
   */
  async restore(ids: string[]): Promise<RestoreResultDto> {
    if (ids.length === 0) return { restored: 0, skipped: 0 };
    const entries = await this.repo.find({ where: { id: In(ids) } });
    if (entries.length === 0) return { restored: 0, skipped: 0 };

    let restored = 0;
    let skipped = 0;
    // One transaction per title: a snapshot that fails to apply must not take
    // the rest of the batch with it, and the sync lock is held only briefly.
    for (const entry of entries) {
      try {
        const done = await withSyncLock(this.dataSource, (mgr) =>
          this.restoreOne(mgr, entry),
        );
        if (done) {
          restored++;
        } else {
          skipped++;
        }
      } catch (err) {
        skipped++;
        this.logger.error(
          `restore of "${entry.title}" failed: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }
    return { restored, skipped };
  }

  /** Forget the registry entries without restoring: a future import may re-add. */
  async purge(ids: string[]): Promise<number> {
    if (ids.length === 0) return 0;
    const result = await this.repo.delete({ id: In(ids) });
    return result.affected ?? 0;
  }

  // ---- internals ----

  private async restoreOne(
    mgr: EntityManager,
    entry: DeletedMangaEntity,
  ): Promise<boolean> {
    const snap = entry.snapshot;

    // The key may have been recreated by some other path in the meantime; the
    // live row wins and the registry entry is simply dropped.
    const existing = await mgr.findOne(MangaEntity, {
      where: { sourceId: entry.sourceId, mangaUrl: entry.mangaUrl },
    });
    if (existing) {
      await mgr.delete(DeletedMangaEntity, { id: entry.id });
      return false;
    }

    const manga = await mgr.save(
      mgr.create(MangaEntity, {
        ...snap.manga,
        sourceId: entry.sourceId,
        mangaUrl: entry.mangaUrl,
        // The archived file went with the row; the cover has to be re-fetched.
        coverPath: null,
        coverState: 'none' as const,
        coverFailedAt: null,
      }),
    );

    if (snap.chapters.length) {
      await mgr.insert(
        ChapterEntity,
        snap.chapters.map((c) => ({ ...c, mangaId: manga.id })),
      );
    }
    if (snap.tracking.length) {
      await mgr.insert(
        TrackingEntity,
        snap.tracking.map((t) => ({ ...t, mangaId: manga.id })),
      );
    }

    await this.relinkCategories(mgr, manga.id, snap.categoryNames);
    await this.relinkImports(mgr, manga.id, snap.importIds);

    await mgr.delete(DeletedMangaEntity, { id: entry.id });
    return true;
  }

  /** Categories are matched by name and recreated if they were removed since. */
  private async relinkCategories(
    mgr: EntityManager,
    mangaId: string,
    names: string[],
  ): Promise<void> {
    for (const name of names) {
      const repo = mgr.getRepository(CategoryEntity);
      const category =
        (await repo.findOne({ where: { name } })) ??
        (await repo.save(repo.create({ name, sort: 0 })));
      await mgr.query(
        `INSERT INTO manga_category (manga_id, category_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [mangaId, category.id],
      );
    }
  }

  /** Only imports that still exist are re-linked; the FK would reject the rest. */
  private async relinkImports(
    mgr: EntityManager,
    mangaId: string,
    importIds: string[],
  ): Promise<void> {
    if (importIds.length === 0) return;
    const alive = await mgr.find(ImportRecordEntity, {
      where: { id: In(importIds) },
      select: { id: true },
    });
    for (const record of alive) {
      await mgr.query(
        `INSERT INTO manga_import (manga_id, import_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [mangaId, record.id],
      );
    }
  }
}
