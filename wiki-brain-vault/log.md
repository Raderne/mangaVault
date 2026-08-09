# File-Touch Log

Newest entries first. Every task that creates/modifies/deletes repo files appends an entry:
date, files touched, one-line summary.

---

## [2026-08-06 22:30] session | Backup export: .tachibk encoder and export wizard
Touched: backup-export (new), index, tachibk-format, backup-apps

## [2026-08-02 17:20] session | Backup source apps: registry, picker, library filter
Touched: backup-apps (new), index, import-pipeline, library-api, database, local-library-mirror,
flutter-app, dashboard-stats, tachibk-format
Note: the dev Postgres volume and `server/storage/` (2,000 titles, 1,121 covers, 147 archived
backups) were **destroyed** on the user's explicit instruction — "just delete everything" — instead
of building a backfill UI for the old untagged import. The vault is now empty.

## [2026-07-31 23:30] session | Cover storage profile: 613 MB -> 126 MB
Touched: cover-fetching, dashboard-stats

## [2026-07-31 22:40] session | Storage: measured the registry, fixed real bloat
Touched: database, deleted-titles, dashboard-stats

## [2026-07-31 21:20] session | Cover archiving as a durable background job
Touched: cover-fetching, database, import-pipeline, index

## [2026-07-31 20:45] session | Deletion registry: imports no longer resurrect deleted titles
Touched: deleted-titles, library-api, import-pipeline, database, flutter-app, index

## [2026-07-31 15:40] session | Source filter, delete, multi-select, display options
Touched: flutter-app, library-api, local-library-mirror, cover-fetching

## [2026-07-31 14:05] session | How Mihon extensions factor into cover fetching
Touched: cover-fetching

## [2026-07-31 12:30] session | Claude Code health check; CLAUDE.md trimmed + split per-subdir
Touched: none

## [2026-07-30 18:30] session | Library filters → bottom sheet (fixes filter-bar overflow)
Touched: flutter-app, local-library-mirror

## [2026-07-30 17:45] session | Local library mirror — on-device SQLite + delta sync
Touched: local-library-mirror (created), database (created), index, backend, flutter-app,
library-api, import-pipeline, cover-fetching, dashboard-stats, migration

## [2026-07-28 23:20] session | Bento tile tonal color pop
Touched: flutter-app, dashboard-stats

## [2026-07-28 23:05] session | Fix shelf tile overflow at enlarged system font
Touched: dashboard-stats, flutter-app

## [2026-07-28 22:55] session | M5 — dashboard stats API + Archive Dashboard screen
Touched: dashboard-stats (created), backend, flutter-app, index

## [2026-07-25 17:20] session | Cover fetcher: Mihon mobile UA + site Referer + cause logging
Touched: cover-fetching

## [2026-07-25 16:45] session | On-device cover disk cache (cached_network_image)
Touched: cover-fetching, flutter-app

## [2026-07-25 15:55] session | Library favorites filter toggle
Touched: library-api

## [2026-07-25 16:15] session | M4 — cover fetching/archiving + serve + app UI
Touched: cover-fetching (created), backend, flutter-app, index

## [2026-07-25 14:30] session | M3 — Library API + grid + Title Details + animations
Touched: library-api (created), flutter-app, index

## [2026-07-18 02:00] session | M2 done — SSE streamed import + Flutter Backups UI
Touched: import-pipeline, flutter-app

## [2026-07-18 01:00] session | M2 import pipeline (server) — parse, merge, endpoints
Touched: tachibk-format (created), import-pipeline (created), index

## [2026-07-18 00:00] session | Bake server config, remove Settings tab
Touched: flutter-app (created), index

## [2026-07-17 00:00] session | Conform vault to Wiki-Brain guide
Touched: index (created), backend, migration; CLAUDE.md rule block rewritten to "READ FIRST, KEEP UPDATED"

## 2026-07-16 — M1: skeletons scaffolded and verified

- `server/` (created) — NestJS 11 scaffold + TypeORM 1.1/pg/config/validation; entities for all
  8 tables, handwritten initial migration (pg_trgm, tsvector, GIN), global bearer-token guard
  (`auth/`), public `/api/v1/health`, Dockerfile, `.env.example`, migration npm scripts.
  Verified: build ✓, 5 unit + 2 e2e tests ✓, migration applied to live Postgres ✓, server boot
  + health 200 ✓.
- `app/` (created) — Flutter scaffold (Android, package `dev.mangavault.mangavault`); Riverpod
  + go_router + dio + shared_preferences; Minimalist Slate theme (`lib/theme/`, tokens from
  DESIGN.md, bundled Inter 400/600/700 in `assets/fonts/`); widgets (BentoCell, StatusChip,
  PillButton, GlowProgressBar, MangaCard); 4-tab shell with glass bottom nav; placeholder
  Dashboard/Library/TitleDetails/Backups screens + working Settings (server URL/token).
  Verified: `flutter analyze` clean ✓, widget test ✓.
- `docker-compose.yml`, `.env.example`, `.env` (created) — Postgres 16 on host port **5433**
  (5432 taken by another project); `--profile prod` adds the server container.
- `.gitignore` (extended), `CLAUDE.md` (commands + real layout), `wiki/backend.md` +
  `wiki/migration.md` (created), `docs/phase-3-todos.md` (M1 items checked).
- TypeORM chosen (confirmed), Riverpod confirmed, deployment = Docker on a VM.

## 2026-07-16

- `CLAUDE.md` (rewritten), `docs/phase-0-research-and-plan.md`, `docs/phase-1-data-structures.md`,
  `docs/phase-2-interfaces.md`, `docs/phase-3-todos.md`, `wiki-brain-vault/log.md`,
  `wiki-brain-vault/wiki/README.md` (created) — Initial /init: researched Mihon `.tachibk`
  format + image fetching, wrote phase 0–3 planning docs; then switched planned stack from
  Tauri desktop to **Flutter (Android) + NestJS + Postgres** per user decision and added the
  wiki-brain-vault convention.
