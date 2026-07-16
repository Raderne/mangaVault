# Phase 3 — Implementation To-Dos

Ordered by milestone (M1–M6 from `phase-0-research-and-plan.md` §3). Each item names the file(s)
it creates or changes. Contracts referenced are in `phase-2-interfaces.md`; schemas in
`phase-1-data-structures.md`.

## M1 — Skeleton

- [ ] `git init` the repo; add `.gitignore` (node_modules, dist, src-tauri/target, `MihonApp/` as
      untracked reference or a submodule — decide; likely add `MihonApp/` to .gitignore).
- [ ] Scaffold Tauri 2 + React 18 + TypeScript + Vite in `src/` + `src-tauri/`
      (`npm create tauri-app`). Enable plugins: `fs`, `dialog`, `sql` (sqlite), `http`.
- [ ] `tailwind.config.ts` + `src/styles/tokens.css`: port every token from
      `App design/minimalist_slate/DESIGN.md` (colors verbatim, Inter font, radius scale
      sm/​default/​md/​lg/​xl, spacing units). Self-host Inter + Material Symbols (archival app —
      no CDN dependencies).
- [ ] `src/components/layout/`: `AppShell.tsx` (glass top nav, 4 routes), `BentoCell.tsx`
      (24px radius, surface-container bg, hover elevation per DESIGN.md), `StatusChip.tsx`,
      `PillButton.tsx`, `ProgressBar.tsx` (4px glow track).
- [ ] `src/router.tsx`: routes `/` (dashboard), `/library`, `/title/:id`, `/backups`
      with placeholder pages matching the four mockup layouts.
- [ ] Update `CLAUDE.md` with the real build/dev/test commands once scaffolded
      (`npm run tauri dev`, `npm test`, etc.).

## M2 — Import pipeline

- [ ] `src/lib/tachibk/backup.proto` + codegen (protobufjs): transcribe schema from phase-1 §1
      exactly; add a comment forbidding field-number edits.
- [ ] `src/lib/tachibk/detect.ts`: `ContainerDetector` (gzip magic 0x1f8b, `{` JSON sniff).
- [ ] `src/lib/tachibk/parse.ts`: `BackupParser` — `DecompressionStream('gzip')` → protobuf
      decode → `ParsedBackup`; filename regex `^(.+)_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$`
      to extract `sourceApp`; collect warnings instead of failing on odd data.
- [ ] `src/lib/tachibk/preferenceValue.ts`: decode kotlinx polymorphic `PreferenceValue`
      wrapper (match serialName suffix). Low priority — prefs aren't shown in v1 UI, but parse
      without crashing.
- [ ] `src/lib/tachibk/legacyJson.ts`: legacy Tachiyomi JSON backup → same `ParsedBackup` shape.
- [ ] `src/lib/tachibk/normalize.ts`: `BackupNormalizer` — status int → `PublicationStatus`,
      category orders → names, history folded into chapters (max lastRead, sum duration),
      tracking syncId → `TrackerId`, int64s as decimal strings.
- [ ] **Tests first-class here**: `src/lib/tachibk/*.test.ts` (Vitest) with fixture backups —
      craft minimal fixtures with a protobuf encoder + a real backup from the user's own apps.
      This module has zero UI/Tauri deps on purpose: keep it pure.
- [ ] `src-tauri` / `src/services/db.ts`: open SQLite via tauri-plugin-sql; migration runner;
      migration 001 = full schema from phase-1 §3.2 including FTS5 + triggers.
- [ ] `src/services/mergeEngine.ts`: `MergeEngine` per phase-1 merge rules + unit tests
      (OR-merge read flags, newest-wins scalars, never-empty-over-value).
- [ ] `src/services/importService.ts`: `ImportService.stage/commit/discard/history`;
      commit = one transaction; copy original file to `imports/<sha256>.tachibk`.
- [ ] `src/pages/Backups.tsx`: drop-zone + file picker (multi-file), staged-import review
      table (MergeResult list, per-title created/merged badges, conflict expander),
      commit/discard actions, import history list — per `backup_sources` mockup.

