# Backend (NestJS)

Created: 2026-07-16 (M1)

Related: [[index]] · [[migration]] · [[database]] · [[deployment]] · [[tachibk-format]] ·
[[import-pipeline]] · [[library-api]] · [[cover-fetching]] · [[dashboard-stats]] ·
[[local-library-mirror]]

## Stack

- NestJS 11 + TypeScript, TypeORM **1.1** (note: major above the long-lived 0.3.x — the
  decorator/DataSource API is unchanged), `pg`, Postgres 16 (alpine, Docker).
- Node 22 in the production image (`server/Dockerfile`, multi-stage, ~prod deps only).

## Layout

```
server/src/
  main.ts                  # global prefix api/v1, ValidationPipe(whitelist+transform), 0.0.0.0
  app.module.ts            # ConfigModule(global) + TypeOrmModule + global ApiTokenGuard
  auth/                    # ApiTokenGuard (Bearer <API_TOKEN>, timing-safe), @Public()
  health/                  # GET /api/v1/health (public)
  common/transformers.ts   # bigint(ms) <-> number column transformer
  entities/                # TypeORM entities; index.ts exports ALL_ENTITIES
  database/data-source.ts  # buildDataSourceOptions() + CLI DataSource (dotenv .env, ../.env)
  database/migrations/     # raw-SQL migrations (schema source of truth)
  modules/import/          # [[import-pipeline]] — stage/commit, SSE progress
  modules/library/         # [[library-api]] — /library, /library/:id, /categories
  modules/covers/          # [[cover-fetching]] — /covers/*, fetcher, StreamableFile serve
  modules/stats/           # [[dashboard-stats]] — /stats/*, derived aggregates, staleness
  modules/sync/            # [[local-library-mirror]] — /sync/library + /sync/meta delta feed
  common/sync-lock.ts      # pg_advisory_xact_lock wrapper: keeps row_version order == commit order
```

## Decisions & gotchas

- **Auth:** single static `API_TOKEN` env var, checked timing-safely by a global guard.
  Fail-closed: unset token ⇒ every non-`@Public()` request 401s. Fine for a personal server on
  a VM; revisit if ever multi-user.
- **Schema is migration-owned** (see [[migration]] for the workflow). `synchronize: false`
  everywhere, `migrationsRun: true` on boot (prod container migrates itself). The initial migration
  is handwritten SQL to get things
  TypeORM can't express: `pg_trgm` extension, generated `search_tsv` tsvector column, GIN
  indexes. Entities deliberately do NOT map `search_tsv`.
- **int64 discipline:** Mihon source ids / tracker media ids are TEXT columns and string fields.
  Epoch-millis BIGINTs use the `bigIntToNumber` transformer (safe: < 2^53).
- **Env loading:** `envFilePath: ['.env', '../.env']` — server-local overrides repo root; the
  root `.env` is shared with docker-compose. `.env.example` files exist at both levels.
- **Local port:** Postgres is published on host **5433** (5432 occupied by `expensy-postgres`
  from another project). In-container/compose networking still uses 5432.
- The e2e test boots a slim module (health + guard) without Postgres on purpose; DB-backed e2e
  starts in M2 with the import pipeline.
- **Actual script names** (CLAUDE.md is stale on two of these): the watch dev server is
  `npm run dev` (there is no `start:dev`), and Jest's single-test flag is now
  `npm test -- --testPathPatterns <name>` (plural — Jest renamed `--testPathPattern` and errors
  out on the old form).

## Container & build (see [[deployment]] for the box it runs on)

- **`npm install`, never `npm ci`** — in the Dockerfile, in CI, everywhere. `sharp` pulls
  platform-specific optional dependencies (`@img/sharp-*`, and `@emnapi/*` beneath them) and npm
  writes into the lockfile only what the *installing* platform resolved (npm/cli#4828). A lockfile
  generated on Windows fails `npm ci` on ARM64 Alpine with `Missing: @emnapi/runtime from lock
  file`; regenerate it on Linux and it fails on Windows with `Missing: @img/sharp-wasm32`. There is
  no single lockfile that satisfies both — this was diagnosed the slow way, by trying. `npm install`
  honours the lockfile where it is consistent and re-resolves only the divergent optional deps.
- **The image runs as `node` (uid 1000), not root.** The server fetches cover art from arbitrary
  third-party URLs and parses untrusted protobuf out of uploaded backups; neither belongs to uid 0.
  If the `storage` volume already has root-owned content from an older image, chown it once —
  Docker only applies the image's ownership to an *empty* named volume:
  `docker run --rm -v mangavault-prod_storage:/data alpine chown -R 1000:1000 /data`.
- **`HEALTHCHECK` on `/api/v1/health`** is in the Dockerfile, so any compose file inherits it.
  Without one, `restart: always` cannot act on a process that is up but wedged.
- **Production log level is `['log','warn','error']`** (`main.ts`). `DEBUG` emits one line per cover
  archived — thousands per import, and it was the largest container log on the VM.
- `x-powered-by` is disabled; the app is typed as `NestExpressApplication` so `app.disable()` is
  checked rather than reached through an `any` (which trips the repo's lint rules).
- **`.github/workflows/server.yml`** lints, tests and builds the real image for **amd64 and
  arm64**, then asserts `sharp` loads and the image is not root. The VM is Ampere A1, so an
  amd64-only build proves nothing about where this actually runs.
