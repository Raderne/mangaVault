# Local library mirror (on-device SQLite + delta sync)

Created: 2026-07-30

Related: [[index]] · [[backend]] · [[flutter-app]] · [[library-api]] · [[import-pipeline]] ·
[[database]] · [[dashboard-stats]] · [[cover-fetching]]

The app no longer reads library data over HTTP. A **Library Sync service** pulls server changes into
an on-device SQLite database, and the Library grid, Title Details, Dashboard and Backups history all
read from that mirror. The server stays authoritative; the mirror is a **disposable cache** that can
be deleted and rebuilt at any time — so `CLAUDE.md`'s "nothing archival lives only on the phone" rule
still holds.

Why: every scroll, filter flip and back-navigation used to be a round trip (2,000 titles / 182k
chapters), and nothing worked with the server unreachable. It also closed a real bug — committing an
import never invalidated the library or dashboard providers, so new titles didn't appear until a
manual refresh.

## The load-bearing constraint: `updated_at` cannot be a cursor

This is the trap to remember. `manga.updated_at` looks like a change timestamp and is not:

- `merge.engine.ts` sets it to `max(existing.updatedAt, incoming.lastModifiedAt)` — the **backup's**
  modification time. Importing an old backup writes an *older* value, so it moves backwards.
- `CoverService` archives covers with `mangaRepo.update(id, {coverPath, coverState})`, which never
  touches it at all. Cover progress would be invisible.
- Child tables (`chapter`, `tracking`, `manga_category`, `manga_import`) have **no timestamp
  whatsoever**, so a chapter read-flag change is undetectable — and the mirror is denormalized
  (it stores `chapterCount`/`unreadCount`/`lastReadAt` per title), so a child change *must*
  invalidate its parent.

## Server: `row_version`, stamped by the database

Migration `1753900000000-sync-row-version.ts` (the second migration ever). See [[database]].

- `mv_row_version_seq` + `manga.row_version BIGINT`, backfilled for existing rows, indexed.
- `trg_manga_stamp` — `BEFORE INSERT OR UPDATE ON manga` assigns `nextval()`. Because the **database**
  stamps it, every write path (present and future) produces a correct delta with no cooperation from
  the calling code.
- **Child propagation:** statement-level triggers with transition tables on `chapter`, `tracking`,
  `manga_category`, `manga_import` issue `UPDATE manga SET row_version = m.row_version` for the
  affected parents, which re-fires `trg_manga_stamp`. Postgres allows transition tables for only one
  event per trigger, hence three triggers per child table. Cheap: the import already does one upsert
  statement per title.
- **Tombstones:** `sync_tombstone` + an `AFTER DELETE` trigger on `manga` (and an `AFTER INSERT` one
  clearing stale entries). Nothing deletes manga today — this is the seam that makes the future
  delete feature sync with no protocol change.
- **`sync_state.server_epoch`** — a UUID identifying this database, so a client re-pointed at a
  different server rebuilds instead of trusting a meaningless cursor.
  **It does not cover a restore**: `pg_dump` round-trips `sync_state`, so the epoch survives while
  `row_version` rewinds. That case is caught client-side instead — a stored cursor **ahead** of the
  server's reported maximum is impossible while versions only increase, and forces a full resync.

`row_version` is deliberately **not mapped** on `MangaEntity` (like `search_tsv`): TypeORM must never
write it, and `migration:generate` may propose dropping it — always review the diff.

### Why the advisory lock exists

`nextval()` is assigned at **write** time, not commit time. Two concurrent writers can interleave:
txn A stamps v100, txn B stamps v101 and commits first, a client syncs and records cursor 101, then A
commits — and A's row is never delivered. Real exposure: `CoverService.archiveMissing` runs up to
`COVER_CONCURRENCY` (6) workers each issuing its own `UPDATE manga`.

`common/sync-lock.ts` provides `acquireSyncLock(mgr)` / `withSyncLock(dataSource, work)` around
`pg_advisory_xact_lock(834221)`, applied to the import commit transactions (header + each batch) and
the cover write path. Version order then equals commit order. It must be taken **inside** a
transaction — on a bare statement it releases immediately and protects nothing. Slow work (HTTP
fetches, file writes) stays outside, so the lock is held only for the row update.

## Server: `server/src/modules/sync/`

| Endpoint | Returns |
|---|---|
| `GET /sync/library?since=&limit=` | `SyncPageDto { changed, deleted, cursor, hasMore, serverEpoch }` |
| `GET /sync/meta` | `SyncMetaDto { serverEpoch, cursor, totalTitles, categories, imports, vaultSizeBytes }` |

Both bearer-guarded. `limit` defaults to 500, capped at 1000. A malformed `since` is treated as `0`
(a client with a corrupt cursor wants a full resync anyway) rather than a 400.

