# Database (Postgres schema)

Created: 2026-07-30

Related: [[index]] · [[backend]] · [[migration]] · [[library-api]] · [[import-pipeline]] ·
[[dashboard-stats]] · [[local-library-mirror]] · [[deleted-titles]] · [[cover-fetching]]

Postgres 16 (alpine, Docker), published on host port **5433** (5432 is taken by `expensy-postgres`
from another project; in-container networking still uses 5432). The schema is **migration-owned** —
`synchronize: false` everywhere, `migrationsRun: true` on boot. See [[migration]] for the workflow
and its two hard rules: never enable `synchronize`, never edit an applied migration.

## Migrations

| Migration | What it adds |
|---|---|
| `1752600000000-initial-schema` | The 8 core tables, `pg_trgm`, the generated `search_tsv` column, GIN indexes |
| `1753900000000-sync-row-version` | `manga.row_version` + stamping triggers, `sync_tombstone`, `sync_state` — see [[local-library-mirror]] |
| `1754000000000-deleted-manga` | `deleted_manga` — the deletion registry / import block list, see [[deleted-titles]] |
| `1754100000000-cover-jobs` | `cover_job` + `manga.cover_failed_at` — durable cover-archiving runs, see [[cover-fetching]] |

Both are **hand-written SQL**, because they need things TypeORM cannot express: extensions, a
`GENERATED ALWAYS AS … STORED` tsvector, GIN indexes, PL/pgSQL functions and statement-level triggers
with transition tables.

## Tables

```
manga ──┬─< chapter            (uq: manga_id + url)
        ├─< tracking           (uq: manga_id + tracker)
        ├─< manga_category >── category      (uq: category.name)
        └─< manga_import   >── import_record (uq: sha256)
known_source        (PK source_id TEXT — not a uuid)
sync_tombstone      (PK entity + entity_id)
sync_state          (singleton: server_epoch)
deleted_manga       (uq: source_id + manga_url)
cover_job           (partial uq: status WHERE status = 'running')
```

- `manga` is keyed by uuid but its **natural key is `UNIQUE (source_id, manga_url)`** — the Mihon
  ecosystem's identity for a title, and the dedup key the import merge engine matches on.
- Every child FK is `ON DELETE CASCADE`. Nothing in application code deletes manga (archival
  semantics: [[import-pipeline]]), so cascades are latent until the delete feature lands.
- **int64 discipline:** Mihon source ids and tracker media ids are **TEXT** columns holding decimal
  strings — they exceed `Number.MAX_SAFE_INTEGER` and must never be parsed. Epoch-millis columns are
  BIGINT and go through the `bigIntToNumber` transformer (safe: < 2^53). Raw `dataSource.query`
  returns every BIGINT as a **string**, so mappers convert explicitly.

## Columns entities deliberately do NOT map

Two columns exist in SQL but are absent from `MangaEntity`, on purpose. TypeORM must never write
them, and `migration:generate` may propose **dropping** them — always review a generated diff.

| Column | Why unmapped |
|---|---|
| `search_tsv` | `GENERATED ALWAYS AS (to_tsvector('simple', title ‖ author ‖ artist)) STORED`; Postgres owns it |
| `row_version` | Stamped by `trg_manga_stamp` on every write; the sync module reads it via raw SQL |

## Indexes

| Index | Purpose |
|---|---|
| `idx_manga_search` GIN(`search_tsv`) | Word search for `GET /library?text=` |
| `idx_manga_trgm` GIN(`title gin_trgm_ops`) | Substring / typo-tolerant title matching |
| `idx_manga_status` | The status filter chips |
| `idx_chapter_manga` | The grouped chapter aggregate every list query joins |
| `idx_manga_row_version` | Keyset pagination for the delta feed |
| `idx_tombstone_version` | Same, for deletions |

`search_tsv` uses the `'simple'` configuration (no stemming) because the library is
multilingual — romanized Japanese/Korean titles get no benefit from an English stemmer and would be
mangled by one.

## Write ordering and the sync lock

`manga.row_version` comes from a single sequence assigned at **write** time, not commit time, so
concurrent writers can commit out of version order and a sync cursor could skip a row. Any
transaction mutating `manga` or its children must therefore take
`pg_advisory_xact_lock(834221)` first — see `common/sync-lock.ts` and the full rationale in
[[local-library-mirror]]. Currently applied in `import.service.ts` (header + each batch transaction)
and `cover.service.ts`.

**`manga.updated_at` is not a row-mutation timestamp.** It carries the *backup's* `lastModifiedAt`
(so it can move backwards) and cover archiving never touches it. Do not build change detection on it.

## Derived data is never stored

There is no stats table. Every dashboard figure is computed on read ([[dashboard-stats]]), so nothing
can drift out of sync with the library. Chapter counts, unread counts and last-read timestamps are
likewise derived per query from a single grouped scan over `chapter` (~182k rows) rather than
denormalized onto `manga` — the one place they *are* denormalized is the on-device mirror, which is a
disposable cache rebuilt from these queries.

## Scale (measured 2026-07-30)

2,000 titles · 182,016 chapters · 75,997 read · 1,061 covers archived / 939 failed · 2 imports ·
`pg_database_size` + `storage/` ≈ 681 MB. Warm query latency: `/stats/library` ~67 ms,
`/sync/library?limit=500` ~600 ms (671 KB per page).

