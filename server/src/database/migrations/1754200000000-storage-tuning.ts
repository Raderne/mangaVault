import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Storage tuning, from measurements taken on the live 2,000-title vault.
 *
 * **1. `fillfactor` so re-imports can update HOT.** `chapter` was carrying
 * 16.3% dead tuples and only **0.7%** of its updates were HOT (839 of 125,042).
 * With the default fillfactor of 100 a page has no free space, so an `UPDATE`
 * must place the new row version on another page — which means writing a new
 * entry into *every* index on the table, including the 28 MB `uq_chapter_url`.
 * Leaving free space per page lets the merge engine's repeated updates stay on
 * the page (HOT: no index writes, and the dead space is reused in place).
 * `chapter` is update-heavy (every re-import touches most rows), `manga` less
 * so but still hit by cover-state writes.
 *
 * This only affects pages written *after* it — existing bloat needs a
 * `VACUUM (ANALYZE)`, or `VACUUM FULL` + `REINDEX` to actually give the disk
 * back. Both live in `npm run db:maintenance`, deliberately **not** here:
 * TypeORM runs migrations inside a transaction and `VACUUM` cannot run in one,
 * and rewriting a 95 MB table on boot is not something a deploy should do
 * silently.
 *
 * **2. Dropping two dead indexes.** `idx_manga_search` (GIN on `search_tsv`)
 * had **0** scans and `idx_manga_trgm` (GIN trigram on `title`) had **3**, for
 * 3.4 MB. They only back `GET /library?text=`, which no client has called since
 * the app started reading its on-device SQLite mirror; at 2,000 rows the
 * sequential scan is ~1 ms. The generated `search_tsv` column and the query
 * itself stay, so the endpoint and its e2e are unchanged — only the index
 * maintenance on every write goes away. `down()` puts both back.
 */
export class StorageTuning1754200000000 implements MigrationInterface {
  name = 'StorageTuning1754200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE chapter SET (fillfactor = 85)`);
    await queryRunner.query(`ALTER TABLE manga SET (fillfactor = 90)`);

    await queryRunner.query(`DROP INDEX IF EXISTS idx_manga_search`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_manga_trgm`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE INDEX idx_manga_search ON manga USING GIN (search_tsv)`,
    );
    await queryRunner.query(
      `CREATE INDEX idx_manga_trgm ON manga USING GIN (title gin_trgm_ops)`,
    );

    await queryRunner.query(`ALTER TABLE manga RESET (fillfactor)`);
    await queryRunner.query(`ALTER TABLE chapter RESET (fillfactor)`);
  }
}
