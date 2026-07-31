# Cover fetching & archiving (server + app)

Created: 2026-07-25 (M4)

Related: [[index]] · [[backend]] · [[library-api]] · [[flutter-app]] · [[tachibk-format]] ·
[[local-library-mirror]]

> **2026-07-30:** cover-state writes now go through `CoverService.updateCover`, which wraps the row
> update in `withSyncLock` so concurrent archive workers can't break the sync cursor's ordering
> ([[local-library-mirror]]). The image disk cache (`CoverCache`) is unchanged and independent of the
> metadata mirror.

The read side ([[library-api]]) surfaces titles; **M4 archives their cover images** so the app shows
real art instead of placeholders. Thumbnail URLs rot, so covers are pulled into permanent local
storage at import-adjacent time and the **archived file** (never the remote URL) is what the app
renders. Server module: `server/src/modules/covers/`.

## Endpoints (`/api/v1/covers`, all bearer-guarded)

| Endpoint | Method | Purpose |
|---|---|---|
| `/covers/archive-missing` | POST | Start (or join) the background job archiving every missing cover → `{ jobId, total, alreadyRunning }` |
| `/covers/jobs` | GET | Recent runs, newest first (20) → `CoverJobDto[]` |
| `/covers/jobs/active` | GET | The run in progress, or `null` — lets a client adopt a run it didn't start |
| `/covers/jobs/:jobId` | GET | Poll one run → `CoverJobDto` |
| `/covers/jobs/:jobId/cancel` | POST | Ask a running job to stop → `CoverJobDto` |
| `/covers/:mangaId/retry` | POST | Archive/re-archive one title's cover synchronously → `CoverResult` |
| `/covers/:mangaId/custom` | PUT (multipart `file`) | Replace with a user-uploaded image → `CoverResult` |
| `/covers/:mangaId` | GET | Serve the archived image (`StreamableFile`, `Cache-Control: private, max-age=86400`); **404 until archived** |

**Route order is load-bearing:** the `jobs*` routes must be declared *before* `:mangaId`, or
`ParseUUIDPipe` rejects `active` / `jobs` as a malformed manga id.

## The fetcher (`cover.fetcher.ts`, pure, unit-tested)

`CoverFetcher.fetch(url, hint?)` — Node 22's **global `fetch`** (undici), no new dependency.
Modelled on Mihon's `MangaCoverFetcher` + `HttpSource`/`NetworkHelper` (read from the reference clone):

- **Mihon's *mobile* default User-Agent** (`NetworkPreferences.kt`:
  `…Android 10; K…Chrome/141.0.0.0 Mobile Safari/537.36`) — **not** a desktop UA. Source CDNs
  fingerprint the Mihon UA; a desktop string gets blocked by some. This alone flipped AsuraScans from
  a connection-level `fetch failed` to a real HTTP response.
- **`Referer` = the source *site* origin**, i.e. the **registrable domain** of the thumbnail host
  (`gg.asuracomic.net` → `https://asuracomic.net/`), which is what a browser loading an `<img>` sends —
  not the CDN sub-domain. Bare domains / IPs fall back to the thumbnail origin. Plus browser-like
  `Accept` / `Accept-Language` / `Sec-Fetch-*` image headers. (Mihon's *default* `headersBuilder()` only
  sets the UA; per-site Referer/headers live in each extension — which we don't have, hence the
  registrable-domain heuristic.)
- **Per-source overrides** via `known_source.fetch_hint` (`{ referer?, userAgent? }`) are the escape
  hatch for a site that needs something specific — they win over the defaults.
- **Validates by sniffing the bytes** (`image-sniff.ts`), not the claimed `Content-Type` — a host lying
  with an HTML error page under `image/jpeg` won't poison the archive.
