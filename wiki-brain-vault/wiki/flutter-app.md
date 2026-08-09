# Flutter App

Created: 2026-07-18

Related: [[index]] · [[backend]] · [[library-api]] · [[cover-fetching]] · [[dashboard-stats]] ·
[[local-library-mirror]] · [[manga-neon-accents]]

## Stack

- Flutter (Dart, SDK ^3.12), Riverpod 3 + go_router 17 (`StatefulShellRoute.indexedStack`),
  Dio 5 for HTTP. Dark-only "Minimalist Slate" theme built from design tokens.

## Layout

```
app/lib/
  main.dart                     # ProviderScope + MaterialApp.router
  router.dart                   # StatefulShellRoute, 3 tabs (see below)
  theme/                        # app_colors, app_dimens, app_theme (Minimalist Slate)
  widgets/                      # app_shell (glass bottom nav), bento_cell, manga_card, …
  core/
    config/app_config.dart      # compile-time server config (SERVER_URL, API_TOKEN)
    api/api_client.dart         # apiClientProvider → Dio(baseUrl + bearer)
    format.dart                 # groupedNumber / formatBytes / relativeDate / chapterNumberLabel
  features/<screen>/            # dashboard, library, title_details, backups
app/config/
  dev.json                      # git-ignored: real LAN URL + API token
  dev.example.json              # committed template
```

## Server connection (rewritten 2026-08-09 — full page: [[server-connection]])

> **Superseded.** The 2026-07-18 decision recorded here was "no in-app connection settings; the
> server URL and `API_TOKEN` are baked in at build time". That held while the APK was built
> privately for one LAN. It stopped holding when the app began shipping as a **public** artifact
> on GitHub Releases ([[app-updates]]) — a compile-time token in a public APK is a published
> credential.

- The server address and token are now **entered by the user on first launch** and stored in the
  device keystore (`flutter_secure_storage`). Every user runs their own server; there is no
  account and no shared instance.
- **The router gates the whole app**: `routerProvider` redirects every route to `/setup` until
  `isConfiguredProvider` is true, so no screen can fire an unauthenticated request. `main()` is
  `async` and loads the config before `runApp` so that decision is synchronous.
- `apiClientProvider` **watches** `serverConfigProvider` again, so connecting or switching servers
  rebuilds the client and every repository under it.
- Switching servers wipes the drift mirror; rotating the token on the same server does not. See
  [[local-library-mirror]].
- `--dart-define=SERVER_URL/API_TOKEN` survives as a **dev prefill only** for the setup form
  (`AppConfig.devSeedServerUrl`). Nothing reads it after setup, and the release workflow passes
  no defines. Android emulator: `http://10.0.2.2:3000`.

## Navigation

Bottom nav has **3 tabs**: Dashboard (`/`), Library (`/library`, with nested
`title/:id` → Title Details), Backups (`/backups`). These match the four design mockups
(`archive_dashboard`, `library_archive`, `title_details`, `backup_sources`); Settings was never a
design screen and is gone.

## Import UI (M2, 2026-07-18) — Backups screen + live stream

Backs the `backup_sources` mockup. Talks to the server [[import-pipeline]].

```
lib/data/import/
  import_models.dart      # DTOs + sealed ImportEvent (manual fromJson, no codegen)
  import_repository.dart  # importRepositoryProvider (Dio): stage/commit/streamEvents/discard/history
lib/core/sse/sse_parser.dart   # transport-agnostic SSE `data:` frame parser (unit-tested)
lib/features/backups/
  import_controller.dart  # NotifierProvider<ImportController, ImportState> + importHistoryProvider
  backups_screen.dart     # ConsumerWidget, state-driven bento cells
```

- **Flow (state machine `ImportState`):** `Idle → Staging → Review(queue) → Committing(live) →
  Done/Failed`. `pickAndStage()` uses `file_picker` with **`FileType.any`** + `withData:true`, then
  filters to `.tachibk`/`.json` in code — `FileType.custom`+`allowedExtensions` greys `.tachibk`
  files out in Android's document picker (no registered MIME type). Then `POST /imports/stage` per file. `commitAll()` commits each staged import sequentially:
  `POST …/commit` → `jobId` → subscribe `streamEvents(jobId)` and fold each `ImportEvent` into state.
