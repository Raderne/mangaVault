# Backup export (creating `.tachibk` files)

Created: 2026-08-06

Related: [[index]] · [[tachibk-format]] · [[backup-apps]] · [[import-pipeline]] · [[library-api]] ·
[[backend]] · [[flutter-app]] · [[database]]

The way *out* of the vault: any slice of the library written back as a `.tachibk` that Mihon and its
forks restore natively. This is what makes MangaVault an archive rather than a roach motel — if the
server disappears, everything it holds can still be handed back to a reading app.

## The load-bearing decision: the encoder is the parser run backwards

`domain -> denormalize -> wire -> encode -> bytes` is the exact mirror of the import path's
`bytes -> parse -> wire -> normalize -> domain` ([[tachibk-format]]). Both directions share the one
embedded proto schema in `backup.proto.ts`, so they cannot drift apart.

This is why the export service reads the DB into **`NormalizedBackup`** — the same domain type the
*importer* produces — instead of building protobuf objects directly. A second, independent mapper
would be a second place for the format's traps to be got wrong, and the round-trip property
(`normalize(parse(encode(denormalize(x)))) == x`) would have nothing to assert against.

New pure files under `server/src/tachibk/`, still zero Nest/TypeORM imports:

| File | Role |
|---|---|
| `denormalize.ts` | `BackupDenormalizer`: domain → wire. Inverse of `normalize.ts`. |
| `encode.ts` | `BackupEncoder`: wire → protobuf → gzip. Inverse of `parse.ts`. Plus `buildBackupFileName`. |
| `encode.spec.ts` | 17 round-trip cases — the whole safety net for the writer. |

### Gotchas the writer has to get right

- **`favorite` must always be written.** Absent means **TRUE** to every reader, so an encoder that
  omits `false` silently re-favorites the entire export. It is `optional bool` in the proto, so
  protobufjs tracks presence; the denormalizer sets it explicitly either way. Pinned by a test.
- **int64 stays a decimal string** end to end, and `Type.fromObject` (not `create`) is what accepts
  it. Verified against int64-max.
- **Tracker ids ride `mediaId` (field 100), never `mediaIdInt` (field 3).** The latter is the
  deprecated 32-bit field; an AniList id above 2^31 would be mangled. `mediaIdInt` is written as 0,
  which is exactly the condition the normalizer's fallback checks for.
- **`unknown:<n>` trackers round-trip.** The normalizer parks an unrecognised `syncId` as
  `unknown:42`; the denormalizer parses the number back out, so nothing is lost.
- **History is unfolded, not invented.** The parser folds `BackupHistory` into chapters
  (`max(lastRead)`, `sum(readDuration)`); the writer emits **one** history row per chapter that has
  any, which re-normalizes to the same numbers.
- **Category membership travels as `order` values**, re-indexed dense from 0 over the categories
  actually used. Vault uuids never leave. A `categoryName` with no matching category row is dropped
  rather than corrupting the list.
- **Zero-valued flags are written, not omitted** (`viewer`, `chapterFlags`, `updateStrategy`,
  `version`). MangaVault doesn't model them; a restoring app should apply its own defaults.
- **gzip is async** (`promisify(zlib.gzip)`). `gzipSync` on a multi-MB backup parks the event loop
  for the whole compression, and this is a request-path call.
- **`BackupEncodeError`** is deliberately a separate class from `BackupParseError`: an encode failure
  is always our bug, never the user's file, and must never be reported as a corrupt input.

## Nothing is persisted (decision, 2026-08-06)

`POST /exports/build` assembles the file in memory and streams it back. **No export storage, no
history table, no cleanup job** — and no stale copy that could outlive a title deleted from the
vault. The user chose this over a server-stored export history.

The client saves it through the platform's own picker (`FilePicker.saveFile`), not into app storage:
a backup you can't find is not a backup, and on Android the SAF dialog is the only route to a folder
that survives an uninstall. No new dependency — `file_picker` was already in `pubspec.yaml` for
import.

## API — `server/src/modules/export/`

| Route | Notes |
|---|---|
| `GET /exports/facets` | Apps, sources, categories, statuses — each with a **title count** — plus vault totals. One call, because the wizard needs all of them on its first frame. |
| `POST /exports/preview` | Counts, filename and estimated size for a scope, without building it. |
| `POST /exports/build` | The file. `application/gzip`, `Content-Disposition`, and `X-Export-File-Name` / `X-Export-Titles` echo headers. |

