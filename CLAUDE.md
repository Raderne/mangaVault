# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**MangaVault** — a personal archival app for manga/manhwa libraries. It imports backup files
(`.tachibk` / legacy `.json`) exported from Mihon and its forks (Tachiyomi lineage), consolidates
them into one library, and keeps the collection (metadata, reading progress, covers) safe even if
the source reading apps disappear.

**The MangaVault app itself has not been scaffolded yet.** There are no build/lint/test commands
until that happens — update this file with them as soon as the app skeleton exists. The repo is
also not yet a git repository.

## Repository layout

- `App design/` — Stitch-generated UI mockups (self-contained Tailwind HTML + screenshots) for the
  four screens: `archive_dashboard`, `library_archive`, `title_details`, `backup_sources`.
  - `App design/project_brief_library_archive.md` — product brief (features, screen architecture).
  - `App design/minimalist_slate/DESIGN.md` — the design system ("Minimalist Slate"): full color
    tokens, Inter typography scale, bento-grid layout rules, radii, spacing. Treat this as the
    source of truth for all UI work.
- `MihonApp/mihon/` — a **read-only reference clone** of Mihon (Apache 2.0, so porting
  schema/logic with attribution is fine). Never modify it; it is not part of the MangaVault build.
  The forks users import from share Mihon's exact backup format.
- `docs/` — phase planning documents (research, data structures, interfaces, to-dos) that drive
  implementation. Read `docs/phase-0-research-and-plan.md` first.

## The .tachibk backup format (critical domain knowledge)

A `.tachibk` file is a **gzip-compressed protobuf** payload (kotlinx.serialization ProtoBuf) of the
`Backup` message. Decoding rules, learned from `MihonApp/mihon/.../data/backup/BackupDecoder.kt`:

- Peek first 2 bytes: `0x1f8b` → gunzip first; `{}`/`{"`/`{\n` → legacy JSON (Mihon rejects it;
  MangaVault should parse legacy Tachiyomi JSON backups instead); anything else → raw protobuf.
- Proto field numbers are the wire contract and must never change. Canonical definitions live in
  `MihonApp/mihon/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/` (`Backup.kt`,
  `BackupManga.kt`, `BackupChapter.kt`, `BackupHistory.kt`, `BackupTracking.kt`,
  `BackupCategory.kt`, `BackupSource.kt`, `BackupPreference.kt`). The full schema is mirrored in
  `docs/phase-1-data-structures.md`.
- Gotchas: fields are sparse/optional with defaults (old backups omit newer fields); numbering has
  gaps (skipped legacy 1.x fields; Mihon-specific fields start at 100+); `PreferenceValue` is a
  kotlinx *polymorphic* type — on the wire it's a wrapper message (field 1 = serialName string,
  field 2 = payload), not a plain oneof.
- Manga↔category linkage is by `BackupCategory.order` values listed in `BackupManga.categories`.
- Filename convention: `<applicationId>_yyyy-MM-dd_HH-mm.tachibk`; the app id prefix identifies
  which fork produced it (e.g. `app.mihon`).

## How Mihon fetches images (the model for MangaVault's cover fetching)

- Every manga row carries `source` (a 64-bit source ID) and `thumbnailUrl` (an absolute URL,
  preserved in backups). Source IDs are derived as the first 8 bytes of
  `MD5("${name.lowercase()}/$lang/$versionId")` masked to a positive Long
  (`HttpSource.generateId`); `backupSources` maps id → display name.
- Covers are plain HTTP GETs, **but through the owning source's OkHttp client and headers**
  (`MangaCoverFetcher` → `sourceLazy.value?.headers`). Many sites require the source's custom
  `User-Agent`/`Referer` or they 403. MangaVault has no extensions, so it must approximate:
  browser-like UA + `Referer` derived from the thumbnail URL's origin, per-host retry/fallbacks.
- Two-tier caching, worth copying: a *permanent* cover store for library entries (Mihon's
  `CoverCache`, keyed by thumbnail URL) vs. an ephemeral LRU disk cache for everything else. For
  an archival app, downloading covers at import time into permanent storage is the point —
  thumbnail URLs rot.
- Chapter *page* images require executing per-site extension parsing code
  (`HttpSource.getPageList` → `Page.imageUrl`); that is out of scope for MangaVault v1 (metadata +
  covers archive), noted as a possible later phase.

## Design conventions

- Dark-only "Minimalist Slate" theme; use the exact tokens from
  `App design/minimalist_slate/DESIGN.md` (surface tiers for bento cells, 24px cell radius, 12px
  cover radius, pill buttons, Inter everywhere, uppercase micro-labels).
- Layout is a bento grid: 12 columns on desktop (cells span 3/4/6/12), single column on mobile,
  16px gutters, ≥24px cell padding. The four `code.html` mockups are the visual reference —
  match them, but rebuild as real components; don't copy the CDN-Tailwind mockup HTML wholesale.
- Library views must stay performant at 1,000+ titles (virtualize grids/lists).
