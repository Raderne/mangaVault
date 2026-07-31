# Deleted titles — the deletion registry (recycle bin + import block list)

Created: 2026-07-31

Related: [[index]] · [[library-api]] · [[import-pipeline]] · [[local-library-mirror]] ·
[[database]] · [[flutter-app]] · [[cover-fetching]]

## The problem this solves

Deleting a title was meaningless in an archive fed by repeated backups. `ImportService.upsertManga`
keys on **`(source_id, manga_url)`** — the Mihon identity pair — finds nothing, and creates the title
again. The next import of any backup that still contained it silently undid the deletion.

(The *same file* was already blocked by the `import_record.sha256` duplicate check, so this only bit
on a newer export — which is the normal case.)

## The model

One table, `deleted_manga` (migration `1754000000000-deleted-manga.ts`, the third migration), doing
two jobs at once:

1. **Block list** — imports skip any incoming title whose key is registered.
2. **Recycle bin** — each row carries a `snapshot` JSONB with everything needed to put the title
   back, so restoring is instant and exact.

| Column | Why |
|---|---|
| `source_id` + `manga_url` (UNIQUE) | the identity the merge engine keys on — what makes the block work |
| `title`, `source_name`, `thumbnail_url`, `chapter_count`, `read_count` | list display without opening the snapshot |
| `deleted_at` | ordering (newest first) |
| `last_seen_at`, `seen_count` | **bumped every time an import offers the title again** — the signal the restore UI shows ("in 2 backups since") |
| `snapshot` | `{ manga, chapters[], tracking[], categoryNames[], importIds[] }` |

**Why a snapshot rather than "re-import it from the archived backup"** (we do keep every imported
file at `STORAGE_DIR/<sha256>.tachibk`): reading progress in the vault can be *newer* than any backup
on disk, the contributing backup may be months old, and replaying a whole `.tachibk` to recover one
title is far more machinery than a JSON blob. Size is a non-issue — the entire 182k-chapter library
would be ~27 MB of snapshot JSON.

Snapshot field lists are **spelled out** in `deleted-titles.service.ts` (not spread-minus-keys):
this is a persisted format, so it should change deliberately, and the `Omit<>` types make TypeScript
flag anything left behind.

## Server — `server/src/modules/library/deleted-titles.service.ts`

| Endpoint | Purpose |
|---|---|
| `GET /library/deleted` | the registry, newest first (snapshots stay server-side) |
| `POST /library/deleted/restore` | `{ ids }` (**registry** ids) → `{ restored, skipped }` |
| `POST /library/deleted/purge` | `{ ids }` → `{ purged }` — forget the entry; the title stays deleted but is no longer blocked |

- **Routes are declared before `GET /library/:id`.** Nest matches in declaration order, so
  `library/deleted` would otherwise be swallowed by the uuid param route and 400 on the pipe.
- `record(mgr, ids)` runs **inside the delete transaction, before the rows go** — it reads the very
  data that is about to cascade. A key that is already registered is refreshed (`orUpdate`), which
  happens when a title is restored and deleted again.
- `restore` runs **one transaction per title** under `withSyncLock` (it inserts a manga row, so the
  `row_version` trigger fires): a bad snapshot must not take the batch down with it. If the key
  exists again by some other path, the live row wins and the entry is simply dropped.
- **Restored titles get new ids and `cover_state='none'`** — the old id is tombstoned and gone from
  every mirror, and the archived cover file was unlinked with the row ([[cover-fetching]]), so it has
  to be re-fetched. Categories are re-linked **by name** (recreated if they were removed since);
  imports are re-linked only where the `import_record` still exists.

## Import pipeline changes ([[import-pipeline]])

- `blockedKeys()` is read **once per stage and once per commit**, never per title.
- **Preview**: a blocked title previews as `action: 'skipped'`, so the review screen states what the
  backup will *not* bring back **before** the user commits.
- **Commit**: skipped titles increment `titlesSkipped` (new field on `ImportStats` /
  `ImportSummaryDto`) and emit a `manga` event with `action: 'skipped'`.
- **The review card's count chips are filters** (2026-07-31): tapping *new* / *merged* / *skipped*
  narrows the preview list below to that outcome, tapping again (or "Show all") clears it, and a
  "Showing 3 of 2,000" line states the filtered state. `StatusChip` gained `onTap` + `selected` for
  this — `selected` outranks `emphasized` and adds a ring, since flat tones alone can't say
  *chosen*; tappable chips also get a taller pill (a 24pt target is too small). A zero count stays
  inert. On a 2,000-title backup this is the difference between "3 skipped" being a number and being
  a list you can actually read.
- `noteSeen()` runs **after** the batches, outside their transactions — it touches no library row and
  must never be able to fail an import that already committed.
- `ImportModule` now imports `LibraryModule` for `DeletedTitlesService` (no cycle — the library
  module knows nothing about imports).

## App — the Deleted titles screen

```
lib/data/library/deleted_models.dart          # DeletedTitle, RestoreResult
lib/data/library/library_write_repository.dart # + deletedTitles / restore / purgeDeleted
lib/features/library/deleted_titles_screen.dart # deletedTitlesProvider + the screen
```

- **Read straight from the server, not mirrored in SQLite.** The registry is small, rarely opened,
  and every action on it needs the server anyway — a drift table would only buy a schema bump (which
  wipes and re-pulls the whole mirror, see [[local-library-mirror]]).
- The screen is in **multi-select from the first tap** — choosing is the entire point, so there is no
  long-press mode (unlike the library grid). Two actions in a persistent bar: **Restore** (primary)
  and **Remove** (secondary, confirmed — "the titles stay deleted, but a future import will add them
  again").
- Entries a backup has offered again carry an accent chip ("in 2 backups since"); that is the field
  that tells the user what is worth restoring.
- **Restore runs a sync afterwards** — a restored title is a *new row* server-side, and the mirror
  only learns about it from the next delta.
- Reachable from the Library app bar's overflow menu, and from the **import result** ("Review 3
  skipped titles", which `context.go`s across shell branches).

## Gotchas

- **Source ids in test backups must stay below int64 max** (`9_223_372_036_854_775_807`). A larger
  literal wraps negative through the protobuf field, and the seeded rows become impossible to scope
  by source id — cost an hour of confusing e2e failures.
- The **first e2e run after a new migration** can fail: all six/seven suites boot their own Nest app
  with `migrationsRun: true` in parallel and race the DDL. Re-run once; steady state is green.
- e2e suites that delete titles **through the API** must clean `deleted_manga` in `afterAll`, or the
  registry keeps blocking those keys forever (added to `library.e2e-spec.ts`).

## Tests

- `server/test/deleted-titles.e2e-spec.ts` (6) — the full loop through the **real import pipeline**:
  import 2 titles → delete one → registry records it with `chapterCount`/`readCount` → a *newer*
  backup previews it `skipped`, emits a skipped event, does not re-add it, and bumps `seenCount` →
  restore returns it with chapters + read progress and `coverState: 'none'` → purge unblocks it and
  the next import adds it back → auth/validation.
- `app/test/backups_import_test.dart` — the review card's chip filtering (filter, toggle off,
  "Show all", and the "Showing N of M" line).
- `app/test/deleted_titles_test.dart` (4) — list rendering incl. the "in N backups since" chip,
  select→restore (calls the server, re-syncs, row disappears), remove-with-confirmation (does *not*
  restore), empty state.
