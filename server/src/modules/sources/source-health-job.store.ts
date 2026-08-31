import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { SourceHealthJobEntity } from '../../entities';
import type {
  SourceHealthJobStatus,
  SourceHealthJobTrigger,
} from '../../entities/source-health-job.entity';
import type { SourceHealth } from '../../entities/known-source.entity';
import type { SourceHealthJobDto } from './source.dto';

/** Counter flush throttle. A health run is tens of requests, not thousands. */
const FLUSH_INTERVAL_MS = 1_000;
const FLUSH_EVERY = 5;

interface LiveJob {
  id: string;
  trigger: SourceHealthJobTrigger;
  total: number;
  done: number;
  ok: number;
  degraded: number;
  unhealthy: number;
  startedAt: number;
  abort: AbortController;
  cancelRequested: boolean;
  sinceFlush: number;
  lastFlushAt: number;
  flushing: boolean;
}

/**
 * Progress tracker for source health runs, durable in Postgres.
 *
 * A direct sibling of `CoverJobStore` and deliberately so — same in-memory live
 * counters, same throttled flush, same "prefer memory, fall back to the row"
 * status read, same boot sweep for rows orphaned by a restart. A health run is
 * much shorter than a cover run, but it is still network-bound work a client
 * polls, so it earns the same shape rather than a second, subtly different one.
 */
@Injectable()
export class SourceHealthJobStore {
  private readonly logger = new Logger(SourceHealthJobStore.name);
  private live: LiveJob | null = null;

  constructor(
    @InjectRepository(SourceHealthJobEntity)
    private readonly jobs: Repository<SourceHealthJobEntity>,
  ) {}

  async start(params: {
    total: number;
    trigger: SourceHealthJobTrigger;
  }): Promise<SourceHealthJobDto> {
    const now = Date.now();
    const row = await this.jobs.save(
      this.jobs.create({
        status: 'running',
        trigger: params.trigger,
        total: params.total,
        done: 0,
        ok: 0,
        degraded: 0,
        unhealthy: 0,
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
      total: params.total,
      done: 0,
      ok: 0,
      degraded: 0,
      unhealthy: 0,
      startedAt: now,
      abort: new AbortController(),
      cancelRequested: false,
      sinceFlush: 0,
      lastFlushAt: now,
      flushing: false,
    };
    return this.toDto(this.live, 'running');
  }

  activeJobId(): string | null {
    return this.live?.id ?? null;
  }

  signal(jobId: string): AbortSignal | undefined {
    return this.live?.id === jobId ? this.live.abort.signal : undefined;
  }

  /** Record one checked source. Synchronous — only touches memory. */
  record(jobId: string, verdict: SourceHealth): void {
    const job = this.live;
    if (!job || job.id !== jobId) return;
    job.done++;
    if (verdict === 'ok') job.ok++;
    else if (verdict === 'degraded') job.degraded++;
    else if (verdict !== 'unknown') job.unhealthy++;
    job.sinceFlush++;
    if (
      job.sinceFlush >= FLUSH_EVERY ||
      Date.now() - job.lastFlushAt >= FLUSH_INTERVAL_MS
    ) {
      void this.flush(job);
    }
  }

  async finish(
    jobId: string,
    status: Exclude<SourceHealthJobStatus, 'running'>,
    error?: string,
  ): Promise<void> {
    const job = this.live;
    if (!job || job.id !== jobId) return;
    this.live = null;
    const now = Date.now();
    await this.jobs.update(jobId, {
      status,
      done: job.done,
      ok: job.ok,
      degraded: job.degraded,
      unhealthy: job.unhealthy,
      cancelRequested: job.cancelRequested,
      error: error ?? null,
      updatedAt: now,
      finishedAt: now,
    });
  }

  async cancel(jobId: string): Promise<SourceHealthJobDto> {
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
    if (!row) throw new NotFoundException('health job not found');
    if (row.status === 'running') {
      // A `running` row with no live owner: the process that owned it is gone.
      row.status = 'cancelled';
      row.cancelRequested = true;
      row.finishedAt = Date.now();
      row.updatedAt = row.finishedAt;
      await this.jobs.save(row);
    }
    return this.rowToDto(row);
  }

  async status(jobId: string): Promise<SourceHealthJobDto> {
    if (this.live?.id === jobId) {
      return this.toDto(this.live, 'running', this.live.cancelRequested);
    }
    const row = await this.jobs.findOne({ where: { id: jobId } });
    if (!row) throw new NotFoundException('health job not found');
    return this.rowToDto(row);
  }

  /** The run in progress, so a client that never started one can still watch. */
  async active(): Promise<SourceHealthJobDto | null> {
    if (this.live) {
      return this.toDto(this.live, 'running', this.live.cancelRequested);
    }
    const row = await this.jobs.findOne({ where: { status: 'running' } });
    return row ? this.rowToDto(row) : null;
  }

  /** Close out rows left `running` by a process that no longer exists. */
  async reclaimInterrupted(): Promise<number> {
    const rows = await this.jobs.find({ where: { status: 'running' } });
    if (rows.length === 0) return 0;
    const now = Date.now();
    await this.jobs.update(
      { status: 'running' },
      { status: 'interrupted', updatedAt: now, finishedAt: now },
    );
    return rows.length;
  }

  // ---- internals ----

  private async flush(job: LiveJob): Promise<void> {
    if (job.flushing) return;
    job.flushing = true;
    job.sinceFlush = 0;
    job.lastFlushAt = Date.now();
    try {
      await this.jobs.update(job.id, {
        done: job.done,
        ok: job.ok,
        degraded: job.degraded,
        unhealthy: job.unhealthy,
        updatedAt: job.lastFlushAt,
      });
    } catch (err) {
      this.logger.debug(
        `health job ${job.id} progress flush failed: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    } finally {
      job.flushing = false;
    }
  }

  private toDto(
    job: LiveJob,
    status: SourceHealthJobStatus,
    cancelRequested = false,
  ): SourceHealthJobDto {
    return {
      jobId: job.id,
      status,
      trigger: job.trigger,
      total: job.total,
      done: job.done,
      ok: job.ok,
      degraded: job.degraded,
      unhealthy: job.unhealthy,
      finished: status !== 'running',
      cancelRequested,
      error: null,
      startedAt: job.startedAt,
      finishedAt: null,
    };
  }

  private rowToDto(row: SourceHealthJobEntity): SourceHealthJobDto {
    return {
      jobId: row.id,
      status: row.status,
      trigger: row.trigger,
      total: row.total,
      done: row.done,
      ok: row.ok,
      degraded: row.degraded,
      unhealthy: row.unhealthy,
      finished: row.status !== 'running',
      cancelRequested: row.cancelRequested,
      error: row.error,
      startedAt: row.startedAt,
      finishedAt: row.finishedAt,
    };
  }
}
