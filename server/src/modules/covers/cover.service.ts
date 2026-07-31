import { mkdir, stat, unlink, writeFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  type OnApplicationBootstrap,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { withSyncLock } from '../../common/sync-lock';
import { MangaEntity } from '../../entities';
import type {
  CoverJobEntity,
  CoverJobTrigger,
} from '../../entities/cover-job.entity';
import type { CoverFetchHint } from '../../entities/known-source.entity';
import { runPool } from './concurrency';
import type {
  CoverArchiveStartedDto,
  CoverJobDto,
  CoverResultDto,
} from './cover.dto';
import { CoverFetcher } from './cover.fetcher';
import { CoverJobStore } from './cover-job.store';
import { extForMime, mimeForExt, sniffImage } from './image-sniff';

/** A title that still needs its cover archived. */
interface Candidate {
  id: string;
  sourceId: string;
  thumbnailUrl: string;
  coverPath: string | null;
}

/** How a bulk run is scoped. */
export interface ArchiveMissingOptions {
  /** What asked for the run (recorded on the job row). */
  trigger?: CoverJobTrigger;
  /**
   * Re-attempt covers already marked `failed`. True for a manual run — the user
   * tapping the button means "try again". False for an automatic one, so a
   * source that can't be fetched at all isn't hammered on every import.
   */
  retryFailed?: boolean;
  /**
   * Skip covers that failed at or after this timestamp. Used when resuming an
   * interrupted run so it doesn't re-try what it already tried.
   */
  failedSince?: number;
}

const posInt = (value: unknown, fallback: number): number => {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};

const hostOf = (url: string): string => {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
};

/**
 * Downloads and permanently archives manga covers into `STORAGE_DIR/covers/`.
 * Thumbnail URLs rot, so covers are pulled into local storage; the archived
 * file (not the remote URL) is what the app renders.
 *
 * `archiveMissing` is a **durable background job**: it returns as soon as the
 * work is registered, downloads through a bounded pool, checkpoints progress to
 * the `cover_job` table (see {@link CoverJobStore}), can be cancelled mid-run,
 * and is resumed automatically if the process dies while it is going. Only one
 * run exists at a time — a second trigger joins the first.
 */
@Injectable()
export class CoverService implements OnApplicationBootstrap {
  private readonly logger = new Logger(CoverService.name);
  private readonly storageDir: string;
  private readonly coversDir: string;
  private readonly globalConcurrency: number;
  private readonly perHostConcurrency: number;
  private readonly autoArchive: boolean;
  /**
   * In-flight `archiveMissing` call. Starting a run awaits the candidate query
   * before the job row exists, so without this two triggers landing in that gap
   * would both start a run and every cover would be fetched twice.
   */
  private pendingStart: Promise<CoverArchiveStartedDto> | null = null;

  /**
   * An import landed while a run was already going, so its titles weren't in
   * that run's candidate list. Set here, consumed when the run finishes.
   */
  private rerunAfterCurrent = false;

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(MangaEntity)
    private readonly mangaRepo: Repository<MangaEntity>,
    private readonly fetcher: CoverFetcher,
    private readonly jobs: CoverJobStore,
    config: ConfigService,
  ) {
    this.storageDir = config.get<string>('STORAGE_DIR') ?? './storage';
    this.coversDir = join(this.storageDir, 'covers');
    this.globalConcurrency = posInt(config.get('COVER_CONCURRENCY'), 6);
    this.perHostConcurrency = posInt(config.get('COVER_PER_HOST'), 2);
    // Gates the runs the *server* decides to start: the post-import archive and
    // the post-restart resume. On by default — a title should get its art
    // without being asked twice. Off, both become no-ops and only the explicit
    // `POST /covers/archive-missing` starts anything.
    //
    // The escape hatch matters because an automatic run reaches out to the
    // internet for the whole library: e2e tests set it false (see
    // test/setup-e2e.ts), and so would an operator debugging a boot loop who
    // doesn't want thousands of downloads starting on every restart.
    this.autoArchive = config.get('COVER_AUTO_ARCHIVE') !== 'false';
  }

  /**
   * Pick up a run the previous process died in the middle of.
   *
   * The candidate set is re-derived from `cover_state` rather than stored per
   * title, so the only thing to carry across the restart is "don't re-attempt
   * what that run already failed" — which is what `failedSince` does. Covers it
   * had already archived are simply no longer candidates.
   */
  async onApplicationBootstrap(): Promise<void> {
    let interrupted: CoverJobEntity[];
    try {
      // Still reclaimed when resuming is off, so an abandoned row never blocks
      // the single-running-job index or shows as running forever.
      interrupted = await this.jobs.reclaimInterrupted();
    } catch (err) {
      // Never block boot on this; the manual trigger still works.
      this.logger.warn(
        `could not check for interrupted cover jobs: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    }
    const previous = interrupted[0];
    if (!previous) return;
    if (!this.autoArchive) {
      this.logger.log(
        `cover job ${previous.id} was interrupted at ${previous.done}/${previous.total}; ` +
          `not resuming (COVER_AUTO_ARCHIVE=false)`,
      );
      return;
    }
    this.logger.log(
      `resuming cover job ${previous.id} (interrupted at ${previous.done}/${previous.total})`,
    );
    await this.archiveMissing({
      trigger: 'resume',
      retryFailed: previous.retryFailed,
      failedSince: previous.startedAt,
    }).catch((err: unknown) => {
      this.logger.warn(
        `could not resume cover job ${previous.id}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    });
  }

  /**
   * Kick off archiving every title whose cover is still `none`/`failed` and has
   * a thumbnail URL. Returns immediately with the job id; if a run is already in
   * flight, that job is returned instead of starting a second one.
   */
  async archiveMissing(
    opts: ArchiveMissingOptions = {},
  ): Promise<CoverArchiveStartedDto> {
    if (this.pendingStart) {
      return { ...(await this.pendingStart), alreadyRunning: true };
    }
    const liveId = this.jobs.activeJobId();
    if (liveId) {
      const live = await this.jobs.status(liveId);
      return { jobId: live.jobId, total: live.total, alreadyRunning: true };
    }

    this.pendingStart = this.beginRun(opts);
    try {
      return await this.pendingStart;
    } finally {
      this.pendingStart = null;
    }
  }

  /**
   * Archive covers for titles a finished import just added.
   *
   * Scoped to covers that have never been tried (`retryFailed: false`): a
   * source that can't be fetched at all — the Cloudflare cases — shouldn't be
   * re-hammered on every import. A manual run is what retries those.
   *
   * A run already in flight took its candidate list *before* these titles
   * existed, so joining it would silently drop them. Instead the import flags a
   * rerun, and the current run starts a fresh pass when it finishes.
   */
  async archiveAfterImport(): Promise<CoverArchiveStartedDto | null> {
    if (!this.autoArchive) return null;
    const started = await this.archiveMissing({
      trigger: 'import',
      retryFailed: false,
    });
    if (started.alreadyRunning) this.rerunAfterCurrent = true;
    return started;
  }

  /** Ask the running job to stop; no-op for a job that already finished. */
  cancel(jobId: string): Promise<CoverJobDto> {
    return this.jobs.cancel(jobId);
  }

  /** Archive (or re-archive) a single title's cover synchronously. */
  async archiveOne(mangaId: string): Promise<CoverResultDto> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m) throw new NotFoundException('manga not found');
    const hint = await this.loadHint(m.sourceId);
    return this.archiveCandidate(
      {
        id: m.id,
        sourceId: m.sourceId,
        thumbnailUrl: m.thumbnailUrl ?? '',
        coverPath: m.coverPath,
      },
      hint,
    );
  }

  /**
   * Replace a title's cover with a user-supplied image. The bytes are sniffed
   * (not trusted from the upload's declared MIME) to pick the stored format.
   */
  async setCustomCover(
    mangaId: string,
    bytes: Buffer,
  ): Promise<CoverResultDto> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m) throw new NotFoundException('manga not found');
    const sniffed = sniffImage(bytes);
    if (!sniffed) {
      throw new BadRequestException('uploaded file is not a recognised image');
    }
    const relPath = await this.writeCoverFile(
      mangaId,
      bytes,
      sniffed.ext,
      m.coverPath,
    );
    await this.updateCover(mangaId, {
      coverPath: relPath,
      coverState: 'archived',
      coverFailedAt: null,
    });
    return { mangaId, outcome: 'archived', coverState: 'archived' };
  }

  /**
   * Resolve the on-disk cover for serving, or `null` when the title has no
   * archived cover (or the file went missing) — the caller returns 404.
   */
  async resolveCoverFile(
    mangaId: string,
  ): Promise<{ absPath: string; mime: string } | null> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m || m.coverState !== 'archived' || !m.coverPath) return null;
    const absPath = join(this.storageDir, m.coverPath);
    try {
      await stat(absPath);
    } catch {
      return null;
    }
    return { absPath, mime: mimeForExt(extname(m.coverPath).slice(1)) };
  }

  /**
   * Remove archived cover files by their stored relative paths — used when
   * titles are deleted, since `manga.cover_path` is the only pointer to the
   * file and the row is about to go. Returns how many files were actually
   * unlinked; a missing file is not an error (the goal is that nothing is left
   * behind, not that every path resolved).
   */
  async deleteCoverFiles(relPaths: readonly string[]): Promise<number> {
    let removed = 0;
    for (const rel of relPaths) {
      if (!rel) continue;
      try {
        await unlink(join(this.storageDir, rel));
        removed += 1;
      } catch {
        // Already gone, or never written — nothing to clean up.
      }
    }
    return removed;
  }

  jobStatus(jobId: string): Promise<CoverJobDto> {
    return this.jobs.status(jobId);
  }

  /** The run in progress, or null — lets a client adopt a run it didn't start. */
  activeJob(): Promise<CoverJobDto | null> {
    return this.jobs.active();
  }

  /** Recent runs, newest first. */
  jobHistory(): Promise<CoverJobDto[]> {
    return this.jobs.list();
  }

  // ---- internals ----

  private async beginRun(
    opts: ArchiveMissingOptions,
  ): Promise<CoverArchiveStartedDto> {
    const retryFailed = opts.retryFailed ?? true;
    const candidates = await this.loadCandidates(retryFailed, opts.failedSince);
    const job = await this.jobs.start({
      total: candidates.length,
      trigger: opts.trigger ?? 'manual',
      retryFailed,
    });
    if (candidates.length === 0) {
      // Nothing to do — close the run out at once so it neither sits in history
      // as forever-running nor holds the single-run slot.
      await this.jobs.finish(job.jobId, 'finished');
      return { jobId: job.jobId, total: 0, alreadyRunning: false };
    }
    const hints = await this.loadHints();
    setImmediate(() => void this.runArchive(job.jobId, candidates, hints));
    return {
      jobId: job.jobId,
      total: candidates.length,
      alreadyRunning: false,
    };
  }

  private async runArchive(
    jobId: string,
    candidates: Candidate[],
    hints: Map<string, CoverFetchHint>,
  ): Promise<void> {
    const signal = this.jobs.signal(jobId);
    try {
      await mkdir(this.coversDir, { recursive: true });
      await runPool(
        candidates,
        {
          globalLimit: this.globalConcurrency,
          perKeyLimit: this.perHostConcurrency,
          keyOf: (c) => hostOf(c.thumbnailUrl),
          signal,
        },
        async (c) => {
          const result = await this.archiveCandidate(
            c,
            hints.get(c.sourceId) ?? null,
          );
          this.jobs.record(jobId, result.outcome);
        },
      );
      const cancelled = signal?.aborted === true;
      const summary = await this.jobs.status(jobId);
      await this.jobs.finish(jobId, cancelled ? 'cancelled' : 'finished');
      this.logger.log(
        `cover archive ${jobId} ${cancelled ? 'cancelled' : 'finished'}: ` +
          `${summary.archived} archived, ${summary.failed} failed, ` +
          `${summary.skipped} skipped of ${summary.total}`,
      );
      // An import landed mid-run; its titles need their own pass. Skipped after
      // a cancel — someone who pressed Stop doesn't want it starting again.
      const rerun = this.rerunAfterCurrent;
      this.rerunAfterCurrent = false;
      if (rerun && !cancelled) {
        await this.archiveMissing({
          trigger: 'import',
          retryFailed: false,
        }).catch((err: unknown) => {
          this.logger.warn(
            `could not start follow-up cover run: ${
              err instanceof Error ? err.message : String(err)
            }`,
          );
        });
      }
    } catch (err) {
      // A throw here is the pool/mkdir failing, not an individual cover — those
      // are caught per candidate and recorded as `failed`.
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(`cover archive ${jobId} aborted: ${message}`);
      await this.jobs.finish(jobId, 'failed', message).catch(() => undefined);
    }
  }

  /**
   * Persist a cover-state change under the sync lock, so `row_version` order
   * matches commit order even with `COVER_CONCURRENCY` workers writing at once
   * (see common/sync-lock.ts). The fetch and the file write already happened —
   * only the row update is inside the transaction, so the lock is held briefly.
   */
  private async updateCover(
    mangaId: string,
    patch: Partial<
      Pick<MangaEntity, 'coverPath' | 'coverState' | 'coverFailedAt'>
    >,
  ): Promise<void> {
    await withSyncLock(this.dataSource, async (mgr) => {
      await mgr.update(MangaEntity, mangaId, patch);
    });
  }

  private async archiveCandidate(
    c: Candidate,
    hint: CoverFetchHint | null,
  ): Promise<CoverResultDto> {
    const url = c.thumbnailUrl?.trim();
    if (!url) {
      return { mangaId: c.id, outcome: 'skipped', coverState: 'none' };
    }
    try {
      const { bytes, mime } = await this.fetcher.fetch(url, hint);
      const relPath = await this.writeCoverFile(
        c.id,
        bytes,
        extForMime(mime),
        c.coverPath,
      );
      await this.updateCover(c.id, {
        coverPath: relPath,
        coverState: 'archived',
        coverFailedAt: null,
      });
      return { mangaId: c.id, outcome: 'archived', coverState: 'archived' };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'cover fetch failed';
      // Stamped so a resumed run can tell "already tried in this run" from a
      // failure old enough to be worth another attempt.
      await this.updateCover(c.id, {
        coverState: 'failed',
        coverFailedAt: Date.now(),
      });
      this.logger.debug(`cover ${c.id} failed: ${message}`);
      return {
        mangaId: c.id,
        outcome: 'failed',
        coverState: 'failed',
        error: message,
      };
    }
  }

  /**
   * Write cover bytes to `covers/<mangaId>.<ext>` (relative path stored, forward
   * slashes for portability) and drop any previous file whose extension differed.
   */
  private async writeCoverFile(
    mangaId: string,
    bytes: Buffer,
    ext: string,
    oldRelPath: string | null,
  ): Promise<string> {
    await mkdir(this.coversDir, { recursive: true });
    const relPath = `covers/${mangaId}.${ext}`;
    await writeFile(join(this.storageDir, relPath), bytes);
    if (oldRelPath && oldRelPath !== relPath) {
      await unlink(join(this.storageDir, oldRelPath)).catch(() => undefined);
    }
    return relPath;
  }

  /**
   * Titles still needing a cover. `retryFailed` decides whether previously
   * failed covers are re-attempted at all; `failedSince` narrows that further
   * for a resumed run, excluding the ones the interrupted run already tried.
   */
  private async loadCandidates(
    retryFailed: boolean,
    failedSince?: number,
  ): Promise<Candidate[]> {
    const params: unknown[] = [];
    let stateClause = `cover_state = 'none'`;
    if (retryFailed && failedSince !== undefined) {
      params.push(failedSince);
      stateClause = `(cover_state = 'none' OR (cover_state = 'failed'
                      AND (cover_failed_at IS NULL OR cover_failed_at < $1)))`;
    } else if (retryFailed) {
      stateClause = `cover_state IN ('none', 'failed')`;
    }
    return this.dataSource.query<Candidate[]>(
      `SELECT id,
              source_id     AS "sourceId",
              thumbnail_url AS "thumbnailUrl",
              cover_path    AS "coverPath"
       FROM manga
       WHERE ${stateClause}
         AND thumbnail_url IS NOT NULL
         AND btrim(thumbnail_url) <> ''`,
      params,
    );
  }

  private async loadHints(): Promise<Map<string, CoverFetchHint>> {
    const rows = await this.dataSource.query<
      { source_id: string; fetch_hint: CoverFetchHint | null }[]
    >(
      `SELECT source_id, fetch_hint FROM known_source WHERE fetch_hint IS NOT NULL`,
    );
    const map = new Map<string, CoverFetchHint>();
    for (const r of rows) {
      if (r.fetch_hint) map.set(r.source_id, r.fetch_hint);
    }
    return map;
  }

  private async loadHint(sourceId: string): Promise<CoverFetchHint | null> {
    const rows = await this.dataSource.query<
      { fetch_hint: CoverFetchHint | null }[]
    >(`SELECT fetch_hint FROM known_source WHERE source_id = $1`, [sourceId]);
    return rows[0]?.fetch_hint ?? null;
  }
}