- **`AbortController` timeout** (30s, matching Mihon's OkHttp), **exponential-backoff retries** with
  jitter. Retriability is **explicit** on `CoverFetchError.retriable`: transient HTTP (408/425/429/5xx)
  and network/abort errors retry; a 200 with a bad body (non-image/empty/oversized) **and a plain
  4xx like 403 do not** — the host answered, it just refused. (So a hotlink 403 fails fast, one attempt.)
- **URL fragments are stripped** (`#image-request` etc. — client-side only).
- **Failure cause is surfaced**: Node's `fetch` throws `TypeError: fetch failed` with the real reason
  (`ECONNRESET`, `UND_ERR_*`, TLS, DNS…) buried in `.cause`; `describeCause()` unwraps it into the
  logged/returned error so failures are diagnosable instead of a uniform "fetch failed".
- Config via env (module factory): `COVER_FETCH_TIMEOUT_MS` (30s), `COVER_MAX_BYTES` (15 MB),
  `COVER_MAX_ATTEMPTS` (3), `COVER_USER_AGENT`.

### All cover env vars

| Var | Default | Effect |
|---|---|---|
| `COVER_CONCURRENCY` | 6 | Global in-flight downloads per run |
| `COVER_PER_HOST` | 2 | In-flight downloads against any one host |
| `COVER_FETCH_TIMEOUT_MS` | 30000 | Per-attempt abort timeout |
| `COVER_MAX_BYTES` | 15 MB | Rejects oversized bodies |
| `COVER_MAX_ATTEMPTS` | 3 | Retries for *retriable* failures only |
| `COVER_USER_AGENT` | Mihon mobile UA | Overrides the default UA |
| `COVER_AUTO_ARCHIVE` | `true` | `false` disables the post-import run and the boot resume |

### Why some covers still can't be archived (the Cloudflare ceiling)

Sources behind **Cloudflare bot protection** (AsuraScans / `gg.asuracomic.net`, and similar) block
non-browser clients by **TLS/JS fingerprint** — a `fetch failed` (connection reset) or a `403` that no
header combination fixes (verified: even `curl` gets `000` to that host). Mihon only clears these with
its on-device **`CloudflareInterceptor` (a WebView)** — see `NetworkHelper.kt`; the request rides the
source's OkHttp client with that interceptor + a persistent cookie jar + Brotli. We have **no WebView
and no per-source extension**, so those covers stay `failed` and render the placeholder. Options if it
ever matters: seed a `fetch_hint` for a source that just needs a specific header, or (heavy, out of
scope) route hard sources through a headless browser / FlareSolverr-style solver.

### What Mihon's *extensions* contribute to a cover fetch (2026-07-31, read from the clone)

Confirmed in `MangaCoverFetcher.kt`: the cover **URL** never comes from the extension at render time —
it's `manga.thumbnail_url`, i.e. exactly what `.tachibk` carries ([[tachibk-format]]). But the
**request** rides the extension: `sourceManager.get(manga.source) as? HttpSource` supplies both the
OkHttp `client` (:173) and `headers` (:186). That gives Mihon per-site `Referer`/UA/auth from the
extension's `headersBuilder()`, its interceptors (rate limit, image-proxy rewrites that read `#fragments`
off the thumbnail URL), and the `NetworkHelper.client` chain (`CloudflareInterceptor` + cookie jar +
Brotli + DoH). With the extension **not installed** the cast yields null and even Mihon falls back to a
plain headerless client. Extensions also refresh a rotted `thumbnail_url` via `getMangaDetails()`
(`UpdateManga.kt:57,69`) — we can't, so ours is frozen at backup time.

Consequences for us: `fetch_hint` is our manual stand-in for `headersBuilder()`; our fragment stripping
is safe but makes fragment-encoded proxy URLs unrecoverable; and the Cloudflare ceiling above is
structural, not a header we haven't guessed yet.

## Orchestration (`cover.service.ts`) — a durable background job (2026-07-31)

A bulk run is **minutes to hours** of work (one HTTP fetch per title, thousands of titles), so it is
a job that outlives the request, the poll, the client, and the process.

- **`archiveMissing(opts)`** selects candidates with a non-empty `thumbnail_url` across the **whole
  DB**, writes a `cover_job` row, and runs in the background via `setImmediate`. Covers download
  through `runPool` (`concurrency.ts`): a **global cap** (`COVER_CONCURRENCY`, 6) **and a per-host
  cap** (`COVER_PER_HOST`, 2) — throughput across hosts, politeness to any one. A thrown worker is
  swallowed so one bad cover never sinks the batch.
- **One run at a time**, guarded three ways: a live-job check, a `pendingStart` promise covering the
  await between "decided to start" and "row exists" (without it two triggers in that gap each start a
  run and every cover is fetched twice), and the partial unique index `uq_cover_job_running` in
  Postgres. A second trigger **joins** (`alreadyRunning: true`).
