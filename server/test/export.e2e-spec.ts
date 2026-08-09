import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import {
  BackupNormalizer,
  BackupParser,
  type NormalizedBackup,
} from '../src/tachibk';
import type {
  ExportFacetsDto,
  ExportPreviewDto,
} from '../src/modules/export/export.dto';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/**
 * Backup creation, end to end against the local Postgres (host 5433).
 *
 * The point of this suite is the loop, not the endpoint: it seeds a known slice
 * of the vault, exports it over HTTP, and decodes the returned bytes with the
 * *import* path's own parser. Anything the writer gets wrong — a dropped
 * favorite, a mangled 64-bit source id, a category that lost its membership —
 * shows up as a diff in the decoded model rather than as a file that merely
 * happens to be well-formed gzip.
 */
describe('Export (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  // Unique per run so the suite's assertions are unaffected by whatever else
  // the dev vault holds, and so cleanup can key off it.
  const sourceId = String(runId);
  const sourceName = `E2E Source ${runId}`;
  const appId = `dev.export${runId % 1_000_000}`;
  const categoryName = `E2E Reading ${runId}`;
  const sha = `sha-export-${runId}`;
  let categoryId = '';

  const parser = new BackupParser();
  const normalizer = new BackupNormalizer();

  /** Decode an exported file the same way an import would. */
  const decode = async (bytes: Buffer): Promise<NormalizedBackup> =>
    normalizer.normalize(
      await parser.parse(bytes, `${appId}_2026-08-06.tachibk`),
    );

  const preview = async (
    scope: Record<string, unknown>,
  ): Promise<ExportPreviewDto> => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/exports/preview')
      .set('Authorization', auth)
      .send(scope)
      .expect(200);
    return res.body as ExportPreviewDto;
  };

  /** Export the seeded source only, so assertions don't depend on vault size. */
  const build = async (
    over: Record<string, unknown> = {},
  ): Promise<{ backup: NormalizedBackup; headers: Record<string, string> }> => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/exports/build')
      .set('Authorization', auth)
      .send({ mode: 'filter', filter: { sourceIds: [sourceId] }, ...over })
      .responseType('blob')
      .expect(200);
    return {
      backup: await decode(res.body as Buffer),
      headers: res.headers,
    };
  };

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

    // --- seed: three titles on one source, deliberately varied ---
    categoryId = idOf(
      await ds.query(
        `INSERT INTO category (name, sort) VALUES ($1, 7) RETURNING id`,
        [categoryName],
      ),
    );

    const insertManga = async (
      url: string,
      title: string,
      favorite: boolean,
    ): Promise<string> =>
      idOf(
        await ds.query(
          `INSERT INTO manga (source_id, manga_url, source_name, title, author,
                              description, genres, status, thumbnail_url, notes,
                              favorite, date_added, updated_at)
           VALUES ($1, $2, $3, $4, 'E2E Author', 'A description.',
                   '["Action"]'::jsonb, 'ongoing', 'https://example.test/c.jpg',
                   'note', $5, 1700000000000, 1750000000000)
           RETURNING id`,
          [sourceId, url, sourceName, title, favorite],
        ),
      );

    const alpha = await insertManga('/m/alpha', `E2E Alpha ${runId}`, true);
    const beta = await insertManga('/m/beta', `E2E Beta ${runId}`, false);
    await insertManga('/m/gamma', `E2E Gamma ${runId}`, true);

    // Alpha: 3 chapters, 2 read with real progress. Beta: 2 unread.
    await ds.query(
      `INSERT INTO chapter (manga_id, url, name, chapter_number, scanlator, read,
                            bookmark, last_page_read, date_upload, date_fetch,
                            source_order, last_read_at, read_duration)
       VALUES ($1, '/c/1', 'Chapter 1', 1, 'Team A', true,  false, 14, 1690000000000, 1690000100000, 0, 1710000000000, 45000),
              ($1, '/c/2', 'Chapter 2', 2, 'Team A', true,  true,   0, 1690100000000, 1690100100000, 1, 1710000500000, 30000),
              ($1, '/c/3', 'Chapter 3', 3, NULL,     false, false,  0, 1690200000000, 1690200100000, 2, NULL, 0),
              ($2, '/c/1', 'Chapter 1', 1, NULL,     false, false,  0, 1690000000000, 1690000100000, 0, NULL, 0),
              ($2, '/c/2', 'Chapter 2', 2, NULL,     false, false,  0, 1690100000000, 1690100100000, 1, NULL, 0)`,
      [alpha, beta],
    );

    await ds.query(
      `INSERT INTO manga_category (manga_id, category_id) VALUES ($1, $2)`,
      [alpha, categoryId],
    );

    await ds.query(
      `INSERT INTO tracking (manga_id, tracker, remote_id, tracking_url, title,
                             last_chapter_read, total_chapters, score, status,
                             started_at, finished_at)
       VALUES ($1, 'anilist', '4294967396', 'https://anilist.co/manga/4294967396',
               'E2E Alpha', 2, 3, 8.5, 1, 1600000000000, NULL)`,
      [alpha],
    );

    // Attribute alpha+beta to a backup app, so the app facet/filter has data.
    const importId = idOf(
      await ds.query(
        `INSERT INTO import_record (file_name, file_size, sha256, source_app,
                                    container, imported_at, stats)
         VALUES ($1, 1, $2, $3, 'gzip-proto', $4, '{}') RETURNING id`,
        [`${appId}_${runId}.tachibk`, sha, appId, runId],
      ),
    );
    await ds.query(
      `INSERT INTO manga_import (manga_id, import_id) VALUES ($1, $3), ($2, $3)`,
      [alpha, beta, importId],
    );
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [sha]);
      await ds.query(`DELETE FROM category WHERE name = $1`, [categoryName]);
      await ds.query(`DELETE FROM backup_app WHERE id = $1`, [appId]);
    }
    await app?.close();
  });

  it('rejects the endpoints without auth', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/exports/facets')
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/exports/build')
      .expect(401);
  });

  it('lists the seeded source, app and category as facets with counts', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/exports/facets')
      .set('Authorization', auth)
      .expect(200);
    const facets = res.body as ExportFacetsDto;

    expect(facets.totalTitles).toBeGreaterThanOrEqual(3);
    expect(facets.sources).toContainEqual({
      id: sourceId,
      label: sourceName,
      count: 3,
    });
    expect(facets.apps).toContainEqual({ id: appId, label: appId, count: 2 });
    expect(facets.categories).toContainEqual({
      id: categoryId,
      label: categoryName,
      count: 1,
    });
  });

  it('previews a source scope with exact counts', async () => {
    const p = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId] },
    });
    expect(p).toMatchObject({
      titles: 3,
      chapters: 5,
      readChapters: 2,
      categories: 1,
      sources: 1,
      trackedTitles: 1,
    });
    expect(p.fileName).toMatch(
      /^mangavault_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$/,
    );
    expect(p.estimatedBytes).toBeGreaterThan(0);
    expect(p.sample.map((s) => s.title)).toEqual([
      `E2E Alpha ${runId}`,
      `E2E Beta ${runId}`,
      `E2E Gamma ${runId}`,
    ]);
  });

  it('previews the favorites-only and app scopes', async () => {
    const favorites = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId], favorite: true },
    });
    expect(favorites.titles).toBe(2);

    const byApp = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId], sourceApps: [appId] },
    });
    expect(byApp.titles).toBe(2);

    const started = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId], startedOnly: true },
    });
    expect(started.titles).toBe(1);

    const unread = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId], unreadOnly: true },
    });
    expect(unread.titles).toBe(2);
  });

  it('an empty hand-picked selection exports nothing, not everything', async () => {
    expect((await preview({ mode: 'ids', ids: [] })).titles).toBe(0);
  });

  it('builds a file the import parser reads back title-for-title', async () => {
    const { backup, headers } = await build();

    expect(headers['content-type']).toContain('application/gzip');
    expect(headers['content-disposition']).toContain('.tachibk');
    expect(headers['x-export-titles']).toBe('3');

    expect(backup.manga.map((m) => m.title)).toEqual([
      `E2E Alpha ${runId}`,
      `E2E Beta ${runId}`,
      `E2E Gamma ${runId}`,
    ]);
    expect(backup.sources).toEqual([{ sourceId, name: sourceName }]);

    const alpha = backup.manga[0];
    expect(alpha.key).toEqual({ sourceId, mangaUrl: '/m/alpha' });
    expect(alpha.author).toBe('E2E Author');
    expect(alpha.genres).toEqual(['Action']);
    expect(alpha.status).toBe('ongoing');
    expect(alpha.notes).toBe('note');
    expect(alpha.dateAdded).toBe(1700000000000);
    expect(alpha.categoryNames).toEqual([categoryName]);
    expect(alpha.chapters).toHaveLength(3);
    expect(alpha.chapters[0]).toMatchObject({
      url: '/c/1',
      name: 'Chapter 1',
      chapterNumber: 1,
      scanlator: 'Team A',
      read: true,
      lastPageRead: 14,
      lastReadAt: 1710000000000,
      readDuration: 45000,
    });
    expect(alpha.chapters[1].bookmark).toBe(true);
    expect(alpha.chapters[2].read).toBe(false);
    expect(alpha.tracking).toEqual([
      {
        tracker: 'anilist',
        // Above 2^31 — proves the id rode the int64 field, not the deprecated one.
        remoteId: '4294967396',
        trackingUrl: 'https://anilist.co/manga/4294967396',
        title: 'E2E Alpha',
        lastChapterRead: 2,
        totalChapters: 3,
        score: 8.5,
        status: 1,
        startedAt: 1600000000000,
        finishedAt: undefined,
      },
    ]);

    // The field that defaults to TRUE when absent: a non-favorite must survive.
    expect(backup.manga[1].favorite).toBe(false);
    expect(backup.manga[0].favorite).toBe(true);
    expect(backup.manga[2].chapters).toEqual([]);
  });

  it('honours the include flags', async () => {
    const noChapters = await build({ include: { chapters: false } });
    expect(noChapters.backup.manga.every((m) => m.chapters.length === 0)).toBe(
      true,
    );
    // Titles and their metadata still travel — only the chapters are dropped.
    expect(noChapters.backup.manga).toHaveLength(3);
    expect(noChapters.backup.manga[0].title).toBe(`E2E Alpha ${runId}`);

    const noProgress = await build({
      include: { chapters: true, readProgress: false },
    });
    const alpha = noProgress.backup.manga[0];
    expect(alpha.chapters).toHaveLength(3);
    expect(alpha.chapters.every((c) => !c.read)).toBe(true);
    expect(alpha.chapters.every((c) => c.lastReadAt === undefined)).toBe(true);
    expect(alpha.chapters.every((c) => c.readDuration === 0)).toBe(true);
    // Bookmarks are a deliberate mark, not reading progress — they stay.
    expect(alpha.chapters[1].bookmark).toBe(true);

    const noCategories = await build({ include: { categories: false } });
    expect(noCategories.backup.categories).toEqual([]);
    expect(noCategories.backup.manga[0].categoryNames).toEqual([]);

    const noTracking = await build({ include: { tracking: false } });
    expect(noTracking.backup.manga[0].tracking).toEqual([]);
  });

  it('names the file for the target app, so a re-import attributes it back', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/exports/build')
      .set('Authorization', auth)
      .send({
        mode: 'filter',
        filter: { sourceIds: [sourceId] },
        targetApp: 'app.mihon',
      })
      .responseType('blob')
      .expect(200);

    const fileName = res.headers['x-export-file-name'];
    expect(fileName).toMatch(
      /^app\.mihon_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$/,
    );
    // The filename is the format's only carrier of app identity: prove the
    // import path reads this one back as Mihon.
    const parsed = await parser.parse(res.body as Buffer, fileName);
    expect(parsed.sourceApp).toBe('app.mihon');
    expect(parsed.container).toBe('gzip-proto');
  });

  it('rejects a malformed target app id', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/exports/build')
      .set('Authorization', auth)
      .send({ targetApp: 'not a valid id' })
      .expect(400);
  });

  it('exports a hand-picked selection', async () => {
    const p = await preview({
      mode: 'filter',
      filter: { sourceIds: [sourceId] },
    });
    const pickedId = p.sample[1].id; // Beta
    const res = await request(app.getHttpServer())
      .post('/api/v1/exports/build')
      .set('Authorization', auth)
      .send({ mode: 'ids', ids: [pickedId] })
      .responseType('blob')
      .expect(200);

    const backup = await decode(res.body as Buffer);
    expect(backup.manga.map((m) => m.title)).toEqual([`E2E Beta ${runId}`]);
    expect(res.headers['x-export-titles']).toBe('1');
  });
});
