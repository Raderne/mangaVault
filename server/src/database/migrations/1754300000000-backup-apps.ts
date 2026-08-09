import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * The backup-app registry — which reading app a backup came from.
 *
 * `import_record.source_app` has always held the application id parsed from the
 * filename (`app.mihon`, `app.komikku`, …), but nothing described those ids: no
 * display name, and no list to offer when a filename carries no prefix. This
 * table is that list. It is seeded on boot from `curated-apps.ts` rather than
 * here, so correcting a display name or adding a fork is a code edit, not a
 * migration; rows the user adds themselves carry `curated = false`.
 *
 * Deliberately **no foreign key** from `import_record.source_app`: an import
 * must survive its app being removed from the registry, and `''` (unknown) has
 * to stay a legal value.
 *
 * The two indexes serve the new "filter the library by app" query, which walks
 * `manga → manga_import → import_record`. `manga_import` only had its composite
 * primary key `(manga_id, import_id)`, so the reverse lookup had no index at
 * all.
 */
export class BackupApps1754300000000 implements MigrationInterface {
  name = 'BackupApps1754300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE backup_app (
        id           TEXT    PRIMARY KEY,
        display_name TEXT    NOT NULL,
        accent       TEXT,
        curated      BOOLEAN NOT NULL DEFAULT FALSE,
        created_at   BIGINT  NOT NULL
      )
    `);
    await queryRunner.query(
      `CREATE INDEX idx_import_record_source_app ON import_record (source_app)`,
    );
    await queryRunner.query(
      `CREATE INDEX idx_manga_import_import ON manga_import (import_id)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS idx_manga_import_import`);
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_import_record_source_app`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS backup_app`);
  }
}
