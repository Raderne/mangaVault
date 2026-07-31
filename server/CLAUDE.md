# Server — MangaVault API (NestJS)

Guidance for work under `server/`. See the repo root `CLAUDE.md` for project-wide rules.

## The .tachibk backup format (critical domain knowledge)

A `.tachibk` file is a **gzip-compressed protobuf** payload (kotlinx.serialization ProtoBuf) of the
`Backup` message. Parsing happens **server-side** in NestJS. Decoding rules, learned from
`MihonApp/mihon/.../data/backup/BackupDecoder.kt`:

- Peek first 2 bytes: `0x1f8b` → gunzip first; `{}`/`{"`/`{\n` → legacy JSON (Mihon rejects it;
  MangaVault should parse legacy Tachiyomi JSON backups instead); anything else → raw protobuf.
- Proto field numbers are the wire contract and must never change. Canonical definitions live in
  `MihonApp/mihon/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/`. The full schema is
  mirrored in `docs/phase-1-data-structures.md`.
- Gotchas: fields are sparse/optional with defaults (old backups omit newer fields; notably
  `favorite` defaults to true); numbering has gaps (skipped legacy 1.x fields; Mihon-specific
  fields start at 100+); forks add fields at higher numbers — always ignore unknown fields.
  `PreferenceValue` is a kotlinx *polymorphic* type — a wrapper message (field 1 = serialName,
  field 2 = payload), not a plain oneof.
- A manga's identity within the ecosystem is `(source id, relative manga url)` — the dedup key
  when merging backups from multiple forks.
- Manga↔category linkage is by `BackupCategory.order` values listed in `BackupManga.categories`.
- Filename convention: `<applicationId>_yyyy-MM-dd_HH-mm.tachibk`; the app-id prefix identifies
  which fork produced it (e.g. `app.mihon`).

## How Mihon fetches images (the model for server-side cover archiving)

- Every manga row carries `source` (64-bit source ID) and `thumbnailUrl` (absolute URL, preserved
  in backups). Source IDs = first 8 bytes of `MD5("${name.lowercase()}/$lang/$versionId")` masked
  positive (`HttpSource.generateId`); `backupSources` maps id → display name.
- Covers are plain HTTP GETs, **but through the owning source's OkHttp client and headers**
  (`MangaCoverFetcher`) — many sites 403 without the source's custom User-Agent/Referer.
  MangaVault has no extensions, so the NestJS cover fetcher approximates: browser-like UA +
  `Referer` derived from the thumbnail URL's origin, per-host concurrency limits and retries,
  with per-source overrides when a site needs them.
- Two-tier caching in Mihon (permanent `CoverCache` for library items vs. ephemeral LRU) —
  for MangaVault, download covers **at import time** into permanent server storage; thumbnail
  URLs rot, which defeats an archive.
- Chapter *page* images require per-site extension parsing (`HttpSource.getPageList`); out of
  scope for v1 (metadata + covers archive), seam left for later.

## Conventions

- The schema is owned by raw-SQL migrations in `src/database/migrations/` — TypeORM
  `synchronize` is **off**, never turn it on.
- A global bearer-token guard is applied in `src/auth/`; mark public routes with `@Public()`.
- Pure `.tachibk` parsing lives in `src/tachibk/` with **zero** Nest/TypeORM imports.
- `npm run migration:generate -- src/database/migrations/<name>` — the path argument is required.
