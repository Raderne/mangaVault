import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { CoverJobEntity } from '../../entities';
import type {
  CoverJobStatus,
  CoverJobTrigger,
} from '../../entities/cover-job.entity';
import type { CoverJobDto, CoverResultDto } from './cover.dto';

/**
 * How often the in-memory counters are written back to `cover_job`. A run of a
 * few thousand covers would otherwise issue a row update per cover, competing
 * with the library's own writes for the pool and the sync lock — and the only
 * consumer is a client polling once a second.
 */
const FLUSH_INTERVAL_MS = 1_000;

/** Flush early once this many covers have been processed since the last one. */
const FLUSH_EVERY = 25;

/** History page size for `GET /covers/jobs`. */
const HISTORY_LIMIT = 20;

/** The run currently owned by this process. */
interface LiveJob {
  id: string;
  trigger: CoverJobTrigger;
  retryFailed: boolean;
  total: number;
  done: number;
  archived: number;
  failed: number;
  skipped: number;
  startedAt: number;
  /** Aborted by `cancel`; the pool stops dispatching and drains. */
  abort: AbortController;
  cancelRequested: boolean;
  sinceFlush: number;
  lastFlushAt: number;
  flushing: boolean;
}

/**
 * Progress tracker for cover-archiving runs, durable in Postgres.
 *
 * Runs are long (thousands of HTTP fetches), so a run has to outlive a poll,
 * a client disconnect, and — as a record — the process itself. The live run's
 * counters live in memory and are flushed to its `cover_job` row on a throttle;
 * a status read prefers memory (it is always at least as fresh) and falls back
 * to the row for finished or pre-restart jobs.
 *
 * Only one run exists at a time: the service joins an in-flight run rather than
 * starting a second, and `uq_cover_job_running` backs that up in the database.
 */
@Injectable()
export class CoverJobStore {
  private readonly logger = new Logger(CoverJobStore.name);
  private live: LiveJob | null = null;

  constructor(
    @InjectRepository(CoverJobEntity)
    private readonly jobs: Repository<CoverJobEntity>,
  ) {}

  /** Create a `running` job row and take ownership of it in this process. */
  async start(params: {
    total: number;
    trigger: CoverJobTrigger;
    retryFailed: boolean;
  }): Promise<CoverJobDto> {
    const now = Date.now();
    const row = await this.jobs.save(
      this.jobs.create({
        status: 'running',
        trigger: params.trigger,
        total: params.total,
        done: 0,
        archived: 0,
        failed: 0,
        skipped: 0,
        retryFailed: params.retryFailed,
        cancelRequested: false,
        error: null,
        startedAt: now,
        updatedAt: now,
        finishedAt: null,
      }),
    );
    this.live = {
      id: row.id,
      trigger: params.trigger,
      retryFailed: params.retryFailed,
      total: params.total,
      done: 0,
      archived: 0,
      failed: 0,
      skipped: 0,
      startedAt: now,
      abort: new AbortController(),
      cancelRequested: false,
      sinceFlush: 0,
      lastFlushAt: now,
      flushing: false,
    };
    return this.toDto(this.live, 'running');
  }

  /** The live run's id, or null when nothing is in flight here. */
  activeJobId(): string | null {
    return this.live?.id ?? null;
  }

  /** Abort signal for the live run — passed to the download pool. */
  signal(jobId: string): AbortSignal | undefined {
    return this.live?.id === jobId ? this.live.abort.signal : undefined;
  }

  /**
   * Record one processed cover. Deliberately synchronous: it is called from
   * every pool worker, so it only touches memory and lets a throttled flush
   * carry the numbers to Postgres in the background.
   */
  record(jobId: string, outcome: CoverResultDto['outcome']): void {
    const job = this.live;
    if (!job || job.id !== jobId) return;
    job.done++;
    if (outcome === 'archived') job.archived++;
    else if (outcome === 'failed') job.failed++;
    else job.skipped++;
    job.sinceFlush++;
    if (
      job.sinceFlush >= FLUSH_EVERY ||
      Date.now() - job.lastFlushAt >= FLUSH_INTERVAL_MS
    ) {
      void this.flush(job);
    }
  }

  /** Terminal state for the live run: final counters + status, then release it. */
  async finish(
    jobId: string,
    status: Exclude<CoverJobStatus, 'running'>,
    error?: string,
  ): Promise<void> {
    const job = this.live;
    if (!job || job.id !== jobId) return;
    this.live = null;
    const now = Date.now();
    await this.jobs.update(jobId, {
      status,
      done: job.done,
      archived: job.archived,
      failed: job.failed,
      skipped: job.skipped,
      cancelRequested: job.cancelRequested,
      error: error ?? null,
      updatedAt: now,
      finishedAt: now,
    });
  }

