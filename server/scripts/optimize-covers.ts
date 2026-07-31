/**
 * Re-encode the archived cover corpus to the storage profile.
 *
 *   npm run covers:optimize             # DRY RUN — reports, writes nothing
 *   npm run covers:optimize -- --apply  # actually re-encode
 *   npm run covers:optimize -- --apply --no-backup
 *   npm run covers:optimize -- --limit 50 --apply
 *
 * Measured baseline: 1,121 covers / 613 MB, JPEG averaging 661 KB and PNG
 * 1.8 MB, against a phone that renders them at ~600–1,100 px.
 *
 * **This is lossy and irreversible**, so it defaults to a dry run, keeps the
 * originals under `covers-original/` unless told not to, and never replaces a
 * file it failed to decode, failed to encode, or couldn't make meaningfully
 * smaller. New covers are already encoded to the same profile on ingest
 * (`CoverService.encodeForStorage`), so this only has to fix the backlog.
 */
import { readFile, mkdir, rename, unlink, writeFile } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';

import { config } from 'dotenv';
import { DataSource } from 'typeorm';

import { buildDataSourceOptions } from '../src/database/data-source';
import { runPool } from '../src/modules/covers/concurrency';
import { CoverOptimizer } from '../src/modules/covers/cover.optimizer';
import { optimizerOptionsFromEnv } from '../src/modules/covers/cover.module';
import type { SkipReason } from '../src/modules/covers/cover.optimizer';

config({ path: ['.env', '../.env'], quiet: true });

const argv = process.argv.slice(2);
const has = (flag: string) => argv.includes(flag);
const valueOf = (flag: string): string | undefined => {
  const i = argv.indexOf(flag);
  return i >= 0 ? argv[i + 1] : undefined;
};

const APPLY = has('--apply');
const BACKUP = !has('--no-backup');
const LIMIT = Number(valueOf('--limit') ?? '0');
const CONCURRENCY = Number(valueOf('--concurrency') ?? '4');

const STORAGE_DIR = process.env.STORAGE_DIR ?? './storage';
const COVERS_DIR = join(STORAGE_DIR, 'covers');
const ORIGINALS_DIR = join(STORAGE_DIR, 'covers-original');

interface Row {
  id: string;
  cover_path: string;
}

const bytes = (n: number): string => {
  const units = ['B', 'kB', 'MB', 'GB'];
  let v = n;
  let u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u += 1;
  }
  return `${v.toFixed(v >= 100 || u === 0 ? 0 : 1)} ${units[u]}`;
};

interface Stats {
  scanned: number;
  changed: number;
  before: number;
  after: number;
  missing: number;
  skipped: Record<SkipReason, number>;
  /** Source format → [count, bytes before, bytes after]. */
  byFormat: Map<string, [number, number, number]>;
  biggest: { path: string; before: number; after: number }[];
}

