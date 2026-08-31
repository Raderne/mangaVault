import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Source migration — moving a title off a source that no longer works.
 *
 * Two tables because the operation is genuinely two-phase, and for the same
 * reason Mihon splits it: **planning is slow, network-bound and wrong
 * sometimes; applying is fast, local and must be exactly right.** Planning
 * searches each target source, scores what it finds and writes a candidate per
 * title. The user then reviews, overrides and deselects. Only then does apply
 * run, and by that point it is pure database work with nothing left to fail on.
 *
 * `source_migration_item.snapshot` is what makes the whole thing safe to offer:
 * it holds the title's identity before the rewrite, so a migration the user
 * regrets is one request away from being undone. The same reasoning as
 * `deleted_manga.snapshot` — an archive may not lose things, so every
 * destructive-looking operation carries its own inverse.
 *
 * Note what is *not* here: a second `manga` row. Mihon migrates by pointing the
 * library at a different row and unfavouriting the old one, because in Mihon a
 * row belongs to a source. Here the row is the archived title itself — it owns
 * the chapters, the read progress, the categories, the import history and the
 * cover file — so migrating is an update of its `(source_id, manga_url)`
 * identity, and everything else follows untouched. That is also why read
 * progress survives migration here and does not in Mihon.
 */
export class SourceMigrations1754500000000 implements MigrationInterface {
  name = 'SourceMigrations1754500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE source_migration_job (
        id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        status           TEXT    NOT NULL DEFAULT 'planning',
        from_source_id   TEXT    NOT NULL,
        to_source_ids    JSONB   NOT NULL DEFAULT '[]'::jsonb,
        total            INTEGER NOT NULL DEFAULT 0,
        planned          INTEGER NOT NULL DEFAULT 0,
        matched          INTEGER NOT NULL DEFAULT 0,
        applied          INTEGER NOT NULL DEFAULT 0,
        skipped          INTEGER NOT NULL DEFAULT 0,
        failed           INTEGER NOT NULL DEFAULT 0,
        cancel_requested BOOLEAN NOT NULL DEFAULT FALSE,
        error            TEXT,
        started_at       BIGINT  NOT NULL,
        updated_at       BIGINT  NOT NULL,
        finished_at      BIGINT
      )
    `);
    await queryRunner.query(
      `CREATE INDEX idx_source_migration_job_started_at
         ON source_migration_job (started_at DESC)`,
    );
    // One run at a time across both working states. Indexing a constant with a
    // predicate over the two of them admits exactly one row that is either
    // planning or applying — while any number of `ready` plans may sit waiting
    // for the user to review them.
    await queryRunner.query(`
      CREATE UNIQUE INDEX uq_source_migration_job_active
        ON source_migration_job ((TRUE))
     WHERE status IN ('planning', 'applying')
    `);

    await queryRunner.query(`
      CREATE TABLE source_migration_item (
        id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        job_id           UUID    NOT NULL REFERENCES source_migration_job(id) ON DELETE CASCADE,
        manga_id         UUID    NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
        title            TEXT    NOT NULL,
        from_source_id   TEXT    NOT NULL,
        from_manga_url   TEXT    NOT NULL,
        to_source_id     TEXT,
        to_manga_url     TEXT,
        to_title         TEXT,
        to_thumbnail_url TEXT,
        -- 0.000..1.000 from the matcher; null for a url the user pasted.
        score            NUMERIC(4,3),
        method           TEXT,
        state            TEXT    NOT NULL DEFAULT 'pending',
        -- Ranked alternatives, so the override sheet needs no second search.
        candidates       JSONB   NOT NULL DEFAULT '[]'::jsonb,
        reasons          JSONB   NOT NULL DEFAULT '[]'::jsonb,
        conflict_manga_id UUID,
        error            TEXT,
        applied_at       BIGINT,
        undone_at        BIGINT,
        snapshot         JSONB
      )
    `);
    await queryRunner.query(
      `CREATE INDEX idx_source_migration_item_job
         ON source_migration_item (job_id, state)`,
    );
    // A title appears once per plan.
    await queryRunner.query(
      `CREATE UNIQUE INDEX uq_source_migration_item
         ON source_migration_item (job_id, manga_id)`,
    );
    // Undo reads the most recent applied item for a title.
    await queryRunner.query(
      `CREATE INDEX idx_source_migration_item_manga
         ON source_migration_item (manga_id, applied_at DESC)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_source_migration_item_manga`,
    );
    await queryRunner.query(`DROP INDEX IF EXISTS uq_source_migration_item`);
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_source_migration_item_job`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS source_migration_item`);
    await queryRunner.query(
      `DROP INDEX IF EXISTS uq_source_migration_job_active`,
    );
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_source_migration_job_started_at`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS source_migration_job`);
  }
}
