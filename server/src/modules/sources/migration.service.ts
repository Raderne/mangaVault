import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { withSyncLock } from '../../common/sync-lock';
import {
  SourceMigrationItemEntity,
  SourceMigrationJobEntity,
} from '../../entities';
import type {
  MigrationSnapshot,
  StoredCandidate,
} from '../../entities/source-migration.entity';
import { LibraryService } from '../library/library.service';
import {
  AUTO_ACCEPT_SIMILARITY,
  rankCandidates,
  type ScoredCandidate,
} from './match/title-match';
import { SourceSearchRegistry } from './search/source-search.registry';
import type { SourceCandidate } from './search/source-search.port';
import type {
  ApplyMigrationResultDto,
  MigrationItemDto,
  MigrationJobDto,
  MigrationPlanDto,
  PlanMigrationRequest,
  UpdateMigrationItemRequest,
} from './migration.dto';

/** Candidates kept per title for the override sheet. */
const MAX_STORED_CANDIDATES = 5;

/** Titles searched concurrently while planning. */
const PLAN_CONCURRENCY = 3;

/** A vault title being migrated. */
interface VaultTitle {
  id: string;
  sourceId: string;
  mangaUrl: string;
  title: string;
  author: string | null;
  chapterCount: number;
  thumbnailUrl: string | null;
}

/**
 * Moving archived titles off a source that no longer works.
 *
 * **How this differs from Mihon, and why.** Mihon migrates by pointing the
 * library at a *different row* — the target source's copy — and unfavouriting
 * the original; per-chapter progress is reconstructed from a high-water mark and
 * `lastPageRead` is simply lost. It has no choice: in Mihon a row belongs to a
 * source.
 *
 * Here the row *is* the archived title. It owns the chapters, the read
 * progress, the categories, the import history and the cover file, and its
 * source is one field on it. So a migration is an update of that field, and
 * every relation follows untouched — nothing is copied, reconstructed or lost.
 * It also means the change reaches the device for free: the update re-fires
 * `mv_stamp_manga`, so the next delta carries it like any other edit.
 *
 * Everything slow happens during planning, which writes nothing to the library.
 * Applying is a local transaction, and every applied item keeps a snapshot of
 * the identity it replaced, so it can be undone.
 */
@Injectable()
export class MigrationService {
  private readonly logger = new Logger(MigrationService.name);
  /** Abort handles for planning runs owned by this process. */
  private readonly running = new Map<string, AbortController>();

  constructor(
    private readonly dataSource: DataSource,
    private readonly search: SourceSearchRegistry,
    private readonly library: LibraryService,
    @InjectRepository(SourceMigrationJobEntity)
    private readonly jobs: Repository<SourceMigrationJobEntity>,
    @InjectRepository(SourceMigrationItemEntity)
    private readonly items: Repository<SourceMigrationItemEntity>,
  ) {}

  // ---- planning ----

  /**
   * Build a migration plan. Returns as soon as the job row exists; the search
   * runs behind it and the client polls, the same shape as a cover run.
   */
  async plan(request: PlanMigrationRequest): Promise<MigrationJobDto> {
    const fromSourceId = request.fromSourceId?.trim();
    if (!fromSourceId) {
      throw new BadRequestException('fromSourceId is required');
    }
    const toSourceIds = (request.toSourceIds ?? [])
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && s !== fromSourceId);
    if (toSourceIds.length === 0) {
      throw new BadRequestException('at least one target source is required');
    }

    const active = await this.jobs.findOne({
      where: [{ status: 'planning' }, { status: 'applying' }],
    });
    if (active) {
      throw new ConflictException('a migration is already in progress');
    }

    const titles = await this.titlesToMigrate(fromSourceId, request.mangaIds);
    if (titles.length === 0) {
      throw new BadRequestException('no titles found on that source');
    }

