# Dashboard Stats (M5)

Created: 2026-07-28

Related: [[index]] · [[backend]] · [[flutter-app]] · [[library-api]] · [[cover-fetching]] ·
[[import-pipeline]] · [[database]]

The archive's overview: how much is stored, how much has been read, and whether the backups behind
it are still current. Backs the `archive_dashboard` mockup and replaces the em-dash placeholders that
stood in from M1.

## Server — `server/src/modules/stats/`

```
stats.dto.ts        # LibraryStatsDto, BackupHealthDto, ResumeItemDto, Staleness
staleness.ts        # pure stalenessOf(lastImportAt, now) — fresh/aging/stale (unit-tested)
stats.service.ts    # StatsService: libraryStats / backupHealth / recentlyAdded / resumeReading
stats.controller.ts # GET /stats/library|backup-health|recently-added|resume-reading
stats.module.ts     # imports LibraryModule (reuses LibraryService.query)
```

Registered in `app.module.ts`. **No stats table** — every figure is derived on read, so nothing can
drift out of sync with the library. All read-only.

### Endpoints

| Endpoint | Returns |
|---|---|
| `GET /stats/library` | `LibraryStatsDto` — titles, chapters, read, covers, sources, vault bytes |
| `GET /stats/backup-health` | `BackupHealthDto[]`, newest import first, one row per source app |
| `GET /stats/recently-added?limit=` | `MangaListItemDto[]` (newest `date_added` first) |
| `GET /stats/resume-reading?limit=` | `ResumeItemDto[]` — list row + `readCount` + `nextChapter` |

`limit` is clamped to 1..40 (default 10) in the controller, mirroring how [[library-api]] parses its
loose query strings.

### Decisions & gotchas

- **`recentlyAdded` delegates to `LibraryService.query`** (`sortBy=dateAdded, sortDir=desc`) rather
  than duplicating the chapter-aggregate SQL — that's why `StatsModule` imports `LibraryModule`.
- **`resumeReading` — the LATERAL must be limited *inside* the CTE.** The candidate set is a grouped
  chapter scan (`HAVING MAX(last_read_at) IS NOT NULL AND unread > 0`); without `ORDER BY … LIMIT`
  in the CTE, Postgres ran the "next unread chapter" LATERAL **1,133 times** (once per candidate)
  and only then took the top 12 — 166 ms. With the limit inside the CTE it runs **12 times**: 45 ms,
  and it stays flat as the library grows. Verified with `EXPLAIN ANALYZE` on the real 2,000-title DB.
- **Status breakdown is dense**: `byStatus` always carries every `PublicationStatus` key (zeroed when
  empty), so the client renders a full breakdown without null checks.
- **`bySourceApp` counts titles per backup app** via `import_record ⋈ manga_import`, with
  `COUNT(DISTINCT manga_id)` (a title merged from several backups must not be double-counted). Blank
  `source_app` values collapse to `'unknown'` — the first real import has one, since its filename
  carried no app-id prefix.
- **`vaultSizeBytes` = `pg_database_size()` + `storage/imports/` + `storage/covers/`.** "How big is
  my vault" spans both Postgres and disk. The two directories are flat, so a `readdir` + per-file
  `stat` is enough; every part degrades to 0 on error rather than failing the whole dashboard.
  Real numbers: ~646 MB for 2,000 titles / 182k chapters / 1,061 archived covers.
- **Staleness is pure and lives apart from Nest** (`staleness.ts`): `fresh` <30 d, `aging` <90 d,
  `stale` beyond — and a missing/zero timestamp is **stale**, not fresh (an archive with no known
  import date is the worst case).
- **int64 discipline** as everywhere else: `MAX(imported_at)` / `MAX(last_read_at)` come back from
  raw `dataSource.query` as **strings** and are `Number(...)`-converted in the mapper.
- Tests: `staleness.spec.ts` (3 unit) + `test/stats.e2e-spec.ts` (6 e2e). The e2e seeds a run-unique
  source id **and source app** so it can assert its own health row, its titles in both shelves, and
  that fully-read / never-opened titles are excluded from resume — archive-wide totals are only
  asserted as "at least what I seeded", since the dev DB holds a real library.

## Flutter — `app/lib/data/stats/` + `app/lib/features/dashboard/`

```
data/stats/stats_models.dart       # LibraryStats, BackupHealth, Staleness enum, ResumeItem
data/stats/stats_repository.dart   # statsRepositoryProvider (Dio): the four calls
features/dashboard/dashboard_controller.dart  # dashboardProvider: FutureProvider<DashboardData>
features/dashboard/dashboard_screen.dart      # the bento grid
core/format.dart                   # groupedNumber / formatBytes / relativeDate / chapterNumberLabel
widgets/progress_ring.dart         # the mockup's animated ring
```

