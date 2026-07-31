import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

/**
 * Lifecycle of one bulk-archiving run.
 *
 * `interrupted` is what a `running` row becomes when the process that owned it
 * died — nothing but a restart can produce it, and the boot sweep turns each
 * one into a fresh `resume` run.
 */
export type CoverJobStatus =
  'running' | 'finished' | 'cancelled' | 'failed' | 'interrupted';

/** What asked for the run — surfaced in history so an unexplained run isn't a mystery. */
export type CoverJobTrigger = 'manual' | 'import' | 'resume';

/**
 * A bulk cover-archiving run, persisted so it survives a restart.
 *
 * The counters are flushed here on a throttle by `CoverJobStore`, not once per
 * cover: the live source of truth during a run is in memory, and this row is
 * the durable checkpoint that a poll (or the next boot) can read.
 */
@Entity('cover_job')
export class CoverJobEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /**
   * Guarded by the partial unique index `uq_cover_job_running`, which admits
   * only one `running` row at a time.
   */
  @Column({ type: 'text', default: 'running' })
  status: CoverJobStatus;

  @Column({ type: 'text', default: 'manual' })
  trigger: CoverJobTrigger;

  @Column({ type: 'integer', default: 0 })
  total: number;

  @Column({ type: 'integer', default: 0 })
  done: number;

  @Column({ type: 'integer', default: 0 })
  archived: number;

  @Column({ type: 'integer', default: 0 })
  failed: number;

  @Column({ type: 'integer', default: 0 })
  skipped: number;

  /** Whether this run re-attempts covers already marked `failed`. */
  @Column({ name: 'retry_failed', type: 'boolean', default: true })
  retryFailed: boolean;

  /** Set by the cancel endpoint; the runner stops dispatching new covers. */
  @Column({ name: 'cancel_requested', type: 'boolean', default: false })
  cancelRequested: boolean;

  /** Why the run ended as `failed` (an aborted pool, not an individual cover). */
  @Column({ type: 'text', nullable: true })
  error: string | null;

  @Index('idx_cover_job_started_at')
  @Column({ name: 'started_at', type: 'bigint', transformer: bigIntToNumber })
  startedAt: number;

  /** Last counter flush — also the liveness signal for a run in progress. */
  @Column({ name: 'updated_at', type: 'bigint', transformer: bigIntToNumber })
  updatedAt: number;

  @Column({
    name: 'finished_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  finishedAt: number | null;
}
