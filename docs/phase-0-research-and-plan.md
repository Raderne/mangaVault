# Phase 0 — Research & High-Level Plan

## 1. Research findings

### 1.1 The `.tachibk` format

Verified against the Mihon source in `MihonApp/mihon/` (Apache 2.0):

- **Container:** gzip stream wrapping a protobuf payload. `BackupDecoder` sniffs the first two
  bytes: `0x1f8b` = gzip, `0x7b??` (`{`) = JSON (legacy Tachiyomi backups — Mihon rejects them,
  MangaVault should support them), otherwise raw protobuf.
- **Payload:** the `Backup` message serialized with kotlinx.serialization ProtoBuf. All field
  numbers are catalogued in `docs/phase-1-data-structures.md` §4 and were transcribed directly
  from `data/backup/models/*.kt`.
- **Forks:** forks (TachiyomiSY, TachiyomiJ2K, Komikku, Yōkai, …) keep Mihon's field numbers and
  add their own at higher numbers. Unknown fields are skippable by protobuf design, so **one
  parser handles all forks** as long as we ignore unknown fields and treat everything but
  `BackupManga.source`/`url` as optional.
- **Identity:** a manga is uniquely identified within an app by `(source, url)`. `url` is a
  *relative* URL (Mihon strips scheme+domain via `setUrlWithoutDomain`) — good for dedup across
  forks pointing at the same source, but it means reconstructing a browsable link requires
  knowing the source's `baseUrl`.
- **Categories** are referenced from manga by the category `order` value (not `id`).

### 1.2 Image fetching in Mihon

- Covers: `Manga.thumbnailUrl` is an absolute URL saved in the backup. `MangaCoverFetcher` GETs it
  using the source extension's OkHttp client + `headers` (custom User-Agent, often Referer).
  Cache hierarchy: custom user cover file → permanent `CoverCache` (library items, keyed by
  thumbnail URL) → Coil disk cache → network.
- Source IDs: `HttpSource.generateId` = first 64 bits of `MD5("name/lang/versionId")`, sign bit
  cleared. `backupSources` in each backup maps id → human-readable name, which is all MangaVault
  needs for source attribution.
- **Implication for MangaVault:** we cannot run Android extension code, so the NestJS server
  fetches covers with a browser-like User-Agent and sets `Referer` to the thumbnail URL's origin.
  That works for the majority of sources; failures are recorded per-title so the user can retry
  or upload a custom cover. Covers are downloaded **at import time** into permanent server
  storage — archival means not depending on URLs that rot.
- Chapter page images require per-site parsing logic that lives in extensions → **out of scope
  for v1**. The architecture leaves a seam (`SourceAdapter`) so full-content archiving can be
  added later.

### 1.3 Product & design inputs

- Brief: `App design/project_brief_library_archive.md` — 4 screens: Archive Dashboard, Library
  Archive, Title Details, Backup & Sources.
- Design system: "Minimalist Slate" (`App design/minimalist_slate/DESIGN.md`) — dark bento-grid
  UI, exact tokens provided. Mockups exist as Tailwind HTML for all four screens.

## 2. Chosen stack (user decision)

- **Mobile app:** Flutter (Dart), Android-first, in `app/`. Pure client: uploads backups,
  browses the library, renders the four designed screens with the Minimalist Slate theme
  (its tokens are Material 3 color roles — map straight onto `ColorScheme`).
- **Backend:** NestJS (TypeScript) in `server/`. Owns everything archival: `.tachibk` parsing
  (Node `zlib.gunzipSync` + `protobufjs` with a hand-written `.proto` mirroring Mihon's field
  numbers), merge/dedup, cover fetching + permanent cover storage, stats, export.
- **Database:** PostgreSQL. Migrations managed in `server/` (TypeORM or Prisma). Original
  backup files and cover images stored on server disk (`storage/` dir), paths in Postgres.
- **API:** REST + multipart upload for backup files; JSON responses; pagination everywhere the
  library is listed.

## 3. Execution plan for the phases

| Phase | Deliverable | Status |
|---|---|---|
| 0 | This document — research + plan | done |
| 1 | `docs/phase-1-data-structures.md` — backup wire schema, domain model, DB schema, vault layout | done (review) |
| 2 | `docs/phase-2-interfaces.md` — TypeScript interfaces/API stubs for every service | done (review) |
| 3 | `docs/phase-3-todos.md` — ordered, file-level to-do list for implementation | done (review) |
| 4+ | Implementation milestones (see below) | not started |

Implementation milestones (the order Phase 3's to-dos follow):

1. **M1 – Skeletons:** scaffold NestJS (`server/`) with Postgres + migrations, scaffold Flutter
   (`app/`) with theme from design tokens, app shell + navigation, docker-compose for local dev.
2. **M2 – Import pipeline (server):** `.tachibk` decode (gzip+proto) → normalized domain model
   → Postgres, dedup across multiple backups; upload + import-review endpoints; import UI in app.
3. **M3 – Library & details:** paginated library API + Library Archive grid
   (filter/sort/search) and Title Details screen in Flutter.
4. **M4 – Covers (server):** background cover downloader with header spoofing, permanent cover
   store served over the API, per-title failure states + custom cover upload from the app.
5. **M5 – Dashboard & health:** stats endpoints + bento dashboard, backup health (staleness per
   source app), resume-reading list.
6. **M6 – Vault safety:** export (own JSON format + re-export as `.tachibk`), server storage
   integrity check, legacy JSON import, deployment setup.

## 4. Open decisions (defaults chosen, flag if you disagree)

1. **ORM** — TypeORM vs. Prisma for the NestJS/Postgres layer; Phase 3 assumes TypeORM
   (tighter NestJS integration), trivial to swap before M1.
2. **Auth** — single-user personal server; v1 uses a simple static API token. Real auth only if
   the server is ever exposed publicly.
3. **Chapter-image archiving** — deferred past v1 (needs per-site parsers).
4. **Cloud sync** — the Backup & Sources mockup shows cloud settings; deferred past v1 — the
   server's Postgres + storage dir can be backed up externally in the meantime.
