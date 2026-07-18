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
- [[database]] — _(to be created)_ Postgres schema decisions, indexes, `pg_trgm`/tsvector/GIN.
- [[deployment]] — _(to be created)_ how/where the server is deployed (Docker on a VM).

## Domain

- [[tachibk-format]] — `.tachibk`/legacy-JSON parsing lib: pipeline, protobuf/int64/favorite gotchas.
- [[cover-fetching]] — _(to be created)_ per-source cover-download quirks discovered in practice.

## Meta

- [[README]] — what the `wiki/` folder is and the on-demand page convention.
- `../log.md` — append-only session journal (newest first).