const main = async (): Promise<void> => {
  const optimizer = new CoverOptimizer(
    optimizerOptionsFromEnv((key) => process.env[key]),
  );
  const { maxEdge, quality, effort, maxSizeRatio } = optimizer.options;

  console.log(
    `profile: WebP q${quality}, longest edge ${maxEdge}px, effort ${effort}, ` +
      `replace only under ${Math.round(maxSizeRatio * 100)}% of the original`,
  );
  console.log(
    APPLY
      ? `mode: APPLY — files will be rewritten${
          BACKUP ? `, originals moved to ${ORIGINALS_DIR}` : ' WITHOUT backup'
        }`
      : 'mode: DRY RUN — nothing will be written (pass --apply to commit)',
  );

  const ds = new DataSource(
    buildDataSourceOptions(process.env.DATABASE_URL ?? ''),
  );
  await ds.initialize();

  try {
    const rows = await ds.query<Row[]>(
      `SELECT id, cover_path FROM manga
        WHERE cover_state = 'archived' AND cover_path IS NOT NULL
        ORDER BY id
        ${LIMIT > 0 ? `LIMIT ${LIMIT}` : ''}`,
    );
    console.log(`covers to inspect: ${rows.length}\n`);

    const stats: Stats = {
      scanned: 0,
      changed: 0,
      before: 0,
      after: 0,
      missing: 0,
      skipped: {
        'already-optimal': 0,
        'no-saving': 0,
        undecodable: 0,
        'encode-failed': 0,
      },
      byFormat: new Map(),
      biggest: [],
    };

    if (APPLY && BACKUP) await mkdir(ORIGINALS_DIR, { recursive: true });

    /** Rows whose `cover_path` changed, applied to the DB in batches. */
    const pending: { id: string; path: string }[] = [];

    await runPool(
      rows,
      {
        globalLimit: Math.max(1, CONCURRENCY),
        // CPU-bound and all on one disk, so a single bucket: the global cap is
        // the only limit that means anything here.
        perKeyLimit: Math.max(1, CONCURRENCY),
        keyOf: () => 'local',
      },
      async (row) => {
        const abs = join(STORAGE_DIR, row.cover_path);
        let input: Buffer;
        try {
          input = await readFile(abs);
        } catch {
          stats.missing += 1;
          return;
        }

        const result = await optimizer.optimize(input);
        stats.scanned += 1;
        stats.before += input.length;

        const format = result.original?.format ?? 'unknown';
        const entry = stats.byFormat.get(format) ?? [0, 0, 0];
        entry[0] += 1;
        entry[1] += input.length;

        if (!result.changed) {
          stats.after += input.length;
          entry[2] += input.length;
          stats.byFormat.set(format, entry);
          if (result.skipReason) stats.skipped[result.skipReason] += 1;
          return;
        }

        stats.changed += 1;
        stats.after += result.bytes.length;
        entry[2] += result.bytes.length;
        stats.byFormat.set(format, entry);
        stats.biggest.push({
          path: basename(row.cover_path),
          before: input.length,
          after: result.bytes.length,
        });

        if (!APPLY) return;

        // Write the new file first, then repoint the row, then retire the old
        // one: at no moment is `cover_path` pointing at something absent.
        const newRel = `covers/${basename(row.cover_path, extname(row.cover_path))}.${result.ext}`;
        await writeFile(join(STORAGE_DIR, newRel), result.bytes);
        pending.push({ id: row.id, path: newRel });

        if (newRel !== row.cover_path) {
          if (BACKUP) {
            await rename(abs, join(ORIGINALS_DIR, basename(row.cover_path)));
          } else {
            await unlink(abs).catch(() => undefined);
          }
        } else if (BACKUP) {
          // Same name (already .webp): keep a copy of the original bytes.
          await writeFile(
            join(ORIGINALS_DIR, basename(row.cover_path)),
            input,
          );
        }
      },
    );

    if (APPLY && pending.length > 0) {
      // Batched so 1,000 covers don't take the sync advisory lock 1,000 times.
      // Each UPDATE bumps `row_version`, so devices pick the new paths up on
      // their next delta.
      const BATCH = 100;
      for (let i = 0; i < pending.length; i += BATCH) {
        const slice = pending.slice(i, i + BATCH);
        await ds.transaction(async (mgr) => {
          await mgr.query('SELECT pg_advisory_xact_lock($1)', [834221]);
          await mgr.query(
            `UPDATE manga m SET cover_path = v.path
               FROM unnest($1::uuid[], $2::text[]) AS v(id, path)
              WHERE m.id = v.id`,
            [slice.map((p) => p.id), slice.map((p) => p.path)],
          );
        });
      }
      console.log(`updated ${pending.length} cover paths\n`);
    }

    report(stats);
  } finally {
    await ds.destroy();
  }
};

function report(s: Stats): void {
  const saved = s.before - s.after;
  const pct = s.before > 0 ? (100 * saved) / s.before : 0;

  console.log('by source format');
  console.log('  format    files      before       after     saved');
  for (const [format, [count, before, after]] of [...s.byFormat].sort(
    (a, b) => b[1][1] - a[1][1],
  )) {
    console.log(
      `  ${format.padEnd(9)} ${String(count).padStart(5)} ${bytes(before).padStart(11)} ` +
        `${bytes(after).padStart(11)} ${`${(before > 0 ? (100 * (before - after)) / before : 0).toFixed(0)}%`.padStart(9)}`,
    );
  }

  if (s.biggest.length > 0) {
    console.log('\nbiggest wins');
    for (const w of s.biggest
      .sort((a, b) => b.before - b.after - (a.before - a.after))
      .slice(0, 5)) {
      console.log(
        `  ${w.path.padEnd(42)} ${bytes(w.before).padStart(9)} → ${bytes(w.after).padStart(9)}`,
      );
    }
  }

  console.log('\ntotals');
  console.log(`  inspected     ${s.scanned}`);
  console.log(`  re-encoded    ${s.changed}`);
  console.log(`  left as-is    ${s.scanned - s.changed}`);
  console.log(`    already optimal  ${s.skipped['already-optimal']}`);
  console.log(`    no saving        ${s.skipped['no-saving']}`);
  console.log(`    undecodable      ${s.skipped.undecodable}`);
  console.log(`    encode failed    ${s.skipped['encode-failed']}`);
  if (s.missing > 0) console.log(`  file missing  ${s.missing}`);
  console.log(
    `  ${bytes(s.before)} → ${bytes(s.after)}   saved ${bytes(saved)} (${pct.toFixed(1)}%)`,
  );

  if (!APPLY) {
    console.log('\nDry run — nothing was written. Re-run with --apply to commit.');
  } else {
    console.log(
      BACKUP
        ? `\nOriginals kept in ${ORIGINALS_DIR}. Delete that directory once you're happy.`
        : '\nOriginals were deleted.',
    );
    console.log(
      'Devices keep their cached copies until eviction; the archive is what shrank.',
    );
  }
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