## Operational notes

- Local dev: `docker compose up -d postgres`; container name `mangavault-db`, user/db `mangavault`.
- `npm run migration:run` / `migration:revert`; migrations also run automatically on boot, so the prod
  container migrates itself.
- Backups (M6, not yet built): `pg_dump` plus the `storage/` directory — the vault spans both.

### Restoring a dump rewinds `row_version` — and the epoch does not catch it

`pg_dump`/`pg_restore` round-trips `sync_state` too, so **`server_epoch` comes back identical** while
`row_version` and its sequence rewind to the dump's high-water mark. The epoch check on the client
only detects being re-pointed at a *different* server, not a restore of the same one.

The client therefore also compares its stored cursor with the server's reported one: a local cursor
**ahead** of the server's maximum is impossible while versions only increase, so it forces a full
resync (`LibrarySyncService`, covered by "a cursor ahead of the server forces a full resync"). That
makes restores safe automatically.

Rotating `sync_state.server_epoch` by hand (`UPDATE sync_state SET server_epoch = gen_random_uuid()`)
remains the blunt instrument for forcing every client to rebuild.

## `deleted_manga` (2026-07-31, migration 3)

The deletion registry: a recycle bin that doubles as an import block list, keyed
`UNIQUE (source_id, manga_url)` with a `snapshot` JSONB holding the whole record (manga scalars,
chapters, tracking, category names, contributing import ids). Rationale, restore semantics and the
import-side skip are in [[deleted-titles]].

## `cover_job` (2026-07-31, migration 4)

One row per bulk cover-archiving run, so a run that takes minutes-to-hours survives a restart and
leaves a record. Counters (`total/done/archived/failed/skipped`) are **flushed on a throttle**, not
per cover — the row is a checkpoint, not the live truth. `status` is
`running | finished | cancelled | failed | interrupted`; `interrupted` can only be produced by the
boot sweep finding a row whose process died.

**`CREATE UNIQUE INDEX uq_cover_job_running ON cover_job (status) WHERE status = 'running'`** enforces
one run at a time in the database itself: every running row carries the same `status` value, so a
unique index over that column admits exactly one. A second concurrent run then fails loudly instead
of silently double-fetching the whole library.

`manga.cover_failed_at` (BIGINT, nullable) rides along — it lets a resumed run exclude covers the
interrupted run already tried. Full rationale in [[cover-fetching]].

## Storage tuning (2026-07-31, migration 5)

Prompted by "the deletion registry duplicates `manga` — will the database run out of space?" The
measurements said no (see [[deleted-titles]]) but surfaced two real problems, both fixed by
`1754200000000-storage-tuning.ts`.

### `fillfactor` and HOT updates

`chapter` was carrying **16.3% dead tuples** and only **0.7%** of its 125,042 updates had been HOT
(839). With the default `fillfactor = 100` a page has no spare room, so an `UPDATE` must put the new
row version on a different page — which means inserting into **every** index on the table, including
the 28 MB `uq_chapter_url`. Every re-import touches most chapter rows, so this is what grew the
indexes.

Now `chapter` is `fillfactor = 85` and `manga` `fillfactor = 90`.

**The trap, measured:** `fillfactor` only governs pages built *after* it. Setting it changed nothing
on its own — a no-op `UPDATE` of 3,053 chapter rows produced **1** HOT update. The same test after a
table rewrite produced **585 of 3,053 (19%)**. Existing bloat needs the rewrite; plain `VACUUM` frees
tuples for reuse but does not re-pack pages to the new fillfactor.

`VACUUM` is deliberately **not** in the migration: TypeORM runs migrations in a transaction and
`VACUUM` cannot run in one, and rewriting a 95 MB table on boot is not a thing a deploy should do
silently. It lives in `npm run db:maintenance` (`server/scripts/db-maintenance.mjs`) — report +
`VACUUM (ANALYZE)` online, `-- --full` for `VACUUM FULL` + `REINDEX` under an exclusive lock.

Measured on the 2,000-title vault, `--full`:

| | before | after |
|---|---|---|
| `chapter` | 95.2 MB (40.3 MB indexes) | **68.8 MB** (24.6 MB indexes) |
| `manga` | 5.5 MB | 3.3 MB |
| database | 110 MB | **81.5 MB** |

### Dropped: `idx_manga_search`, `idx_manga_trgm`

3.4 MB of GIN indexes with **0** and **3** scans. They only back `GET /library?text=`, which no
client has called since the app started reading its on-device mirror ([[local-library-mirror]]); at
2,000 rows the sequential scan is ~1 ms and the e2e still passes unchanged. The generated
`search_tsv` column and the query stay, so re-creating them (the migration's `down()`) is all it
takes if a web client ever makes server-side search hot again.

### e2e suites now run serially

`test/jest-e2e.json` sets `maxWorkers: 1`. Every suite talks to the same local Postgres and boots its
own Nest app with `migrationsRun`, so in parallel they raced the same DDL when a migration landed and
— worse — concurrent writes pushed `sync.e2e`'s tombstone above the delta page's safe cursor, failing
6 tests at random. Observed twice. Serial costs a few seconds and removes the class of flake.