## M3 — Library & details

- [ ] `src/services/libraryService.ts`: `LibraryService` on SQLite; `query()` builds
      WHERE/ORDER/LIMIT + FTS join; unread counts via aggregate subquery.
- [ ] `src/pages/Library.tsx`: virtualized cover grid (`@tanstack/react-virtual`),
      filter chips (All/Ongoing/Completed per mockup), sort menu, instant search box,
      empty-state pointing to import.
- [ ] `src/components/MangaCard.tsx`: fixed-aspect cover, 12px radius, chapter-count overlay
      bottom-right, coverState placeholder/spinner/broken states.
- [ ] `src/pages/TitleDetails.tsx`: bento layout per `title_details` mockup — synopsis cell,
      metadata cell (uppercase labels), chapter log (virtualized list, read/bookmark icons),
      reading-progress cell (progress bar + last-read), archive-history cell (imports that
      touched this title), notes editor (`updateNotes`), category assignment.
- [ ] `src/services/__tests__/libraryService.test.ts` against an in-memory/temp DB.

## M4 — Covers

- [ ] `src/services/coverFetcher.ts`: `CoverFetcher` via Tauri HTTP plugin — desktop-browser UA,
      `Referer: origin(thumbnailUrl)`, retry w/ backoff, per-host limit 2, honors
      `KnownSource.coverFetchHint`.
- [ ] `src/services/coverService.ts`: queue over all `coverState in ('none','failed')`;
      write `covers/<vaultId>.<ext>` (sniff mime → ext); update `cover_state`; emit events.
- [ ] Wire into import flow: after `ImportService.commit`, auto-start `archiveMissing()`.
- [ ] UI: global progress toast (n/total), failure badge on cards, Title Details actions
      "Retry cover" / "Upload custom cover" (`setCustomCover` keeps original file untouched,
      writes `covers/<vaultId>.custom.<ext>` and points cover_path at it).
- [ ] Seed `known_source` registry: `src/data/knownSources.ts` with ids/names/baseUrls of the
      user's actual sources (accumulated automatically from every import's `backupSources`).

## M5 — Dashboard & health

- [ ] `src/services/statsService.ts`: `StatsService` (aggregate queries; `resumeReading` = latest
      `last_read_at` with unread successor chapter).
- [ ] `src/pages/Dashboard.tsx` per `archive_dashboard` mockup: stat cells (titles, chapters,
      read %, vault size), backup-health cell (per source app staleness ring —
      fresh <30d / aging <90d / stale), recently-added shelf, resume-reading shelf.

## M6 — Vault safety & export

- [ ] `src/services/vaultService.ts`: vault folder pick/create/open, migrations on open,
      `checkIntegrity()` (FK check, cover files exist, `imports/*` sha256 re-hash),
      `sizeOnDisk()`.
- [ ] First-run experience: no vault configured → guided create/open flow before anything else.
- [ ] `src/services/exportService.ts`:
  - [ ] `exportVault` — zip of `vault.json` (full domain dump) + covers.
  - [ ] `exportTachibk` — re-encode domain → Mihon wire model → protobuf → gzip; **round-trip
        test**: import fixture → export → re-import → deep-equal domain model.
- [ ] Settings section on `/backups`: vault path display/change, integrity check button +
      report UI, export buttons.

## Cross-cutting (applies throughout)

- [ ] Keep `src/lib/tachibk/` free of Tauri/React imports (pure TS) — it's the crown jewels and
      must stay unit-testable and portable.
- [ ] int64 discipline: all source/tracker ids flow as strings end-to-end; only protobufjs Long
      touches the raw values.
- [ ] Every screen must render acceptably with 0 items (fresh vault) and 5,000 items
      (stress fixture generator: `scripts/genFixture.ts`).
- [ ] Attribution: NOTICE file crediting Mihon (Apache 2.0) for the backup schema.