`POST` (not `GET`) for preview/build because the scope is a body: a hand-picked selection can carry
thousands of ids, which has no business in a query string.

### The scope model

```
mode:   'all' | 'filter' | 'ids'
filter: text, status[], categoryIds[], sourceIds[], sourceApps[],
        favorite?, unreadOnly, startedOnly
ids:    manga uuids (mode 'ids', max 5000)
include: chapters, readProgress, categories, tracking
targetApp: app id the filename is built from
```

- **Facets AND together, values within a facet OR** — the identical clause shapes as
  `LibraryService.query` ([[library-api]]), on purpose: a scope that previews as N titles must be the
  same N the library grid shows for that filter. `sourceApps` reuses the
  `COALESCE(NULLIF(source_app,''), 'unknown')` bucketing from [[backup-apps]].
- **`mode: 'ids'` with an empty list selects nothing** (`WHERE FALSE`), never everything. The
  difference between an empty file and accidentally exporting the whole vault.
- **`readProgress` is forced off when `chapters` is off**, normalized in the controller so preview
  and build can never disagree. Bookmarks survive a progress-less export — a bookmark is a
  deliberate mark, not a side effect of reading.
- **`targetApp` is validated against `BACKUP_APP_ID_RE`.** The filename is the format's *only*
  carrier of app identity, so naming a file `app.mihon_<stamp>.tachibk` is what makes a future
  re-import attribute it to Mihon — the same regex, round-tripped. Empty ⇒ `mangavault`.

### Query notes

- The preview is **one query with a `scope` CTE**, not repeated subqueries. The predicate is written
  against the alias `m`, so any other alias silently resolves `m.…` against the outer query — this
  was a real 500 (`subquery uses ungrouped column "m.source_id"`) before the CTE.
- Children (chapters/tracking/categories) load in **batches of 500 manga ids**; a full vault holds
  hundreds of thousands of chapters and a single result set would pull them all into memory.
- `estimatedBytes` is a heuristic (`titles*110 + chapters*26`), always rendered with a `~`, and it
  respects the include flags — otherwise it lies by an order of magnitude on a chapter-less export.

## App — `/backups/export`

A full-screen route nested under `/backups`, launched from an **Export** cell sitting directly
opposite the Import cell on the Backups hub. Nested so the Backups tab stays selected and a
back-swipe returns to the hub.

Three steps (`select → options → review`) with a **persistent summary bar** carrying live counts
across all of them. The bar is the reason the flow feels answerable: every chip tap moves the number,
so the effect of a filter is visible *before* committing to it.

- **Presets first, facets on demand.** Everything / Favorites only / Custom. "Back up everything" is
  one tap; the full facet builder only unfolds under Custom. Which preset is lit is **derived** from
  the scope, not stored — reaching favorites-only by hand lights the same tile.
- Touching any facet flips the mode to `filter` automatically, or the chip would be recorded and
  then ignored by the server.
- **Preview is debounced 300ms** with a cancel token and a request sequence guard — chip taps arrive
  in bursts, and an out-of-order response would show counts for a scope already changed.
- The review step gives the **exclusions** as much room as the counts ("This is a partial backup…"),
  because the failure mode of an archive tool is a backup that looks complete and isn't. An explicit
  note states that covers stay in the vault: the format only stores the cover URL.
- `ExportState` is a single immutable value rather than a sealed union (unlike `ImportState`): the
  scope must survive every status, so a failed build returns the user to their selection intact.

Files: `app/lib/data/export/` (models + repository), `app/lib/features/backups/export/`
(controller, screen, three step widgets, shared widgets).

## Verified (2026-08-06)

- Server: **97 unit** (up from 80 — +17 encoder round-trip) and **80 e2e in 9 suites** (up from 70).
- `test/export.e2e-spec.ts` seeds a known slice of the real Postgres, exports it over HTTP, and
  decodes the returned bytes **with the import path's own parser** — so a dropped favorite, a mangled
  64-bit id or a lost category shows up as a diff, not as a file that merely happens to be valid gzip.
- App: **146 tests** (up from 126), `flutter analyze` clean.
