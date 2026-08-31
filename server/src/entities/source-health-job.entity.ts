import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

/**
 * Lifecycle of one health-check run. Mirrors {@link CoverJobEntity} exactly,
 * `interrupted` included — a `running` row whose owning process died.
 */
export type SourceHealthJobStatus =
  | 'running'
  | 'finished'
  | 'cancelled'
  | 'failed'
  | 'interrupted';

/** What asked for the run. `schedule` is the daily background pass. */
export type SourceHealthJobTrigger = 'manual' | 'schedule' | 'resume';

/**
 * A run of the source health checker, persisted so progress survives a poll,
 * a client disconnect and a restart.
 *
 * The counters bucket the verdicts rather than counting successes: `ok`,
 * `degraded` (answers, but its covers are failing wholesale) and `unhealthy`
 * (blocked, unreachable, or withdrawn from every repository).
 */
@Entity('source_health_job')
export class SourceHealthJobEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** Guarded by `uq_source_health_job_running` — one live run at a time. */
  @Column({ type: 'text', default: 'running' })
  status: SourceHealthJobStatus;

  @Column({ type: 'text', default: 'manual' })
  trigger: SourceHealthJobTrigger;

  @Column({ type: 'integer', default: 0 })
  total: number;

  @Column({ type: 'integer', default: 0 })
  done: number;

  @Column({ type: 'integer', default: 0 })
  ok: number;

  @Column({ type: 'integer', default: 0 })
  degraded: number;

  @Column({ type: 'integer', default: 0 })
  unhealthy: number;

  @Column({ name: 'cancel_requested', type: 'boolean', default: false })
  cancelRequested: boolean;

  @Column({ type: 'text', nullable: true })
  error: string | null;

  @Index('idx_source_health_job_started_at')
  @Column({ name: 'started_at', type: 'bigint', transformer: bigIntToNumber })
  startedAt: number;

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
