# Backup source apps (which reading app a backup came from)

Created: 2026-08-02

Related: [[index]] · [[backend]] · [[import-pipeline]] · [[library-api]] · [[database]] ·
[[local-library-mirror]] · [[flutter-app]] · [[dashboard-stats]] · [[tachibk-format]]

A `.tachibk` is named `<applicationId>_<timestamp>.tachibk`, so the filename says which fork produced
it (`app.mihon`, `app.komikku`, …). That id is now a first-class thing: named, pickable when the
filename doesn't carry it, and filterable in the library. It is also the anchor for the planned
**auto-backup watcher** (below).

## The load-bearing decision: attribution is derived, not stored

There is **no `source_app` column on `manga`**. A title's apps come from
`manga → manga_import → import_record.source_app`, and the relationship is **many-to-many**: a title
merged from a Komikku backup and a Mihon backup belongs to *both* and matches either filter. A
denormalized column would have forced an arbitrary "which app wins".

That join already existed on both sides — server SQL and the drift mirror (`local_manga_import ⋈
local_import_record`) — so the filter needed **no schema change and no sync-protocol change** for the
attribution itself. Only display names had to be shipped (see below).

`COALESCE(NULLIF(source_app, ''), 'unknown')` is the canonical bucketing, mirrored client-side by
`_sourceAppLabel` / `backupAppLabel`: `''` is how an unidentified backup is *stored*, `unknown` is
how it is *selected and read*.

## Filename parsing (`server/src/tachibk/parse.ts`)

`BACKUP_NAME_RE = /^(.+?)_(?:\d{4}-\d{2}-\d{2}.*)\.(?:tachibk|json)$/i`

Anchored on the **ISO date**, not on Mihon's exact `_yyyy-MM-dd_HH-mm`. The old regex demanded the
time segment, so `app.mihon_2026-07-16.tachibk` — a real filename — yielded `''`, which is why the
dev vault's largest import was untagged. Non-greedy, so the first date in the name ends the prefix.

Three deliberate behaviours:

- The legacy-JSON early return is **gone**: `tachiyomi_2026-01-01.json` names its app just as well.
- The capture is rejected if it is empty, contains whitespace, or exceeds 100 chars —
  `my library_2026-07-16.tachibk` yields `''`. **A wrong guess is worse than none**, because `''` is
  the signal that makes the app ask the user.
- The result is lower-cased. Covered by 11 table-driven cases in `parse.spec.ts`.

## The registry — `server/src/modules/backup-apps/`

`backup_app` (migration `1754300000000-backup-apps.ts`): `id` TEXT PK, `display_name`, `accent`,
`curated`, `created_at`.

