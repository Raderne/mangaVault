import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type { BackupAppDto } from '../src/modules/backup-apps/backup-apps.dto';
import { CURATED_APPS } from '../src/modules/backup-apps/curated-apps';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/**
 * The backup-app registry e2e against the local Postgres (host 5433). The
 * curated rows are seeded by `BackupAppsService.onModuleInit`, so booting the
 * AppModule is what puts them there. User-added rows are run-unique and cleaned
 * up; curated rows are shared state and are only read.
 */
describe('Backup apps (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  const customId = `dev.apps.reader${runId % 1_000_000}`;
  const usedId = `dev.apps.used${runId % 1_000_000}`;
  const sha = `sha-apps-${runId}`;

  const list = async (): Promise<BackupAppDto[]> => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/backup-apps')
      .set('Authorization', auth)
      .expect(200);
    return res.body as BackupAppDto[];
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
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [sha]);
      await ds.query(`DELETE FROM backup_app WHERE id = ANY($1)`, [
        [customId, usedId],
      ]);
    }
    await app?.close();
  });

  it('rejects the endpoint without auth', () => {
    return request(app.getHttpServer()).get('/api/v1/backup-apps').expect(401);
  });

  it('seeds the curated apps on boot', async () => {
    const apps = await list();
    for (const curated of CURATED_APPS) {
      expect(apps).toContainEqual(
        expect.objectContaining({
          id: curated.id,
          displayName: curated.displayName,
          curated: true,
        }),
      );
    }
  });

  it('adds a user app, and adding it again updates the name instead of failing', async () => {
    const created = await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: customId, displayName: 'My Reader' })
      .expect(201);
    expect(created.body).toMatchObject({
      id: customId,
      displayName: 'My Reader',
      curated: false,
      importCount: 0,
      titleCount: 0,
      lastImportAt: 0,
    });

    const again = await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: customId, displayName: 'My Reader (renamed)' })
      .expect(201);
    expect((again.body as BackupAppDto).displayName).toBe(
      'My Reader (renamed)',
    );

    const apps = await list();
    expect(apps.filter((a) => a.id === customId)).toHaveLength(1);
  });

  it('lower-cases the id and rejects a malformed one', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: customId.toUpperCase(), displayName: 'Upper' })
      .expect(201);
    expect((await list()).filter((a) => a.id === customId)).toHaveLength(1);

    await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: 'not a valid id', displayName: 'Nope' })
      .expect(409);

    await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: 123, displayName: 'Nope' })
      .expect(400);
  });

  it('deletes a user app', async () => {
    await request(app.getHttpServer())
      .delete(`/api/v1/backup-apps/${customId}`)
      .set('Authorization', auth)
      .expect(204);
    expect((await list()).some((a) => a.id === customId)).toBe(false);

    await request(app.getHttpServer())
      .delete(`/api/v1/backup-apps/${customId}`)
      .set('Authorization', auth)
      .expect(404);
  });

  it('refuses to delete a curated app', () => {
    return request(app.getHttpServer())
      .delete(`/api/v1/backup-apps/${CURATED_APPS[0].id}`)
      .set('Authorization', auth)
      .expect(409);
  });

  it('refuses to delete an app that already labels an import', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/backup-apps')
      .set('Authorization', auth)
      .send({ id: usedId, displayName: 'Used Reader' })
      .expect(201);

    const importId = idOf(
      await ds.query(
        `INSERT INTO import_record (file_name, file_size, sha256, source_app, container, imported_at, stats)
         VALUES ($1, 1, $2, $3, 'gzip-proto', $4, '{}') RETURNING id`,
        [`${usedId}_${runId}.tachibk`, sha, usedId, runId],
      ),
    );
    expect(importId).toBeTruthy();

    await request(app.getHttpServer())
      .delete(`/api/v1/backup-apps/${usedId}`)
      .set('Authorization', auth)
      .expect(409);

    // …and it now reports the import it labels.
    const mine = (await list()).find((a) => a.id === usedId);
    expect(mine).toMatchObject({ importCount: 1, titleCount: 0 });
    expect(mine!.lastImportAt).toBe(runId);
  });

  it('lists an app that only exists on an import record', async () => {
    // A backup can name an app the registry never learned (a restored dump, a
    // row deleted by hand). It must still be listable, or its titles become
    // unfilterable — the id stands in as the display name.
    const orphanApp = `dev.apps.orphan${runId % 1_000_000}`;
    await ds.query(
      `INSERT INTO import_record (file_name, file_size, sha256, source_app, container, imported_at, stats)
       VALUES ($1, 1, $2, $3, 'gzip-proto', $4, '{}')`,
      [`${orphanApp}_${runId}.tachibk`, `${sha}-orphan`, orphanApp, runId],
    );
    try {
      expect(await list()).toContainEqual(
        expect.objectContaining({
          id: orphanApp,
          displayName: orphanApp,
          curated: false,
          importCount: 1,
        }),
      );
    } finally {
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [
        `${sha}-orphan`,
      ]);
    }
  });
});
