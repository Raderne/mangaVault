# App Updates & Releasing

Created: 2026-08-09

Related: [[index]] · [[flutter-app]] · [[deployment]] · [[backend]]

How Manga Vault names itself, versions itself, ships, and updates itself in the field.

## The distribution model

The app is **sideloaded from GitHub Releases** — no Play Store, no F-Droid. That single fact
drives every decision below:

- There is no store to check for updates, so the app checks **GitHub's Releases API** itself.
- There is no store to install them, so the app downloads the APK and hands it to **Android's
  package installer**, which needs the per-app "install unknown apps" grant.
- There is no store to re-sign, so **every release must be signed with the same keystore** or
  Android refuses the upgrade. This is the one genuinely irreversible part.

The repo `Raderne/mangaVault` is **public** as of this change — that is what makes the Releases
API and the asset download work without a credential on the device. A private repo would have
forced either a PAT baked into the APK (extractable by anyone holding it) or a server-side proxy.

## Naming (decided 2026-08-09)

| Thing | Value | Why |
| --- | --- | --- |
| Display name | **Manga Vault** | `android:label`, `MaterialApp.title`, dashboard app bar |
| Dart package | `mangavault` | pub requires lowercase snake_case; it is the import prefix |
| `applicationId` | `dev.mangavault.mangavault` | **Unchanged on purpose.** It is Android's identity for the install — changing it makes the next release a *different app*, not an update |

Renaming the display name is free; renaming the `applicationId` is not. Don't.

## Versioning

`app/pubspec.yaml` holds `version: <semver>+<build>`. Three things must agree, and CI enforces it:

1. `pubspec.yaml` → the APK's `versionName` (semver) and `versionCode` (build number)
2. the git tag `v<semver>` → what triggers the release workflow
3. the top entry of the repo-root `CHANGELOG.md` → the release notes

The build number after `+` is Android's `versionCode` and **must increase every release** —
Android rejects an install whose versionCode is lower than the installed one.

`AppVersion` (`lib/data/updates/update_models.dart`) is a real semver implementation:
pre-releases rank below their release, numeric pre-release identifiers rank below alphanumeric
ones, and **build metadata is parsed but never compared** (semver §10). Unparseable tags return
`null` rather than a guess — a release tagged `nightly` must not be offered as an upgrade.

## CHANGELOG.md is the single source of release notes

One file, sliced at release time, parsed back in the app:

```
CHANGELOG.md  ──scripts/changelog-section.mjs──▶  GitHub release body
                                                        │
                                          parseReleaseNotes() in the app
                                                        ▼
                                            colour-coded changelog UI
```

Section headings map to the [[manga-neon-accents]] hues, which is why they are fixed:

| Heading | Accent | Reads as |
| --- | --- | --- |
| `### Added` | emerald | new |
| `### Fixed` | cyan | repaired |
| `### Changed` | violet | different |
| `### Deprecated` / `### Security` | amber | heads up |
| `### Removed` | rose | gone |

`ChangeKind.fromHeading` also accepts the spellings people actually type (`Fixes`, `Features`,
`Breaking changes`); anything unrecognised becomes `ChangeKind.other` and renders with its own
heading rather than being dropped.

### Parser gotchas (all pinned by `test/update_models_test.dart`)

- **Wrapped bullets.** CHANGELOG.md wraps at 100 columns, so most bullets span several source
  lines. A continuation is detected by the *absence of a blank line*, not by indentation —
  markdown's lazy continuation allows unindented ones. Without this, every long item shredded
  into fragments.
- **Link-reference definitions** (`[1.0.0]: https://…`) are skipped. Keep a Changelog collects
  them at the foot of the file and they survive a naive slice.
- **GitHub's `**Full Changelog**:` footer** ends parsing.
- Inline markdown is stripped, not rendered (`stripInlineMarkdown`) — a full markdown engine
  would be a dependency spent on emphasis the design doesn't style anyway.
- `test/update_models_test.dart` parses **the real CHANGELOG.md** and asserts every heading maps
  to a known kind and every bullet ends in a full stop. That is the round-trip guard: if the file
  and the parser ever disagree, the suite fails before a release ships blank notes.

## App architecture

```
lib/data/updates/
  update_models.dart      # AppVersion, ChangeKind/Group, ReleaseNotes, AppRelease, the parser
  update_repository.dart  # GithubUpdateRepository: latest/history/downloadApk/clearDownloads
  apk_installer.dart      # ApkInstaller over the MethodChannel; typed InstallFailure
lib/features/updates/
  update_controller.dart  # UpdateState machine + installedAppProvider + releaseHistoryProvider
  update_card.dart        # the whole lifecycle as one bento cell
  changelog_view.dart     # accent-coded release notes
  update_banner.dart      # dashboard banner + AboutAction (badged app-bar entry)
lib/features/about/
  about_screen.dart       # /about — identity, update card, release history, build info
```

### Decisions worth remembering

- **The updater has its own Dio.** Not `apiClientProvider` — that one carries the vault's bearer
  token and points at the user's server. Sending the API token to github.com would leak it, and
  updates must keep working when the server is down, which is exactly when someone reinstalls.
- **`latest()` lists and filters instead of calling `/releases/latest`.** That endpoint 404s on a
  repo whose only releases are pre-releases, which would wrongly report "up to date".
- **Never auto-download, never auto-install.** Only the *check* is automatic, throttled to once
  per 6 hours (`UpdateController.checkInterval`, persisted in `shared_preferences`). Spending
  someone's mobile data and replacing their binary without a tap is the wrong default for a
  sideloaded personal tool.
