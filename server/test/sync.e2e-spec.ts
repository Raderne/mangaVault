import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type {
  SyncMangaDto,
  SyncMetaDto,
  SyncPageDto,
} from '../src/modules/sync/sync.dto';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/**
 * Delta-sync e2e against the local Postgres (host 5433).
 *
 * Seeds a run-unique source via SQL so it stays deterministic against the real
 * imported library, and drives the protocol the way the app does: read a
 * cursor, mutate, pull the delta, assert only the affected title comes back.
 *
 * The load-bearing assertions are the ones a timestamp-based cursor would fail:
 * a chapter-only read-flag change and a cover-state change must both surface,
 * even though neither touches `manga.updated_at`.
 */
describe('Library sync (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  const sourceId = String(
    9_300_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const catName = `SyncCat-${runId}`;
  const sha = `sha-sync-${runId}`;

  let alphaId = '';
  let betaId = '';
  let alphaChapterId = '';
  /** High-water mark captured before seeding, so tests can scope a walk. */
  let baseCursor = '0';

  /** Current server high-water mark. */
  async function cursor(): Promise<string> {
    return (await meta()).cursor;
  }

  async function meta(): Promise<SyncMetaDto> {
    const res = await request(app.getHttpServer())
      .get('/api/v1/sync/meta')
      .set('Authorization', auth)
      .expect(200);
    return res.body as SyncMetaDto;
  }

  async function delta(since: string, limit = 500): Promise<SyncPageDto> {
    const res = await request(app.getHttpServer())
      .get(`/api/v1/sync/library?since=${since}&limit=${limit}`)
      .set('Authorization', auth)
      .expect(200);
    return res.body as SyncPageDto;
  }

  /** Only this run's seeded titles, so the shared DB can't perturb counts. */
  const mine = (page: SyncPageDto): SyncMangaDto[] =>
    page.changed.filter((c) => c.sourceId === sourceId);

  beforeAll(async () => {
    process.env.API_TOKEN = token;
    process.env.DATABASE_URL ??=
      'postgres://mangavault:mangavault@localhost:5433/mangavault';

    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    await app.init();
    ds = app.get(DataSource);
    baseCursor = await cursor();

    const insertManga = async (title: string): Promise<string> =>
      idOf(
        await ds.query(
          `INSERT INTO manga (source_id, manga_url, source_name, title, author, status, updated_at, date_added, genres)
           VALUES ($1, $2, 'SyncTest', $3, 'Seed Author', 'ongoing', $4, $4, '["Action"]') RETURNING id`,
          [sourceId, `/m/${title}`, title, runId],
        ),
      );

    alphaId = await insertManga('Sync Alpha');
    betaId = await insertManga('Sync Beta');

    alphaChapterId = idOf(
      await ds.query(
        `INSERT INTO chapter (manga_id, url, name, chapter_number, read, last_read_at)
         VALUES ($1, '/c/1', 'Chapter 1', 1, TRUE, $2) RETURNING id`,
        [alphaId, runId],
      ),
    );
    await ds.query(
      `INSERT INTO chapter (manga_id, url, name, chapter_number, read)
       VALUES ($1, '/c/2', 'Chapter 2', 2, FALSE)`,
      [alphaId],
    );

    const catId = idOf(
      await ds.query(
        `INSERT INTO category (name, sort) VALUES ($1, 0) RETURNING id`,
        [catName],
      ),
    );
    await ds.query(
      `INSERT INTO manga_category (manga_id, category_id) VALUES ($1, $2)`,
      [alphaId, catId],
    );

    const importId = idOf(
      await ds.query(
        `INSERT INTO import_record (file_name, file_size, sha256, source_app, container, imported_at, stats)
         VALUES ($1, 1, $2, 'app.mihon', 'gzip-proto', $3, '{}') RETURNING id`,
        [`app.mihon_sync_${runId}.tachibk`, sha, runId],
      ),
    );
    await ds.query(
      `INSERT INTO manga_import (manga_id, import_id) VALUES ($1, $2)`,
      [alphaId, importId],
    );
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      const rows = await ds.query<{ id: string }[]>(
        `SELECT id FROM manga WHERE source_id = $1`,
        [sourceId],
      );
      // manga delete cascades chapters, manga_category and manga_import rows.
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      // Deleting seeded rows leaves tombstones behind — clear them too, or the
      // next run's delta would carry this run's ids forever.
      for (const r of rows) {
        await ds.query(`DELETE FROM sync_tombstone WHERE entity_id = $1`, [
          r.id,
        ]);
      }
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [sha]);
      await ds.query(`DELETE FROM category WHERE name = $1`, [catName]);
    }
    await app?.close();
  });

  it('rejects both sync routes without auth', async () => {
    await request(app.getHttpServer()).get('/api/v1/sync/library').expect(401);
    await request(app.getHttpServer()).get('/api/v1/sync/meta').expect(401);
  });

  it('meta reports an epoch, a cursor and the vault size', async () => {
    const m = await meta();
    expect(m.serverEpoch).toMatch(/^[0-9a-f-]{36}$/);
    expect(Number(m.cursor)).toBeGreaterThan(0);
    expect(m.totalTitles).toBeGreaterThanOrEqual(2);
    expect(m.vaultSizeBytes).toBeGreaterThan(0);
    expect(m.categories.some((c) => c.name === catName)).toBe(true);
    expect(m.imports.some((i) => i.sha256 === sha)).toBe(true);
  });

  it('a full sync from 0 delivers the seeded titles with their projections', async () => {
    // Walk every page the way the client does, collecting this run's rows.
    let since = '0';
    const found: SyncMangaDto[] = [];
    for (let guard = 0; guard < 50; guard++) {
      const page = await delta(since, 500);
      found.push(...mine(page));
      since = page.cursor;
      if (!page.hasMore) break;
    }

    expect(found).toHaveLength(2);
    const alpha = found.find((c) => c.id === alphaId)!;
    expect(alpha).toMatchObject({
      title: 'Sync Alpha',
      author: 'Seed Author',
      sourceName: 'SyncTest',
      status: 'ongoing',
      chapterCount: 2,
      readCount: 1,
      unreadCount: 1,
      genres: ['Action'],
    });
    // The two chapter pointers the details screen renders.
    expect(alpha.lastReadChapter).toEqual({ name: 'Chapter 1', number: 1 });
    expect(alpha.nextChapter).toEqual({ name: 'Chapter 2', number: 2 });
    expect(alpha.categoryIds).toHaveLength(1);
    expect(alpha.importIds).toHaveLength(1);
    // int64s stay strings on the wire.
    expect(typeof alpha.rowVersion).toBe('string');

    const beta = found.find((c) => c.id === betaId)!;
    expect(beta.chapterCount).toBe(0);
    expect(beta.nextChapter).toBeNull();
    // Walks the whole real library (~2k titles, 5 pages) — needs headroom.
  }, 60_000);

  it('an up-to-date cursor returns nothing of ours', async () => {
    // Scoped to this run's source: Jest runs the e2e suites in parallel against
    // the same database, so another suite's inserts can legitimately land above
    // our cursor between these two calls. Asserting a globally empty page here
    // was flaky for exactly that reason.
    const page = await delta(await cursor());
    expect(mine(page)).toHaveLength(0);
    expect(page.deleted).not.toContain(alphaId);
    expect(page.deleted).not.toContain(betaId);
  });

  it('a chapter-only read change surfaces its parent title', async () => {
    // The load-bearing case: this touches no `manga` column at all, so a
    // cursor built on `updated_at` would never deliver it.
    const before = await cursor();
    await ds.query(`UPDATE chapter SET read = TRUE WHERE manga_id = $1`, [
      alphaId,
    ]);

    const page = await delta(before);
    const changed = mine(page);
    expect(changed).toHaveLength(1);
    expect(changed[0].id).toBe(alphaId);
    expect(changed[0].readCount).toBe(2);
    expect(changed[0].unreadCount).toBe(0);
    expect(changed[0].nextChapter).toBeNull();

    // restore
    await ds.query(`UPDATE chapter SET read = FALSE WHERE id = $1`, [
      alphaChapterId,
    ]);
  });

  it('a cover-state change surfaces the title', async () => {
    // Cover archiving writes cover_state/cover_path and never updated_at.
    const before = await cursor();
    await ds.query(
      `UPDATE manga SET cover_state = 'archived', cover_path = $2 WHERE id = $1`,
      [betaId, `covers/${betaId}.png`],
    );

    const changed = mine(await delta(before));
    expect(changed).toHaveLength(1);
    expect(changed[0].id).toBe(betaId);
    expect(changed[0].coverState).toBe('archived');
  });

  it('a category link surfaces the title', async () => {
    const before = await cursor();
    const catId = idOf(
      await ds.query(`SELECT id FROM category WHERE name = $1`, [catName]),
    );
    await ds.query(
      `INSERT INTO manga_category (manga_id, category_id) VALUES ($1, $2)`,
      [betaId, catId],
    );

    const changed = mine(await delta(before));
    expect(changed).toHaveLength(1);
    expect(changed[0].id).toBe(betaId);
    expect(changed[0].categoryIds).toEqual([catId]);
  });

  it('paginates by keyset and never repeats or skips a title', async () => {
    // limit=1 forces the truncation path on every page, exercising the cursor
    // arithmetic that must not advance past an undelivered row. Walking from
    // the pre-seed high-water mark keeps this to a handful of requests instead
    // of one per title in the real library.
    let since = baseCursor;
    const seen: string[] = [];
    for (let guard = 0; guard < 200; guard++) {
      const page = await delta(since, 1);
      // Only our own rows: a concurrent suite may re-write its title twice
      // during this walk, which would legitimately deliver that id at two
      // different versions.
      seen.push(...mine(page).map((c) => c.id));
      expect(Number(page.cursor)).toBeGreaterThanOrEqual(Number(since));
      since = page.cursor;
      if (!page.hasMore) break;
    }
    // Both seeded titles arrive exactly once across the whole walk — no skips
    // (each appears) and no repeats (exactly once), which is what keyset
    // pagination has to guarantee.
    expect(seen.filter((id) => id === alphaId)).toHaveLength(1);
    expect(seen.filter((id) => id === betaId)).toHaveLength(1);
    expect(new Set(seen).size).toBe(seen.length);
  });

  it('deleting a title delivers a tombstone, not a change', async () => {
    const before = await cursor();
    await ds.query(`DELETE FROM manga WHERE id = $1`, [betaId]);

    const page = await delta(before);
    expect(page.deleted).toContain(betaId);
    expect(mine(page).map((c) => c.id)).not.toContain(betaId);

    await ds.query(`DELETE FROM sync_tombstone WHERE entity_id = $1`, [betaId]);
  });

  it('treats a malformed cursor as a full resync rather than erroring', async () => {
    const page = await delta('not-a-number');
    expect(page.changed.length).toBeGreaterThan(0);
  });
});
