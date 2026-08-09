# Server Connection

Created: 2026-08-09

Related: [[index]] · [[flutter-app]] · [[backend]] · [[app-updates]] · [[local-library-mirror]]

How the app learns which server it belongs to. **This reverses the 2026-07-18 "compiled in at
build time" decision** — see the section at the bottom for why.

## The rule

The server address and API token are **runtime state entered by the user**, never build-time
constants. The app ships as a public APK on GitHub Releases; anything compiled into it is
readable by anyone who downloads it, so a baked-in `API_TOKEN` would hand one person's archive
to every user of the app.

Every Manga Vault user runs their own server. There is no account, no Manga Vault cloud, and no
shared instance — the app only ever talks to the address its owner typed in.

**Until setup is complete, no screen in the app is reachable.** The router redirects everything
to `/setup`, which is what makes it structurally impossible to reach a screen that would fire an
unauthenticated request at somebody's server.

## Pieces

```
lib/core/config/
  server_config.dart             # ServerConfig + normalizeServerUrl + ServerUrlError
  server_config_store.dart       # ServerConfigStore; Secure (keystore) and InMemory (tests)
  server_config_controller.dart  # serverConfigProvider, isConfiguredProvider, bootstrap seed
lib/data/connection/
  connection_check.dart          # ConnectionChecker → ConnectionResult
lib/features/setup/
  setup_controller.dart          # SetupState/SetupPhase, submit()
  setup_screen.dart              # the form (also the change-server form)
```

### Storage

`flutter_secure_storage` — on Android, EncryptedSharedPreferences with a Keystore-held key. The
token is a bearer credential for the whole archive, so it does **not** go in
`shared_preferences` (a plain XML file, readable on a rooted device). A keystore that cannot be
read (a known failure mode after restore-from-backup) is treated as "not set up" rather than
being allowed to brick the app.

### Bootstrap ordering

`main()` is `async` and reads the store **before `runApp`**, then injects the result via
`bootstrapServerConfigProvider`. The router's `redirect` must decide synchronously whether the app
is configured; resolving that asynchronously would flash the dashboard for one frame before
bouncing to setup.

### The router guard

`router.dart` is now a **provider**, not a top-level constant, because it depends on runtime
state. It holds a `ValueNotifier` as `refreshListenable`, bumped from
`ref.listen(isConfiguredProvider, …)` — connecting or disconnecting moves the user with no
explicit navigation.

- `!configured && not at /setup` → `/setup`
- `configured && at /setup` → `/`

Changing servers later uses a **different** route, `/about/server` (nested under Dashboard), with
`SetupScreen(isReconfiguring: true)` — the guard above would bounce `/setup` away once configured.

### URL normalization

`normalizeServerUrl` is deliberately generous, because being strict means rejecting a correct
server over a trailing slash. All of these work:

| Typed | Stored |
| --- | --- |
| `192.168.1.20:3000` | `http://192.168.1.20:3000` |
| `https://Vault.Example.com/` | `https://vault.example.com` |
| `host:3000/api/v1/` | `http://host:3000` |
| `https://example.com/vault` | `https://example.com/vault` (proxy mount kept) |

The scheme test runs **before** `Uri.parse`, because `Uri` reads a bare `host:3000` as scheme
`host`. The `/api/v1` strip matters more than it looks: people paste the URL out of a browser tab
or a curl command, and appending our own prefix would produce `/api/v1/api/v1/library`.

### Two-step connection check

`ConnectionChecker` probes in this order, and the order is the whole point:

1. `GET /health` — **public** (`@Public()` on the server), so it proves the *address* without
   involving the token. It also verifies `service == 'mangavault-server'`, catching the common
   case of pointing at a router admin page, which would otherwise surface as a baffling 401.
2. `GET /categories` — guarded and cheap, so it proves the *token*.

