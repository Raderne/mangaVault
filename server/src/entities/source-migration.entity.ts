import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

/**
 * Lifecycle of a migration plan.
 *
 * `ready` is the state that matters: the plan exists, every title has a
 * candidate or an explicit "nothing found", and **nothing has been written to
 * the library yet**. A plan can sit there indefinitely, be edited, or be thrown
 * away, and the vault is untouched either way.
 */
export type MigrationJobStatus =
  | 'planning'
  | 'ready'
  | 'applying'
  | 'applied'
  | 'cancelled'
  | 'failed'
  | 'interrupted';

/**
 * Per-title state within a plan.
 *
 * `conflict` is its own state rather than a failure: it means the vault already
 * holds this exact title on the target source, which is a normal thing to
 * discover and has its own resolution (merge the two) rather than an error.
 */
export type MigrationItemState =
  | 'pending'
  | 'matched'
  | 'unmatched'
  | 'skipped'
  | 'conflict'
  | 'applied'
  | 'failed'
  | 'undone';

/** How a candidate was found. */
export type MigrationMethod = 'adapter' | 'vault' | 'manual';

/** What a title looked like before it was migrated, so it can be put back. */
export interface MigrationSnapshot {
  sourceId: string;
  mangaUrl: string;
  sourceName: string;
  thumbnailUrl: string | null;
}

/** A stored candidate, kept so the override sheet needs no second search. */
export interface StoredCandidate {
  sourceId: string;
  sourceName: string;
  url: string;
  title: string;
  author: string | null;
  thumbnailUrl: string | null;
  score: number;
  method: MigrationMethod;
  reasons: string[];
}

@Entity('source_migration_job')
export class SourceMigrationJobEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** `uq_source_migration_job_active` admits one planning/applying row. */
  @Column({ type: 'text', default: 'planning' })
  status: MigrationJobStatus;

  @Column({ name: 'from_source_id', type: 'text' })
  fromSourceId: string;

  /** Target sources in preference order — the first good match wins. */
  @Column({ name: 'to_source_ids', type: 'jsonb', default: () => `'[]'::jsonb` })
  toSourceIds: string[];

  @Column({ type: 'integer', default: 0 })
  total: number;

  /** Titles the planner has finished searching for. */
  @Column({ type: 'integer', default: 0 })
  planned: number;

  @Column({ type: 'integer', default: 0 })
  matched: number;

  @Column({ type: 'integer', default: 0 })
  applied: number;

  @Column({ type: 'integer', default: 0 })
  skipped: number;

  @Column({ type: 'integer', default: 0 })
  failed: number;

  @Column({ name: 'cancel_requested', type: 'boolean', default: false })
  cancelRequested: boolean;

  @Column({ type: 'text', nullable: true })
  error: string | null;

  @Index('idx_source_migration_job_started_at')
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

@Entity('source_migration_item')
export class SourceMigrationItemEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'job_id', type: 'uuid' })
  jobId: string;

  @Column({ name: 'manga_id', type: 'uuid' })
  mangaId: string;

  @Column({ type: 'text' })
  title: string;

  @Column({ name: 'from_source_id', type: 'text' })
  fromSourceId: string;

  @Column({ name: 'from_manga_url', type: 'text' })
  fromMangaUrl: string;

  @Column({ name: 'to_source_id', type: 'text', nullable: true })
  toSourceId: string | null;

  @Column({ name: 'to_manga_url', type: 'text', nullable: true })
  toMangaUrl: string | null;

  @Column({ name: 'to_title', type: 'text', nullable: true })
  toTitle: string | null;

  @Column({ name: 'to_thumbnail_url', type: 'text', nullable: true })
  toThumbnailUrl: string | null;

  /**
   * Match score in [0, 1]. Postgres hands `numeric` back as a string, so this
   * is typed as one and converted at the DTO boundary rather than pretending
   * to be a number that TypeORM would silently mistype.
   */
  @Column({ type: 'numeric', precision: 4, scale: 3, nullable: true })
  score: string | null;

  @Column({ type: 'text', nullable: true })
  method: MigrationMethod | null;

  @Column({ type: 'text', default: 'pending' })
  state: MigrationItemState;

  @Column({ type: 'jsonb', default: () => `'[]'::jsonb` })
  candidates: StoredCandidate[];

  @Column({ type: 'jsonb', default: () => `'[]'::jsonb` })
  reasons: string[];

  /** The title already in the vault that blocks this one — `conflict` state. */
  @Column({ name: 'conflict_manga_id', type: 'uuid', nullable: true })
  conflictMangaId: string | null;

  @Column({ type: 'text', nullable: true })
  error: string | null;

  @Column({
    name: 'applied_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  appliedAt: number | null;

  @Column({
    name: 'undone_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  undoneAt: number | null;

  @Column({ type: 'jsonb', nullable: true })
  snapshot: MigrationSnapshot | null;
}
