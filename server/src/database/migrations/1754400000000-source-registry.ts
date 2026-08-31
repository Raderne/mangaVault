import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * The source registry — what a `manga.source_id` actually *is*.
 *
 * Every vault row is keyed on `(source_id, manga_url)`, but until now nothing
 * described the source half of that pair. `manga.source_name` holds whatever
 * the backup's `backupSources` list happened to say (blank for every legacy
 * JSON import, since those carry no source list at all), and `known_source`
 * existed with `base_url` / `fetch_hint` columns that no code ever wrote.
 *
 * Mihon answers the same question from an *extension repository index*: a
 * static JSON document listing every published extension and the sources it
 * provides. That index is plain metadata — no code execution — so we can ingest
 * it here even though a Node server can never run an Android extension. What it
 * buys us is exactly what the vault was missing: a real name, language, icon
 * and home page per source, and — because a source that has been withdrawn
 * simply stops appearing — a reliable signal that a source is *gone*.
 *
 * Three tables, one extended:
 *
 *   * `extension_repo` — a repository we sync from. Keyed by `base_url` because
 *     that is the identity the user pastes; seeded on boot from
 *     `curated-repos.ts` rather than here, so adding a repo is a code edit, not
 *     a migration (same call as `backup_app`).
 *   * `extension` — one installable extension per repo. We never install these;
 *     the row exists so the app can browse the index and hand the user an APK
 *     link, and so an obsolete extension can be named.
 *   * `known_source` — **extended, not replaced**. It already had the right
 *     primary key, and `CoverService` already reads `fetch_hint` off it. The
 *     new columns hang the registry and the health verdict on the row that was
 *     already there.
 *   * `source_health_job` — a durable run of the health checker, modelled on
 *     `cover_job` down to the one-run-at-a-time partial unique index.
 *
 * Deliberately **no foreign key** from `manga.source_id` to `known_source`. A
 * vault row must survive its source being unknown, delisted or never indexed at
 * all — that is the whole point of an archive, and it is the same reasoning
 * that kept `import_record.source_app` unconstrained.
 */
