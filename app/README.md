# Manga Vault — Flutter client

The Android client for [Manga Vault](../README.md). It uploads `.tachibk` / legacy `.json`
backups to the server, browses the consolidated library from an on-device SQLite mirror, and
renders the Minimalist Slate design.

The Dart package is named `mangavault` (lowercase, as pub requires) — the user-facing name is
**Manga Vault**.

## Running

The server URL and API token are **compile-time** values, not settings:

```sh
cp config/dev.example.json config/dev.json   # then fill in your LAN URL + API_TOKEN
flutter run --dart-define-from-file=config/dev.json
```

`config/dev.json` is git-ignored. On the Android emulator use `http://10.0.2.2:3000`.

## Checks

```sh
flutter analyze
flutter test
```

## Releasing

Versions live in `pubspec.yaml` (`version: <semver>+<build>`) and must match the top entry of
the repo-root `CHANGELOG.md`. Pushing a `v<semver>` tag builds a signed APK and publishes it to
GitHub Releases, where the in-app updater finds it. See
[`../wiki-brain-vault/wiki/app-updates.md`](../wiki-brain-vault/wiki/app-updates.md).
