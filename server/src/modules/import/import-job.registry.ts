import { randomUUID } from 'node:crypto';

import { Injectable, NotFoundException } from '@nestjs/common';
import { Observable, ReplaySubject } from 'rxjs';

import type {
  ImportEvent,
  ImportJobSnapshotDto,
  ImportRecordDto,
} from './import.dto';

/** Keep finished jobs around briefly so a reconnecting client can replay them. */
const JOB_TTL_MS = 10 * 60 * 1000; // 10 minutes after completion

interface Job {
  id: string;
  subject: ReplaySubject<ImportEvent>;
  finished: boolean;
  finishedAt?: number;
  processed: number;
  total: number;
  phase: string;
  lastEvent?: ImportEvent;
  record?: ImportRecordDto;
  error?: string;
}

/**
 * In-memory registry of streaming commit jobs. Each job owns a
 * `ReplaySubject` (buffers **all** events) so a client that opens the SSE stream
 * a moment after `POST .../commit` still replays every event from `start`.
 * Events are small; even a 10k-title import is a bounded, short-lived buffer.
 */
@Injectable()
export class ImportJobRegistry {
  private readonly jobs = new Map<string, Job>();

  create(): string {
    this.evictExpired();
    const id = randomUUID();
    this.jobs.set(id, {
      id,
      subject: new ReplaySubject<ImportEvent>(),
      finished: false,
      processed: 0,
      total: 0,
      phase: 'pending',
    });
    return id;
  }

  emit(jobId: string, event: ImportEvent): void {
    const job = this.jobs.get(jobId);
    if (!job || job.finished) return;
    job.lastEvent = event;
    switch (event.type) {
      case 'start':
        job.total = event.total;
        job.phase = 'start';
        break;
      case 'phase':
        job.phase = event.phase;
        break;
      case 'manga':
        job.processed = event.processed;
        break;
      case 'done':
        job.record = event.record;
        break;
      case 'error':
        job.error = event.message;
        break;
    }
    job.subject.next(event);
  }

  /** Emit a terminal event, then complete the stream so the SSE connection closes. */
  complete(jobId: string): void {
    const job = this.jobs.get(jobId);
    if (!job || job.finished) return;
    job.finished = true;
    job.finishedAt = Date.now();
    job.subject.complete();
  }

  stream(jobId: string): Observable<ImportEvent> {
    const job = this.jobs.get(jobId);
    if (!job) throw new NotFoundException('import job not found or expired');
    return job.subject.asObservable();
  }

  snapshot(jobId: string): ImportJobSnapshotDto {
    const job = this.jobs.get(jobId);
    if (!job) throw new NotFoundException('import job not found or expired');
    return {
      jobId: job.id,
      finished: job.finished,
      processed: job.processed,
      total: job.total,
      phase: job.phase,
      lastEvent: job.lastEvent,
      record: job.record,
      error: job.error,
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
