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
| `/covers/jobs/:jobId` | GET | Poll progress → `{ total, done, archived, failed, skipped, finished }` |
| `/covers/:mangaId/retry` | POST | Archive/re-archive one title's cover synchronously → `CoverResult` |
| `/covers/:mangaId/custom` | PUT (multipart `file`) | Replace with a user-uploaded image → `CoverResult` |
| `/covers/:mangaId` | GET | Serve the archived image (`StreamableFile`, `Cache-Control: private, max-age=86400`); **404 until archived** |

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

## Orchestration (`cover.service.ts`)

- **`archiveMissing`** selects `cover_state IN ('none','failed')` with a non-empty `thumbnail_url`
  across the **whole DB**, creates a poll job, and runs in the background via `setImmediate`.
  A `activeJobId` guard means a second trigger **joins** the running job (`alreadyRunning:true`)
  rather than double-fetching. Covers download through `runPool` (`concurrency.ts`): a **global cap**
  (`COVER_CONCURRENCY`, 6) **and a per-host cap** (`COVER_PER_HOST`, 2) — throughput across hosts,
  politeness to any one. A thrown worker is swallowed so one bad cover never sinks the batch.
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
- **Job registry** (`cover-job.registry.ts`) is **poll-based** (counters only — no SSE like the import
  pipeline), TTL-evicted 10 min after finishing.
- `cover_state` enum is `none|pending|archived|failed`; **`pending` is intentionally unused** — rows
  stay `none` until they resolve, so a server restart mid-run leaves them re-archivable (a stuck
  `pending` would be skipped by the candidate query).

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
- **Title Details:** a **"Re-fetch cover"** app-bar action calls `/covers/:id/retry`, evicts any cached
  `NetworkImage`, invalidates `mangaDetailsProvider`, and toasts the outcome.

## Tests

- Unit: `image-sniff.spec`, `cover.fetcher.spec` (mock global fetch: UA/Referer, retry-then-succeed,
  hard-403 no-retry, non-image rejected, size cap, invalid URL), `concurrency.spec` (global + per-host
  caps, throw-safe), `cover.service.spec` (mocked DS/repo/fetcher: archives + marks failed + writes
  files, single-run guard, empty set).
- E2e `test/covers.e2e-spec.ts`: a **local in-process HTTP CDN** (one path serves a PNG, one 403s),
  seeds run-unique titles, then `retry` → `GET /covers/:id` (bytes + content-type) → failed→404 →
  custom upload → 404/400/401. Uses a temp `STORAGE_DIR`.
- App: `cover_models_test`, `cover_archive_controller_test` (fake repos: nothing-missing, poll-to-done,
  dismiss).

## Gotchas / notes

- **Never call `archive-missing` in an e2e / against the shared DB casually** — it scans the *whole*
  library and fetches every real cover from the internet. The e2e covers the pipeline via scoped
  single-title `retry`; `archiveMissing` orchestration is covered by the mocked service unit test.
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
