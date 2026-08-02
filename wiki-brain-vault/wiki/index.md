# Wiki Index

Maintained by Claude. **Entry point for the vault** — start here, then follow `[[links]]` to detail
pages instead of re-reading the whole codebase. One page per topic; pages are created **on demand**
the first time substantial work happens on a topic.

## Components

- [[backend]] — NestJS 11 API: layout, auth guard, migration-owned schema, int64 discipline, ports.
- [[flutter-app]] — app structure, Riverpod + go_router, Minimalist Slate theming, compile-time server config.

## Concepts

- [[migration]] — DB migration workflow, rules (never `synchronize`, never edit applied migrations).
- [[import-pipeline]] — M2 import module: stage/commit flow, merge engine, endpoints, storage.
- [[library-api]] — `/library` query + `/library/:id` + `/categories`, and title **deletion**
  (tombstones, sync lock, cover cleanup); Flutter grid, Title Details, paging, animation language.
- [[deleted-titles]] — the deletion registry: why a delete must survive the next backup import, the
  snapshot/restore model, and the recycle-bin screen.
- [[dashboard-stats]] — M5 dashboard: `/stats/*` aggregates, backup staleness, the bento grid,
  shelves, and the shared `core/format.dart` helpers.
- [[local-library-mirror]] — on-device SQLite mirror + `/sync/*` delta feed: `row_version` triggers,
  the advisory lock, drift schema, and why `updated_at` can't be a cursor.
- [[database]] — Postgres schema, migrations, indexes, int64 discipline, unmapped columns, restores.
- [[deployment]] — _(to be created)_ how/where the server is deployed (Docker on a VM).

## Domain

- [[tachibk-format]] — `.tachibk`/legacy-JSON parsing lib: pipeline, protobuf/int64/favorite gotchas.
- [[backup-apps]] — which reading app a backup came from: filename parsing, the `backup_app`
  registry, the import picker, the library's "from app" filter, and the auto-backup groundwork.
- [[cover-fetching]] — M4 cover archiving: `/covers/*`, the Mihon-style fetcher, concurrency, serve +
  `Image.network` auth, the app's archive banner / progressive reveal, and the **durable `cover_job`**
  (cancel, boot resume, post-import trigger).

## Meta

- [[README]] — what the `wiki/` folder is and the on-demand page convention.
- `../log.md` — append-only session journal (newest first).
