import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * The deletion registry — a recycle bin that also acts as an import block list.
 *
 * Deleting a title used to be undone by the next backup import: the merge
 * engine keys on `(source_id, manga_url)`, finds nothing, and creates the title
 * again. That makes deletion meaningless in an archive that is fed by repeated
 * backups of the same library.
 *
 * So a delete now records the title here. `ImportService` skips any incoming
 * title whose key is registered, and the user restores from this list
 * explicitly. `snapshot` holds the whole record (scalars, chapters, tracking,
 * category names, contributing import ids) so a restore returns the title as it
 * was — including read progress that may be newer than any backup on disk.
 *
 * `last_seen_at` / `seen_count` are bumped every time an import offers the
 * title again, which is what tells the user "this backup wanted to add it
 * back" when they decide what to restore.
 */
export class DeletedManga1754000000000 implements MigrationInterface {
  name = 'DeletedManga1754000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE deleted_manga (
        id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        source_id     TEXT    NOT NULL,
        manga_url     TEXT    NOT NULL,
        source_name   TEXT    NOT NULL DEFAULT '',
        title         TEXT    NOT NULL,
        thumbnail_url TEXT,
        chapter_count INTEGER NOT NULL DEFAULT 0,
        read_count    INTEGER NOT NULL DEFAULT 0,
        deleted_at    BIGINT  NOT NULL,
        last_seen_at  BIGINT,
        seen_count    INTEGER NOT NULL DEFAULT 0,
        snapshot      JSONB   NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT uq_deleted_manga_key UNIQUE (source_id, manga_url)
      )
    `);
    // The list is read newest-first, and looked up by key on every import.
    await queryRunner.query(
      `CREATE INDEX idx_deleted_manga_deleted_at ON deleted_manga (deleted_at DESC)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_deleted_manga_deleted_at`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS deleted_manga`);
  }
}