- **Curated rows are seeded on boot** (`BackupAppsService.onModuleInit`), from `curated-apps.ts` —
  not in the migration. Correcting a name or adding a fork is a one-line edit, no migration. Only
  three ids are shipped, each one *confirmed*: `app.mihon` (Mihon's `BuildConfig.APPLICATION_ID`),
  `app.komikku` (from a real import), `eu.kanade.tachiyomi`. **Do not add a fork on a guess** — a
  wrong id silently fails to match real backups; an unlisted app still works via the learned path.
- `ensure(id)` registers an id the first time it is *used* — from the filename at commit time, or
  from the user's pick. So everything the library can be filtered by has a name behind it.
- `list()` uses a **`FULL JOIN`** against import counts, not a LEFT JOIN: an import can name an app
  the registry doesn't have (restored dump, hand-deleted row) and those titles must stay filterable.
  Such a row falls back to its id as the display name.
- **No FK** from `import_record.source_app`: an import must survive its app being removed, and `''`
  has to stay legal.

| Route | Notes |
|---|---|
| `GET /backup-apps` | `{id, displayName, accent, curated, importCount, titleCount, lastImportAt}`, used apps first |
| `POST /backup-apps` | idempotent on id; an explicit `displayName` overwrites (the user is correcting it) |
| `DELETE /backup-apps/:id` | 409 for curated, or when it already labels an import |

## Tagging a staged import — `PATCH /imports/stage/:id`

Body `{ sourceApp }`, returns the updated `StagedImportDto`. Chosen over a body on `commit` so the
review UI re-renders from the server's answer, correcting a wrong pick is the same call again, and
`commit` stays bodyless. `''` is accepted and means unknown — an unidentified backup must still be
importable. **This endpoint takes an explicit id rather than re-deriving one**, which is what the
future watcher needs.

## Library filter

`LibraryQueryDto.sourceApps` → an `EXISTS` over `manga_import ⋈ import_record`, the same shape as the
`categoryIds` clause. Two new indexes back it (`idx_import_record_source_app`,
`idx_manga_import_import` — `manga_import` previously had only its composite PK, so the reverse
lookup had no index at all). The client filters off its mirror, so there is no
`GET /library/source-apps`.

## App side

- `data/backup_apps/` — `BackupApp`, `SourceAppOption`, `backupAppLabel`, plus the Dio repository.
  `backupAppsProvider` reads the **network** (the picker must offer apps you hold no titles from);
  `backupAppNamesProvider` and `libraryAppsProvider` read the **mirror**, so names and chips work
  offline.
- `LocalBackupApp` joined the drift schema — **`schemaVersion` 2 → 3**, which drops and re-pulls the
  mirror by design ([[local-library-mirror]]).
- **`ImportNeedsApp{queue, index}`** is a new state in the sealed `ImportState` union, not a callback:
  `ImportController` is a `Notifier` with no `BuildContext`, and the screen already renders from the
  union. `_NeedsAppCell` auto-opens `showSourceAppSheet` once per staged id; dismissing leaves the
  cell with a button to reopen so a stray back-swipe can't strand the import.
- **Routing resumes at `index + 1`, never rescanning from the start.** Skipping leaves `sourceApp`
  empty, so a rescan would ask about the same file forever. This was a real bug in the first cut,
  now pinned by `backups_import_test`'s "skipping does not re-ask the same file".
- `SelectableChip` was promoted out of `library_filter_sheet.dart` into `widgets/` so the picker and
  the filter render the identical control.
- Filter UI: a **FROM APP** section of chips in the sheet's FILTER tab (chips, not the searchable
  source list — a handful of apps against 25+ sources), plus an app segment on the `_MetaLine`.
  `LibraryFilters.sourceApps` had to move in lockstep across constructor/`copyWith`, `_fetch`,
  `reload`, `_sameFilters` (the stale-response guard) and `hasActiveFilters`.

## Groundwork for auto-backup monitoring (not built)

Decision (2026-08-02): **the Flutter app watches the device folder**, not the server.

- **The server owns the app registry; the device owns the folder grants.** A SAF tree URI is
  device-specific and meaningless to the vault, so a `WatchedFolder {appId, safTreeUri,
  lastImportedFileName, lastImportedAt}` belongs in `shared_preferences` — not in the mirror, per
  CLAUDE.md's rule about device-only state.
- Re-scan dedup is already free: `import_record.sha256` is unique, staging returns `duplicateOf`, and
  `startCommit` 409s on it.
- Mihon keeps only the **last 4** auto-backups (`BackupCreator.kt` `MAX_AUTO_BACKUPS`), named
  `<applicationId>_yyyy-MM-dd_HH-mm.tachibk` — so scan on every app resume, not on a slow timer, or
  backups are lost before they are seen.
- Deps deliberately **not** added yet: a SAF persistent-permission plugin and WorkManager.

## Verified (2026-08-02, against a freshly wiped vault)

The dev database and `storage/` were destroyed on the user's instruction rather than backfilling the
old untagged import — see the log entry. Against the empty vault, over real HTTP:

- Boot seeded the 3 curated apps.
- `app.mihon_2026-08-02.tachibk` staged with `sourceApp = 'app.mihon'` (date-only name — the case the
  old regex rejected); `library-backup.tachibk` staged with `''`.
- `POST /backup-apps` + `PATCH /imports/stage/:id` tagged the untagged file; the committed
  `import_record.source_app` was the chosen id and the registry then reported `importCount = 1`.
- A third backup re-importing one of the Mihon titles under `app.komikku` previewed as `merged`;
  afterwards that title matched **both** `sourceApps=app.mihon` and `sourceApps=app.komikku`, and the
  combined filter returned it **once**.
- `/sync/meta.backupApps` carried the registry; `/stats/library.bySourceApp` split correctly.
- Tests: server 80 unit + 70 e2e (8 suites), app 126 (up from 111), `flutter analyze` clean.
