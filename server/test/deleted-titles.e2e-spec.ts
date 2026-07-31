import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type {
  CommitStartedDto,
  ImportEvent,
  StagedImportDto,
} from '../src/modules/import/import.dto';
import type {
  DeletedTitleDto,
  LibraryPageDto,
  RestoreResultDto,
} from '../src/modules/library/library.dto';
import { encodeBackupGzip } from '../src/tachibk/test-util';

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

const parseSse = (raw: string): ImportEvent[] =>
  raw
    .split('\n\n')
    .map((block) => block.split('\n').find((l) => l.startsWith('data:')))
    .filter((l): l is string => !!l)
    .map((l) => JSON.parse(l.slice(l.indexOf(':') + 1).trim()) as ImportEvent);

/**
 * The deletion registry end to end: delete → the next backup no longer brings
 * the title back → restore returns it with its reading progress → purge lets a
 * future import add it again.
 *
 * This is the behaviour the whole feature exists for, so it is tested through
 * the real import pipeline rather than by poking the table.
 */
describe('Deleted titles registry (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  // Must stay below int64 max (9_223_372_036_854_775_807): the protobuf field
  // is signed, so a larger literal wraps negative and the seeded rows become
  // impossible to scope by source id.
  const sourceId = String(
    8_800_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const fileName = `app.mihon_del_${runId}.tachibk`;

  /** A backup with both titles; `salt` changes the bytes so the sha256 differs. */
  const backup = (salt: string) =>
    encodeBackupGzip({
      backupSources: [{ name: 'MangaDex', sourceId }],
      backupManga: [
        {
          source: sourceId,
          url: `/manga/keep-${runId}`,
          title: `Keeper ${salt}`,
          status: 2,
          chapters: [{ url: '/c/1', name: 'Ch 1', read: true }],
        },
        {
          source: sourceId,
          url: `/manga/doomed-${runId}`,
          title: 'Doomed Title',
          status: 2,
          chapters: [
            { url: '/c/1', name: 'Ch 1', read: true },
            { url: '/c/2', name: 'Ch 2', read: true },
            { url: '/c/3', name: 'Ch 3' },
          ],
        },
      ],
    });

  async function stage(salt: string): Promise<StagedImportDto> {
    const res = await request(app.getHttpServer())
      .post('/api/v1/imports/stage')
      .set('Authorization', auth)
      .attach('file', Buffer.from(backup(salt)), fileName)
      .expect(201);
    return res.body as StagedImportDto;
  }

  async function commit(stagedId: string): Promise<ImportEvent[]> {
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
    return parseSse(res.body as string);
  }

  /** Titles currently in the library for this run's source. */
  async function titles(): Promise<string[]> {
    const res = await request(app.getHttpServer())
      .get(`/api/v1/library?sourceIds=${sourceId}&limit=50`)
      .set('Authorization', auth)
      .expect(200);
    return (res.body as LibraryPageDto).items.map((i) => i.title);
  }

  async function registry(): Promise<DeletedTitleDto[]> {
    const res = await request(app.getHttpServer())
      .get('/api/v1/library/deleted')
      .set('Authorization', auth)
      .expect(200);
    return (res.body as DeletedTitleDto[]).filter(
      (d) => d.sourceId === sourceId,
    );
  }

  async function idOfTitle(title: string): Promise<string> {
    const rows = await ds.query(
      `SELECT id FROM manga WHERE source_id = $1 AND title = $2`,
      [sourceId, title],
    );
    return rows[0].id;
  }

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
    if (ds?.isInitialized) {
      const rows = await ds.query(`SELECT id FROM manga WHERE source_id = $1`, [
        sourceId,
      ]);
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      await ds.query(`DELETE FROM deleted_manga WHERE source_id = $1`, [
        sourceId,
      ]);
      await ds.query(`DELETE FROM import_record WHERE file_name = $1`, [
        fileName,
      ]);
      await ds.query(`DELETE FROM known_source WHERE source_id = $1`, [
        sourceId,
      ]);
      // Deleting seeded rows leaves tombstones; clear them or this run's ids
      // ride along in every future sync delta.
      for (const r of rows) {
        await ds.query(`DELETE FROM sync_tombstone WHERE entity_id = $1`, [
          r.id,
        ]);
      }
    }
    await app?.close();
  });

  let doomedRegistryId = '';

  it('imports both titles', async () => {
    const staged = await stage('one');
    expect(staged.summary).toMatchObject({ titlesNew: 2, titlesSkipped: 0 });
    await commit(staged.id);
    expect((await titles()).sort()).toEqual(['Doomed Title', 'Keeper one']);
  });

  it('deleting a title records it in the registry with its progress', async () => {
    await request(app.getHttpServer())
      .delete(`/api/v1/library/${await idOfTitle('Doomed Title')}`)
      .set('Authorization', auth)
      .expect(204);

    const entries = await registry();
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      title: 'Doomed Title',
      sourceName: 'MangaDex',
      chapterCount: 3,
      readCount: 2,
      seenCount: 0,
      lastSeenAt: null,
    });
    doomedRegistryId = entries[0].id;
  });

  it('a later backup previews it as skipped and does not bring it back', async () => {
    // A different salt = different bytes, so this isn't rejected as a duplicate
    // file — it is a genuinely newer backup that still contains the title.
    const staged = await stage('two');
    expect(staged.summary).toMatchObject({
      titlesTotal: 2,
      titlesMerged: 1,
      titlesNew: 0,
      titlesSkipped: 1,
    });
    expect(staged.preview.find((p) => p.title === 'Doomed Title')?.action).toBe(
      'skipped',
    );

    const events = await commit(staged.id);
    expect(events).toContainEqual(
      expect.objectContaining({
        type: 'manga',
        title: 'Doomed Title',
        action: 'skipped',
      }),
    );

    expect(await titles()).not.toContain('Doomed Title');
    // The registry now knows a backup wanted it back — the signal the restore
    // list shows the user.
    const entry = (await registry())[0];
    expect(entry.seenCount).toBe(1);
    expect(entry.lastSeenAt).toBeGreaterThan(0);
  });

  it('restores it with chapters and read progress intact', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/library/deleted/restore')
      .set('Authorization', auth)
      .send({ ids: [doomedRegistryId] })
      .expect(200);
    expect(res.body as RestoreResultDto).toMatchObject({
      restored: 1,
      skipped: 0,
    });

    expect(await titles()).toContain('Doomed Title');
    expect(await registry()).toHaveLength(0);

    const restoredId = await idOfTitle('Doomed Title');
    const detail = await request(app.getHttpServer())
      .get(`/api/v1/library/${restoredId}`)
      .set('Authorization', auth)
      .expect(200);
    expect(detail.body).toMatchObject({
      chapterCount: 3,
      readCount: 2,
      // The archived cover file was unlinked with the row, so it comes back
      // unarchived and has to be re-fetched.
      coverState: 'none',
    });
  });

  it('purging unblocks a title instead of restoring it', async () => {
    await request(app.getHttpServer())
      .delete(`/api/v1/library/${await idOfTitle('Doomed Title')}`)
      .set('Authorization', auth)
      .expect(204);
    const entryId = (await registry())[0].id;

    const purge = await request(app.getHttpServer())
      .post('/api/v1/library/deleted/purge')
      .set('Authorization', auth)
      .send({ ids: [entryId] })
      .expect(200);
    expect(purge.body).toEqual({ purged: 1 });
    expect(await registry()).toHaveLength(0);
    // Still deleted — purge forgets the entry, it doesn't restore.
    expect(await titles()).not.toContain('Doomed Title');

    // …and now an import is free to add it again.
    const staged = await stage('three');
    expect(staged.summary).toMatchObject({ titlesNew: 1, titlesSkipped: 0 });
    await commit(staged.id);
    expect(await titles()).toContain('Doomed Title');
  });

  it('guards the registry endpoints', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/library/deleted')
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/library/deleted/restore')
      .set('Authorization', auth)
      .send({ ids: [] })
      .expect(400);
  });
});
