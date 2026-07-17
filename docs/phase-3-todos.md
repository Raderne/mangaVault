# Phase 3 — Implementation To-Dos

Ordered by milestone (M1–M6 from `phase-0-research-and-plan.md` §3). Each item names the file(s)
it creates or changes. Contracts referenced are in `phase-2-interfaces.md`; schemas in
`phase-1-data-structures.md`. Remember the CLAUDE.md rule: log touched files in
`wiki-brain-vault/log.md` and create/update `wiki-brain-vault/wiki/<topic>.md` as topics come up.

## M1 — Skeletons ✅ (done 2026-07-16)

- [x] `git init` the repo; `.gitignore` (node_modules, dist, build, .dart_tool, `server/storage/`,
      `MihonApp/` as untracked reference).
- [x] Scaffold NestJS in `server/` (`nest new`): TypeORM + Postgres config from env
      (`DATABASE_URL`, `STORAGE_DIR`, `API_TOKEN`), global validation pipe, bearer-token guard.
- [x] `docker-compose.yml` at repo root: postgres 16 + server dev containers; document startup
      in `wiki-brain-vault/wiki/backend.md` (create it here).
- [x] Migration 001: full schema from phase-1 §3.2 (incl. `pg_trgm` extension, tsvector column,
      GIN indexes). Start `wiki-brain-vault/wiki/migration.md` with the workflow
      (generate/run/revert commands).
- [x] Scaffold Flutter in `app/` (`flutter create`, Android-only for now): `dio` + retrofit-style
      API client, riverpod (or bloc — pick one, note in wiki) for state, `go_router` for the
      4 routes: dashboard `/`, library `/library`, title `/title/:id`, backups `/backups`.
- [x] `app/lib/theme/`: build `ThemeData`/`ColorScheme` from
      `App design/minimalist_slate/DESIGN.md` tokens (they are Material 3 role names — map 1:1),
      Inter via `google_fonts` (bundle the font files — no runtime fetching, archival app),
      radius constants (cell 24, cover 12, pill 32).
- [x] `app/lib/widgets/`: `BentoCell`, `StatusChip`, `PillButton`, `GlowProgressBar`,
      `MangaCard` (fixed-aspect cover, 12px radius, chapter-count overlay).
- [x] Settings screen stub: server base URL + API token, persisted with
      `shared_preferences`/`flutter_secure_storage`.
- [x] Update `CLAUDE.md` with real commands (`flutter run`, `flutter test`,
      `npm run start:dev`, `npm test`, migration commands, docker-compose up).

M1 notes: Riverpod chosen; Postgres published on host port 5433 (5432 occupied on dev machine);
Inter bundled from the rsms 4.1 release (not google_fonts); settings persist via
shared_preferences with a TODO to move the token to flutter_secure_storage in M2.

## M2 — Import pipeline (server) + import UI (app)

Server — `server/src/tachibk/` (pure TS lib, **zero Nest imports**, unit-testable):
- [ ] `backup.proto` + protobufjs codegen: transcribe schema from phase-1 §1 exactly; comment
      forbidding field-number edits.
- [ ] `detect.ts`: `ContainerDetector` (gzip magic `0x1f8b`, `{` JSON sniff).
- [ ] `parse.ts`: `BackupParser` — `zlib.gunzipSync` → protobuf decode → `ParsedBackup`;
      filename regex `^(.+)_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$` extracts `sourceApp`;
      collect warnings instead of failing on odd data; int64s as `Long` → decimal strings.
- [ ] `preferenceValue.ts`: decode kotlinx polymorphic `PreferenceValue` wrapper (match
      serialName suffix). Low priority — don't crash, don't need to surface in v1.
- [ ] `legacyJson.ts`: legacy Tachiyomi JSON backup → same `ParsedBackup` shape.
- [ ] `normalize.ts`: `BackupNormalizer` — status int → `PublicationStatus`, category orders →
      names, history folded into chapters (max lastRead, sum duration), syncId → `TrackerId`.
- [ ] **Tests first-class**: `server/src/tachibk/*.spec.ts` (Jest) with fixture backups —
      minimal crafted fixtures + a real backup from the user's own apps. Record parsing gotchas
      discovered along the way in `wiki-brain-vault/wiki/tachibk-format.md`.

Server — import module (`server/src/modules/import/`):
- [x] TypeORM entities for all tables (phase-1 §3.2) in `server/src/entities/` *(done early in
      M1; revisit if M2 parsing reveals gaps)*.
- [ ] `merge.engine.ts`: `MergeEngine` per phase-1 merge rules + unit tests (OR-merge read
      flags, newest-wins scalars, never-empty-over-value, nothing deleted).
