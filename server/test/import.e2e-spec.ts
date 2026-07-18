import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type {
  CommitStartedDto,
  ImportEvent,
  ImportRecordDto,
  StagedImportDto,
} from '../src/modules/import/import.dto';
import { encodeBackupGzip } from '../src/tachibk/test-util';

const countOf = (rows: unknown): number =>
  (rows as Array<{ count: number }>)[0].count;
const firstRow = <T>(rows: unknown): T => (rows as T[])[0];

/** supertest parser that buffers a text/event-stream response into a string. */
const textParser = (
  res: NodeJS.ReadableStream,
  cb: (err: Error | null, body: string) => void,
) => {
  let data = '';
  (res as NodeJS.ReadableStream & { setEncoding(e: string): void }).setEncoding(
    'utf8',
  );
  res.on('data', (chunk: string) => (data += chunk));
  res.on('end', () => cb(null, data));
};

/** Extract the `data:` payloads from an SSE body into typed events. */
function parseSse(raw: string): ImportEvent[] {
  return raw
    .split('\n\n')
    .map((block) => block.split('\n').find((l) => l.startsWith('data:')))
    .filter((l): l is string => !!l)
    .map((l) => JSON.parse(l.slice(l.indexOf(':') + 1).trim()) as ImportEvent);
}

/**
 * Full-AppModule e2e against the local Postgres (host 5433). Exercises the
 * streamed import pipeline: stage → commit (jobId) → consume SSE → merge/batch →
 * history. `IMPORT_BATCH_SIZE=2` so a small library still crosses batch bounds.
 * Uses run-unique source ids so counts are deterministic; cleans up its own rows.
 */
describe('Import pipeline (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  const sourceId = String(
    9_000_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const sourceIdBatch = String(
    9_100_000_000_000_000_000n + BigInt(runId % 1_000_000),
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

  async function stageFile(bytes: Uint8Array): Promise<StagedImportDto> {
    const res = await request(app.getHttpServer())
      .post('/api/v1/imports/stage')
      .set('Authorization', auth)
      .attach('file', Buffer.from(bytes), fileName)
      .expect(201);
    return res.body as StagedImportDto;
  }

  /** POST commit, then consume the SSE stream to completion; return events + record. */
  async function commitAndWait(
    stagedId: string,
  ): Promise<{ events: ImportEvent[]; record: ImportRecordDto }> {
    const started = await request(app.getHttpServer())
      .post(`/api/v1/imports/stage/${stagedId}/commit`)
      .set('Authorization', auth)
      .expect(201);
    const { jobId } = started.body as CommitStartedDto;

    const res = await request(app.getHttpServer())
      .get(`/api/v1/imports/jobs/${jobId}/events`)
      .set('Authorization', auth)
      .buffer(true)
      .parse(textParser as never)
      .expect(200);

    const events = parseSse(res.body as string);
    const done = events.find((e) => e.type === 'done');
    if (!done || done.type !== 'done') {
      throw new Error(`no done event; got: ${JSON.stringify(events)}`);
    }
    return { events, record: done.record };
  }

  beforeAll(async () => {
    process.env.API_TOKEN = token;
    process.env.IMPORT_BATCH_SIZE = '2';
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
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM manga WHERE source_id = ANY($1)`, [
        [sourceId, sourceIdBatch],
      ]);
      await ds.query(
        `DELETE FROM import_record WHERE source_app = 'app.mihon' AND file_name = $1 AND imported_at >= $2`,
        [fileName, runId],
      );
      await ds.query(`DELETE FROM category WHERE name = $1`, [
        `Reading-${runId}`,
      ]);
      await ds.query(`DELETE FROM known_source WHERE source_id = ANY($1)`, [
        [sourceId, sourceIdBatch],
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
    const body = await stageFile(backup());
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

  it('commits via a streamed job and emits start/manga/done events', async () => {
    const { events, record } = await commitAndWait(stagedId);

    expect(events[0]).toMatchObject({ type: 'start', total: 1 });
    expect(
      events.some((e) => e.type === 'phase' && e.phase === 'categories'),
    ).toBe(true);
    expect(events).toContainEqual(
      expect.objectContaining({
        type: 'manga',
        title: 'Solo Leveling',
        action: 'created',
        processed: 1,
        total: 1,
      }),
    );
    expect(record.stats).toMatchObject({
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
    const changed = backup({
      description: 'An E-rank hunter.',
      chapters: [
        { url: '/c/1', name: 'Ch 1', read: true, lastPageRead: '20' },
        { url: '/c/2', name: 'Ch 2', read: true, lastPageRead: '5' },
      ],
    });
    const staged = await stageFile(changed);
    expect(staged.summary).toMatchObject({ titlesNew: 0, titlesMerged: 1 });
    expect(staged.preview[0].action).toBe('merged');

    const { events } = await commitAndWait(staged.id);
    expect(events).toContainEqual(
      expect.objectContaining({ type: 'manga', action: 'merged' }),
    );

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

  it('commits a multi-title library across batch boundaries (batch size 2)', async () => {
    const titles = 5;
    const bytes = encodeBackupGzip({
      backupSources: [{ name: 'MangaDex', sourceId: sourceIdBatch }],
      backupManga: Array.from({ length: titles }, (_, i) => ({
        source: sourceIdBatch,
        url: `/manga/${runId}/b/${i}`,
        title: `Batch Title ${i}`,
        status: 1,
      })),
    });
    const staged = await stageFile(bytes);
    expect(staged.summary.titlesTotal).toBe(titles);

    const { events, record } = await commitAndWait(staged.id);

    // ceil(5 / 2) = 3 batch commits, all 5 manga streamed.
    expect(events.filter((e) => e.type === 'batch')).toHaveLength(3);
    expect(events.filter((e) => e.type === 'manga')).toHaveLength(titles);
    expect(record.stats).toMatchObject({ titlesNew: titles });
    expect(
      countOf(
        await ds.query(`SELECT count(*)::int FROM manga WHERE source_id = $1`, [
          sourceIdBatch,
        ]),
      ),
    ).toBe(titles);
  });

  it('lists imports in history (newest first)', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/imports')
      .set('Authorization', auth)
      .expect(200);
    const mine = (res.body as ImportRecordDto[]).filter(
      (r) => r.fileName === fileName,
    );
    expect(mine.length).toBeGreaterThanOrEqual(3);
  });
});
