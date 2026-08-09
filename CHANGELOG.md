# Changelog

All notable changes to Manga Vault are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**This file is the source of the release notes shown inside the app.** The release workflow
slices the section for the tag being built and posts it as the GitHub release body; the app's
updater parses that body back into typed, colour-coded entries. So the section headings matter —
use only the six below, and keep every item a single `- ` bullet on one line.

| Heading         | Shown in-app as | Accent  |
| --------------- | --------------- | ------- |
| `### Added`     | ADDED           | emerald |
| `### Fixed`     | FIXED           | cyan    |
| `### Changed`   | CHANGED         | violet  |
| `### Deprecated`| DEPRECATED      | amber   |
| `### Security`  | SECURITY        | amber   |
| `### Removed`   | REMOVED         | rose    |

## [Unreleased]

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

[Unreleased]: https://github.com/Raderne/mangaVault/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Raderne/mangaVault/releases/tag/v1.0.0
