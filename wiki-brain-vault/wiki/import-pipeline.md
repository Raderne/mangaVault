# Import pipeline (server)

Created: 2026-07-18 (M2)

Related: [[index]] · [[backend]] · [[tachibk-format]] · [[database]] · [[local-library-mirror]]

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

## Deleted titles are skipped (2026-07-31)

`upsertManga` keys on `(source_id, manga_url)`, so before this an import silently recreated anything
the user had deleted. The commit and the staging preview now both consult the deletion registry:
a blocked title previews as `action: 'skipped'`, counts into the new `titlesSkipped` stat, emits a
`manga` event with `action: 'skipped'`, and has its `seen_count` bumped afterwards. Full design in
[[deleted-titles]].
