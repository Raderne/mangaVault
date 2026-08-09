# File selector (MangaVault's own file browser)

Created: 2026-08-09

Related: [[index]] · [[flutter-app]] · [[import-pipeline]] · [[backup-export]] · [[backup-apps]]

Both ends of the backup flow used to hand off to Android's system dialogs — the only place in the
app where the user left Minimalist Slate. They now open a first-party browser instead:
`app/lib/core/files/` (access, filesystem, roots) and `app/lib/features/files/` (screen, controller,
widgets, gate).

## The load-bearing decision: all-files access, not SAF

`MANAGE_EXTERNAL_STORAGE`, requested through `permission_handler` (the one new dependency), so the
browser reads the device with plain `dart:io`.

A `.tachibk` **is not media**, so `READ_MEDIA_*` grants nothing for it — on Android 13+ the only two
routes to a backup are the broad grant or a SAF tree the user hands over one folder at a time. This
app is sideloaded and never goes through Play, so the Play policy that normally rules out
`MANAGE_EXTERNAL_STORAGE` doesn't bind, and it buys a browser that can actually browse.

> **This supersedes the SAF decision recorded in [[backup-apps]]** ("Groundwork for auto-backup
> monitoring", 2026-08-02), which planned a persisted `safTreeUri`. The watcher, when built, polls a
> plain path instead: no SAF plugin, no content URIs, no per-folder grants. See that page's amended
> section.

**The system picker is still wired up and still works.** It is the fallback whenever access hasn't
been granted, on both the import (`ImportController.pickAndStage`) and export
(`FilePicker.saveFile`) sides. An archive tool whose import button opens a wall is worse than one
that looks less polished.

### The permission gotcha that decides whether this ships working

`MANAGE_EXTERNAL_STORAGE` is granted from a **system settings page, not a runtime dialog**. The
`request()` future resolves the moment the app is backgrounded — routinely *before* the user flips
the switch — so its return value is worthless on its own. `FileAccessController` therefore holds an
`AppLifecycleListener(onResume: refresh)` and re-reads the grant on every resume; the browser screen
also `ref.listen`s for the transition and loads its first folder off the back of it. Remove either
and the feature looks broken in exactly the way that is hardest to diagnose: the user grants
permission, comes back, and sees the gate.

Below API 30 the permission does not exist, so `request()` falls back to `Permission.storage`.
Branching on the returned status rather than the API level is what keeps `device_info_plus` out of
the dependency list. The manifest carries the legacy pair at `maxSdkVersion="29"`.

Both `status` and `request` are wrapped in try/catch that maps a missing plugin to `denied`, so a
widget test that merely reads the access state needs no plugin registration.

## `VaultFileSystem` — the seam that exists for the tests

`core/files/vault_file_system.dart` defines `VaultFileSystem` (`list` / `exists` / `isDirectory` /
`createDirectory` / `writeBytes`) with `IoFileSystem` behind `vaultFileSystemProvider`, and
`test/support/fake_file_system.dart` behind it in tests. The app's suite has never touched the real
filesystem and must not start: results would depend on the runner's home directory, and there is no
`/storage/emulated/0` on a desktop to browse.

Notes worth keeping:

- **`p.posix`, never bare `p`.** `package:path` follows the *host* platform, so under a Windows test
  runner `p.join('/storage/emulated/0', 'Download')` yields a backslash and every path assertion
  fails. These are always Android paths; the context is pinned everywhere the browser touches one.
- **A failure on one entry drops that entry, not the listing.** A dangling symlink or a protected
  child must not blank a folder. A failure on the *directory* raises `FileAccessException`, and
  `errno 13` is translated to "Android won't let this app read that folder" — the likeliest failure
  and the one the user can act on.
- `isBackupFileName` was lifted out of `ImportController._isBackupFile` so the browser and the
  staging code cannot disagree about what a backup is.

## Storage roots and quick access

- Primary volume is `/storage/emulated/0`. Secondary volumes come from `path_provider`'s
  `getExternalStorageDirectories()`, which returns the *app-scoped* dir on each one — the volume root
  is the substring before `/Android/`. There is no plugin-free way to enumerate volumes, and this
  trick needs no new dependency.
- Quick-access folders are **checked for existence, not assumed**: a chip pointing at a folder the
  device doesn't have is a dead tap. `autobackup` is Mihon's own constant (`StorageManager.kt`
  `AUTOMATIC_BACKUPS_PATH`) — automatic backups land in `<AppName>/autobackup`, manual ones wherever
  the user's SAF picker put them, in practice `Download`.
- Last-used and recent folders live in `shared_preferences`, following
  `LibraryDisplayController`'s pattern — device-local state never belongs in the mirror.
  **`_load()` bails if `state` is already non-empty**: a `remember()` that lands while the read is in
  flight is newer than disk, and restoring over it silently sends the next browse to the wrong
  folder. That was a real bug, caught by the "remembered folder is reopened" test.

## The screen

A full-screen route pushed on the **root** navigator (`file_browser_route.dart`:
`openFileBrowser` / `openSaveBrowser`), not a go_router route and not a bottom sheet. Save mode needs
the keyboard, back has to mean *up one folder* (which fights a sheet's own dismiss gesture), and
covering the tab bar is correct for a blocking task.

- **`PopScope(canPop: isAtVolumeRoot)`** — back walks up the tree, then closes. Going above a volume
  root would land in `/storage`, which is unreadable and reads as a bug.
- Accents follow the cell that launched it: **violet** for import, **emerald** for save (matching
  `_ImportCtaCell` / `_ExportCtaCell`), **amber** for the gate (blocked-on-user, like `_NeedsAppCell`),
  **rose** for an unreadable folder. See [[manga-neon-accents]].
- **Files that can't be imported are hidden, not shown greyed** — until the "All" toggle, which
  reveals them muted and inert. The empty state then says *how many* were hidden, because "No backups
  here" in a folder the user knows is full of files reads as a broken browser.
- Default sort is **modified-descending**: the backup you want is nearly always the last one your
  reading app wrote. Ties fall through to name — a batch export writes several in the same second.
- **Rows are deliberately not staggered individually.** A recycled `ListView` row replays its
  entrance every time it scrolls back into view. Folder changes cross-fade instead
  (`AnimatedSwitcher` keyed by directory, 260ms in / 160ms out, the same asymmetry
  `_ImportStateSection` uses).
- Save mode restores a stripped extension: `my library` becomes `my library.tachibk`, because the
  format's identity is carried entirely by its filename ([[backup-apps]]). Overwriting asks first.
- Navigation clears search and selection: carrying either across a folder change hides files in the
  new folder, or imports one the user can no longer see.

## Wiring

| Flow | Granted | Not granted |
|---|---|---|
| Import | `openFileBrowser` → `ImportController.stagePaths(paths)` | `pickAndStage()` (unchanged) |
| Export | `openSaveBrowser` → controller writes via `VaultFileSystem` | `FilePicker.saveFile` writes it |

- `ImportState` and `ExportState` are **unchanged**. `stagePaths` and `pickAndStage` share one
  `_stageAll` loop, so the two ways in cannot drift.
- `ImportRepository.stageFile(path, name)` streams the upload with `MultipartFile.fromFile` instead
  of the picker path's `withData: true` full-heap read.
- `ExportController.buildAndSave` takes a `chooseDestination` callback rather than reaching for a
  `BuildContext` it doesn't have — the same discipline as `ImportNeedsApp`. When it is supplied *we*
  write the bytes; when it isn't, the platform dialog does. A `null` return is still a cancel that
  keeps the scope intact, and `ExportResult.fileName` now comes from the chosen path, since the user
  can rename the file in the browser.

### The bug that made the save browser never appear (fixed 2026-08-09)

`chooseDestination` originally resolved its navigator inside the callback, guarded by
`context.mounted`. But `buildAndSave` sets `status: building` on its **first line**, and
`ExportScreen`'s `switch (state.status)` swaps `_EditingBody` — and with it the action bar the call
came from — straight out of the tree. So by the time there was a file to save, the context was
unmounted, the guard returned `null`, the controller correctly read that as "cancelled", and the
user got no dialog at all.

Hence `pushFileBrowser` / `pushSaveBrowser`, which take a **`NavigatorState` captured before the
await**. Any caller that reaches the browser after an await must use those; the `BuildContext`
variants are only safe when the browser opens immediately.

Worth noting for future work here: **every controller-level test passed throughout.** The defect
lived entirely in the widget lifecycle, so only a test that drives the real screen
(`'tapping Create backup pushes the save browser'`) could see it — and that test in turn caught a
second bug, a 27px footer overflow at 400dp that the default 800dp test surface had been hiding.
The browser's widget tests now pump at phone width for that reason.
- The gate cell also appears inline on the Backups hub — but **only in `ImportIdle`**, or it would
  push a running import's progress off the screen.

## Verified (2026-08-09)

- `flutter analyze` clean; **181 app tests** (up from 157), of which 18 are new in
  `test/file_browser_test.dart` plus 2 import and 4 export cases.
- `flutter build apk --debug` succeeds with no Gradle change; the merged manifest carries
  `MANAGE_EXTERNAL_STORAGE` and the two legacy permissions.
- **Not yet exercised on a device.** The grant flow, the resume re-check, real volume discovery and
  writing to a real folder need a physical device or a Play-image emulator.
