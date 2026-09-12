# Changelog

All notable changes to Manga Vault are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**This file is the source of the release notes shown inside the app.** The release workflow
slices the section for the tag being built and posts it as the GitHub release body; the app's
updater parses that body back into typed, colour-coded entries. So the section headings matter —
use only the six below, and keep every item a single `- ` bullet on one line.

| Heading          | Shown in-app as | Accent  |
| ---------------- | --------------- | ------- |
| `### Added`      | ADDED           | emerald |
| `### Fixed`      | FIXED           | cyan    |
| `### Changed`    | CHANGED         | violet  |
| `### Deprecated` | DEPRECATED      | amber   |
| `### Security`   | SECURITY        | amber   |
| `### Removed`    | REMOVED         | rose    |

## [Unreleased]

## [1.1.0] - 2026-09-12

The vault can now feed itself. Point Manga Vault at the folder your reading app drops its
automatic backups into, and each new one is imported on its own.

### Added

- Auto-import: name the folders your reading apps write automatic backups into, and Manga Vault imports each new backup for you — no picking a file, no review step.
- A folder can be chosen from the detected `autobackup` folders in one tap, or browsed to anywhere on the device for a fork Manga Vault doesn't know by name.
- Each watched folder is tagged with the app it belongs to, so a backup whose filename doesn't identify its app is still filed correctly with nobody there to ask.
- Check for new backups every 6, 12 or 24 hours, or turn the schedule off and scan only when you tap Scan now.
- Only the newest backup in a folder is imported — a backup is a complete snapshot, so the older ones hold nothing it doesn't — and a file already in your vault is never imported twice.
- Auto-import cell on Backups & Sources showing what is being watched and what the last check found.
- Auto-import checks when you open Manga Vault, at most once per chosen interval — it cannot wake the app by itself while it is closed, so open it now and then if your reading app only keeps its last few backups.

## [1.0.3] - 2026-09-10

### Fixed

- The library could go empty after updating to 1.0.2, and newly imported titles never appeared. Nothing was lost — the vault on your server was always intact, and the app refills its copy on the next sync.

## [1.0.2] - 2026-08-31

Sources gain an identity. The vault can now tell you where each title came from, whether that
place still works, and move titles off one that doesn't.

### Added

- Source registry: every source now shows a real name, icon, language and website, read from the Keiyoushi extension repository index instead of a bare 64-bit id.
- Sources screen (Library → Sources): every source your library depends on, ranked by whether it still works, with a health check you can run on demand.
- Source health verdicts — working, degraded, blocked, unreachable or removed — including sources that answer normally but whose cover images have all stopped loading.
- Replacement suggestions for a source no repository publishes any more, so a renamed source points at its successor.
- Source migration: move titles off a dead source onto one that works, keeping every chapter, read position, category and archive record. Confident matches are pre-selected, uncertain ones are left for you, and anything moved can be undone.
- Manual migration targets: pick a different match, or paste a title's address on the new source.
- Merge for a title that is already in your library on the target source, carrying reading progress across.
- Extensions browser: search the 1,380 published extensions and copy an install link.

### Fixed

- Titles imported from a backup with no source list (every legacy `.json` backup) stayed permanently nameless even after a later backup named the source. Existing blank names are filled in automatically.

## [1.0.0] - 2026-08-09

First public release. The archive is feature-complete for a single-user vault: import, browse,
export, and keep the collection alive independently of the reading apps it came from.

### Added

- Import `.tachibk` and legacy `.json` backups from Mihon and its forks, with a staged review
  step before anything is committed to the vault.
- Live import progress streamed from the server, with per-title NEW / MERGED outcomes.
- Consolidated library across every backup source, with merge-on-import so re-importing a newer
  backup updates titles instead of duplicating them.
- Library browsing over an on-device SQLite mirror — instant, offline, and rebuilt by delta sync.
- Filter, sort and display options: reading status, source, source app, favourites, three grid
  layouts and an adjustable column count.
- Title details with synopsis, genres, reading progress and per-title archive history.
- Cover archiving: fetches and stores cover art server-side so it survives the source going away.
- Backup export back to `.tachibk`, scoped to the whole vault or a chosen subset.
- Multi-select delete with a recycle bin, so a deleted title stays deleted across future imports.
- Archive dashboard: totals, reading progress, status mix, backup staleness and vault size.
- Manga Vault's own file browser for picking and saving backups, replacing the system dialogs.
- In-app update checks against GitHub Releases, with download progress, install, and these
  release notes rendered in the app.
- First-run setup that connects the app to your own server. The address and API token are stored
  in the device keystore and verified before they are saved, so a typo tells you which of the two
  is wrong instead of failing later.
- Change server and disconnect, from About. Switching servers clears the offline copy of the
  library on the device; nothing on either server is touched.

[Unreleased]: https://github.com/Raderne/mangaVault/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Raderne/mangaVault/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/Raderne/mangaVault/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Raderne/mangaVault/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Raderne/mangaVault/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Raderne/mangaVault/releases/tag/v1.0.0
