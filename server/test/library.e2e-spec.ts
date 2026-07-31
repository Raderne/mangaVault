import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type {
  CategoryDto,
  LibraryPageDto,
  VaultMangaDto,
} from '../src/modules/library/library.dto';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/**
 * Library query API e2e against the local Postgres (host 5433). Seeds a small,
 * run-unique set of titles/chapters/category/import directly via SQL (so counts
 * are deterministic even when the DB already holds a real imported library) and
 * scopes every assertion by `sourceIds` to isolate them. Cleans up its own rows.
 */
describe('Library queries (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  const sourceId = String(
    9_200_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const catName = `Seinen-${runId}`;
  const fileName = `app.mihon_lib_${runId}.tachibk`;
  const sha = `sha-lib-${runId}`;

  let alphaId = '';
  let betaId = '';
  let gammaId = '';
  let storageDir = '';

  /** Ids seeded by the destructive tests, so their tombstones can be cleared. */
  const disposableIds: string[] = [];

  /** Insert a throwaway title for the destructive tests. */
  async function seedDisposable(title: string): Promise<string> {
    const id = idOf(
      await ds.query(
        `INSERT INTO manga (source_id, manga_url, source_name, title, status, updated_at, date_added)
         VALUES ($1, $2, 'MangaVaultTest', $3, 'ongoing', $4, $4) RETURNING id`,
        [sourceId, `/del/${title}`, title, runId],
      ),
    );
    disposableIds.push(id);
    return id;
  }

  /** Shorthand: fetch a library page scoped to this run's source. */
  async function page(qs: string): Promise<LibraryPageDto> {
    const res = await request(app.getHttpServer())
      .get(`/api/v1/library?sourceIds=${sourceId}&${qs}`)
      .set('Authorization', auth)
      .expect(200);
    return res.body as LibraryPageDto;
  }

  beforeAll(async () => {
    process.env.API_TOKEN = token;
    process.env.DATABASE_URL ??=
      'postgres://mangavault:mangavault@localhost:5433/mangavault';
    // Deleting a title unlinks its archived cover, so the destructive tests
    // need a storage dir of their own — never the real vault.
    storageDir = await mkdtemp(join(tmpdir(), 'mv-e2e-library-'));
    process.env.STORAGE_DIR = storageDir;

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

    const insertManga = async (
      title: string,
      status: string,
      author: string | null,
    ): Promise<string> =>
      idOf(
        await ds.query(
          `INSERT INTO manga (source_id, manga_url, source_name, title, author, status, updated_at, date_added)
           VALUES ($1, $2, 'MangaVaultTest', $3, $4, $5, $6, $6) RETURNING id`,
          [sourceId, `/m/${title}`, title, author, status, runId],
        ),
      );

    const insertChapter = async (
      mangaId: string,
      n: number,
      read: boolean,
      lastReadAt: number | null,
    ): Promise<void> => {
      await ds.query(
        `INSERT INTO chapter (manga_id, url, name, chapter_number, read, last_read_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [mangaId, `/c/${n}`, `Chapter ${n}`, n, read, lastReadAt],
      );
    };

    alphaId = await insertManga('Alpha Archivist', 'ongoing', 'Author One');
    betaId = await insertManga('Beta Compendium', 'completed', 'Author Two');
    gammaId = await insertManga('Gamma Chronicle', 'on_hiatus', null);
    // Gamma is the non-favorite title for the favorite filter test (DB default is true).
    await ds.query(`UPDATE manga SET favorite = FALSE WHERE id = $1`, [
      gammaId,
    ]);

    // Alpha: 3 chapters, 2 read (ch 2 most recently).
    await insertChapter(alphaId, 1, true, runId - 1000);
    await insertChapter(alphaId, 2, true, runId);
    await insertChapter(alphaId, 3, false, null);
    // Beta: 5 chapters, none read.
    for (let n = 1; n <= 5; n++) await insertChapter(betaId, n, false, null);
    // Gamma: no chapters.

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
        [fileName, sha, runId],
      ),
    );
    await ds.query(
      `INSERT INTO manga_import (manga_id, import_id) VALUES ($1, $2)`,
      [alphaId, importId],
    );
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      // manga delete cascades chapters, manga_category and manga_import rows.
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [sha]);
      // Deleting through the API registers the titles in the recycle bin, which
      // would otherwise keep blocking this source's keys for good.
      await ds.query(`DELETE FROM deleted_manga WHERE source_id = $1`, [
        sourceId,
      ]);
      await ds.query(`DELETE FROM category WHERE name = $1`, [catName]);
      // Every delete above (and in the delete tests) leaves a tombstone; drop
      // them, or this run's ids ride along in every future sync delta forever.
      for (const id of [alphaId, betaId, gammaId, ...disposableIds].filter(
        Boolean,
      )) {
        await ds.query(`DELETE FROM sync_tombstone WHERE entity_id = $1`, [id]);
      }
    }
    await rm(storageDir, { recursive: true, force: true });
    await app?.close();
  });

  it('rejects the library endpoint without auth', () => {
    return request(app.getHttpServer()).get('/api/v1/library').expect(401);
  });

  it('paginates: total counts the whole match, items honor the limit', async () => {
    const p = await page('sortBy=title&sortDir=asc&limit=2');
    expect(p.total).toBe(3);
    expect(p.items).toHaveLength(2);
    expect(p.items.map((i) => i.title)).toEqual([
      'Alpha Archivist',
      'Beta Compendium',
    ]);

    const p2 = await page('sortBy=title&sortDir=asc&limit=2&offset=2');
    expect(p2.total).toBe(3);
    expect(p2.items.map((i) => i.title)).toEqual(['Gamma Chronicle']);
  });

  it('filters by status', async () => {
    const p = await page('status=completed');
    expect(p.total).toBe(1);
    expect(p.items[0].title).toBe('Beta Compendium');
  });

  it('filters by favorite', async () => {
    const fav = await page('favorite=true&sortBy=title&sortDir=asc');
    expect(fav.total).toBe(2);
    expect(fav.items.map((i) => i.title)).toEqual([
      'Alpha Archivist',
      'Beta Compendium',
    ]);

    const unfav = await page('favorite=false');
    expect(unfav.total).toBe(1);
    expect(unfav.items[0].title).toBe('Gamma Chronicle');
  });

  it('full-text searches the title', async () => {
    const p = await page('text=Chronicle');
    expect(p.total).toBe(1);
    expect(p.items[0].title).toBe('Gamma Chronicle');
  });

  it('sorts by chapter count and exposes unread counts', async () => {
    const p = await page('sortBy=chapterCount&sortDir=desc');
    expect(p.items.map((i) => i.title)).toEqual([
      'Beta Compendium',
      'Alpha Archivist',
      'Gamma Chronicle',
    ]);
    const alpha = p.items.find((i) => i.title === 'Alpha Archivist')!;
    expect(alpha.chapterCount).toBe(3);
    expect(alpha.unreadCount).toBe(1);
    expect(alpha.lastReadAt).toBe(runId);
  });

  it('returns a full title with computed progress and archive history', async () => {
    const res = await request(app.getHttpServer())
      .get(`/api/v1/library/${alphaId}`)
      .set('Authorization', auth)
      .expect(200);
    const m = res.body as VaultMangaDto;

    expect(m.title).toBe('Alpha Archivist');
    expect(m.chapterCount).toBe(3);
    expect(m.readCount).toBe(2);
    expect(m.unreadCount).toBe(1);
    expect(m.lastReadChapter).toMatchObject({ name: 'Chapter 2', number: 2 });
    expect(m.nextChapter).toMatchObject({ name: 'Chapter 3', number: 3 });
    expect(m.categories.map((c) => c.name)).toContain(catName);
    expect(m.archive).toHaveLength(1);
    expect(m.archive[0]).toMatchObject({ fileName, sourceApp: 'app.mihon' });
  });

  it('404s an unknown id and 400s a non-uuid id', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/library/00000000-0000-0000-0000-000000000000')
      .set('Authorization', auth)
      .expect(404);
    await request(app.getHttpServer())
      .get('/api/v1/library/not-a-uuid')
      .set('Authorization', auth)
      .expect(400);
  });

  it('lists categories with title counts', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/categories')
      .set('Authorization', auth)
      .expect(200);
    const mine = (res.body as CategoryDto[]).find((c) => c.name === catName);
    expect(mine).toBeDefined();
    expect(mine!.count).toBe(1);
  });

  // Silence unused-var lint for the id captured only for symmetry.
  it('seeded three titles', () => {
    expect([alphaId, betaId, gammaId].every(Boolean)).toBe(true);
  });

  // ---- deletion (destructive: seeds and removes its own throwaway rows) ----

  it('deletes a title with its chapters, cover file and a tombstone', async () => {
    const id = await seedDisposable('Doomed One');
    await ds.query(
      `INSERT INTO chapter (manga_id, url, name, chapter_number, read)
       VALUES ($1, '/c/1', 'Chapter 1', 1, false)`,
      [id],
    );
    // A stand-in for an archived cover, stored exactly as CoverService does.
    const rel = `covers/${id}.png`;
    await mkdir(join(storageDir, 'covers'), { recursive: true });
    await writeFile(join(storageDir, rel), Buffer.from([0x89, 0x50]));
    await ds.query(
      `UPDATE manga SET cover_path = $2, cover_state = 'archived' WHERE id = $1`,
      [id, rel],
    );

    await request(app.getHttpServer())
      .delete(`/api/v1/library/${id}`)
      .set('Authorization', auth)
      .expect(204);

    await request(app.getHttpServer())
      .get(`/api/v1/library/${id}`)
      .set('Authorization', auth)
      .expect(404);

    const chapters = await ds.query<{ n: number }[]>(
      `SELECT COUNT(*)::int AS n FROM chapter WHERE manga_id = $1`,
      [id],
    );
    expect(chapters[0].n).toBe(0);

    // The tombstone is what carries the delete to every device mirror.
    const tombs = await ds.query<{ n: number }[]>(
      `SELECT COUNT(*)::int AS n FROM sync_tombstone
        WHERE entity = 'manga' AND entity_id = $1`,
      [id],
    );
    expect(tombs[0].n).toBe(1);

    await expect(stat(join(storageDir, rel))).rejects.toThrow();
  });

  it('404s deleting an unknown id and 400s a non-uuid', async () => {
    await request(app.getHttpServer())
      .delete('/api/v1/library/00000000-0000-0000-0000-000000000000')
      .set('Authorization', auth)
      .expect(404);
    await request(app.getHttpServer())
      .delete('/api/v1/library/not-a-uuid')
      .set('Authorization', auth)
      .expect(400);
  });

  it('bulk-deletes, tolerating ids that are already gone', async () => {
    const first = await seedDisposable('Doomed Two');
    const second = await seedDisposable('Doomed Three');

    const res = await request(app.getHttpServer())
      .post('/api/v1/library/delete')
      .set('Authorization', auth)
      .send({
        ids: [first, second, '00000000-0000-0000-0000-000000000000'],
      })
      .expect(200);
    expect(res.body).toMatchObject({ deleted: 2, coversRemoved: 0 });

    const left = await ds.query<{ n: number }[]>(
      `SELECT COUNT(*)::int AS n FROM manga WHERE id = ANY($1::uuid[])`,
      [[first, second]],
    );
    expect(left[0].n).toBe(0);
  });

  it('rejects an empty or malformed bulk delete, and requires auth', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/library/delete')
      .set('Authorization', auth)
      .send({ ids: [] })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/library/delete')
      .set('Authorization', auth)
      .send({ ids: ['not-a-uuid'] })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/library/delete')
      .send({ ids: [alphaId] })
      .expect(401);
  });
});
