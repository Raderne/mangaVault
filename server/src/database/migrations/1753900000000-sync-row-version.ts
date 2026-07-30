import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Delta-sync foundation for the on-device library mirror.
 *
 * Why a dedicated `row_version` instead of reusing `manga.updated_at`:
 * `updated_at` carries the *backup's* `lastModifiedAt` (see merge.engine.ts —
 * `max(existing.updatedAt, incoming.lastModifiedAt)`), so it moves backwards
 * relative to write order, and cover archiving updates `cover_state` without
 * touching it at all. Neither makes a usable cursor.
 *
 * `row_version` is stamped by the database itself from one global sequence, so
 * every write path — present and future — produces a correct delta with no
 * cooperation from the calling code.
 *
 * Child rows matter too: the mirror is denormalized (it stores chapter/unread
 * counts per title), so a chapter or category change must invalidate its parent.
 * Statement-level triggers with transition tables bump the parent cheaply — the
 * import already issues one upsert statement per title.
 */
export class SyncRowVersion1753900000000 implements MigrationInterface {
  name = 'SyncRowVersion1753900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE SEQUENCE mv_row_version_seq`);

    // ---- manga.row_version ------------------------------------------------
    await queryRunner.query(
      `ALTER TABLE manga ADD COLUMN row_version BIGINT NOT NULL DEFAULT 0`,
    );
    // Backfill so existing rows sync exactly once rather than looking unchanged.
    await queryRunner.query(
      `UPDATE manga SET row_version = nextval('mv_row_version_seq')`,
    );
    await queryRunner.query(
      `CREATE INDEX idx_manga_row_version ON manga(row_version)`,
    );

    await queryRunner.query(`
      CREATE FUNCTION mv_stamp_manga() RETURNS trigger AS $$
      BEGIN
        NEW.row_version := nextval('mv_row_version_seq');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql
    `);

    await queryRunner.query(`
      CREATE TRIGGER trg_manga_stamp
        BEFORE INSERT OR UPDATE ON manga
        FOR EACH ROW EXECUTE FUNCTION mv_stamp_manga()
    `);

    // ---- tombstones -------------------------------------------------------
    await queryRunner.query(`
      CREATE TABLE sync_tombstone (
        entity      TEXT   NOT NULL,
        entity_id   UUID   NOT NULL,
        row_version BIGINT NOT NULL,
        deleted_at  BIGINT NOT NULL,
        PRIMARY KEY (entity, entity_id)
      )
    `);
    await queryRunner.query(
      `CREATE INDEX idx_tombstone_version ON sync_tombstone(row_version)`,
    );

    // Nothing deletes manga today (archival semantics); this is the seam that
    // makes the later delete feature sync with no protocol change.
    await queryRunner.query(`
      CREATE FUNCTION mv_tombstone_manga() RETURNS trigger AS $$
      BEGIN
        INSERT INTO sync_tombstone (entity, entity_id, row_version, deleted_at)
        VALUES ('manga', OLD.id, nextval('mv_row_version_seq'),
                (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT)
        ON CONFLICT (entity, entity_id) DO UPDATE
          SET row_version = EXCLUDED.row_version,
              deleted_at  = EXCLUDED.deleted_at;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql
    `);
    await queryRunner.query(`
      CREATE TRIGGER trg_manga_tombstone
        AFTER DELETE ON manga
        FOR EACH ROW EXECUTE FUNCTION mv_tombstone_manga()
    `);

    // A re-created id must not stay tombstoned.
    await queryRunner.query(`
      CREATE FUNCTION mv_untombstone_manga() RETURNS trigger AS $$
      BEGIN
        DELETE FROM sync_tombstone WHERE entity = 'manga' AND entity_id = NEW.id;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql
    `);
    await queryRunner.query(`
      CREATE TRIGGER trg_manga_untombstone
        AFTER INSERT ON manga
        FOR EACH ROW EXECUTE FUNCTION mv_untombstone_manga()
    `);