- [ ] `import.service.ts`: `stage/commit/discard/history`; staged imports held in a TTL cache;
      commit = one transaction; copy original file to `storage/imports/<sha256>.tachibk`.
- [ ] `import.controller.ts`: multipart upload endpoints per phase-2 §8; e2e test with a
      fixture file.

App:
- [ ] `app/lib/data/`: DTO models (`json_serializable`) + `ImportRepository`.
- [ ] Backups screen (per `backup_sources` mockup): file picker (`file_picker`, multi-select),
      staged-import review (created/merged badges, conflict expander), commit/discard, import
      history list.
- [ ] Move API token storage to `flutter_secure_storage`.

## M3 — Library & details

Server (`server/src/modules/library/`):
- [ ] `library.service.ts`: `LibraryService.query` — QueryBuilder with tsvector + trgm search,
      filters, sort, offset/limit; unread counts via aggregate subquery. `get/updateNotes/
      setCategories/remove/listCategories`.
- [ ] `library.controller.ts` + DTO validation; e2e tests against a seeded test DB.

App:
- [ ] Library screen (per `library_archive` mockup): `GridView.builder` + infinite scroll on
      the paged API, filter chips (All/Ongoing/Completed), sort menu, debounced search field,
      empty state pointing to import.
- [ ] Title Details screen (per `title_details` mockup): bento column — synopsis cell, metadata
      cell (uppercase labels), chapter log (`ListView.builder`, read/bookmark icons),
      reading-progress cell, archive-history cell (imports that touched this title), notes
      editor, category assignment sheet.

## M4 — Covers (server) + cover UX (app)

- [ ] `server/src/modules/covers/cover.fetcher.ts`: `CoverFetcher` — browser UA,
      `Referer: origin(thumbnailUrl)`, retry w/ backoff, per-host limit 2, honors
      `KnownSource.coverFetchHint`. Log per-source quirks in
      `wiki-brain-vault/wiki/cover-fetching.md`.
- [ ] `cover.service.ts`: background job over `cover_state IN ('none','failed')`; write
      `storage/covers/<vaultId>.<ext>` (sniff mime → ext); update `cover_state`; job progress
      pollable.
- [ ] Auto-start `archiveMissing()` after every `ImportService.commit`.
- [ ] `cover.controller.ts`: job endpoints + static cover serving with long-lived cache headers
      (immutable filenames).
- [ ] App: `CachedNetworkImage` for covers (auth header interceptor), failure badge on cards,
      Title Details actions "Retry cover" / "Upload custom cover" (custom cover saved alongside,
      original never overwritten), global progress indicator while a cover job runs.

## M5 — Dashboard & health

- [ ] `server/src/modules/stats/`: `StatsService` aggregate queries (`resumeReading` = latest
      `last_read_at` with an unread successor chapter) + controller.
- [ ] App Dashboard (per `archive_dashboard` mockup): stat cells (titles, chapters, read %,
      vault size), backup-health cell (per source app staleness ring — fresh <30d / aging <90d /
      stale), recently-added shelf, resume-reading shelf with tap-through to Title Details.

## M6 — Vault safety, export & deployment

- [ ] `server/src/modules/storage/`: `StorageService.checkIntegrity` (FK orphans, cover files
      exist, `storage/imports/*` sha256 re-hash) + `sizeOnDisk`.
- [ ] `server/src/modules/export/`:
  - [ ] `exportVault` — zip of `vault.json` (full domain dump) + covers, download endpoint.
  - [ ] `exportTachibk` — domain → Mihon wire model → protobuf → gzip; **round-trip test**:
        import fixture → export → re-import → deep-equal domain model.
- [ ] App: settings section on Backups screen — integrity check button + report UI, export
      buttons (download/share sheet).
- [ ] Production deployment: VM + Docker (`docker compose --profile prod up -d`), Postgres
      backup cron (`pg_dump` + `storage/` sync) — document fully in
      `wiki-brain-vault/wiki/deployment.md`.
- [ ] Android release build config (signing, app icon per design) — document in
      `wiki-brain-vault/wiki/flutter-app.md`.

## Cross-cutting (applies throughout)

- [ ] Keep `server/src/tachibk/` free of Nest/TypeORM imports — it's the crown jewels; pure TS,
      portable, fully unit-tested.
- [ ] int64 discipline: source/tracker ids flow as decimal **strings** end-to-end (TS, JSON,
      Dart); only protobufjs `Long` touches raw values.
- [ ] Every screen must render acceptably with 0 items (fresh install) and 5,000 items
      (stress fixture generator: `server/scripts/gen-fixture.ts`).
- [ ] Update `wiki-brain-vault/log.md` after every task; create wiki topic files as scheduled
      above.
- [ ] Attribution: NOTICE file crediting Mihon (Apache 2.0) for the backup schema.