One shot against a guarded route could not tell "wrong address" from "wrong token", and that
distinction is the entire difficulty of setting this up. The result type is a sealed union so the
setup screen can attach each failure to the field that owns it: a bad token must not put a message
under the address box.

Nothing is persisted until the server has answered **and** accepted the token — saving an
unverified address would drop the user into an app whose every screen fails, with no way back to
the form.

### Switching servers wipes the mirror

`ServerConfigController.save()` clears the drift database (`AppDatabase.wipe()`) when the
**baseUrl** changes; a token rotation against the same server keeps it, since that data is still
valid. `clear()` (disconnect) always wipes.

This is not housekeeping — the [[local-library-mirror]] holds one server's library keyed by that
server's ids, and its sync cursor is only meaningful against the server that issued it. Carrying
either across a switch would show the previous vault's titles under the new server's credentials
and then fail to reconcile them.

The disconnect dialog says plainly what is and isn't destroyed: the device forgets the address and
token and deletes the offline copy; **nothing on the server is touched**. "Disconnect" next to a
library is alarming, and the alarming reading is the wrong one.

## Gotchas

- **`SetupState.copyWith` preserves `phase`.** A failure branch that forgot to pass
  `phase: editing` left the screen spinning on "Contacting your server…" forever — error
  invisible, Connect button gone, no way to retry. Every failure now goes through
  `SetupController._fail`, and a test asserts `phase == editing` after a rejection.
- **Widget tests can't `pumpAndSettle` across a live connect.** The in-flight state renders a
  `CircularProgressIndicator`, which animates forever. Drive the controller with
  `tester.runAsync` (Dio completes on the real event loop, which a fake clock never services),
  then pump and assert the rendered error.
- **The setup form is taller than the 600pt default test surface**, so Connect is off-screen and
  untappable. Tests set a tall `tester.view.physicalSize`; the real screen scrolls.
- `CoverRepository.coverUrl` / `authHeaders` **used to be statics** over the compile-time config.
  They are now `CoverUrls` behind `coverUrlsProvider`, and `ArchivedCover` is a `ConsumerWidget` —
  a cover URL built against a stale origin 404s, or after a server switch points at someone
  else's image.
- Any test that pumps `MangaVaultApp` must override `bootstrapServerConfigProvider`, or the guard
  redirects it to setup.
- **Clearing the cover cache goes through `coverCacheCleanerProvider`, not `CoverCache.clear`
  directly.** Merely *touching* `CoverCache.manager` constructs a `flutter_cache_manager` `Config`,
  which calls `getTemporaryDirectory()` and raises a `MissingPluginException` **as an unhandled
  async error in the zone** — it never reaches the `await`, so no `try`/`catch` contains it, and it
  fails whichever test happens to be running at the time. Tests override the provider with a
  counter. It is also fire-and-forget for the same reason title deletion is.

## Dev workflow

`--dart-define=SERVER_URL=… --dart-define=API_TOKEN=…` still exists, but **only prefills the setup
form** (`AppConfig.devSeedServerUrl` / `devSeedApiToken`). So
`flutter run --dart-define-from-file=config/dev.json` is one tap from connected instead of
retyping a LAN address and a long token on every fresh install.

They are not config: nothing reads them after the setup screen, and a release build passes no
defines, so they are empty in a published APK. **Never reintroduce them as a fallback for
`ServerConfig`** — that puts the token back in the binary, which is the whole thing this avoids.

The release workflow passes no `--dart-define` at all. See [[app-updates]].

## Why this reverses the earlier decision

[[flutter-app]] recorded (2026-07-18): *"No in-app connection settings. The server is the single
source of truth, baked in at build time."* That was correct while the APK was built privately for
one person on one LAN.

It stopped being correct the moment the app started shipping as a public artifact on GitHub
Releases ([[app-updates]]). A compile-time token in a public APK is a published credential. The
setup screen is not a settings screen creeping back in — the app still has no settings — it is the
app's front door, and it exists once per install.