  /**
   * Ask a run to stop. The live run is aborted immediately (in-flight downloads
   * are left to drain, so no cover is half-written); the flag is persisted so
   * the reason survives in history. A job that is not running is left alone.
   */
  async cancel(jobId: string): Promise<CoverJobDto> {
    const job = this.live;
    if (job?.id === jobId) {
      job.cancelRequested = true;
      job.abort.abort();
      await this.jobs.update(jobId, {
        cancelRequested: true,
        updatedAt: Date.now(),
      });
      return this.toDto(job, 'running', true);
    }
    const row = await this.jobs.findOne({ where: { id: jobId } });
    if (!row) throw new NotFoundException('cover job not found');
    if (row.status === 'running') {
      // A `running` row with no live owner means the process that owned it is
      // gone; there is nothing to abort, so close it out directly.
      row.status = 'cancelled';
      row.cancelRequested = true;
      row.finishedAt = Date.now();
      row.updatedAt = row.finishedAt;
      await this.jobs.save(row);
    }
    return this.rowToDto(row);
  }

  /** Status of one job — from memory while it runs, from its row afterwards. */
  async status(jobId: string): Promise<CoverJobDto> {
    if (this.live?.id === jobId) {
      return this.toDto(this.live, 'running', this.live.cancelRequested);
    }
    const row = await this.jobs.findOne({ where: { id: jobId } });
    if (!row) throw new NotFoundException('cover job not found');
    return this.rowToDto(row);
  }

  /**
   * The run in progress, if any. This is what lets a client that never started
   * a run — a freshly opened app, an import-triggered or resumed run — pick up
   * live progress instead of showing nothing.
   */
  async active(): Promise<CoverJobDto | null> {
    if (this.live) {
      return this.toDto(this.live, 'running', this.live.cancelRequested);
    }
    const row = await this.jobs.findOne({ where: { status: 'running' } });
    return row ? this.rowToDto(row) : null;
  }

  /** Recent runs, newest first (the live one first when there is one). */
  async list(limit = HISTORY_LIMIT): Promise<CoverJobDto[]> {
    const rows = await this.jobs.find({
      order: { startedAt: 'DESC' },
      take: limit,
    });
    return rows.map((row) =>
      this.live?.id === row.id
        ? this.toDto(this.live, 'running', this.live.cancelRequested)
        : this.rowToDto(row),
    );
  }

  /**
   * Boot sweep: any row still marked `running` belongs to a process that no
   * longer exists, so it is closed as `interrupted` and returned for the caller
   * to resume. Runs before anything can create a new job, so it can never
   * reclaim a live one.
   */
  async reclaimInterrupted(): Promise<CoverJobEntity[]> {
    const rows = await this.jobs.find({ where: { status: 'running' } });
    if (rows.length === 0) return [];
    const now = Date.now();
    await this.jobs.update(
      { status: 'running' },
      { status: 'interrupted', updatedAt: now, finishedAt: now },
    );
    return rows;
  }

  // ---- internals ----

  /**
   * Write the live counters to the job row. Never rejects: losing a checkpoint
   * costs the client a stale poll, and must not take down the archive run that
   * is producing the real work.
   */
  private async flush(job: LiveJob): Promise<void> {
    if (job.flushing) return;
    job.flushing = true;
    job.sinceFlush = 0;
    job.lastFlushAt = Date.now();
    try {
      await this.jobs.update(job.id, {
        done: job.done,
        archived: job.archived,
        failed: job.failed,
        skipped: job.skipped,
        updatedAt: job.lastFlushAt,
      });
    } catch (err) {
      this.logger.debug(
        `cover job ${job.id} progress flush failed: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    } finally {
      job.flushing = false;
    }
  }

  private toDto(
    job: LiveJob,
    status: CoverJobStatus,
    cancelRequested = false,
  ): CoverJobDto {
    return {
      jobId: job.id,
      status,
      trigger: job.trigger,
      total: job.total,
      done: job.done,
      archived: job.archived,
      failed: job.failed,
      skipped: job.skipped,
      finished: status !== 'running',
      cancelRequested,
      error: null,
      startedAt: job.startedAt,
      finishedAt: null,
    };
  }

  private rowToDto(row: CoverJobEntity): CoverJobDto {
    return {
      jobId: row.id,
      status: row.status,
      trigger: row.trigger,
      total: row.total,
      done: row.done,
      archived: row.archived,
      failed: row.failed,
      skipped: row.skipped,
      finished: row.status !== 'running',
      cancelRequested: row.cancelRequested,
      error: row.error,
      startedAt: row.startedAt,
      finishedAt: row.finishedAt,
    };
  }
}