- **A silent (launch) check that fails restores the previous state.** An offline launch must not
  greet the user with an error they never asked for. An explicit check always reports.
- **`.wait` on a record is banned here.** It wraps failures in `ParallelWaitError`, which swallowed
  the `UpdateException` carrying the message and the offline flag. `check()` awaits sequentially.
- **Skip vs dismiss.** Dismiss is a session-only gesture on the banner; skip persists the version
  and suppresses the banner but *never* the About screen, which must always tell the truth.
- **Downloads land in `<cache>/updates/` as `.part`, then rename.** The installable path can never
  point at a truncated APK.
- **The auto-check is kicked from `main.dart`, not from a widget.** `main` owns an explicit
  `ProviderContainer` and fires `autoCheck()` after the first frame. Wiring it into the app shell
  would fire a real GitHub request in every widget test that pumps a screen.

### Android install plumbing

`MainActivity.kt` hosts channel `dev.mangavault/installer` with `canInstall`,
`openInstallSettings`, and `install`. Three pieces are required and each fails silently if missing:

- `REQUEST_INSTALL_PACKAGES` in the manifest.
- A `FileProvider` with authority `${applicationId}.updates`, scoped by
  `res/xml/update_paths.xml` to the cache `updates/` folder. A raw `file://` Uri throws
  `FileUriExposedException` on API 24+ — the installer is a different process.
- `androidx.core:core-ktx`, depended on explicitly in `app/build.gradle.kts`.

The channel exposes the *permission check* and *route to Settings* alongside the install itself.
A plugin that only fired the intent could not tell an ungranted permission apart from a corrupt
download — so `UpdateReady.needsPermission` turns that case into an "Open settings" button, and
`AboutScreen` re-checks the grant on `AppLifecycleState.resumed` (Android gives no callback).

## UI

Entry point is the Dashboard app bar's badged info icon → **`/about`**, nested under the Dashboard
branch so the tab stays selected and back returns to it. There is still **no Settings screen** —
the server is compiled in, and About talks about the *app*, not the library.

- **Hue carries the update state**: violet = the way forward (checking / available / downloading),
  emerald = a good resting place (up to date / downloaded), amber = you must act first
  (permission, offline), rose = it actually failed.
- The `UpdateBanner` rides inside the dashboard's **welcome slot**, not its own list entry — it is
  absent most of the time and an empty entry would leave a gutter-sized hole. Padding is top-only
  because the list separator supplies the gap below.
- The downloading cell obeys the fixed-height rule from `app/CLAUDE.md`: the byte counter is a
  **single** `Text` with `maxLines: 1`, so a changing label can never reflow the cell. Pinned by a
  test that asserts the card's height is identical at `1 / 100000000` and `99999999 / 100000000`.
- Release history uses one `ExpansionTile` per release with the **installed** one expanded and
  badged, so "what am I running" and "what changed before" are one list, not two sections.

## Releasing

### One-time setup

1. **Generate the keystore** (keep it forever, back it up off-machine):

   ```sh
   keytool -genkey -v -keystore manga-vault-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias manga-vault
   ```

2. **Add repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 manga-vault-release.jks` |
   | `ANDROID_KEYSTORE_PASSWORD` | store password |
   | `ANDROID_KEY_ALIAS` | `manga-vault` |
   | `ANDROID_KEY_PASSWORD` | key password |

   **No `SERVER_URL` or `API_TOKEN` secrets.** The published APK contains no server address and
   no credential: each user points the app at their own server on first launch and the token is
   kept in that device's keystore. See [[server-connection]]. Never add a `--dart-define` for
   them to this workflow — it would publish the credential to everyone who downloads the release.

3. Locally, `app/android/key.properties` (git-ignored) does the same job for a local release
   build. Without it the release build falls back to **debug keys** and logs a warning.

### Release history

- **v1.0.0** — tagged 2026-08-09 from `release/1.0.0`. First public release; the repo was made
  public for it, which is what lets the in-app updater read the Releases API without a credential.

### Cutting a release

1. Move the `## [Unreleased]` items into a new `## [x.y.z] - YYYY-MM-DD` section.
2. Bump `app/pubspec.yaml` — semver **and** the build number.
3. Commit, then `git tag vx.y.z && git push origin vx.y.z`.

`.github/workflows/release.yml` then: checks the tag against pubspec, slices the changelog,
`flutter analyze` + `flutter test`, writes `key.properties` from the secrets, builds the APK,
**verifies with `apksigner` that it is not debug-signed**, and publishes the release with the
notes and the `manga-vault-<version>.apk` asset. A tag containing `-` publishes as a pre-release,
which `latest()` skips.

`workflow_dispatch` runs everything except the publish, for a dry run.

> **Why apksigner and not a gradle task:** `gradlew` and `gradle-wrapper.jar` are git-ignored by
> Flutter's own Android template, so a `./gradlew verifySigning` step has no wrapper to run until
> `flutter build apk` regenerates one. Verifying the finished artifact is both possible and
> stronger.

## To do / not done

- The APK is universal (all ABIs). `--split-per-abi` would roughly halve the download but means
  three assets and picking the right one in `AppRelease.fromJson`; deferred until size hurts.
- No R8/minification on release — deliberately left off, since it is untested against drift's
  native assets and the installer channel.
- `app/android/build/reports/problems/problems-report.html` is tracked in git and shouldn't be;
  it is stray Gradle build output.
