# Import pipeline (server)

Created: 2026-07-18 (M2)

Related: [[index]] · [[backend]] · [[tachibk-format]] · [[database]]

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
2. **`POST /api/v1/imports/stage/:id/commit`** → one DB transaction: upsert categories (by name) &
   sources, insert the `import_record`, then per manga create-or-merge, link `manga_category` and
   `manga_import`, write `stats`. After commit, the original bytes are archived to
   `STORAGE_DIR/imports/<sha256>.tachibk` and the staged entry is dropped. Commit of a
   `duplicateOf` entry is refused (409). Returns `ImportRecordDto`.
3. **`DELETE /api/v1/imports/stage/:id`** → `discard` (drop from cache, 204).
4. **`GET /api/v1/imports`** → history, newest first.

All routes require the bearer token (global guard); none are `@Public()`.

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

- Children written with `manager.upsert(ChapterEntity, rows, ['mangaId','url'])` /
  `['mangaId','tracker']` — relies on the unique constraints from the initial migration.
- Junction rows (`manga_category`, `manga_import`) inserted via query builder `.orIgnore()`.
- `updatedAt` doubles as the source `lastModifiedAt` that drives newer-wins.
- **Uploads capped at 200 MB** (`FileInterceptor` limit); real libraries are a few MB gzipped.
- `STORAGE_DIR` (default `./storage`) — `server/storage/` is git-ignored. Added `@types/multer`.

## Tests

- `merge.engine.spec.ts` — the merge rules (OR reads, never-empty-over-value, newer-wins conflict,
  notes concat, unions).
- `test/import.e2e-spec.ts` — **full AppModule against local Postgres (5433)**: stage → commit →
  re-import merge (chapter union, no dupes, newer-wins scalar) → history, plus a 401 without auth.
  Uses a run-unique source id and cleans up its own rows.

## Not done in M2 (app side)

The Flutter Backups screen + `ImportRepository` (upload/review/commit/history) is still to build —
the API it will call is done and verified. See [[flutter-app]].