export class SourceRegistry1754400000000 implements MigrationInterface {
  name = 'SourceRegistry1754400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE extension_repo (
        id             UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        base_url       TEXT    NOT NULL UNIQUE,
        name           TEXT    NOT NULL,
        short_name     TEXT,
        website        TEXT    NOT NULL DEFAULT '',
        signing_key_fingerprint TEXT,
        index_url      TEXT,
        index_etag     TEXT,
        index_format   TEXT,
        enabled        BOOLEAN NOT NULL DEFAULT TRUE,
        curated        BOOLEAN NOT NULL DEFAULT FALSE,
        extension_count INTEGER NOT NULL DEFAULT 0,
        source_count   INTEGER NOT NULL DEFAULT 0,
        last_synced_at BIGINT,
        last_error     TEXT,
        created_at     BIGINT  NOT NULL
      )
    `);

    await queryRunner.query(`
      CREATE TABLE extension (
        repo_id         UUID    NOT NULL REFERENCES extension_repo(id) ON DELETE CASCADE,
        package_name    TEXT    NOT NULL,
        name            TEXT    NOT NULL,
        version_name    TEXT    NOT NULL DEFAULT '',
        version_code    INTEGER NOT NULL DEFAULT 0,
        extension_lib   TEXT    NOT NULL DEFAULT '',
        content_warning TEXT    NOT NULL DEFAULT 'safe',
        apk_url         TEXT    NOT NULL DEFAULT '',
        icon_url        TEXT    NOT NULL DEFAULT '',
        source_count    INTEGER NOT NULL DEFAULT 0,
        last_seen_at    BIGINT  NOT NULL,
        PRIMARY KEY (repo_id, package_name)
      )
    `);

    // The extensions browser lists alphabetically and filters by name; 1,380
    // rows per repo is small, but this keeps the paged query off a sort.
    await queryRunner.query(
      `CREATE INDEX idx_extension_name ON extension (lower(name))`,
    );

    // --- known_source: registry + health ---
    //
    // `registry_state` is the delisting signal and the reason the whole feature
    // works: 'listed' means a repo published this id in the last sync,
    // 'delisted' means it used to and no longer does (the extension was
    // withdrawn), and 'unknown' means no repo has ever listed it — a fork's
    // private source, or a source that predates every repo we sync.
    await queryRunner.query(`
      ALTER TABLE known_source
        ADD COLUMN repo_id            UUID REFERENCES extension_repo(id) ON DELETE SET NULL,
        ADD COLUMN package_name       TEXT,
        ADD COLUMN lang               TEXT NOT NULL DEFAULT '',
        ADD COLUMN mirror_urls        JSONB,
        ADD COLUMN icon_url           TEXT,
        ADD COLUMN content_warning    TEXT,
        ADD COLUMN registry_state     TEXT NOT NULL DEFAULT 'unknown',
        ADD COLUMN first_listed_at    BIGINT,
        ADD COLUMN last_listed_at     BIGINT,
        ADD COLUMN health             TEXT NOT NULL DEFAULT 'unknown',
        ADD COLUMN health_http_status INTEGER,
        ADD COLUMN health_latency_ms  INTEGER,
        ADD COLUMN health_checked_at  BIGINT,
        ADD COLUMN health_note        TEXT
    `);

    // The sources screen ranks dead sources first, so it reads by state.
    await queryRunner.query(
      `CREATE INDEX idx_known_source_state ON known_source (registry_state, health)`,
    );

    await queryRunner.query(`
      CREATE TABLE source_health_job (
        id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        status           TEXT    NOT NULL DEFAULT 'running',
        trigger          TEXT    NOT NULL DEFAULT 'manual',
        total            INTEGER NOT NULL DEFAULT 0,
        done             INTEGER NOT NULL DEFAULT 0,
        ok               INTEGER NOT NULL DEFAULT 0,
        degraded         INTEGER NOT NULL DEFAULT 0,
        unhealthy        INTEGER NOT NULL DEFAULT 0,
        cancel_requested BOOLEAN NOT NULL DEFAULT FALSE,
        error            TEXT,
        started_at       BIGINT  NOT NULL,
        updated_at       BIGINT  NOT NULL,
        finished_at      BIGINT
      )
    `);
    await queryRunner.query(
      `CREATE INDEX idx_source_health_job_started_at ON source_health_job (started_at DESC)`,
    );
    // One run at a time, enforced by the database — same trick as
    // `uq_cover_job_running`: every running row shares a `status` value, so a
    // unique index over it admits exactly one.
    await queryRunner.query(`
      CREATE UNIQUE INDEX uq_source_health_job_running
        ON source_health_job (status) WHERE status = 'running'
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS uq_source_health_job_running`,
    );
    await queryRunner.query(
      `DROP INDEX IF EXISTS idx_source_health_job_started_at`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS source_health_job`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_known_source_state`);
    await queryRunner.query(`
      ALTER TABLE known_source
        DROP COLUMN IF EXISTS health_note,
        DROP COLUMN IF EXISTS health_checked_at,
        DROP COLUMN IF EXISTS health_latency_ms,
        DROP COLUMN IF EXISTS health_http_status,
        DROP COLUMN IF EXISTS health,
        DROP COLUMN IF EXISTS last_listed_at,
        DROP COLUMN IF EXISTS first_listed_at,
        DROP COLUMN IF EXISTS registry_state,
        DROP COLUMN IF EXISTS content_warning,
        DROP COLUMN IF EXISTS icon_url,
        DROP COLUMN IF EXISTS mirror_urls,
        DROP COLUMN IF EXISTS lang,
        DROP COLUMN IF EXISTS package_name,
        DROP COLUMN IF EXISTS repo_id
    `);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_extension_name`);
    await queryRunner.query(`DROP TABLE IF EXISTS extension`);
    await queryRunner.query(`DROP TABLE IF EXISTS extension_repo`);
  }
}
