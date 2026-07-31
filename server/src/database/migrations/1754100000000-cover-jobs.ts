import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Durable cover-archiving jobs.
 *
 * Bulk cover archiving was already off the request path, but its progress lived
 * only in a `Map` in the API process. A restart mid-run left the client polling
 * a job id that no longer existed, with no record that a run had ever happened
 * and no way to stop one that was hammering a slow source. For a library of a
 * few thousand titles that run is minutes-to-hours of work — long enough that
 * surviving a deploy matters.
 *
 * So a run is a row. `status` is the lifecycle (`running` → `finished` /
 * `cancelled` / `failed`, or `interrupted` when the process died under it), and
 * the counters are flushed onto it periodically rather than per cover.
 *
 * `manga.cover_failed_at` exists for resume: a resumed run re-derives its
 * candidates from `cover_state`, which would otherwise re-attempt every cover
 * that had already failed in the interrupted run (many of them permanently —
 * see the Cloudflare ceiling in the wiki). Stamping the failure time lets the
 * resume exclude "already tried during this run" without persisting a row per
 * candidate.
 */
export class CoverJobs1754100000000 implements MigrationInterface {
  name = 'CoverJobs1754100000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE cover_job (
        id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        status           TEXT    NOT NULL DEFAULT 'running',
        trigger          TEXT    NOT NULL DEFAULT 'manual',
        total            INTEGER NOT NULL DEFAULT 0,
        done             INTEGER NOT NULL DEFAULT 0,
        archived         INTEGER NOT NULL DEFAULT 0,
        failed           INTEGER NOT NULL DEFAULT 0,
        skipped          INTEGER NOT NULL DEFAULT 0,
        retry_failed     BOOLEAN NOT NULL DEFAULT TRUE,
        cancel_requested BOOLEAN NOT NULL DEFAULT FALSE,
        error            TEXT,
        started_at       BIGINT  NOT NULL,
        updated_at       BIGINT  NOT NULL,
        finished_at      BIGINT
      )
    `);

    // History is read newest-first.
    await queryRunner.query(
      `CREATE INDEX idx_cover_job_started_at ON cover_job (started_at DESC)`,
    );

    // One run at a time, enforced by the database rather than only by an
    // in-process flag: every running row has the same `status` value, so a
    // unique index over it admits exactly one. A concurrent second trigger then
    // fails loudly instead of silently double-fetching every cover.
    await queryRunner.query(`
      CREATE UNIQUE INDEX uq_cover_job_running
        ON cover_job (status) WHERE status = 'running'
    `);

    await queryRunner.query(
      `ALTER TABLE manga ADD COLUMN cover_failed_at BIGINT`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE manga DROP COLUMN IF EXISTS cover_failed_at`,
    );
    await queryRunner.query(`DROP INDEX IF EXISTS uq_cover_job_running`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_cover_job_started_at`);
    await queryRunner.query(`DROP TABLE IF EXISTS cover_job`);
  }
}
