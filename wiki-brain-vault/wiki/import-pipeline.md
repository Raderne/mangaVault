# Import pipeline (server)

Created: 2026-07-18 (M2)

Related: [[index]] · [[backend]] · [[tachibk-format]] · [[database]] · [[local-library-mirror]] ·
[[cover-fetching]] · [[deleted-titles]] · [[backup-apps]] · [[flutter-app]] · [[manga-neon-accents]]

NestJS module that turns an uploaded backup into library rows. `server/src/modules/import/`.
Consumes the pure [[tachibk-format]] lib; owns the DB writes and file archiving.

## Flow: stage → commit (or discard)

Two-phase so the app can show a **review screen** before anything is written.

1. **`POST /api/v1/imports/stage`** (multipart, field `file`) → `stage(buffer, fileName)`:
   sha256 the file → parse → normalize → look up existing manga by `(sourceId, mangaUrl)` to build a
   per-title `preview` (`created` vs `merged` + scalar/notes conflicts) and a `summary` (counts +
   warnings). Held **in-memory** in a `Map` with a **30-min TTL** (lazy eviction). If the sha256 was
   already imported, `duplicateOf` is set. **No DB writes.** Returns `StagedImportDto` (the full
   normalized library stays server-side; the client only gets preview + summary).
2. **`POST /api/v1/imports/stage/:id/commit`** → `startCommit`: validates the staged entry (404 if
   expired, 409 if `duplicateOf`), registers a **job** and returns `{ jobId }` immediately (the work
   runs in the background). The original bytes are archived to `STORAGE_DIR/imports/<sha256>.tachibk`
   up front. Then: one small txn for categories + sources + the `import_record` header, then the
   manga are committed in **batches of `IMPORT_BATCH_SIZE` (default 100, env-overridable)** — each
   batch its own transaction, with running `import_record.stats` persisted after each. **Batched, not
   one big transaction** (chosen for large libraries + live progress): a mid-way failure keeps the
   batches already committed and emits an `error` event.
3. **`GET /api/v1/imports/jobs/:jobId/events`** (`@Sse`) → live progress as Server-Sent Events; each
   message `data` is an `ImportEvent` (see below). Backed by a per-job `ReplaySubject`
   (`import-job.registry.ts`) so a client connecting a moment after the POST still replays from
   `start`; the stream completes on the terminal `done`/`error`. Jobs are evicted ~10 min after
   finishing. **Consumed by the Flutter Dio client** (native, so it sends the bearer header on the
   GET — not a browser `EventSource`).
4. **`GET /api/v1/imports/jobs/:jobId`** → point-in-time snapshot (reconnect / polling fallback).
5. **`DELETE /api/v1/imports/stage/:id`** → `discard` (drop from cache, 204).
6. **`GET /api/v1/imports`** → history, newest first.
7. **`PATCH /api/v1/imports/stage/:id`** (2026-08-02) → `{ sourceApp }` re-tags which **reading app**
   the backup came from, before commit. Returns the updated `StagedImportDto`. `''` = unknown.
   `runCommit` also `ensure()`s the tag in the app registry. See [[backup-apps]].

All routes require the bearer token (global guard); none are `@Public()`.

### `ImportEvent` stream contract (`import.dto.ts`)
Discriminated union pushed over SSE, mirrored 1:1 by the Flutter client:
`start{fileName,total}` → `phase{categories|sources|manga|archiving|done, detail?}` → many
`manga{title, action:created|merged, processed, total}` + `batch{committed,total}` → `done{record}`
(or terminal `error{message,processed}`). The `phase` events carry the "which settings are being
applied" detail the UI shows (e.g. "Applying 5 categories").

## Merge engine (`merge.engine.ts`, pure + unit-tested)

Dedup key is `(sourceId, mangaUrl)`. Archival semantics — **nothing is ever deleted**, a non-empty
value is **never** overwritten by an empty one, read state only accumulates:

- Scalars (title/author/artist/description/thumbnail/status): **newer wins** by
  `lastModifiedAt` vs the row's `updatedAt`; genuine two-non-empty disagreements are reported as
  `FieldConflict`s (surfaced in the review UI).
- `favorite`: OR. `genres`, `categoryNames`: union. `dateAdded`: earliest positive.
- `notes`: keep both if they differ (concatenated with a `---` divider) + flag a conflict.
- Chapters: union by url; `read`/`bookmark` OR; `lastPageRead`/`lastReadAt`/`readDuration` max.
- Tracking: union by tracker; higher progress wins; existing links preserved.

The engine is DB-agnostic: the service projects a `MangaEntity` (+children) into a
`MergeableManga`, merges, then writes back — so the rules stay unit-testable with no TypeORM.

## Persistence notes

- **Every commit transaction takes the sync advisory lock first** (`acquireSyncLock(mgr)`, both the
  header transaction and each batch) so `manga.row_version` order matches commit order — see
  [[local-library-mirror]]. Do not add a new write path here without it.
- Children written with `manager.upsert(ChapterEntity, rows, ['mangaId','url'])` /
  `['mangaId','tracker']` — relies on the unique constraints from the initial migration.
