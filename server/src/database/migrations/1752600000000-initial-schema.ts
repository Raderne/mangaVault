import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Initial schema, mirroring docs/phase-1-data-structures.md §3.2.
 * Epoch timestamps are BIGINT millis; int64 identifiers are TEXT.
 */
export class InitialSchema1752600000000 implements MigrationInterface {
  name = 'InitialSchema1752600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pg_trgm`);

    await queryRunner.query(`
      CREATE TABLE manga (
        id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        source_id     TEXT NOT NULL,
        manga_url     TEXT NOT NULL,
        source_name   TEXT NOT NULL DEFAULT '',
        title         TEXT NOT NULL,
        author        TEXT,
        artist        TEXT,
        description   TEXT,
        genres        JSONB NOT NULL DEFAULT '[]',
        status        TEXT NOT NULL DEFAULT 'unknown',
        thumbnail_url TEXT,
        cover_path    TEXT,
        cover_state   TEXT NOT NULL DEFAULT 'none',
        notes         TEXT NOT NULL DEFAULT '',
        favorite      BOOLEAN NOT NULL DEFAULT TRUE,
        date_added    BIGINT NOT NULL DEFAULT 0,
        updated_at    BIGINT NOT NULL,
        search_tsv    TSVECTOR GENERATED ALWAYS AS (
                        to_tsvector('simple',
                          coalesce(title,'') || ' ' || coalesce(author,'') || ' ' ||
                          coalesce(artist,''))
                      ) STORED,
        CONSTRAINT uq_manga_source UNIQUE (source_id, manga_url)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE chapter (
        id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        manga_id       UUID NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
        url            TEXT NOT NULL,
        name           TEXT NOT NULL,
        chapter_number DOUBLE PRECISION NOT NULL DEFAULT -1,
        scanlator      TEXT,
        read           BOOLEAN NOT NULL DEFAULT FALSE,
        bookmark       BOOLEAN NOT NULL DEFAULT FALSE,
        last_page_read BIGINT NOT NULL DEFAULT 0,
        date_upload    BIGINT NOT NULL DEFAULT 0,
        date_fetch     BIGINT NOT NULL DEFAULT 0,
        source_order   BIGINT NOT NULL DEFAULT 0,
        last_read_at   BIGINT,
        read_duration  BIGINT NOT NULL DEFAULT 0,
        CONSTRAINT uq_chapter_url UNIQUE (manga_id, url)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE category (
        id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name  TEXT NOT NULL UNIQUE,
        sort  INTEGER NOT NULL DEFAULT 0
      )
    `);

    await queryRunner.query(`
      CREATE TABLE manga_category (
        manga_id    UUID NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
        category_id UUID NOT NULL REFERENCES category(id) ON DELETE CASCADE,
        PRIMARY KEY (manga_id, category_id)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE tracking (
        id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        manga_id  UUID NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
        tracker   TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        tracking_url TEXT NOT NULL DEFAULT '',
        title     TEXT NOT NULL DEFAULT '',
        last_chapter_read DOUBLE PRECISION NOT NULL DEFAULT 0,
        total_chapters    INTEGER NOT NULL DEFAULT 0,
        score     DOUBLE PRECISION NOT NULL DEFAULT 0,
        status    INTEGER NOT NULL DEFAULT 0,
        started_at  BIGINT,
        finished_at BIGINT,
        CONSTRAINT uq_tracking_tracker UNIQUE (manga_id, tracker)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE import_record (
        id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        file_name   TEXT NOT NULL,
        file_size   BIGINT NOT NULL,
        sha256      TEXT NOT NULL UNIQUE,
        source_app  TEXT NOT NULL DEFAULT '',
        container   TEXT NOT NULL,
        imported_at BIGINT NOT NULL,
        stats       JSONB NOT NULL DEFAULT '{}'
      )
    `);

    await queryRunner.query(`
      CREATE TABLE manga_import (
        manga_id  UUID NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
        import_id UUID NOT NULL REFERENCES import_record(id) ON DELETE CASCADE,
        PRIMARY KEY (manga_id, import_id)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE known_source (
        source_id  TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        base_url   TEXT,
        fetch_hint JSONB
      )
    `);

    await queryRunner.query(
      `CREATE INDEX idx_manga_search ON manga USING GIN (search_tsv)`,
    );
    await queryRunner.query(
      `CREATE INDEX idx_manga_trgm ON manga USING GIN (title gin_trgm_ops)`,
    );
    await queryRunner.query(`CREATE INDEX idx_manga_status ON manga(status)`);
    await queryRunner.query(
      `CREATE INDEX idx_chapter_manga ON chapter(manga_id)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS manga_import`);
    await queryRunner.query(`DROP TABLE IF EXISTS manga_category`);
    await queryRunner.query(`DROP TABLE IF EXISTS tracking`);
    await queryRunner.query(`DROP TABLE IF EXISTS chapter`);
    await queryRunner.query(`DROP TABLE IF EXISTS import_record`);
    await queryRunner.query(`DROP TABLE IF EXISTS known_source`);
    await queryRunner.query(`DROP TABLE IF EXISTS category`);
    await queryRunner.query(`DROP TABLE IF EXISTS manga`);
  }
}
