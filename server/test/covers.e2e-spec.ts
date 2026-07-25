import { createServer, Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type { CoverResultDto } from '../src/modules/covers/cover.dto';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/** A minimal but valid PNG (magic bytes + padding — enough to sniff). */
const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(48),
]);

/**
 * Cover archiving e2e against the local Postgres (host 5433). A tiny in-process
 * HTTP server stands in for a source CDN (one path serves a PNG, one 403s), so
 * the fetch → archive → serve path is exercised end-to-end without hitting the
 * internet. Deliberately does NOT call `archive-missing` (which would scan the
 * whole DB and try to fetch every real cover); single-title `retry`/`custom`
 * are scoped to the seeded rows. Uses a temp STORAGE_DIR and cleans up.
 */
describe('Covers (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  let cdn: Server;
  let cdnBase: string;
  let storageDir: string;

  const token = 'e2e-token';
  const auth = `Bearer ${token}`;
  const runId = Date.now();
  const sourceId = String(
    9_300_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );

  let okId = '';
  let denyId = '';

  beforeAll(async () => {
    process.env.API_TOKEN = token;
    process.env.DATABASE_URL ??=
      'postgres://mangavault:mangavault@localhost:5433/mangavault';
    storageDir = await mkdtemp(join(tmpdir(), 'mv-e2e-covers-'));
    process.env.STORAGE_DIR = storageDir;

    // Stand-in source CDN.
    cdn = createServer((req, res) => {
      if (req.url === '/cover.png') {
        res.writeHead(200, { 'content-type': 'image/png' });
        res.end(PNG);
      } else {
        res.writeHead(403).end('denied');
      }
    });
    await new Promise<void>((resolve) => cdn.listen(0, '127.0.0.1', resolve));
    cdnBase = `http://127.0.0.1:${(cdn.address() as AddressInfo).port}`;

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

    const insert = async (title: string, thumb: string): Promise<string> =>
      idOf(
        await ds.query(
          `INSERT INTO manga (source_id, manga_url, source_name, title, status,
                              thumbnail_url, cover_state, updated_at, date_added)
           VALUES ($1, $2, 'CoverTest', $3, 'ongoing', $4, 'none', $5, $5)
           RETURNING id`,
          [sourceId, `/m/${title}`, title, thumb, runId],
        ),
      );

    okId = await insert('Fetchable', `${cdnBase}/cover.png`);
    denyId = await insert('Forbidden', `${cdnBase}/deny.png`);
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
    }
    await app?.close();
    await new Promise<void>((resolve) => cdn.close(() => resolve()));
    await rm(storageDir, { recursive: true, force: true });
  });

  /** GET a binary body as a Buffer (superagent won't parse image/*). */
  const getBinary = (path: string) =>
    request(app.getHttpServer())
      .get(path)
      .set('Authorization', auth)
      .buffer(true)
      .parse((res, cb) => {
        const chunks: Buffer[] = [];
        res.on('data', (c: Buffer) => chunks.push(c));
        res.on('end', () => cb(null, Buffer.concat(chunks)));
      });

  it('rejects cover routes without auth', () => {
    return request(app.getHttpServer())
      .post(`/api/v1/covers/${okId}/retry`)
      .expect(401);
  });

  it('archives a fetchable cover and then serves it', async () => {
    const retry = await request(app.getHttpServer())
      .post(`/api/v1/covers/${okId}/retry`)
      .set('Authorization', auth)
      .expect(201);
    expect(retry.body as CoverResultDto).toMatchObject({
      mangaId: okId,
      outcome: 'archived',
      coverState: 'archived',
    });

    const img = await getBinary(`/api/v1/covers/${okId}`).expect(200);
    expect(img.headers['content-type']).toMatch(/image\/png/);
    expect(Buffer.isBuffer(img.body)).toBe(true);
    expect((img.body as Buffer).length).toBe(PNG.length);
  });

  it('marks a forbidden cover failed and 404s its image', async () => {
    const retry = await request(app.getHttpServer())
      .post(`/api/v1/covers/${denyId}/retry`)
      .set('Authorization', auth)
      .expect(201);
    expect(retry.body as CoverResultDto).toMatchObject({
      mangaId: denyId,
      outcome: 'failed',
      coverState: 'failed',
    });

    await request(app.getHttpServer())
      .get(`/api/v1/covers/${denyId}`)
      .set('Authorization', auth)
      .expect(404);
  });

  it('accepts a custom cover upload and serves it', async () => {
    const put = await request(app.getHttpServer())
      .put(`/api/v1/covers/${denyId}/custom`)
      .set('Authorization', auth)
      .attach('file', PNG, { filename: 'custom.png', contentType: 'image/png' })
      .expect(200);
    expect(put.body as CoverResultDto).toMatchObject({
      outcome: 'archived',
      coverState: 'archived',
    });

    const img = await getBinary(`/api/v1/covers/${denyId}`).expect(200);
    expect((img.body as Buffer).length).toBe(PNG.length);
  });

  it('rejects a non-image custom upload', () => {
    return request(app.getHttpServer())
      .put(`/api/v1/covers/${okId}/custom`)
      .set('Authorization', auth)
      .attach('file', Buffer.from('<html>nope</html>'), {
        filename: 'x.html',
        contentType: 'text/html',
      })
      .expect(400);
  });

  it('404s an unknown id and 400s a non-uuid id', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/covers/00000000-0000-0000-0000-000000000000')
      .set('Authorization', auth)
      .expect(404);
    await request(app.getHttpServer())
      .get('/api/v1/covers/not-a-uuid')
      .set('Authorization', auth)
      .expect(400);
  });
});