`SyncMangaDto` is exactly **`MangaListItemDto` ∪ `VaultMangaDto` minus the chapter list** — the union
of what the grid and details screens render. The 182k chapter rows stay server-side; progress travels
as the pre-computed aggregates plus the two `ChapterRefDto` pointers the details screen shows.
`tracking` is omitted (the Dart `VaultManga` doesn't model it and no screen renders it).

**Query:** keyset pagination (`WHERE row_version > $1 ORDER BY row_version ASC LIMIT $2`) — an offset
would skip or repeat rows as they mutate mid-sync. Chapter aggregates and the two chapter refs come
from `LEFT JOIN LATERAL`s (the pattern from [[dashboard-stats]]); category/import ids from
`array_agg` laterals. BIGINTs arrive as **strings** from raw `dataSource.query`.

**Cursor arithmetic (subtle).** Changes and tombstones are two independently-limited streams over the
same version axis, so the returned cursor may only advance to a point below which **both** are
complete. A full page of changes at v1..v500 alongside a tombstone at v700 must not move the cursor
past 500, or v501..v699 are lost forever. Rows above the safe cursor are trimmed and re-delivered on
the next page.

`/sync/meta` carries categories and import records **whole** (both are small and append-only, so
they're replaced rather than versioned) plus `vaultSizeBytes` — the one dashboard figure the device
cannot derive, so `StatsService.vaultSizeBytes()` became public and `StatsModule` now exports itself.

## App: the mirror

```
app/lib/data/local/
  tables.dart             # LocalManga (wide row), LocalCategory, LocalMangaCategory,
                          # LocalImportRecord, LocalMangaImport, SyncMeta
  app_database.dart       # @DriftDatabase + appDatabaseProvider; AppDatabase.memory() for tests
  local_library_dao.dart  # queryPage / get / categories / importHistory + dashboard aggregates
app/lib/data/sync/
  sync_models.dart        # SyncManga, SyncPage, SyncImportRecord, SyncMetaSnapshot (manual fromJson)
  sync_repository.dart    # the app's ONLY network reader for library data
  library_sync_service.dart
app/lib/features/sync/sync_controller.dart   # SyncState machine + localRevisionProvider
```

Deps added: `drift`, `path_provider`, `path`; dev `drift_dev`, `build_runner`. **This is the project's
first codegen**, scoped strictly to the drift layer — all DTOs stay manual `fromJson`.

- **`sqlite3_flutter_libs` is NOT used.** `package:sqlite3` 3.x bundles SQLite via native assets and
  the old package is a no-op marked `+eol`; `flutter pub add` pulls it in but it should be removed.
  Verified `flutter build apk --debug` succeeds with native assets on Flutter 3.44.
- **Schema policy is destructive.** `onUpgrade` drops and recreates every table and clears the cursor,
  so a `schemaVersion` bump triggers a full re-pull instead of a hand-written migration. Correct for a
  pure cache, and a full resync is only a few seconds.
- **Search escaping:** `titleLower`/`authorLower` are stored case-folded (SQLite's `LIKE` is only
  ASCII-case-insensitive and these titles are not ASCII). The `LIKE` pattern escapes `%`, `_` and `\`
  **and must pass `escapeChar: r'\'`** — without the clause SQLite matches the backslashes literally
  and a search for `%` returns nothing. This was a real bug caught by test.
- **NULLS LAST:** SQLite sorts NULL first in `DESC`, so every ordering leads with
  `OrderingTerm.asc(column.isNull())` before the real term, then `titleLower` + `id` for a stable page.

## App: the sync service

`LibrarySyncService.sync({force, onProgress})`:

1. `GET /sync/meta`; compare `serverEpoch` with the stored one.
2. Full resync when `force`, the epoch changed, or there is no cursor → start at `0` with a
   **wipe pending**.
3. Loop `GET /sync/library` until `hasMore == false`.
4. **Each page commits in one drift transaction**: the wipe (first page only), upserts, junction
   replacement, tombstone deletes, cursor advance. A dropped connection mid-sync therefore resumes
   from the last committed page.
5. Finally replace categories + imports wholesale and store `vaultSizeBytes` / `lastSyncedAt`.

**Wipe-on-first-page, never before it** — a failed full resync leaves the user's existing library on
screen instead of blanking it. A second concurrent `sync()` joins the in-flight future rather than
double-pulling (mirrors `CoverService`'s `activeJobId`).

Junction rows are **replaced per title**, not merged: the server sends complete membership each time,
so a removed category must disappear locally.

## App: read paths and reactivity

`LibraryRepository` and `StatsRepository` became **abstract interfaces** with `LocalLibraryRepository`
/ `LocalStatsRepository` implementations. Method signatures are unchanged, so `LibraryController`,
`dashboardProvider` and every screen were untouched by the switch — and test fakes now `extend` the
interface with no super-call.

**`localRevisionProvider` is an in-process `Notifier<int>`, not a drift stream.** `LibrarySyncService`
is the only writer to the mirror and runs in this isolate, so watching `sync_meta.local_revision` in
the database would buy nothing while dragging a live drift subscription into every widget tree
(including tests — it opened real database files and left pending timers). The column and
`LocalLibraryDao.watchRevision()` still exist if a second writer ever appears.

The controller bumps it after **each committed page**, so titles appear progressively;
`LibraryController` listens and calls the existing in-place `reload()` (no skeleton flash, scroll
kept), and `dashboardProvider` / `categoriesProvider` / `mangaDetailsProvider` / `importHistoryProvider`
just `ref.watch` it.

Covers are untouched — `ArchivedCover` / `CoverCache` already keep a persistent disk cache keyed by
manga id. This feature is metadata-only; keep that separation.

## Sync triggers

- **After an import commits** — `ImportController.commitAll()` runs a sync before emitting
  `ImportDone`. This is the diagram's *Import Service → Library Sync service* arrow, and it fixes the
  pre-existing "imported titles don't appear" bug. A sync failure never fails a successful import.
- **Pull-to-refresh** on Library and Dashboard (both `RefreshIndicator`s now sync rather than merely
  re-reading), plus the Dashboard's app-bar refresh.
- **First-run bootstrap** — the Library screen's `initState` calls `bootstrap()`, a no-op once a
  cursor exists. It must never throw (post-frame callback), so failures land in the banner.
- **No periodic polling**, by decision — a single-user archive only changes on import.

Offline is non-fatal: `_SyncBanner` reports "Couldn't reach the server — showing the last synced
library" with Retry, and a `_MetaLine` above the grid ("1,234 favorites · synced 5m ago") keeps
staleness visible. That line replaced the inline filter bar, which overflowed once the sync label
joined it — filters now live in a bottom sheet (see [[flutter-app]] §Filters moved to a bottom
sheet).

## Deletes (built 2026-07-31)

The seam held: `DELETE /library/:id` and `POST /library/delete` drop the rows, the `AFTER DELETE`
trigger writes tombstones, and the next delta removes them locally — **no protocol change**, and the
sync service needed no edit at all. Endpoint details in [[library-api]].

Two things did change on the device:

- **The sync service is no longer the only writer to the mirror.** `LocalLibraryDao.deleteTitles(ids)`
  removes the rows and their junction entries the moment the server confirms a delete, so the grid
  updates without waiting for a delta. It is deliberately **idempotent** — the tombstone arrives later
  and deletes the same, already-absent rows. `localRevisionProvider` stays a plain in-process
  `Notifier` because this second writer also runs in the app isolate.
- `TitleDeleter` (`features/library/library_selection.dart`) is the one place that orchestrates it:
  server → mirror → `LibraryController.removeItems` → revision bump → cover-cache eviction. Nothing is
  removed locally unless the server confirmed it.

For device→server *edits* (notes, categories), the original plan still stands: a `LocalPendingOp`
table the sync service drains *before* pulling.

## Verified (2026-07-30, against the real 2,000-title DB)

- **Triggers:** chapter insert/update/delete, cover-state update, category link, and a cascade delete
  (the risky one) all bump `row_version`; the manga delete writes exactly one tombstone.
- **Protocol:** full walk = 5 pages / 2,000 titles / 3.7 s / ~2.7 MB (671 KB per 500-title page).
  A chapter-only read-flag flip surfaced exactly one changed title.
- **End-to-end with the real Dart service against the live server:** 2,000 titles synced in **3.6 s**,
  and every dashboard aggregate matched `/stats/library` exactly — totalTitles 2000, favoriteTitles
  692, totalChapters 182016, readChapters 75997, sourceCount 25, coversArchived 1061, coversFailed
  939, vaultSizeBytes 681418083, plus identical `byStatus` / `bySourceApp` maps, identical first-page
  ordering, identical resume shelf, identical detail record. A second sync wrote **0** titles.
- `flutter build apk --debug` succeeds (native assets).

## Tests

- `server/test/sync.e2e-spec.ts` (10) — full sync, empty delta, **chapter-only change**,
  **cover-state change**, category link, keyset walk at `limit=1` with no repeats/skips, tombstone,
  malformed cursor, 401. Seeds a run-unique source and **clears its tombstones** in `afterAll`, or the
  next run's delta would carry this run's ids forever.
- `app/test/local_library_dao_test.dart` (19) — pagination, all five sorts, NULLS-LAST, every filter,
  search incl. the LIKE-wildcard case, `get`, malformed-genres tolerance, category counts, each
  dashboard aggregate, `watchRevision`.
- `app/test/library_sync_service_test.dart` (13) — multi-page walk, resume from cursor, upsert-not-
  duplicate, tombstone + junction cleanup, membership removal, epoch wipe, `force`, failure keeps old
  data, first-page failure keeps old data, partial-sync resume, wholesale category/import replacement,
  concurrent-join, `ensureBootstrapped`.
- `app/test/backups_import_test.dart` now asserts a finished import triggers a sync.
- **Every test uses `AppDatabase.memory()`** — no test may open a real database file (drift warns about
  multiple instances, and a file-backed test would hit `path_provider`'s missing platform channel).