- Junction rows (`manga_category`, `manga_import`) inserted via query builder `.orIgnore()`.
- `updatedAt` doubles as the source `lastModifiedAt` that drives newer-wins.
- **Uploads capped at 200 MB** (`FileInterceptor` limit); real libraries are a few MB gzipped.
- `STORAGE_DIR` (default `./storage`) — `server/storage/` is git-ignored. Added `@types/multer`.

## Tests

- `merge.engine.spec.ts` — the merge rules (OR reads, never-empty-over-value, newer-wins conflict,
  notes concat, unions).
- `test/import.e2e-spec.ts` — **full AppModule against local Postgres (5433)**: stage → commit
  (returns `jobId`) → **consume the real SSE stream** (asserts `start`/`manga`/`done` events) →
  re-import merge (chapter union, no dupes, newer-wins scalar) → a **multi-title batch-boundary**
  case (`IMPORT_BATCH_SIZE=2`, 5 titles ⇒ 3 `batch` events, all 5 rows land) → history, plus 401
  without auth. Run-unique source ids; cleans up its own rows.

## App client

The Flutter Backups screen consumes all of the above — see [[flutter-app]] (Import UI section):
`ImportRepository` (multipart stage, commit→jobId, Dio SSE stream via `core/sse/sse_parser.dart`),
an `ImportController` state machine, and a live-progress screen that renders each `manga` event as
it streams in. M2 is complete.

Since 2026-07-30, `commitAll()` also **runs a library sync** before emitting `ImportDone`, so the
newly imported titles land in the on-device mirror and the Library/Dashboard update immediately —
the *Import Service → Library Sync service* hand-off. A sync failure never fails a successful
import. See [[local-library-mirror]].

## Live import view: the vanishing ticker (2026-08-09)

`app/lib/features/backups/import_ticker.dart`. The committing cell used to render every `manga`
event into a `ListView` capped at 50 rows and 280px. It grew as the import ran, and on a real backup
it was an unreadable blur. It is now a **fixed-height well of four slots**: the newest title enters
at the top, each older one steps down and dims (100 / 55 / 30 / 12%), and the oldest fades out. The
card's height never changes. Motion rules are in DESIGN.md §Motion; hues in [[manga-neon-accents]].

Decisions worth keeping:

- **The ticker samples the stream; it does not follow it.** A 1,200-title backup emits ~40 events a
  second — faster than any transition, so every row would be a strobe. One admission per 140ms,
  intermediates dropped. Throttling lives in the widget, not `ImportController`: it is a legibility
  concern, and the controller's job is to be the truth, not the pace.
- **A fifth "exit slot" at opacity 0.** Without somewhere to fade *to*, the oldest row is cut from
  the tree while still partly visible and pops. Rows also dim (200ms) faster than they glide (320ms)
  so the residual at removal is invisible.
- **Rows are keyed by a monotonic counter, not by the event.** `MangaEvent` has no id and titles
  repeat across backups; a duplicate key puts two rows in one slot.
- **`_recentCap` dropped 50 → 4.** Only the head of `recent` is ever read now; the old cap copied a
  50-element list per title, ~60k allocations across a large import.
- **Slot geometry comes from `MediaQuery.textScalerOf`**, like the dashboard shelves. Note the
  failure mode differs: a too-short slot **squashes** the badge rather than overflowing it, so a
  bounds assertion passes while the label is clipped. `import_ticker_test.dart` compares each badge
  against a reference chip rendered at the same text scale — verified to fail against a deliberately
  wrong metric before being kept.
- **`ExcludeSemantics`.** A screen reader announcing 1,200 titles is noise; the phase label and the
  `n / total` counter beside the well already carry the progress.

The phase cells (staging → needs-app → review → committing → done/failed) are wrapped in
`_ImportStateSection`: an `AnimatedSwitcher` inside an `AnimatedSize`, keyed on `state.runtimeType`
**only**. Keying on the state instance would rebuild the committing cell on every progress tick and
the ticker would never show anything. Its `layoutBuilder` overrides the default centred `Stack` —
otherwise a tall cell leaving and a short one arriving slide past each other.

> **Testing gotcha, cost an hour:** swapping a `NotifierProvider` override
> (`overrideWith(() => Seeded(newState))`) on a `pumpWidget` does **not** re-run the notifier's
> `build()`, so the screen keeps rendering the first seed. It looks exactly like a broken widget.
> Drive a single controller instance from the test instead.

## Covers follow the import (2026-07-31)

A title without its art isn't archived yet, so a successful commit calls
`CoverService.archiveAfterImport()` — **after** the `done` event, and wrapped so that a cover run
failing to start can never turn a committed import into a failed one. `ImportModule` imports
`CoverModule` for it (no cycle: `LibraryModule` already did).

The run is scoped to covers **never tried** (`retryFailed: false`), so a source that can't be fetched
at all isn't re-hammered on every import; the user's manual run is what retries those. If a run was
already in flight its candidate list predates these titles, so a follow-up pass is queued instead of
joining it. Details and the trigger table in [[cover-fetching]].

## Deleted titles are skipped (2026-07-31)

`upsertManga` keys on `(source_id, manga_url)`, so before this an import silently recreated anything
the user had deleted. The commit and the staging preview now both consult the deletion registry:
a blocked title previews as `action: 'skipped'`, counts into the new `titlesSkipped` stat, emits a
`manga` event with `action: 'skipped'`, and has its `seen_count` bumped afterwards. Full design in
[[deleted-titles]].
