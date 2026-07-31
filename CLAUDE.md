# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**MangaVault** — a personal archival system for manga/manhwa libraries. It imports backup files
(`.tachibk` / legacy `.json`) exported from Mihon and its forks (Tachiyomi lineage), consolidates
them into one library, and keeps the collection (metadata, reading progress, covers) safe even if
the source reading apps disappear.

Responsibilities: the **server** (`server/`, NestJS) owns `.tachibk` parsing (Node gunzip +
protobuf), the Postgres library store, cover fetching/archiving, and stats. The **Flutter app**
(`app/`) is a client — it uploads backup files, browses the library, and renders the four designed
screens. Nothing archival lives only on the phone.

The app *does* keep an on-device SQLite **mirror** of the library for fast, offline browsing, filled
by a delta sync (`/sync/*`). That is a disposable cache, not storage: it holds only the fields the
screens render, can be deleted and rebuilt in seconds, and never holds anything the server doesn't.
The rule above is unchanged. See `wiki-brain-vault/wiki/local-library-mirror.md`.

## Setup & non-obvious commands

First-time setup: copy `.env.example` → `.env` at the repo root (set a real `API_TOKEN`), then
`docker compose up -d postgres` (local Postgres on host port **5433** — 5432 is taken by another
project on this machine).

- `npm run migration:generate -- src/database/migrations/<name>` (from `server/`) — diff entities →
  new migration; the path argument is required. `migration:run` / `migration:revert` also auto-run
  on boot.
- `docker compose --profile prod up -d` — production stack; builds `server/Dockerfile` and runs
  Postgres + server (deploy target: a VM with Docker; details in
  `wiki-brain-vault/wiki/deployment.md` when it exists).

Everything else is the standard invocation for the tool — see `server/package.json` scripts and
`flutter run` / `flutter analyze` / `flutter test` in `app/`.

## Conventions & prohibitions

- `MihonApp/mihon/` is a **read-only reference clone** of Mihon (Apache 2.0, so porting
  schema/logic with attribution is fine). **Never modify it**; it is not part of any build.
- `server/` — schema is owned by raw-SQL migrations; TypeORM `synchronize` is **off**, never turn
  it on. Global bearer-token guard; mark public routes with `@Public()`. Pure `.tachibk` parsing
  stays in `src/tachibk/` with zero Nest/TypeORM imports.
- `App design/minimalist_slate/DESIGN.md` is the **source of truth for all UI work**. Its color
  tokens use Material 3 color role names (`surface-container`, `on-primary`, …), so they map
  directly onto a Flutter `ColorScheme`. `App design/project_brief_library_archive.md` is the
  product brief; the Stitch mockups cover `archive_dashboard`, `library_archive`, `title_details`,
  `backup_sources`.
- Read `docs/phase-0-research-and-plan.md` first — `docs/` holds the phase planning documents
  (research, data structures, interfaces, to-dos).

Subdirectory guidance loads automatically when you work there: `server/CLAUDE.md` (the `.tachibk`
format, cover archiving) and `app/CLAUDE.md` (Minimalist Slate design conventions).

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