- **SSE over Dio:** `dio.get(responseType: ResponseType.stream)`; byte stream → `utf8.decoder` →
  `parseSseData` (custom parser — handles CRLF, cross-chunk splits, trailing event) → `jsonDecode` →
  `ImportEvent.fromJson`. Dio sends the bearer header (native client, not browser `EventSource`).
- **Live progress cell:** `GlowProgressBar(processed/total)`, phase label, and a **bounded** list
  (last 50) of the most recent `manga` records with NEW/MERGED `StatusChip`s, appearing as events
  arrive. Review + progress lists are `ListView.builder` (smooth at 1000+ titles).
- **DTOs use manual `fromJson`** (no `json_serializable`/build_runner) — small read-only set; M3's
  Library DTOs can revisit. Dep added: `file_picker`.
- Tests: `test/sse_parser_test.dart`, `import_models_test.dart`, `backups_import_test.dart`
  (commitAll fold with a fake scripted stream + widget render of review/progress cells).
- **Android gotcha:** `file_picker`'s `flutter_plugin_android_lifecycle` needs **compileSdk 36**,
  but Flutter 3.44 defaults to 34 and doesn't propagate an app-level bump to plugin modules. Fixed
  by pinning `compileSdk = 36` in `android/app/build.gradle.kts` **and** a
  `subprojects { afterEvaluate { …compileSdkVersion(36) } }` override in `android/build.gradle.kts`
  (registered *before* the `evaluationDependsOn(":app")` block, else Gradle errors "afterEvaluate …
  already evaluated"). Verified with `flutter build apk --debug`.

## Library + Title Details (M3, 2026-07-25)

Backs the `library_archive` and `title_details` mockups. Talks to the [[library-api]] server module.
This is the first screen wired to *browse* imported data — verified against the real 1,228-title DB.

```
lib/data/library/          # library_models.dart + library_repository.dart (query/get/categories)
lib/features/library/      # library_controller.dart (paged Notifier), library_screen.dart (grid)
lib/features/title_details/title_details_screen.dart   # stacked bento cells from mangaDetailsProvider
```

- **Grid:** `library_screen.dart` is a `ConsumerStatefulWidget` — an `AppBar` search toggle, a
  filter-bar `BentoCell` (status chips + sort pill + result count), and a `CustomScrollView` with a
  `SliverGrid` (2 cols, aspect 0.7). Infinite scroll: a `ScrollController` listener calls
  `loadMore()` ~600px from the end (page size 40). Cards are cover-fill + gradient scrim + title/
  status/meta overlay (matches the mockup, *not* the below-cover `MangaCard`). Skeleton grid on
  first load, "no titles match" empty state, retry error state.
- **State:** `LibraryController extends Notifier<LibraryState>` — `build()` schedules the first
  `refresh()`; setters (`setStatus`/`setSort`/`setSearch`, search debounced 300ms in the widget)
  reset to page 0; a **stale-response guard** drops a page whose filters changed mid-flight.
  `mangaDetailsProvider` is a `FutureProvider.family<VaultManga,String>`.
- **Details:** `ListView` of `EntranceFade`-staggered `BentoCell`s — hero cover (with the shared
  Hero), synopsis + genre chips, metadata (author / total chapters / **source**, since the mockup's
  "release year" isn't in our data), reading-progress (`GlowProgressBar` + read/total + informational
  "Continue reading" SnackBar — no in-app reader in v1), and archive history from the title's imports.
- **Covers** land in M4 (see below); before archiving, cells render a placeholder.
- Tests: `library_models_test.dart`, `library_controller_test.dart` (fake repo: refresh/loadMore/
  filter/empty), `library_screen_test.dart` (grid + empty + details widget render; details needs a
  tall test surface since the detail `ListView` builds lazily).

## Covers (M4, 2026-07-25)

Renders and archives cover art. Server side + the full rationale live in [[cover-fetching]].

```
lib/data/covers/           # cover_models.dart + cover_repository.dart (archiveMissing/jobStatus/retry)
lib/features/covers/cover_archive_controller.dart   # Notifier: start → poll (1s) → progressive reload
lib/widgets/archived_cover.dart                     # the one cover widget (auth header + fade-in)
```

- **`ArchivedCover`** replaced the inline `Image.network` in both the grid card and the details hero.
  It uses **`CachedNetworkImage`** over a persistent disk cache (`CoverCache`, `cover_cache.dart` —
  `cached_network_image` + `flutter_cache_manager`), so a cover is fetched **once** and then read from
  disk across restarts/scrolling. It attaches the bearer via `httpHeaders:` (the `/covers/:id` route is
  guarded and the loader isn't Dio), keys the cache by **manga id**, fades in on decode
  (`fadeInDuration` + `kEntranceCurve`), and falls back to the caller's placeholder while
  unarchived / loading / on error. Replaced covers are evicted via `CoverCache.evict(id, url)` (disk +
  memory) in the Title Details re-fetch flow. Deps added: `cached_network_image`, `flutter_cache_manager`.
- **Library:** app-bar **cloud-download** action → `CoverArchiveController.start()` → `POST
  /covers/archive-missing`; a slim **`_CoverBanner`** (`AnimatedSize` slide-in) shows `done/total` +
  `GlowProgressBar`, then the archived/failed summary + dismiss. The controller polls every 1 s and
  calls the new **`LibraryController.reload()`** (in-place re-fetch, no skeleton flash, scroll kept)
  as the archived count climbs — covers appear progressively.
- **Title Details:** **"Re-fetch cover"** app-bar action → `/covers/:id/retry`, evicts the cached
  `NetworkImage`, invalidates `mangaDetailsProvider`, toasts the outcome.
- `LibraryRepository.coverUrl` moved to **`CoverRepository.coverUrl`** (+ `authHeaders`).
- Tests: `cover_models_test.dart`, `cover_archive_controller_test.dart` (fake repos: nothing-missing,
  poll-to-done, dismiss).

## Dashboard (M5, 2026-07-28)

Backs the `archive_dashboard` mockup — the last placeholder screen, now fed from `GET /stats/*`.
Full rationale (including the server aggregates) in [[dashboard-stats]].

```
lib/data/stats/                     # stats_models.dart + stats_repository.dart
lib/features/dashboard/             # dashboard_controller.dart (one snapshot) + dashboard_screen.dart
lib/widgets/progress_ring.dart      # the mockup's animated CustomPaint ring
lib/core/format.dart                # shared formatters (relativeDate moved here from Title Details)
```

- `dashboardProvider` is a `FutureProvider<DashboardData>` that awaits all four `/stats` calls
  together (record `.wait`), so the bento grid appears in one pass; app-bar refresh invalidates it and
  `RefreshIndicator` re-awaits `.future`. Loading/error/empty states are all scrollable so
  pull-to-refresh never dies.
- Cells: hero total-titles → paired Chapters/Covers → reading-progress ring + status mix → backup
  health (staleness dot per source app) → resume-reading shelf → recently-added shelf → vault size.
- **Bento tonal layering (2026-07-28):** `BentoCell` takes an optional `BentoTone` (`low` /
  `mid` / `high` → `surfaceContainerLow` / `surfaceContainer` / `surfaceContainerHigh`). Shared
  `AccentIconWell` (`primaryContainer` + `primary` icon) and `NestedWell` (low surface + light
  border) live in `widgets/bento_cell.dart`. Accents stay sparse — no whole-cell indigo fills.
  Dashboard: hero + reading-progress use `high`; stat/vault cells lead with icon wells; health rows
  sit in nested wells; Aging uses `onTertiaryContainer` (Fresh keeps `secondary`) because the scheme
  maps `secondary` ≡ `tertiary`. Backups CTA / done / history follow the same wells.
- **Manga Neon accents (2026-08-09)** — full page: [[manga-neon-accents]]. Every cell on Dashboard
  and Backups now takes a `VaultAccent` (`theme/app_accents.dart`): a 12% diagonal wash + 28%
  border over the *unchanged* slate surface, with matching icon wells, chips, pills, bars and ring.
  This supersedes the "Aging uses `onTertiaryContainer`" workaround above — health rows are a real
  emerald/amber/rose traffic light now. `accent:` is optional and null renders exactly as before, so
  Library / Title Details / nav were untouched.
- Gotchas worth remembering: `IntrinsicHeight` is required around the paired-cell `Row` (stretch in a
  `ListView` = infinite height), the horizontal shelves size themselves from
  `MediaQuery.textScalerOf` rather than a constant (a hardcoded height overflowed on a device with an
  enlarged system font), shelf taps use `context.go('/library/title/:id')` so the shell switches to
  the Library branch (and shelf covers carry no Hero, which belongs to the grid), and chapter numbers
  must go through `chapterNumberLabel` because Mihon's floats carry float32 noise.
- **Layout overflow is invisible to `flutter test`** — `RenderFlex` reports it from `paint`, so
  `tester.takeException()` stays null while a device throws. Assert rects (`tester.getRect`) for any
  fixed-height layout. Details in [[dashboard-stats]].
- Tests: `format_test.dart`, `stats_models_test.dart`, `dashboard_screen_test.dart`.

## Local library mirror (2026-07-30) — the app reads SQLite, not HTTP

Full rationale in [[local-library-mirror]]; the app-side essentials:

```
lib/data/local/       # drift: tables.dart, app_database.dart, local_library_dao.dart
lib/data/sync/        # sync_models.dart, sync_repository.dart, library_sync_service.dart
lib/features/sync/sync_controller.dart   # SyncState + localRevisionProvider + lastSyncedAtProvider
```

- **`LibraryRepository` and `StatsRepository` are now interfaces**, implemented by
  `LocalLibraryRepository` / `LocalStatsRepository` over drift. Signatures are unchanged, so
  `LibraryController`, `dashboardProvider` and every screen were untouched — only the provider
  bindings moved. `SyncRepository` is the app's **only** network reader for library data.
- **First codegen in the project**: `drift_dev` + `build_runner`, scoped strictly to `lib/data/local/`.
  All DTOs stay manual `fromJson`. Run `dart run build_runner build` after editing `tables.dart`.
- **`sqlite3_flutter_libs` must NOT be a dependency** — `package:sqlite3` 3.x bundles SQLite via
  native assets and the old package is a `+eol` no-op. `flutter pub add drift` pulls it in; remove it.
  Verified `flutter build apk --debug` works with native assets on Flutter 3.44.
- **`localRevisionProvider` is a plain `Notifier<int>`, not a drift stream.** The sync service is the
  only writer and runs in this isolate, so a database watch bought nothing and dragged a live drift
  subscription into every widget tree — which opened real DB files in tests and left pending timers.
  It's bumped per committed sync page; controllers `ref.watch`/`ref.listen` it.
- **Every test must use `AppDatabase.memory()`** and override `appDatabaseProvider`. A test that
  doesn't will silently open a file-backed DB (and trip drift's multiple-instance warning).
  `backups_import_test` also stubs `syncControllerProvider`, otherwise `commitAll()` fires a real
  network sync at the compiled-in `SERVER_URL`.
- **Library screen** gained a `RefreshIndicator` (pull-to-refresh syncs), a `_SyncBanner` mirroring
  `_CoverBanner`, and a first-run `bootstrap()` in `initState`. The `CustomScrollView` needs
  `AlwaysScrollableScrollPhysics` so the pull works on an empty library.

### Filters moved to a bottom sheet (2026-07-30)

The inline filter bar (status chips + sort pill + favourites toggle + counts) **overflowed
horizontally** once a "Synced …" label joined it — reported from a real device at a 347pt row width,
and reproducible at a 1.6× text scale. Rather than keep squeezing a five-element `Row`, the filters
moved out:

```
lib/features/library/library_filter_sheet.dart
  showLibraryFilterSheet(context)   # status · show (favorites/others) · sort by · reset
  hasActiveFilters(filters)         # drives the app-bar badge
  kLibraryBranchIndex = 1
```

- **Two entry points:** the app bar's `Icons.tune` action (badged when filters are non-default,
  since they're now off-screen), and **re-tapping the Library tab** — `AppShell` intercepts a
  re-select and opens the sheet, but only when already at `/library`, so re-tapping from Title
  Details still just pops back to the grid.
- The screen keeps one quiet `_MetaLine` above the grid: `"1,234 favorites · hiatus · synced 5m ago"`.
  It is a **single `Text`** with `maxLines: 1` + ellipsis — a lone Text cannot overflow a Row, which
  is the structural fix rather than another round of `Flexible` tuning.
- `LibraryController.resetFilters()` returns status/favorite/sort to defaults while keeping the
  search term (typed separately from the sheet).
- Deleted from `library_screen.dart`: `_FilterChipButton`, `_SortPill`, `_FavoriteToggle`,
  `_SortSheet` (the old sort-only sheet). `labelForStatus` stays — dashboard and title details
  import it.
- **Testing overflow:** widget tests do not fail on `RenderFlex` overflow, and an overflowing Row
  still reports the *constrained* size — so `test/library_filter_bar_test.dart` measures the
  **children's** rects against the screen at 320pt and 1.6× scale. Writing `SyncMeta` in a test must
  use `update().write()` (the service's own path); `insertOnConflictUpdate` against the seeded
  singleton silently does not persist the field.

## Library options, sources, display & delete (2026-07-31)

The filter sheet grew into the library's whole control surface, and the grid gained multi-select with
a destructive action. Server side of the delete is in [[library-api]]; the mirror side in
[[local-library-mirror]].

```
lib/features/library/
  library_filter_sheet.dart   # LibraryOptionsSheet — FILTER · SORT · DISPLAY tabs
  library_display.dart        # LibraryDisplay + LibraryDisplayController (shared_preferences)
  library_selection.dart      # LibrarySelection(+Controller) + TitleDeleter
lib/data/library/library_write_repository.dart   # the app's ONLY vault mutation path
```

- **Three tabs, not one column.** A single scrolling sheet worked for status+sort, but a 25-row source
  list would bury the sort options under it. `TabBarView` over a **fixed** body height
  (`0.55 × screen`, clamped 300–520) so the sheet doesn't resize as you switch tabs.
- **Source filter** (`LibraryFilters.sourceIds`, multi-select) comes from
  `LocalLibraryDao.sources()` — `GROUP BY source_id` over the mirror, busiest first, with counts.
  Deliberately *not* the server's `known_source` registry: the filter should only offer sources you
  actually hold titles from. Counts are whole-library, so the list doesn't shift while you pick from
  it. A filter box appears past 8 sources.
  **Unnamed sources show their numeric id** (`sourceLabel(name, id)` in `library_models.dart`, used by
  the card, the list row, the source picker and Title Details) — several backups carry
  `source_name = ''`, and a blank chip is unusable. `MAX(source_name)` in the group-by means any
  non-empty spelling wins over `''` for the same id. `VaultManga` gained `sourceId` for this.
- **Sort now reverses**: tapping the *active* field flips `sortDir` instead of re-applying it, so
  `LibrarySort.isActive` (field only) drives the UI while `matches` (field+dir) stays for exact checks.
- **Display options** — layout (`comfortable` / `compact` / `list`), column count per grid layout
  (2–3 comfortable, 3–5 compact), unread badge, source name. Persisted in **`shared_preferences`**,
  re-added as a dependency for this: these are device-local UI prefs and CLAUDE.md forbids putting
  anything the server doesn't own into the mirror. Load and save are best-effort (a missing plugin
  leaves the defaults, which is also why widget tests need no stub).
- **Multi-select**: long-press enters (with `HapticFeedback` — `Pressable` gained `onLongPress`), tap
  toggles while active, a contextual `AppBar` replaces the normal one with the count, select-all/none
  over the *loaded* items, and `PopScope` makes back exit the selection instead of the screen.
  `clear()` keeps selection mode; only `exit()` leaves it, so deselecting the last card doesn't yank
  the toolbar away mid-gesture.
- **Delete** is confirmed in a dialog (irreversible: chapters, progress and covers), disables its own
  button while in flight, and reports the outcome in a SnackBar. Also on Title Details for one title
  (pops the route first — the screen reads a record that no longer exists).
- **Gotcha:** `CoverCache.evict` **never completes under `flutter_test`** (flutter_cache_manager's
  store waits on a platform channel), so awaiting it inside the delete hung `pumpAndSettle` forever.
  Eviction is now fire-and-forget (`unawaited(... .catchError(...))`) — correct in production too:
  opportunistic local cleanup must not hold up a delete the server already committed.
- Tests: `library_selection_test.dart` (controller + widget: long-press, toggle, select-none, confirm
  →delete→card gone→SnackBar, failure keeps the selection), sheet tests in `library_filter_bar_test`
  (tabs, source names/id fallback, sort reversal, layout switch), `local_library_dao_test`
  (`sources()` grouping + id fallback, `deleteTitles` idempotence), `library_controller_test`
  (`toggleSource`, sort reversal, `removeItems`).

## Backup source apps (2026-08-02)

Which reading app each backup came from — shown at import, and a library filter. Full design in
[[backup-apps]]; the app-side essentials:

```
lib/data/backup_apps/        # backup_app_models.dart (+ backupAppLabel) + backup_apps_repository.dart
lib/features/backups/source_app_sheet.dart   # showSourceAppSheet → Future<String?>
lib/widgets/selectable_chip.dart             # SelectableChip, promoted out of the filter sheet
```

- **`ImportNeedsApp{queue, index}`** is a new `ImportState`, not a callback — the controller is a
  `Notifier` with no `BuildContext` and the screen already renders from the sealed union.
  `_NeedsAppCell` auto-opens the sheet once per staged id (post-frame guard); dismissing leaves the
  cell with a "Choose app" button so a back-swipe can't strand the import.
- **Routing resumes at `index + 1`.** Skipping tags the file `''`, so rescanning the queue from the
  start would re-ask it forever. Pinned by a test.
- `backupAppsProvider` reads the **network** (the picker offers apps you hold no titles from yet);
  `libraryAppsProvider` / `backupAppNamesProvider` read the **mirror**, so the filter and every place
  a backup's app is displayed work offline.
- Filter sheet gained a **FROM APP** chip section; `LibraryFilters.sourceApps` had to be threaded
  through all five lockstep sites, `_sameFilters` included.

## Animations (M3) — subtle, design-aligned

The mockups define the motion language (bento cells fade-up staggered on `cubic-bezier(0.22,1,0.36,1)`,
`active:scale-95` press feedback, `duration-1000` progress fills). Implemented as reusable widgets:

- `widgets/entrance_fade.dart` — **`EntranceFade`**: one-shot fade + slide-up, `kEntranceCurve =
  Cubic(0.22,1,0.36,1)`. Honors reduce-motion (`MediaQuery.disableAnimations` → snaps to final
  frame). Grid cards stagger by column and animate **once per id** (`_animated` Set), so scrolling
  back up doesn't replay; detail cells stagger by index (70ms).
- `widgets/pressable.dart` — **`Pressable`**: `AnimatedScale` press-in (0.97, fast down / gentle up).
- **Hero shared element** — cover tag `manga-cover-<id>` grid card → details, with a **fade route
  transition** for the details page (`router.dart` `CustomTransitionPage`) so the platform slide
  doesn't fight the Hero.
- `widgets/glow_progress_bar.dart` — now animates its fill via `TweenAnimationBuilder` (also smooths
  live import progress on the Backups screen).

## About & in-app updates (2026-08-09)

Full page: [[app-updates]]. App-side essentials:

- The app is now **Manga Vault** (display name only — Dart package and `applicationId` unchanged)
  at version `1.0.0+1`, shipped as an APK on GitHub Releases.
- **Navigation gained a nested route, not a tab.** `/about` sits under the Dashboard branch,
  reached from a badged info action in its app bar (`AboutAction`). Bottom nav stays at 3 tabs and
  Settings is still deliberately absent — About talks about the *app*, not the library.
- `lib/data/updates/` + `lib/features/updates/` hold the whole lifecycle; `UpdateController` is a
  `Notifier` over a sealed `UpdateState` (idle → checking → upToDate | available → downloading →
  ready → installed).
- **`main.dart` now owns an explicit `ProviderContainer`** and fires the throttled `autoCheck()`
  after the first frame. Deliberate: a check wired into the widget tree would fire a real GitHub
  request in every widget test that pumps a screen.
- The dashboard's welcome slot now holds `[_WelcomeBlock, UpdateBanner]` in one `Column` — the
  banner is absent most of the time and its own list entry would leave a gutter-sized hole.
- **Gotcha:** `(a, b).wait` on a record wraps failures in `ParallelWaitError`, silently discarding
  a typed exception. It cost the updater its error messages until `check()` was made sequential.
- **Gotcha:** any test that touches `shared_preferences` needs
  `SharedPreferences.setMockInitialValues({})` in `setUp`. Without it `getInstance()` waits on a
  platform channel that a widget test's fake clock never services — the suite *hangs* rather than
  failing.
- Tests: `update_models_test.dart` (semver, the changelog parser, a round-trip against the real
  `CHANGELOG.md`), `update_controller_test.dart` (fake repo + installer, plus a height-invariance
  test for the downloading cell), `about_screen_test.dart`.

## Removed / deferred

- `shared_preferences` dependency removed (only the settings module used it). The M2 "move token
  to flutter_secure_storage" to-do is moot — no token is stored on-device; it's compiled in.
- Deferred on the Backups screen (out of M2): Active Sources / Storage / Cloud Sync cells
  (cloud sync is past-v1 per CLAUDE.md). Storage/vault size landed on the **Dashboard** in M5
  ([[dashboard-stats]]); the storage *breakdown* and integrity report are M6.
- `backups_screen.dart` still has its own private `_relativeDate`; it can fold into
  `core/format.dart` next time that file is touched.
