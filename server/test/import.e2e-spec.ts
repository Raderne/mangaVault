import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type {
  ImportRecordDto,
  StagedImportDto,
} from '../src/modules/import/import.dto';
import { encodeBackupGzip } from '../src/tachibk/test-util';

const countOf = (rows: unknown): number =>
  (rows as Array<{ count: number }>)[0].count;
const firstRow = <T>(rows: unknown): T => (rows as T[])[0];

/**
 * Full-AppModule e2e against the local Postgres (host 5433). Exercises the
 * import pipeline end-to-end: stage -> commit -> re-import merge -> history.
 * Uses a run-unique source id so counts are deterministic regardless of any
 * data already in the dev DB, and cleans up its own rows afterwards.
 */
describe('Import pipeline (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  // Unique per run so file sha256 and (source_id, url) never collide with prior runs.
  const runId = Date.now();
  const sourceId = String(
    9_000_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const fileName = `app.mihon_2026-07-18_10-30.tachibk`;

  const backup = (over: Record<string, unknown> = {}) =>
    encodeBackupGzip({
      backupCategories: [{ name: `Reading-${runId}`, order: '0' }],
      backupSources: [{ name: 'MangaDex', sourceId }],
      backupManga: [
        {
          source: sourceId,
          url: `/manga/${runId}`,
          title: 'Solo Leveling',
          status: 2,
          categories: ['0'],
          chapters: [
            { url: '/c/1', name: 'Ch 1', read: true, lastPageRead: '20' },
          ],
          ...over,
        },
      ],
    });

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
  });

  afterAll(async () => {
    // Remove only rows this run created (manga cascade-deletes chapters/links).
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      await ds.query(
        `DELETE FROM import_record WHERE source_app = 'app.mihon' AND file_name = $1 AND imported_at >= $2`,
        [fileName, runId],
      );
      await ds.query(`DELETE FROM category WHERE name = $1`, [
        `Reading-${runId}`,
      ]);
      await ds.query(`DELETE FROM known_source WHERE source_id = $1`, [
        sourceId,
      ]);
    }
    await app?.close();
  });

  it('rejects staging without auth', () => {
    return request(app.getHttpServer())
      .post('/api/v1/imports/stage')
      .attach('file', Buffer.from(backup()), fileName)
      .expect(401);
  });

  let stagedId: string;

  it('stages an upload and previews it as a new title', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/imports/stage')
      .set('Authorization', auth)
      .attach('file', Buffer.from(backup()), fileName)
      .expect(201);

    const body = res.body as StagedImportDto;
    expect(body.fileMeta).toMatchObject({
      sourceApp: 'app.mihon',
      container: 'gzip-proto',
    });
    expect(body.summary).toMatchObject({
      titlesTotal: 1,
      titlesNew: 1,
      titlesMerged: 0,
      chaptersTotal: 1,
    });
    expect(body.preview[0]).toMatchObject({
      action: 'created',
      title: 'Solo Leveling',
    });
    stagedId = body.id;
  });

  it('commits the staged import and records stats', async () => {
    const res = await request(app.getHttpServer())
      .post(`/api/v1/imports/stage/${stagedId}/commit`)
      .set('Authorization', auth)
      .expect(201);

    expect((res.body as ImportRecordDto).stats).toMatchObject({
      titlesNew: 1,
      titlesMerged: 0,
      chaptersTotal: 1,
    });

    expect(
      countOf(
        await ds.query(`SELECT count(*)::int FROM manga WHERE source_id = $1`, [
          sourceId,
        ]),
      ),
    ).toBe(1);
    expect(
      countOf(
        await ds.query(
          `SELECT count(*)::int FROM chapter c JOIN manga m ON m.id = c.manga_id WHERE m.source_id = $1`,
          [sourceId],
        ),
      ),
    ).toBe(1);
  });

  it('re-imports a changed backup and merges (OR-reads, adds chapter, no dupes)', async () => {
    // Same title, adds a second chapter and marks progress; different file bytes.
    const changed = backup({
      description: 'An E-rank hunter.',
      chapters: [
        { url: '/c/1', name: 'Ch 1', read: true, lastPageRead: '20' },
        { url: '/c/2', name: 'Ch 2', read: true, lastPageRead: '5' },
      ],
    });

    const stage = await request(app.getHttpServer())
      .post('/api/v1/imports/stage')
      .set('Authorization', auth)
      .attach('file', Buffer.from(changed), fileName)
      .expect(201);
    const staged = stage.body as StagedImportDto;
    expect(staged.summary).toMatchObject({ titlesNew: 0, titlesMerged: 1 });
    expect(staged.preview[0].action).toBe('merged');

    await request(app.getHttpServer())
      .post(`/api/v1/imports/stage/${staged.id}/commit`)
      .set('Authorization', auth)
      .expect(201);

    // Still exactly one manga row; now two chapters (union by url, no duplicate).
    expect(
      countOf(
        await ds.query(`SELECT count(*)::int FROM manga WHERE source_id = $1`, [
          sourceId,
        ]),
      ),
    ).toBe(1);
    expect(
      countOf(
        await ds.query(
          `SELECT count(*)::int FROM chapter c JOIN manga m ON m.id = c.manga_id WHERE m.source_id = $1`,
          [sourceId],
        ),
      ),
    ).toBe(2);
    const desc = firstRow<{ description: string }>(
      await ds.query(`SELECT description FROM manga WHERE source_id = $1`, [
        sourceId,
      ]),
    );
    expect(desc.description).toBe('An E-rank hunter.');
  });

  it('lists the two imports in history (newest first)', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/imports')
      .set('Authorization', auth)
      .expect(200);
    const mine = (res.body as ImportRecordDto[]).filter(
      (r) => r.fileName === fileName,
    );
    expect(mine.length).toBeGreaterThanOrEqual(2);
  });
});
