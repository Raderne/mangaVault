# Flutter App

Created: 2026-07-18

Related: [[index]] · [[backend]]

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
  features/<screen>/            # dashboard, library, title_details, backups
app/config/
  dev.json                      # git-ignored: real LAN URL + API token
  dev.example.json              # committed template
```

## Server connection (decided 2026-07-18)

- **No in-app connection settings.** The old Settings tab (server URL + token text fields backed
  by `shared_preferences`) was removed entirely — the `server/` backend is the single source of
  truth, baked in at **build time**.
- `core/config/app_config.dart` reads `String.fromEnvironment('SERVER_URL')` (default
  `http://192.168.1.12:3000` — this dev machine's LAN IP, so a physical device on the same Wi-Fi
  works out of the box) and `String.fromEnvironment('API_TOKEN')`.
- Supply real values via `flutter run --dart-define-from-file=config/dev.json`. `config/dev.json`
  holds the token and is git-ignored; `config/dev.example.json` is the committed template. The
  token must match the server's `API_TOKEN` env var (see [[backend]] auth guard).
- `apiClientProvider` builds a Dio with `baseUrl = '${AppConfig.baseUrl}/api/v1'` and, when a
  token is set, an `Authorization: Bearer <token>` header. It no longer watches any provider —
  config is constant, so the client is constructed once.
- Android emulator alternative: set `SERVER_URL` to `http://10.0.2.2:3000` in the config file.

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
- **Covers are placeholders** until M4: `LibraryRepository.coverUrl` returns null unless
  `coverState=='archived'`.
- Tests: `library_models_test.dart`, `library_controller_test.dart` (fake repo: refresh/loadMore/
  filter/empty), `library_screen_test.dart` (grid + empty + details widget render; details needs a
  tall test surface since the detail `ListView` builds lazily).

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

## Removed / deferred

- `shared_preferences` dependency removed (only the settings module used it). The M2 "move token
  to flutter_secure_storage" to-do is moot — no token is stored on-device; it's compiled in.
- Deferred on the Backups screen (out of M2): Active Sources / Storage / Cloud Sync cells
  (cloud sync is past-v1 per CLAUDE.md; storage stats are M5).