    const now = Date.now();
    const job = await this.jobs.save(
      this.jobs.create({
        status: 'planning',
        fromSourceId,
        toSourceIds,
        total: titles.length,
        planned: 0,
        matched: 0,
        applied: 0,
        skipped: 0,
        failed: 0,
        cancelRequested: false,
        error: null,
        startedAt: now,
        updatedAt: now,
        finishedAt: null,
      }),
    );

    // One row per title up front, so the review screen has something to render
    // the moment it opens rather than an empty list that fills in.
    await this.items.save(
      titles.map((t) =>
        this.items.create({
          jobId: job.id,
          mangaId: t.id,
          title: t.title,
          fromSourceId: t.sourceId,
          fromMangaUrl: t.mangaUrl,
          state: 'pending',
          candidates: [],
          reasons: [],
        }),
      ),
    );

    const abort = new AbortController();
    this.running.set(job.id, abort);
    void this.runPlan(job.id, titles, toSourceIds, abort.signal);

    return this.toJobDto(job, await this.sourceName(fromSourceId));
  }

  private async runPlan(
    jobId: string,
    titles: VaultTitle[],
    toSourceIds: string[],
    signal: AbortSignal,
  ): Promise<void> {
    try {
      // Loaded once for the whole run: the in-vault matcher compares against
      // every other title in the library, and re-querying per title would turn
      // a plan into a thousand scans.
      const vaultPool = await this.vaultCandidatePool(toSourceIds);
      const targets = await this.describeTargets(toSourceIds);

      let cursor = 0;
      const workers = Array.from(
        { length: Math.min(PLAN_CONCURRENCY, titles.length) },
        async () => {
          while (!signal.aborted) {
            const index = cursor++;
            if (index >= titles.length) return;
            await this.planOne(jobId, titles[index], targets, vaultPool, signal);
          }
        },
      );
      await Promise.all(workers);

      await this.refreshCounters(jobId);
      await this.jobs.update(jobId, {
        status: signal.aborted ? 'cancelled' : 'ready',
        updatedAt: Date.now(),
        finishedAt: signal.aborted ? Date.now() : null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(`migration plan ${jobId} failed: ${message}`);
      await this.jobs.update(jobId, {
        status: 'failed',
        error: message,
        updatedAt: Date.now(),
        finishedAt: Date.now(),
      });
    } finally {
      this.running.delete(jobId);
    }
  }

  /**
   * Find the best target for one title.
   *
   * Candidates come from two places, and both matter. The **vault pool** costs
   * nothing and is often decisive: a library assembled from several backups
   * usually already contains the same book under another source. The **adapter
   * search** covers the rest, for the target sources we can query at all.
   */
  private async planOne(
    jobId: string,
    title: VaultTitle,
    targets: TargetSource[],
    vaultPool: SourceCandidate[],
    signal: AbortSignal,
  ): Promise<void> {
    const collected: SourceCandidate[] = vaultPool.filter(
      (c) => c.title.length > 0,
    );

    for (const target of targets) {
      if (signal.aborted) return;
      if (!target.searchable) continue;
      const hits = await this.search.search(target.source, title.title, signal);
      collected.push(...hits);
    }

    // `url` is the matcher's name for the title's own address on its source —
    // it is what stops a title being offered itself as a migration target.
    const ranked = rankCandidates(
      { ...title, url: title.mangaUrl },
      collected,
    );
    // Preference order is the user's ranking of target sources, so a strong
    // match on their first choice beats a marginally better one further down.
    const ordered = [...ranked].sort((a, b) => {
      const rank =
        targetRank(targets, a.sourceId) - targetRank(targets, b.sourceId);
      return rank !== 0 ? rank : b.score - a.score;
    });

    const stored = ordered
      .slice(0, MAX_STORED_CANDIDATES)
      .map((c) => this.toStoredCandidate(c, targets, collected));
    const best = ordered[0];

    if (!best) {
      await this.items.update(
        { jobId, mangaId: title.id },
        { state: 'unmatched', candidates: [], reasons: [] },
      );
      return;
    }

    await this.items.update(
      { jobId, mangaId: title.id },
      {
        state: 'matched',
        toSourceId: best.sourceId,
        toMangaUrl: best.url,
        toTitle: best.title,
        toThumbnailUrl: best.thumbnailUrl ?? null,
        score: best.score.toFixed(3),
        method: methodOf(best, collected),
        candidates: stored,
        reasons: best.reasons,
      },
    );
  }

  // ---- review ----

  /** A plan and every title in it. */
  async getPlan(jobId: string): Promise<MigrationPlanDto> {
    const job = await this.jobs.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('migration not found');

    const rows = await this.items.find({
      where: { jobId },
      order: { title: 'ASC' },
    });
    const names = await this.sourceNames([
      job.fromSourceId,
      ...job.toSourceIds,
      ...rows.flatMap((r) => (r.toSourceId ? [r.toSourceId] : [])),
    ]);
    const conflictTitles = await this.titlesById(
      rows.flatMap((r) => (r.conflictMangaId ? [r.conflictMangaId] : [])),
    );
    const targets = await this.describeTargets(job.toSourceIds);

    return {
      job: this.toJobDto(job, names.get(job.fromSourceId) ?? job.fromSourceId),
      items: rows.map((r) => this.toItemDto(r, names, conflictTitles)),
      unsearchable: targets
        .filter((t) => !t.searchable)
        .map((t) => ({
          sourceId: t.source.sourceId,
          name: t.source.name,
          reason: t.reason,
        })),
      autoAcceptScore: AUTO_ACCEPT_SIMILARITY,
    };
  }

  /** Recent plans, newest first. */
  async listJobs(limit = 20): Promise<MigrationJobDto[]> {
    const rows = await this.jobs.find({
      order: { startedAt: 'DESC' },
      take: limit,
    });
    const names = await this.sourceNames(rows.map((r) => r.fromSourceId));
    return rows.map((r) =>
      this.toJobDto(r, names.get(r.fromSourceId) ?? r.fromSourceId),
    );
  }

  /** Change or clear the match chosen for one title. */
  async updateItem(
    jobId: string,
    mangaId: string,
    request: UpdateMigrationItemRequest,
  ): Promise<MigrationItemDto> {
    const item = await this.items.findOne({ where: { jobId, mangaId } });
    if (!item) throw new NotFoundException('title not in this migration');
    if (item.state === 'applied') {
      throw new ConflictException('this title has already been migrated');
    }

    if (request.skip) {
      item.state = 'skipped';
      item.error = null;
    } else if (typeof request.candidateIndex === 'number') {
      const candidate = item.candidates[request.candidateIndex];
      if (!candidate) throw new BadRequestException('no such candidate');
      item.state = 'matched';
      item.toSourceId = candidate.sourceId;
      item.toMangaUrl = candidate.url;
      item.toTitle = candidate.title;
      item.toThumbnailUrl = candidate.thumbnailUrl;
      item.score = candidate.score.toFixed(3);
      item.method = candidate.method;
      item.reasons = candidate.reasons;
      item.error = null;
    } else if (request.toSourceId && request.toMangaUrl) {
      const url = request.toMangaUrl.trim();
      if (!url) throw new BadRequestException('toMangaUrl is required');
      item.state = 'matched';
      item.toSourceId = request.toSourceId.trim();
      item.toMangaUrl = url;
      item.toTitle = null;
      item.toThumbnailUrl = null;
      // A url the user supplied is not scored — there is nothing to score it
      // against, and pretending otherwise would put a fake number on screen.
      item.score = null;
      item.method = 'manual';
      item.reasons = ['entered by hand'];
      item.error = null;
    } else {
      throw new BadRequestException(
        'provide candidateIndex, a source + url, or skip',
      );
    }

    item.conflictMangaId = null;
    await this.items.save(item);
    await this.refreshCounters(jobId);

    const names = await this.sourceNames(
      item.toSourceId ? [item.toSourceId] : [],
    );
    return this.toItemDto(item, names, new Map());
  }

  // ---- applying ----

  /**
   * Apply every matched title in a plan.
   *
   * Each title is its own transaction: a plan of 300 titles that hits a
   * conflict on number 200 must leave the first 199 migrated, not roll them
   * back. The per-item snapshot is what makes that safe — anything applied can
   * be undone individually.
   */
  async apply(
    jobId: string,
    mangaIds?: string[],
  ): Promise<ApplyMigrationResultDto> {
    const job = await this.jobs.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('migration not found');
    if (job.status === 'planning') {
      throw new ConflictException('the plan is still being built');
    }
    if (job.status === 'applying') {
      throw new ConflictException('this migration is already being applied');
    }

    await this.jobs.update(jobId, {
      status: 'applying',
      updatedAt: Date.now(),
    });

    const matched = await this.items.find({
      where: { jobId, state: 'matched' },
    });

    // Which titles actually get rewritten.
    //
    // The app sends the exact set the user ticked. When nothing is specified,
    // the default is deliberately conservative: only matches at or above the
    // auto-accept bar, plus urls the user typed themselves (no score, because
    // there is nothing to score a hand-entered url against — but the user has
    // already decided). A plausible-but-uncertain match like a 0.69 is left for
    // a human to confirm rather than applied because an API call omitted a
    // field.
    const selected = new Set(mangaIds ?? []);
    const pending =
      selected.size > 0
        ? matched.filter((i) => selected.has(i.mangaId))
        : matched.filter(
            (i) =>
              i.method === 'manual' ||
              (i.score !== null && Number(i.score) >= AUTO_ACCEPT_SIMILARITY),
          );

    let applied = 0;
    let conflicts = 0;
    let failed = 0;
    try {
      for (const item of pending) {
        const outcome = await this.applyOne(item);
        if (outcome === 'applied') applied++;
        else if (outcome === 'conflict') conflicts++;
        else failed++;
      }
    } finally {
      await this.refreshCounters(jobId);
      await this.jobs.update(jobId, {
        status: 'applied',
        updatedAt: Date.now(),
        finishedAt: Date.now(),
      });
    }

    this.logger.log(
      `migration ${jobId}: ${applied} applied, ${conflicts} conflicts, ${failed} failed`,
    );
    return { jobId, applied, conflicts, failed };
  }

  /**
   * Re-point one title.
   *
   * The whole operation is a single `UPDATE manga` behind the sync lock. The
   * lock is not optional: `row_version` is stamped at write time, not commit
   * time, so without it a concurrent cover write could commit a higher version
   * first and a client would sync straight past the migration.
   */
  private async applyOne(
    item: SourceMigrationItemEntity,
  ): Promise<'applied' | 'conflict' | 'failed'> {
    if (!item.toSourceId || !item.toMangaUrl) return 'failed';

    try {
      const result = await withSyncLock(this.dataSource, async (mgr) => {
        const current = (await mgr.query(
          `SELECT source_id AS "sourceId", manga_url AS "mangaUrl",
                  source_name AS "sourceName", thumbnail_url AS "thumbnailUrl",
                  cover_state AS "coverState"
             FROM manga WHERE id = $1`,
          [item.mangaId],
        )) as Array<MigrationSnapshot & { coverState: string }>;
        if (current.length === 0) {
          return { outcome: 'failed' as const, error: 'title no longer exists' };
        }

        // The identity we are about to take may already belong to another
        // archived title — the user already has this book on the target source.
        // That is not an error and must not be forced: two rows cannot share
        // `uq_manga_source`, and overwriting one would destroy its history.
        const clash = (await mgr.query(
          `SELECT id FROM manga
            WHERE source_id = $1 AND manga_url = $2 AND id <> $3`,
          [item.toSourceId, item.toMangaUrl, item.mangaId],
        )) as Array<{ id: string }>;
        if (clash.length > 0) {
          return { outcome: 'conflict' as const, conflictId: clash[0].id };
        }

        const snapshot: MigrationSnapshot = {
          sourceId: current[0].sourceId,
          mangaUrl: current[0].mangaUrl,
          sourceName: current[0].sourceName,
          thumbnailUrl: current[0].thumbnailUrl,
        };

        const targetName = (await mgr.query(
          `SELECT name FROM known_source WHERE source_id = $1`,
          [item.toSourceId],
        )) as Array<{ name: string }>;

        // A cover already archived keeps its file — `cover_path` is untouched,
        // so the app shows the same image throughout. Only the *upstream*
        // pointer moves, and a cover that never landed is reset to `none` so
        // the archiver retries it against the new source.
        const nextThumb = item.toThumbnailUrl ?? current[0].thumbnailUrl;
        const resetCover =
          current[0].coverState !== 'archived' &&
          nextThumb !== current[0].thumbnailUrl;

        await mgr.query(
          `UPDATE manga
              SET source_id = $2,
                  manga_url = $3,
                  source_name = $4,
                  thumbnail_url = $5
                  ${resetCover ? `, cover_state = 'none', cover_failed_at = NULL` : ''}
            WHERE id = $1`,
          [
            item.mangaId,
            item.toSourceId,
            item.toMangaUrl,
            targetName[0]?.name ?? '',
            nextThumb,
          ],
        );

        return { outcome: 'applied' as const, snapshot };
      });

      if (result.outcome === 'conflict') {
        item.state = 'conflict';
        item.conflictMangaId = result.conflictId;
        item.error = 'this title is already in the vault on the target source';
        await this.items.save(item);
        return 'conflict';
      }
      if (result.outcome === 'failed') {
        item.state = 'failed';
        item.error = result.error;
        await this.items.save(item);
        return 'failed';
      }

      item.state = 'applied';
      item.snapshot = result.snapshot;
      item.appliedAt = Date.now();
      item.undoneAt = null;
      item.error = null;
      await this.items.save(item);
      return 'applied';
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      item.state = 'failed';
      item.error = message;
      await this.items.save(item);
      this.logger.warn(`migrating ${item.title} failed: ${message}`);
      return 'failed';
    }
  }

  /**
   * Put a migrated title back where it was.
   *
   * The inverse of {@link applyOne}, using the snapshot taken at the time. It
   * can itself hit a conflict — if something else has since claimed the old
   * identity — and says so rather than clobbering it.
   */
  async undo(itemId: string): Promise<MigrationItemDto> {
    const item = await this.items.findOne({ where: { id: itemId } });
    if (!item) throw new NotFoundException('migration record not found');
    if (item.state !== 'applied' || !item.snapshot) {
      throw new ConflictException('this title has not been migrated');
    }
    const snapshot = item.snapshot;

    await withSyncLock(this.dataSource, async (mgr) => {
      const clash = (await mgr.query(
        `SELECT id FROM manga
          WHERE source_id = $1 AND manga_url = $2 AND id <> $3`,
        [snapshot.sourceId, snapshot.mangaUrl, item.mangaId],
      )) as Array<{ id: string }>;
      if (clash.length > 0) {
        throw new ConflictException(
          'another title now holds the original source and url',
        );
      }
      await mgr.query(
        `UPDATE manga
            SET source_id = $2, manga_url = $3, source_name = $4,
                thumbnail_url = $5
          WHERE id = $1`,
        [
          item.mangaId,
          snapshot.sourceId,
          snapshot.mangaUrl,
          snapshot.sourceName,
          snapshot.thumbnailUrl,
        ],
      );
    });

    item.state = 'undone';
    item.undoneAt = Date.now();
    await this.items.save(item);
    await this.refreshCounters(item.jobId);

    const names = await this.sourceNames(
      item.toSourceId ? [item.toSourceId] : [],
    );
    return this.toItemDto(item, names, new Map());
  }

  /**
   * Resolve a conflict by folding the migrating title into the copy the vault
   * already holds on the target source.
   *
   * Read state is carried over the way Mihon does it, because it is the only
   * way that works across sources: chapter urls differ, so the match is on
   * chapter *number* — every chapter at or below the old title's highest read
   * number is marked read, and bookmarks transfer where numbers line up.
   * Categories and import history are unioned, then the now-redundant row is
   * removed through the normal delete path, which snapshots it into the recycle
   * bin and blocks the next import from resurrecting it.
   */
  async resolveConflict(itemId: string): Promise<MigrationItemDto> {
    const item = await this.items.findOne({ where: { id: itemId } });
    if (!item) throw new NotFoundException('migration record not found');
    if (item.state !== 'conflict' || !item.conflictMangaId) {
      throw new ConflictException('this title is not in conflict');
    }
    const loser = item.mangaId;
    const winner = item.conflictMangaId;

    await withSyncLock(this.dataSource, async (mgr) => {
      // Highest chapter number the old title had actually read.
      const highWater = (await mgr.query(
        `SELECT MAX(chapter_number) AS n FROM chapter
          WHERE manga_id = $1 AND read AND chapter_number >= 0`,
        [loser],
      )) as Array<{ n: number | null }>;
      const readUpTo = highWater[0]?.n ?? null;

      if (readUpTo !== null) {
        await mgr.query(
          `UPDATE chapter SET read = TRUE
            WHERE manga_id = $1 AND chapter_number >= 0
              AND chapter_number <= $2 AND NOT read`,
          [winner, readUpTo],
        );
      }

      // Bookmarks and per-chapter progress where the numbers line up.
      await mgr.query(
        `UPDATE chapter w
            SET bookmark = w.bookmark OR l.bookmark,
                last_page_read = GREATEST(w.last_page_read, l.last_page_read),
                last_read_at = GREATEST(
                  COALESCE(w.last_read_at, 0), COALESCE(l.last_read_at, 0)
                )
           FROM chapter l
          WHERE w.manga_id = $1 AND l.manga_id = $2
            AND w.chapter_number >= 0
            AND w.chapter_number = l.chapter_number`,
        [winner, loser],
      );

      await mgr.query(
        `INSERT INTO manga_category (manga_id, category_id)
         SELECT $1, category_id FROM manga_category WHERE manga_id = $2
         ON CONFLICT DO NOTHING`,
        [winner, loser],
      );
      // Import history is provenance — the winner should show that it also
      // came from the backups the loser came from.
      await mgr.query(
        `INSERT INTO manga_import (manga_id, import_id)
         SELECT $1, import_id FROM manga_import WHERE manga_id = $2
         ON CONFLICT DO NOTHING`,
        [winner, loser],
      );
      await mgr.query(
        `UPDATE manga w
            SET favorite = w.favorite OR l.favorite,
                date_added = LEAST(
                  NULLIF(w.date_added, 0), NULLIF(l.date_added, 0)
                ),
                notes = CASE
                  WHEN btrim(l.notes) = '' OR w.notes = l.notes THEN w.notes
                  WHEN btrim(w.notes) = '' THEN l.notes
                  ELSE w.notes || E'\n\n---\n\n' || l.notes
                END
           FROM manga l
          WHERE w.id = $1 AND l.id = $2`,
        [winner, loser],
      );
    });

    await this.library.deleteMany([loser]);

    item.state = 'applied';
    item.appliedAt = Date.now();
    item.error = null;
    // No snapshot: the row is gone, so this one is not undoable from here —
    // the recycle bin is where it is recovered from.
    item.snapshot = null;
    await this.items.save(item);
    await this.refreshCounters(item.jobId);

    const names = await this.sourceNames(
      item.toSourceId ? [item.toSourceId] : [],
    );
    return this.toItemDto(item, names, new Map());
  }

  /** Stop a plan that is still searching. */
  async cancel(jobId: string): Promise<MigrationJobDto> {
    const job = await this.jobs.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('migration not found');
    this.running.get(jobId)?.abort();
    job.cancelRequested = true;
    if (job.status === 'planning') {
      job.status = 'cancelled';
      job.finishedAt = Date.now();
    }
    job.updatedAt = Date.now();
    await this.jobs.save(job);
    return this.toJobDto(job, await this.sourceName(job.fromSourceId));
  }

  // ---- data ----

  private async titlesToMigrate(
    fromSourceId: string,
    mangaIds?: string[],
  ): Promise<VaultTitle[]> {
    const args: unknown[] = [fromSourceId];
    let filter = '';
    if (mangaIds && mangaIds.length > 0) {
      args.push(mangaIds);
      filter = `AND m.id = ANY($2::uuid[])`;
    }
    return (await this.dataSource.query(
      `SELECT m.id, m.source_id AS "sourceId", m.manga_url AS "mangaUrl",
              m.title, m.author, m.thumbnail_url AS "thumbnailUrl",
              COALESCE(c.n, 0)::int AS "chapterCount"
         FROM manga m
         LEFT JOIN (
             SELECT manga_id, COUNT(*) AS n FROM chapter GROUP BY manga_id
         ) c ON c.manga_id = m.id
        WHERE m.source_id = $1 ${filter}
        ORDER BY m.title ASC`,
      args,
    )) as VaultTitle[];
  }

  /**
   * Titles already in the vault on the target sources.
   *
   * This is the candidate pool that needs no network and no adapter, and on a
   * library built from several backups it is often the one that answers. Loaded
   * once per plan.
   */
  private async vaultCandidatePool(
    toSourceIds: string[],
  ): Promise<SourceCandidate[]> {
    const rows = (await this.dataSource.query(
      `SELECT m.source_id AS "sourceId", m.manga_url AS url, m.title,
              m.author, m.thumbnail_url AS "thumbnailUrl",
              COALESCE(c.n, 0)::int AS "chapterCount"
         FROM manga m
         LEFT JOIN (
             SELECT manga_id, COUNT(*) AS n FROM chapter GROUP BY manga_id
         ) c ON c.manga_id = m.id
        WHERE m.source_id = ANY($1::text[])`,
      [toSourceIds],
    )) as Array<Omit<SourceCandidate, 'via'>>;
    return rows.map((r) => ({ ...r, via: 'vault' as const }));
  }

  private async describeTargets(
    toSourceIds: string[],
  ): Promise<TargetSource[]> {
    const out: TargetSource[] = [];
    for (const sourceId of toSourceIds) {
      const source = await this.search.describe(sourceId);
      if (!source) {
        out.push({
          source: {
            sourceId,
            packageName: null as unknown as string,
            name: sourceId,
            lang: '',
            homeUrl: null,
          },
          searchable: false,
          reason: 'this source is not in any repository index',
        });
        continue;
      }
      const adapter = this.search.adapterFor(source.packageName);
      out.push({
        source,
        searchable: adapter !== null,
        reason: adapter
          ? ''
          : 'no built-in search for this source — pick from your library or paste a url',
      });
    }
    return out;
  }

  /** Recompute the job counters from its items — the single source of truth. */
  private async refreshCounters(jobId: string): Promise<void> {
    const rows = (await this.dataSource.query(
      `SELECT state, COUNT(*)::int AS n
         FROM source_migration_item WHERE job_id = $1 GROUP BY state`,
      [jobId],
    )) as Array<{ state: string; n: number }>;
    const by = new Map(rows.map((r) => [r.state, r.n]));
    const pending = by.get('pending') ?? 0;
    const total = [...by.values()].reduce((a, b) => a + b, 0);
    await this.jobs.update(jobId, {
      planned: total - pending,
      matched: by.get('matched') ?? 0,
      applied: by.get('applied') ?? 0,
      skipped: by.get('skipped') ?? 0,
      failed: (by.get('failed') ?? 0) + (by.get('conflict') ?? 0),
      updatedAt: Date.now(),
    });
  }

  private async sourceName(sourceId: string): Promise<string> {
    const names = await this.sourceNames([sourceId]);
    return names.get(sourceId) ?? sourceId;
  }

  private async sourceNames(ids: string[]): Promise<Map<string, string>> {
    const unique = [...new Set(ids.filter((id) => id.length > 0))];
    if (unique.length === 0) return new Map();
    const rows = (await this.dataSource.query(
      `SELECT source_id, name FROM known_source WHERE source_id = ANY($1::text[])`,
      [unique],
    )) as Array<{ source_id: string; name: string }>;
    return new Map(rows.map((r) => [r.source_id, r.name || r.source_id]));
  }

  private async titlesById(ids: string[]): Promise<Map<string, string>> {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map();
    const rows = await this.dataSource.query<Array<{ id: string; title: string }>>(
      `SELECT id, title FROM manga WHERE id = ANY($1::uuid[])`,
      [unique],
    );
    return new Map(rows.map((r) => [r.id, r.title]));
  }

  // ---- mapping ----

  private toStoredCandidate(
    c: ScoredCandidate,
    targets: TargetSource[],
    collected: SourceCandidate[],
  ): StoredCandidate {
    return {
      sourceId: c.sourceId,
      sourceName:
        targets.find((t) => t.source.sourceId === c.sourceId)?.source.name ??
        c.sourceId,
      url: c.url,
      title: c.title,
      author: c.author ?? null,
      thumbnailUrl: c.thumbnailUrl ?? null,
      score: c.score,
      method: methodOf(c, collected),
      reasons: c.reasons,
    };
  }

  private toJobDto(
    job: SourceMigrationJobEntity,
    fromSourceName: string,
  ): MigrationJobDto {
    return {
      jobId: job.id,
      status: job.status,
      fromSourceId: job.fromSourceId,
      fromSourceName,
      toSourceIds: job.toSourceIds,
      total: job.total,
      planned: job.planned,
      matched: job.matched,
      applied: job.applied,
      skipped: job.skipped,
      failed: job.failed,
      finished: job.status !== 'planning' && job.status !== 'applying',
      cancelRequested: job.cancelRequested,
      error: job.error,
      startedAt: job.startedAt,
      finishedAt: job.finishedAt,
    };
  }

  private toItemDto(
    row: SourceMigrationItemEntity,
    names: Map<string, string>,
    conflictTitles: Map<string, string>,
  ): MigrationItemDto {
    return {
      id: row.id,
      mangaId: row.mangaId,
      title: row.title,
      fromSourceId: row.fromSourceId,
      fromMangaUrl: row.fromMangaUrl,
      toSourceId: row.toSourceId,
      toSourceName: row.toSourceId
        ? (names.get(row.toSourceId) ?? row.toSourceId)
        : null,
      toMangaUrl: row.toMangaUrl,
      toTitle: row.toTitle,
      toThumbnailUrl: row.toThumbnailUrl,
      score: row.score === null ? null : Number(row.score),
      method: row.method,
      state: row.state,
      reasons: row.reasons ?? [],
      candidates: row.candidates ?? [],
      conflictMangaId: row.conflictMangaId,
      conflictTitle: row.conflictMangaId
        ? (conflictTitles.get(row.conflictMangaId) ?? null)
        : null,
      error: row.error,
      undoable: row.state === 'applied' && row.snapshot !== null,
    };
  }
}

interface TargetSource {
  source: {
    sourceId: string;
    packageName: string;
    name: string;
    lang: string;
    homeUrl: string | null;
  };
  searchable: boolean;
  reason: string;
}

/** Position of a candidate's source in the user's preference order. */
function targetRank(targets: TargetSource[], sourceId: string): number {
  const index = targets.findIndex((t) => t.source.sourceId === sourceId);
  return index === -1 ? targets.length : index;
}

/** Where a ranked candidate originally came from. */
function methodOf(
  candidate: { sourceId: string; url: string },
  collected: SourceCandidate[],
): StoredCandidate['method'] {
  const origin = collected.find(
    (c) => c.sourceId === candidate.sourceId && c.url === candidate.url,
  );
  return origin?.via ?? 'adapter';
}
