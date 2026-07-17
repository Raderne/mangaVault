# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**MangaVault** — a personal archival system for manga/manhwa libraries. It imports backup files
(`.tachibk` / legacy `.json`) exported from Mihon and its forks (Tachiyomi lineage), consolidates
them into one library, and keeps the collection (metadata, reading progress, covers) safe even if
the source reading apps disappear.

## Tech stack & app structure

| Part | Stack | Location |
|---|---|---|
| Mobile app (Android) | Flutter (Dart) | `app/` |
| Backend API | NestJS (TypeScript) | `server/` |
| Database | PostgreSQL | via `server/` (TypeORM/Prisma migrations) |

Responsibilities: the **server** owns `.tachibk` parsing (Node gunzip + protobuf), the Postgres
library store, cover fetching/archiving, and stats. The **Flutter app** is a client — it uploads
backup files, browses the library, and renders the four designed screens. Nothing archival lives
only on the phone.

## Commands

First-time setup: copy `.env.example` → `.env` at the repo root (set a real `API_TOKEN`), then
`docker compose up -d postgres` (local Postgres on host port **5433** — 5432 is taken by another
project on this machine).

Server (run from `server/`):
- `npm run start:dev` — dev server with watch (http://localhost:3000/api/v1, health at `/health`)
- `npm run build` / `npm run lint` / `npm test` / `npm run test:e2e`
- `npm run migration:run` / `migration:revert` — apply/revert migrations (also auto-run on boot)
- `npm run migration:generate -- src/database/migrations/<name>` — diff entities → new migration
- Jest single test: `npm test -- --testPathPattern api-token`

App (run from `app/`):
- `flutter run` — launch on connected Android device/emulator
- `flutter analyze` / `flutter test`

Production: `docker compose --profile prod up -d` builds `server/Dockerfile` and runs
Postgres + server (deploy target: a VM with Docker; details in `wiki-brain-vault/wiki/deployment.md`
when it exists).

## Repository layout

- `app/` — Flutter Android app. `lib/theme/` (Minimalist Slate tokens), `lib/widgets/` (BentoCell,
  MangaCard, …), `lib/features/<screen>/`, `lib/core/` (settings, API client), Riverpod +
  go_router (StatefulShellRoute with 4 tabs).
- `server/` — NestJS API. `src/entities/` (TypeORM, schema owned by raw-SQL migrations in
  `src/database/migrations/` — `synchronize` is off, never turn it on), `src/auth/` (global
  bearer-token guard; mark public routes with `@Public()`), future modules under `src/modules/`.
  Pure `.tachibk` parsing will live in `src/tachibk/` with zero Nest/TypeORM imports.
- `App design/` — Stitch-generated UI mockups (Tailwind HTML + screenshots) for the four screens:
  `archive_dashboard`, `library_archive`, `title_details`, `backup_sources`.
  - `App design/project_brief_library_archive.md` — product brief.
  - `App design/minimalist_slate/DESIGN.md` — the "Minimalist Slate" design system. Its color
    tokens use **Material 3 color role names** (`surface-container`, `on-primary`, …), so they map
    directly onto a Flutter `ColorScheme`. Source of truth for all UI work.
- `MihonApp/mihon/` — a **read-only reference clone** of Mihon (Apache 2.0, so porting
  schema/logic with attribution is fine). Never modify it; it is not part of any build.
- `docs/` — phase planning documents (research, data structures, interfaces, to-dos). Read
  `docs/phase-0-research-and-plan.md` first.
- `wiki-brain-vault/` — the project knowledge base (see rule below).

## Wiki-Brain — knowledge base (READ FIRST, KEEP UPDATED)

This repo has a persistent, cross-linked knowledge base at **`wiki-brain-vault/`**. It is the
accumulated understanding of this solution and exists to reduce token usage — consult it instead of
re-reading the whole codebase. Treat it as primary context.

### Use it

- **At the start of a task, consult the wiki before spelunking the code.** Entry point:
  `wiki-brain-vault/wiki/index.md`. Follow `[[Page]]` links to the relevant pages.
- Pages are one-per-topic and **created on demand** — the first time you do substantial work on a
  topic, create its file under `wiki-brain-vault/wiki/` and record decisions, gotchas, and how-tos.

### Keep it updated (mandatory)

- **Claude fully owns `wiki-brain-vault/wiki/`.** When a task produces durable knowledge — a
  decision, a resolved bug, an architecture/state change, a new subsystem — create or update the
  relevant wiki page(s) before finishing. Don't ask permission per page; just report what changed.
  Keep CLAUDE.md lean — deep details belong in the wiki, referenced from here when load-bearing.
- **Cross-link aggressively** with Obsidian `[[Page Name]]` syntax. A page with no inbound links is
  a dead end.
- **Always update `wiki-brain-vault/wiki/index.md`** when you create or rename a page.
- **End every session with a log line** appended to `wiki-brain-vault/log.md` (newest first):

  ```text
  ## [YYYY-MM-DD HH:MM] session | <title in 3-8 words>
  Touched: <comma-separated wiki pages, or "none">
  ```

  If the session was trivial (one-off fix, routine chore, pure exploration), just add the log line
  and skip the wiki update.
- **Flag contradictions, don't silently resolve them.** If new info conflicts with an existing
  page, surface it to the user.

## The .tachibk backup format (critical domain knowledge)

A `.tachibk` file is a **gzip-compressed protobuf** payload (kotlinx.serialization ProtoBuf) of the
`Backup` message. Parsing happens **server-side** in NestJS. Decoding rules, learned from
`MihonApp/mihon/.../data/backup/BackupDecoder.kt`:

- Peek first 2 bytes: `0x1f8b` → gunzip first; `{}`/`{"`/`{\n` → legacy JSON (Mihon rejects it;
  MangaVault should parse legacy Tachiyomi JSON backups instead); anything else → raw protobuf.
- Proto field numbers are the wire contract and must never change. Canonical definitions live in
  `MihonApp/mihon/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/`. The full schema is
  mirrored in `docs/phase-1-data-structures.md`.
- Gotchas: fields are sparse/optional with defaults (old backups omit newer fields; notably
  `favorite` defaults to true); numbering has gaps (skipped legacy 1.x fields; Mihon-specific
  fields start at 100+); forks add fields at higher numbers — always ignore unknown fields.
  `PreferenceValue` is a kotlinx *polymorphic* type — a wrapper message (field 1 = serialName,
  field 2 = payload), not a plain oneof.
- A manga's identity within the ecosystem is `(source id, relative manga url)` — the dedup key
  when merging backups from multiple forks.
- Manga↔category linkage is by `BackupCategory.order` values listed in `BackupManga.categories`.
- Filename convention: `<applicationId>_yyyy-MM-dd_HH-mm.tachibk`; the app-id prefix identifies
  which fork produced it (e.g. `app.mihon`).

## How Mihon fetches images (the model for server-side cover archiving)

- Every manga row carries `source` (64-bit source ID) and `thumbnailUrl` (absolute URL, preserved
  in backups). Source IDs = first 8 bytes of `MD5("${name.lowercase()}/$lang/$versionId")` masked
  positive (`HttpSource.generateId`); `backupSources` maps id → display name.
- Covers are plain HTTP GETs, **but through the owning source's OkHttp client and headers**
  (`MangaCoverFetcher`) — many sites 403 without the source's custom User-Agent/Referer.
  MangaVault has no extensions, so the NestJS cover fetcher approximates: browser-like UA +
  `Referer` derived from the thumbnail URL's origin, per-host concurrency limits and retries,
  with per-source overrides when a site needs them.
- Two-tier caching in Mihon (permanent `CoverCache` for library items vs. ephemeral LRU) —
  for MangaVault, download covers **at import time** into permanent server storage; thumbnail
  URLs rot, which defeats an archive.
- Chapter *page* images require per-site extension parsing (`HttpSource.getPageList`); out of
  scope for v1 (metadata + covers archive), seam left for later.

## Design conventions

- Dark-only "Minimalist Slate" theme; build the Flutter `ThemeData`/`ColorScheme` from the exact
  tokens in `App design/minimalist_slate/DESIGN.md` (surface tiers for bento cells, 24px cell
  radius, 12px cover radius, pill buttons, Inter everywhere, uppercase micro-labels).
- Layout is a bento grid; on the phone, cells stack in a single column (mockups' mobile rule),
  16px gutters, ≥24px cell padding. The four `code.html` mockups are the visual reference —
  match them, but rebuild as Flutter widgets; don't mimic the HTML structure.
- Library views must stay smooth at 1,000+ titles: paginate/lazy-load from the API and use
  builder-based lists/grids.