- **Cancellable.** `POST /covers/jobs/:id/cancel` aborts an `AbortSignal` threaded into `runPool`,
  which **stops dispatching but lets in-flight downloads finish** — a cancelled cover is never left
  half-written. Untried covers stay `none` and are picked up by the next run.
- **Resumed on boot.** `onApplicationBootstrap` closes any row still marked `running` (its process is
  gone) as **`interrupted`** and starts a fresh `resume` run.
- **Storage:** `writeCoverFile` writes `STORAGE_DIR/covers/<mangaId>.<ext>`; `cover_path` stores the
  **relative** path with forward slashes (portable), `cover_state='archived'`. A previous file with a
  different extension is unlinked. On failure `cover_state='failed'` (no path) → picked up again next
  run / by retry.
- **`resolveCoverFile`** (for serving) returns the abs path + mime only when `archived` and the file
  `stat`s; otherwise the controller 404s.
- **`deleteCoverFiles(relPaths)`** (added 2026-07-31) unlinks archived covers when their titles are
  deleted — `manga.cover_path` is the only pointer to the file, so it has to go with the row. Missing
  files are not an error. Called by `LibraryService.deleteMany` ([[library-api]]), which is why
  `LibraryModule` imports `CoverModule`.
- `cover_state` enum is `none|pending|archived|failed`; **`pending` is intentionally unused** — rows
  stay `none` until they resolve, so a server restart mid-run leaves them re-archivable (a stuck
  `pending` would be skipped by the candidate query).

### What starts a run

| Trigger | Scope | Started by |
|---|---|---|
| `manual` | `none` + `failed` | The Library screen's cloud-download action (`POST /archive-missing`) |
| `import` | `none` **only** | `CoverService.archiveAfterImport()`, called by [[import-pipeline]] after a successful commit |
| `resume` | `none` + `failed` **not already tried in the interrupted run** | `onApplicationBootstrap` |

`retryFailed` is the axis: a **manual** run means "try again, including the ones that failed", an
**automatic** one must not re-hammer a source that can't be fetched at all (the Cloudflare cases
below would otherwise be retried on every single import).

**`COVER_AUTO_ARCHIVE=false`** turns both automatic triggers into no-ops, leaving only the explicit
endpoint. Every e2e sets it (`test/setup-e2e.ts`) — booting `AppModule` against the dev database
would otherwise download the whole library from the real internet.

### `manga.cover_failed_at` — why resume needs it

A resumed run re-derives its candidates from `cover_state`; nothing stores which titles the dead run
had reached. Covers it *archived* are simply no longer candidates, but covers it **failed** look
identical to ones that failed weeks ago, so the resume would re-attempt every one of them (mostly the
permanently-blocked hosts). Stamping the failure time makes "already tried during this run"
expressible as `cover_failed_at < job.started_at`, without a row per candidate. Cleared to null when
a cover archives.

### An import landing mid-run

The running job took its candidate list before those titles existed, so joining it would silently
drop them. `archiveAfterImport` therefore sets `rerunAfterCurrent`, and `runArchive` starts a fresh
`import` pass on its way out — **unless the run was cancelled**, since someone who pressed Stop does
not want it starting again by itself.

### `CoverJobStore` (`cover-job.store.ts`)

Live counters in memory, **flushed to the `cover_job` row on a throttle** (every 1 s or 25 covers,
whichever first) — a 2,000-cover run would otherwise issue 2,000 extra row updates competing with the
library's own writes and the sync lock, to serve a client that polls once a second. `record()` is
deliberately synchronous (it runs in every pool worker) and a failed flush is logged, never thrown:
losing a checkpoint costs one stale poll and must not sink the run producing the real work. Status
reads prefer memory (always at least as fresh) and fall back to the row for finished or pre-restart
jobs. Still **poll-based**, no SSE like the import pipeline.

## Serving + the auth gotcha

`GET /covers/:mangaId` is **guarded like every route** (cover UUIDs are unguessable, but the token
still gates it). Flutter's `Image.network` uses its **own** HTTP client (not Dio), so it must pass the
bearer explicitly — `Image.network(url, headers: CoverRepository.authHeaders)`. This is why covers
aren't `@Public()`.

## App wiring (M4)

```
lib/data/covers/            # cover_models.dart + cover_repository.dart + cover_cache.dart
lib/features/covers/cover_archive_controller.dart   # Notifier: start → poll → progressive reload
lib/widgets/archived_cover.dart                     # CachedNetworkImage (disk cache) + fade-in + placeholder
```

