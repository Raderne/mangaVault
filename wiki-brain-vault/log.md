# File-Touch Log

Newest entries first. Every task that creates/modifies/deletes repo files appends an entry:
date, files touched, one-line summary.

---

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
