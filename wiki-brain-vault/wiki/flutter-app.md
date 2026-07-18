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

## Removed / deferred

- `shared_preferences` dependency removed (only the settings module used it). The M2 "move token
  to flutter_secure_storage" to-do is now moot — no token is stored on-device; it's compiled in.