    // ---- child-change propagation ----------------------------------------
    // The UPDATE below re-fires trg_manga_stamp, which assigns the real version;
    // `row_version = row_version` just makes it a valid no-op update. No
    // recursion: mv_stamp_manga only mutates NEW, it issues no statements.
    await queryRunner.query(`
      CREATE FUNCTION mv_touch_parents_new() RETURNS trigger AS $$
      BEGIN
        UPDATE manga m SET row_version = m.row_version
          FROM (SELECT DISTINCT manga_id FROM mv_new_rows) t
         WHERE m.id = t.manga_id;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql
    `);
    await queryRunner.query(`
      CREATE FUNCTION mv_touch_parents_old() RETURNS trigger AS $$
      BEGIN
        UPDATE manga m SET row_version = m.row_version
          FROM (SELECT DISTINCT manga_id FROM mv_old_rows) t
         WHERE m.id = t.manga_id;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql
    `);

    // Postgres allows transition tables on a single event per trigger, so each
    // child table needs three.
    const childTables = [
      'chapter',
      'tracking',
      'manga_category',
      'manga_import',
    ];
    for (const table of childTables) {
      await queryRunner.query(`
        CREATE TRIGGER trg_${table}_touch_ins
          AFTER INSERT ON ${table}
          REFERENCING NEW TABLE AS mv_new_rows
          FOR EACH STATEMENT EXECUTE FUNCTION mv_touch_parents_new()
      `);
      await queryRunner.query(`
        CREATE TRIGGER trg_${table}_touch_upd
          AFTER UPDATE ON ${table}
          REFERENCING NEW TABLE AS mv_new_rows
          FOR EACH STATEMENT EXECUTE FUNCTION mv_touch_parents_new()
      `);
      // On DELETE the parent may itself be gone (ON DELETE CASCADE); the UPDATE
      // then simply matches nothing, and the manga tombstone covers that case.
      await queryRunner.query(`
        CREATE TRIGGER trg_${table}_touch_del
          AFTER DELETE ON ${table}
          REFERENCING OLD TABLE AS mv_old_rows
          FOR EACH STATEMENT EXECUTE FUNCTION mv_touch_parents_old()
      `);
    }

    // ---- server identity --------------------------------------------------
    // If Postgres is restored from a dump, row_version rewinds and a client's
    // stored cursor would silently skip rows. A changed epoch forces a full
    // resync instead.
    await queryRunner.query(`
      CREATE TABLE sync_state (
        id           BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
        server_epoch UUID NOT NULL DEFAULT gen_random_uuid()
      )
    `);
    await queryRunner.query(`INSERT INTO sync_state DEFAULT VALUES`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    const childTables = [
      'chapter',
      'tracking',
      'manga_category',
      'manga_import',
    ];
    for (const table of childTables) {
      await queryRunner.query(
        `DROP TRIGGER IF EXISTS trg_${table}_touch_ins ON ${table}`,
      );
      await queryRunner.query(
        `DROP TRIGGER IF EXISTS trg_${table}_touch_upd ON ${table}`,
      );
      await queryRunner.query(
        `DROP TRIGGER IF EXISTS trg_${table}_touch_del ON ${table}`,
      );
    }
    await queryRunner.query(
      `DROP TRIGGER IF EXISTS trg_manga_untombstone ON manga`,
    );
    await queryRunner.query(
      `DROP TRIGGER IF EXISTS trg_manga_tombstone ON manga`,
    );
    await queryRunner.query(`DROP TRIGGER IF EXISTS trg_manga_stamp ON manga`);

    await queryRunner.query(`DROP FUNCTION IF EXISTS mv_touch_parents_old()`);
    await queryRunner.query(`DROP FUNCTION IF EXISTS mv_touch_parents_new()`);
    await queryRunner.query(`DROP FUNCTION IF EXISTS mv_untombstone_manga()`);
    await queryRunner.query(`DROP FUNCTION IF EXISTS mv_tombstone_manga()`);
    await queryRunner.query(`DROP FUNCTION IF EXISTS mv_stamp_manga()`);

    await queryRunner.query(`DROP TABLE IF EXISTS sync_state`);
    await queryRunner.query(`DROP TABLE IF EXISTS sync_tombstone`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_manga_row_version`);
    await queryRunner.query(
      `ALTER TABLE manga DROP COLUMN IF EXISTS row_version`,
    );
    await queryRunner.query(`DROP SEQUENCE IF EXISTS mv_row_version_seq`);
  }
}