- **One snapshot, one pass.** `dashboardProvider` awaits all four requests together with Dart's
  record `.wait` and returns a `DashboardData`, so the grid appears at once instead of cell-by-cell.
  `ref.invalidate` (app-bar refresh) or `ref.refresh(...future)` (pull-to-refresh via
  `RefreshIndicator`) re-runs the lot. Every state — loading, error, empty — is a **scrollable**, so
  pull-to-refresh keeps working when there's nothing to show.
- **Cells** (single column on the phone, `EntranceFade`-staggered 70 ms apart): welcome block →
  hero total-titles (display-lg figure, "+N added this week", pulsing dot with favorites/sources) →
  paired Chapters / Covers cells → reading-progress `ProgressRing` + top-3 status mix → backup health
  (a staleness dot per source app + relative last-import + `Import a backup` pill) → resume-reading
  shelf → recently-added shelf → vault-on-disk cell.
- **`ProgressRing`** (`widgets/progress_ring.dart`) is a `CustomPaint` arc from 12 o'clock with a
  rounded cap over a track, animating its sweep via `TweenAnimationBuilder` on `kEntranceCurve` and
  snapping under reduce-motion — the mockup's "90%" ring, reused for archive read progress.
- **Paired stat cells need `IntrinsicHeight`.** `CrossAxisAlignment.stretch` inside a `ListView`
  forces an infinite height constraint and throws in layout; `IntrinsicHeight` bounds the `Row` so
  the two cells still match heights when one caption wraps.
- **A horizontal shelf's fixed height must be derived from the text scale, never hardcoded.** The
  first cut used `_shelfHeight = 238`, computed by hand at scale 1.0 (234 of content). On a device
  with the system font enlarged (~1.1) the tile needed 240 and Flutter reported *"A RenderFlex
  overflowed by 2.0 pixels"* — repeated once per visible tile. `_ShelfMetrics.of(context)` now
  measures both text blocks with `MediaQuery.textScalerOf`, and the tile's title/caption sit in
  `SizedBox`es of exactly those heights, so the children sum to the reserved height by construction.
  The theme sets an explicit `height` on `bodyMedium`/`labelSmall`, which is what makes a line box
  exactly `scaledFontSize * height` and the arithmetic trustworthy.
- **Widget tests do NOT fail on `RenderFlex` overflow — don't trust `takeException()` for layout.**
  Verified deliberately: with the shelf box shrunk to 100px against ~242px of tile (a 142px
  overflow), `flutter test` still reported "All tests passed" and `tester.takeException()` returned
  null, while a real device threw loudly. Overflow is reported from `RenderFlex.paint`, which the
  test harness doesn't surface. So `dashboard_screen_test.dart` asserts the **geometry** instead —
  the caption's `getRect().bottom` must sit inside the shelf `ListView`'s rect — and that assertion
  was confirmed to fail against both the 238 constant and the 100px probe before being kept.
- **Shelf tiles navigate with `context.go('/library/title/<id>')`, not `push`.** The details route
  lives in the Library branch of the `StatefulShellRoute`; `go` switches the shell to that branch
  with details on top, so the back gesture lands on the Library grid instead of a dead end. Shelf
  covers deliberately carry **no Hero** — the grid owns the `manga-cover-<id>` tag in its own branch
  navigator.
- **`core/format.dart` replaced the duplicated date helper.** `relativeDate` moved out of
  `title_details_screen.dart`; `groupedNumber` (1,284) and `formatBytes` (3.0 GB) avoid adding
  `intl`. **`chapterNumberLabel` exists because Mihon chapter numbers carry float32 noise** — a real
  title's next chapter arrived as `0.10000000149011612`, so numbers are rounded to two decimals,
  whole ones lose the `.0`, and `-1` (unnumbered) falls back to the chapter name.
- Tests: `format_test.dart` (formatters incl. the float-noise case), `stats_models_test.dart`
  (parsing, derived fractions, sparse payload, staleness default), `dashboard_screen_test.dart`
  (real figures / empty archive / error+retry / **enlarged system font**, on a tall test surface
  since the cells build lazily). Text scale is set with
  `tester.platformDispatcher.textScaleFactorTestValue` — a `MediaQuery` wrapped *above* `MaterialApp`
  is silently overridden by the `MediaQuery.fromView` that `WidgetsApp` installs, so that route
  looks like it works and tests nothing.

## Verified against real data (2026-07-28)

2,000 titles · 182,016 chapters · 75,996 read (42%) · 1,061 covers archived, 939 failed ·
2 backups (`app.komikku` 863 titles, `unknown` 1,228) · ~646 MB vault. Warm latency: `/stats/library`
~67 ms, `/stats/resume-reading` ~33 ms, `/stats/recently-added` ~47 ms.

## Deferred

- `coversFailed` is high (939) because many sources 403 without their extension's headers — see
  [[cover-fetching]]; the dashboard now makes that visible, but per-source hints are still the fix.
- Storage **breakdown** and integrity checking (`/storage/*`) stay in M6; `vaultSizeBytes` here is a
  single rolled-up figure.
