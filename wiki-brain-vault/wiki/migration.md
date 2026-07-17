# Database Migrations

Created: 2026-07-16 (M1)

Related: [[index]] · [[backend]] · [[database]]

Workflow (all from `server/`, Postgres running via `docker compose up -d postgres`):

```bash
npm run migration:run                                          # apply pending
npm run migration:revert                                       # revert last
npm run migration:generate -- src/database/migrations/<name>   # diff entities -> file
```

- CLI entry: `typeorm-ts-node-commonjs -d src/database/data-source.ts` (the `typeorm` npm
  script). The data source loads env from `server/.env` then `../.env` (see [[backend]] for the
  full env-loading order).
- Migrations glob `src/database/migrations/*{.ts,.js}` resolves to `.ts` under ts-node and
  `.js` in `dist/` — generated files are picked up automatically, no registration needed.
- `migrationsRun: true` ⇒ the server (and prod container) applies pending migrations on boot.
- **Rules:**
  - Never enable `synchronize`. Never edit an applied migration — write a new one.
  - Hand-write SQL when TypeORM can't express it (extensions, generated columns, partial/GIN
    indexes); `001 initial-schema` is the template.
  - After `migration:generate`, always review the diff — TypeORM does not know about the
    unmapped `search_tsv` column and may try to drop it. Remove any such statements.
- Schema reference lives in `docs/phase-1-data-structures.md` §3.2; keep it in sync when the
  schema evolves.