- **`ArchivedCover`** is the single cover widget used by the grid card and the details hero. It uses
  **`CachedNetworkImage`** (package `cached_network_image` + `flutter_cache_manager`) with a dedicated
  **persistent disk cache** — `CoverCache.manager` (`lib/data/covers/cover_cache.dart`, key
  `mangavault_covers`, 180-day stale period, 5000 objects) — so a cover is fetched from the server
  **once** and then read from disk across restarts and grid scrolling (no more re-fetch per view).
  It attaches `authHeaders` (the serve route is guarded and the image loader isn't Dio), keys the cache
  by **manga id** (stable even if the compiled-in `SERVER_URL` changes), fades in on decode
  (`fadeInDuration` + `kEntranceCurve`), and falls back to the screen's placeholder while
  unarchived / loading / on error — identical layout either way.
- **Library screen:** an app-bar **cloud-download action** starts `archive-missing`; a slim
  **`_CoverBanner`** (`AnimatedSize` slide-in) shows live `done/total` + a `GlowProgressBar`, then the
  archived/failed summary with a dismiss button. The controller **polls every 1 s** and calls
  `LibraryController.reload()` (new: in-place re-fetch, **no skeleton flash**, scroll kept) whenever the
  archived count advances, so covers pop in progressively.
- **Adopting a server-side run (2026-07-31):** `CoverArchiveController.adopt()` runs from the Library
  screen's `initState` and calls `GET /covers/jobs/active`. Because runs are durable and can be
  started by the server itself, the app must show one it never asked for — otherwise an import- or
  boot-triggered run is invisible and covers appear "by magic" with no progress. `adopt()` is
  **opportunistic and silent**: no active run, or a failed call, leaves the banner idle rather than
  putting an error in front of someone who just opened a screen.
- **Stopping:** the running banner carries a **Stop** button (`cancel()`), which shows *Stopping…*
  while in-flight downloads drain, then a `Stopped · N archived` summary with a **Resume** action.
  The banner title reads *Downloading new covers* when `trigger != 'manual'`, so a run the user
  didn't start is labelled as such.
- **Title Details:** a **"Re-fetch cover"** app-bar action calls `/covers/:id/retry`, evicts any cached
  `NetworkImage`, invalidates `mangaDetailsProvider`, and toasts the outcome.

## Tests

- Unit: `image-sniff.spec`, `cover.fetcher.spec` (mock global fetch: UA/Referer, retry-then-succeed,
  hard-403 no-retry, non-image rejected, size cap, invalid URL), `concurrency.spec` (global + per-host
  caps, throw-safe, **abort stops dispatch but every started item completes**, already-aborted signal
  does nothing), `cover.service.spec` (mocked DS/repo/fetcher + an in-memory `cover_job` repo:
  archives + marks failed + stamps `cover_failed_at`, single-run guard, **concurrent-start guard**,
  empty set, **cancel**, `retryFailed:false` SQL scope, **boot resume with `failedSince`**,
  **mid-run import queues a follow-up pass**, `COVER_AUTO_ARCHIVE=false`).
- E2e `test/covers.e2e-spec.ts`: a **local in-process HTTP CDN** (one path serves a PNG, one 403s),
  seeds run-unique titles, then `retry` → `GET /covers/:id` (bytes + content-type) → failed→404 →
  custom upload → 404/400/401, plus a **durable-jobs** block (real `cover_job` rows: active → status →
  cancel → history, reclaim-as-interrupted, 404/401). Uses a temp `STORAGE_DIR`.
- App: `cover_models_test`, `cover_archive_controller_test` (fake repos: nothing-missing,
  poll-to-done, dismiss, **adopt a server-started run**, **adopt silent when idle**, **cancel**).

## Gotchas / notes

- **Never call `archive-missing` in an e2e / against the shared DB casually** — it scans the *whole*
  library and fetches every real cover from the internet. The e2e covers the pipeline via scoped
  single-title `retry`; `archiveMissing` orchestration is covered by the mocked service unit test.
  Since runs became automatic this is no longer only about calling the endpoint: **any e2e booting
  `AppModule` would trigger one** (post-import, or a boot resume of a leftover `running` row), which
  is why `test/setup-e2e.ts` sets `COVER_AUTO_ARCHIVE=false` for every suite. A test that inserts a
  `cover_job` row **must delete it** — a stray `running` row makes the *next* boot resume it.
- Real covers can be **large** (verified: the One Piece MangaDex cover is an ~8 MB PNG — under the
  15 MB cap). 2000 titles → plan for a few GB of `covers/`.
- **Cache-busting:** the serve URL is stable (`/covers/:id`) and the on-device cache is keyed by manga
  id, so a *replaced* cover (custom/re-fetch) must be **explicitly evicted** — `CoverCache.evict(id, url)`
  drops it from both the disk cache and Flutter's decoded-image cache, wired into the Title Details
  re-fetch flow. The first-time `none→archived` case has nothing cached to bust. No per-cover version
  param is exposed (list/detail DTOs carry no cover version) — revisit if in-place replacement needs to
  invalidate the grid on other devices too.
- **Verified end-to-end against the real DB** (2026-07-25): retried 3 real covers (One Piece, Tales of
  Demons and Gods) → `archived`; served with `image/png` + cache header; 404/401 correct; list
  `coverState` flipped to `archived`.

## Cover storage profile — re-encoding (2026-07-31)

Covers were the vault's real weight: **613 MB across 1,121 files** against 83 MB of Postgres, with
JPEG averaging 661 KB, PNG averaging 1.8 MB and a 14 MB outlier at 2894×3858 — print resolution for
something a phone draws at ~600 px in the grid and ~1,100 px on the details hero. This was
[[deleted-titles]]'s "where the space actually goes" question, answered.

**`cover.optimizer.ts`** owns the storage profile: **WebP q80, longest edge 1600 px, effort 4**, and
it only replaces a file when the result is **under 90%** of the original. It runs in two places, which
is why the profile lives in its own class rather than in either of them:

- **On ingest** — `CoverService.encodeForStorage`, used by both the archive path and custom uploads,
  so the archive can't re-accumulate full-resolution originals. Best-effort: anything it can't decode,
  can't encode, or can't shrink is stored exactly as fetched. Archiving the cover at all matters far
  more than archiving it small.
- **`npm run covers:optimize`** (`scripts/optimize-covers.ts`) for the existing backlog. **Dry run by
  default** — it is lossy and irreversible, so `--apply` is explicit and originals move to
  `storage/covers-original/` unless `--no-backup`. Order is write-new → repoint row → retire old, so
  `cover_path` never points at something absent. Path updates are batched 100 at a time under the
  sync advisory lock ([[local-library-mirror]]).

Env overrides: `COVER_MAX_EDGE`, `COVER_QUALITY`, `COVER_ENCODE_EFFORT` (`optimizerOptionsFromEnv`,
shared by the module factory and the script so the two can't drift).

### Result, applied to the real archive

| source | files | before | after | saved |
|---|---|---|---|---|
| jpeg | 711 | 459 MB | 90.7 MB | 80% |
| png | 55 | 97.4 MB | 5.8 MB | 94% |
| webp | 353 | 48.3 MB | 27.1 MB | 44% |
| gif | 2 | 8.3 MB | 2.7 MB | 67% |
| **total** | **1,121** | **613 MB** | **126 MB** | **79.4%** |

560 re-encoded, 561 left alone (310 already optimal, 249 not worth it). Verified afterwards: all
1,121 `cover_path`s resolve to a real file. Before/after crops compared at native resolution were
visually indistinguishable.

### Gotchas found doing it

- **Animated covers**: sharp must be given `{ animated: true }` on read *and* the encode, or it
  silently writes only the first frame. Verified on a real 50-frame GIF (8.2 MB → 2.7 MB, 50 pages
  kept). A synthetic 1×1 2-frame GIF is **not** a usable fixture — libvips flattens it — so the unit
  test pins the metadata handling and the frame preservation was checked against real data.
- **Frame-height reporting**: sharp presents an animated image as a vertically stacked strip, so
  `metadata().height` is `frames × frameHeight`. Without using `pageHeight`, every animated cover
  looks N× too tall and gets pointlessly resized.
- **Two covers in the archive are corrupt** — truncated 1 KB files that no decoder can read:
  `0f55442e-…jpg` (Monster Eater) and `530659d2-…png` (Regression of the Third Prince), both from
  AllManga. They are `cover_state = 'archived'` but unrenderable. The optimizer left them untouched
  (it never replaces what it can't decode); re-fetching those two titles is the fix.
- Devices keep their cached copies until eviction — the archive shrank, the phones don't re-download.
