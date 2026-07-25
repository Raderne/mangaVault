import { randomUUID } from 'node:crypto';

import { Injectable, NotFoundException } from '@nestjs/common';

import type { CoverJobStatusDto, CoverResultDto } from './cover.dto';

/** Keep finished jobs pollable for a while after they complete. */
const JOB_TTL_MS = 10 * 60 * 1000; // 10 minutes

interface CoverJob {
  id: string;
  total: number;
  done: number;
  archived: number;
  failed: number;
  skipped: number;
  finished: boolean;
  finishedAt?: number;
}

/**
 * In-memory progress tracker for cover-archiving runs. Unlike the import job
 * registry this is **poll-based** (the client hits `GET /covers/jobs/:id`), so
 * there is no event stream — just running counters the archive loop bumps.
 */
@Injectable()
export class CoverJobRegistry {
  private readonly jobs = new Map<string, CoverJob>();

  create(total: number): string {
    this.evictExpired();
    const id = randomUUID();
    this.jobs.set(id, {
      id,
      total,
      done: 0,
      archived: 0,
      failed: 0,
      skipped: 0,
      finished: total === 0,
      finishedAt: total === 0 ? Date.now() : undefined,
    });
    return id;
  }

  /** Record one processed title's outcome, advancing the counters. */
  record(jobId: string, outcome: CoverResultDto['outcome']): void {
    const job = this.jobs.get(jobId);
    if (!job || job.finished) return;
    job.done++;
    if (outcome === 'archived') job.archived++;
    else if (outcome === 'failed') job.failed++;
    else job.skipped++;
  }

  finish(jobId: string): void {
    const job = this.jobs.get(jobId);
    if (!job) return;
    job.finished = true;
    job.finishedAt = Date.now();
  }

  status(jobId: string): CoverJobStatusDto {
    const job = this.jobs.get(jobId);
    if (!job) throw new NotFoundException('cover job not found or expired');
    return {
      jobId: job.id,
      total: job.total,
      done: job.done,
      archived: job.archived,
      failed: job.failed,
      skipped: job.skipped,
      finished: job.finished,
    };
  }

  private evictExpired(): void {
    const cutoff = Date.now() - JOB_TTL_MS;
    for (const [id, job] of this.jobs) {
      if (job.finished && (job.finishedAt ?? 0) < cutoff) {
        this.jobs.delete(id);
      }
    }
  }
}
