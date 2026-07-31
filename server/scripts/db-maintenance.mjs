#!/usr/bin/env node
/**
 * Reports what the vault costs in Postgres, then reclaims dead space.
 *
 *   npm run db:maintenance          # report + VACUUM (ANALYZE): online, safe any time
 *   npm run db:maintenance -- --full # + VACUUM FULL & REINDEX: rewrites, EXCLUSIVE LOCK
 *
 * Why this is a script and not a migration: `VACUUM` cannot run inside a
 * transaction and TypeORM wraps every migration in one — and rewriting a 95 MB
 * table is not something a deploy should do behind your back.
 *
 * Plain `VACUUM` marks dead tuples reusable (the file stays the same size, but
 * stops growing). `VACUUM FULL` rewrites the table to give the disk back and
 * takes an ACCESS EXCLUSIVE lock — nothing can read the table while it runs, so
 * only do it when the server is idle.
 */
import { config } from 'dotenv';
import pg from 'pg';

config({ path: ['.env', '../.env'], quiet: true });

const FULL = process.argv.includes('--full');
const TABLES = ['chapter', 'manga', 'deleted_manga'];

const bytes = (n) => {
  const units = ['B', 'kB', 'MB', 'GB'];
  let v = Number(n);
  let u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u += 1;
  }
  return `${v.toFixed(v >= 100 || u === 0 ? 0 : 1)} ${units[u]}`;
};

/** Size + bloat + HOT-update ratio per table, which is what we're tuning for. */
async function report(client, label) {
  const { rows } = await client.query(`
    SELECT c.relname                            AS table,
           pg_total_relation_size(c.oid)        AS total,
           pg_indexes_size(c.oid)               AS indexes,
           s.n_live_tup                         AS live,
           s.n_dead_tup                         AS dead,
           s.n_tup_upd                          AS updates,
           s.n_tup_hot_upd                      AS hot_updates
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
     WHERE n.nspname = 'public' AND c.relkind = 'r'
     ORDER BY pg_total_relation_size(c.oid) DESC`);

  console.log(`\n${label}`);
  console.log(
    '  table            total     indexes    live      dead   dead%   HOT%',
  );
  for (const r of rows) {
    const dead = Number(r.dead ?? 0);
    const live = Number(r.live ?? 0);
    const deadPct = live + dead > 0 ? ((100 * dead) / (live + dead)).toFixed(1) : '0.0';
    const upd = Number(r.updates ?? 0);
    const hotPct = upd > 0 ? ((100 * Number(r.hot_updates ?? 0)) / upd).toFixed(1) : '—';
    console.log(
      `  ${r.table.padEnd(15)} ${bytes(r.total).padStart(8)} ${bytes(r.indexes).padStart(9)} ` +
        `${String(live).padStart(8)} ${String(dead).padStart(8)} ${deadPct.padStart(6)} ${String(hotPct).padStart(6)}`,
    );
  }
  const { rows: db } = await client.query(
    `SELECT pg_database_size(current_database()) AS size`,
  );
  console.log(`  database total: ${bytes(db[0].size)}`);
}

const main = async () => {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('DATABASE_URL is not set (server/.env or repo-root .env)');
    process.exit(1);
  }

  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    await report(client, 'BEFORE');

    for (const table of TABLES) {
      if (FULL) {
        console.log(`\nVACUUM FULL ${table} … (exclusive lock)`);
        await client.query(`VACUUM (FULL, ANALYZE) ${table}`);
        console.log(`REINDEX TABLE ${table} …`);
        await client.query(`REINDEX TABLE ${table}`);
      } else {
        console.log(`\nVACUUM (ANALYZE) ${table} …`);
        await client.query(`VACUUM (ANALYZE) ${table}`);
      }
    }

    await report(client, 'AFTER');
    if (!FULL) {
      console.log(
        '\nSpace is now reusable but the files have not shrunk. To hand it back to\n' +
          'the OS, stop traffic and run:  npm run db:maintenance -- --full',
      );
    }
  } finally {
    await client.end();
  }
};

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
