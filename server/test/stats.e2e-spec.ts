import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { DataSource } from 'typeorm';

import { AppModule } from '../src/app.module';
import type { MangaListItemDto } from '../src/modules/library/library.dto';
import type {
  BackupHealthDto,
  LibraryStatsDto,
  ResumeItemDto,
} from '../src/modules/stats/stats.dto';

const idOf = (rows: unknown): string => (rows as Array<{ id: string }>)[0].id;

/**
 * Dashboard stats e2e against the local Postgres (host 5433). The endpoints
 * aggregate the *whole* archive, so this suite seeds a run-unique source app /
 * source id and asserts its own contribution (its health row, its titles in the
 * shelves, counts at least as large as what it seeded) rather than exact
 * archive-wide totals — the dev DB holds a real 1.2k-title library.
 */
describe('Dashboard stats (e2e)', () => {
  let app: INestApplication<App>;
  let ds: DataSource;
  const token = 'e2e-token';
  const auth = `Bearer ${token}`;

  const runId = Date.now();
  const sourceId = String(
    9_300_000_000_000_000_000n + BigInt(runId % 1_000_000),
  );
  const sourceApp = `e2e.stats.${runId}`;
  const sha = `sha-stats-${runId}`;
  const resumeTitle = `Resume Me ${runId}`;

  let resumeId = '';

  const get = async <T>(path: string): Promise<T> => {
    const res = await request(app.getHttpServer())
      .get(`/api/v1${path}`)
      .set('Authorization', auth)
      .expect(200);
    return res.body as T;
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

    const insertManga = async (
      title: string,
      status: string,
      coverState: string,
    ): Promise<string> =>
      idOf(
        await ds.query(
          `INSERT INTO manga (source_id, manga_url, source_name, title, status, cover_state, updated_at, date_added)
           VALUES ($1, $2, 'MangaVaultStats', $3, $4, $5, $6, $6) RETURNING id`,
          [sourceId, `/s/${title}`, title, status, coverState, runId],
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

    resumeId = await insertManga(resumeTitle, 'ongoing', 'archived');
    const finishedId = await insertManga(
      `Finished ${runId}`,
      'completed',
      'failed',
    );
    const untouchedId = await insertManga(
      `Untouched ${runId}`,
      'ongoing',
      'none',
    );

    // Resume candidate: read up to chapter 2, chapter 3 still unread.
    await insertChapter(resumeId, 1, true, runId - 1000);
    await insertChapter(resumeId, 2, true, runId);
    await insertChapter(resumeId, 3, false, null);
    // Fully read — must not show up in resume-reading.
    await insertChapter(finishedId, 1, true, runId);
    // Never opened — also not a resume candidate.
    await insertChapter(untouchedId, 1, false, null);

    const importId = idOf(
      await ds.query(
        `INSERT INTO import_record (file_name, file_size, sha256, source_app, container, imported_at, stats)
         VALUES ($1, 4096, $2, $3, 'gzip-proto', $4, '{}') RETURNING id`,
        [`${sourceApp}_2026-07-28_10-00.tachibk`, sha, sourceApp, runId],
      ),
    );
    for (const mangaId of [resumeId, finishedId, untouchedId]) {
      await ds.query(
        `INSERT INTO manga_import (manga_id, import_id) VALUES ($1, $2)`,
        [mangaId, importId],
      );
    }
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM manga WHERE source_id = $1`, [sourceId]);
      await ds.query(`DELETE FROM import_record WHERE sha256 = $1`, [sha]);
    }
    await app?.close();
  });

  it('rejects stats without auth', () => {
    return request(app.getHttpServer())
      .get('/api/v1/stats/library')
      .expect(401);
  });

  it('aggregates library totals, statuses and source apps', async () => {
    const s = await get<LibraryStatsDto>('/stats/library');

    expect(s.totalTitles).toBeGreaterThanOrEqual(3);
    expect(s.totalChapters).toBeGreaterThanOrEqual(5);
    expect(s.readChapters).toBeGreaterThanOrEqual(3);
    expect(s.addedLast7Days).toBeGreaterThanOrEqual(3);
    expect(s.sourceCount).toBeGreaterThanOrEqual(1);
    expect(s.coversArchived).toBeGreaterThanOrEqual(1);
    expect(s.coversFailed).toBeGreaterThanOrEqual(1);
    // The seeded import is the newest one in the archive.
    expect(s.lastImportAt).toBeGreaterThanOrEqual(runId);
    expect(s.importCount).toBeGreaterThanOrEqual(1);
    // Postgres always reports a database size, so the vault is never 0 bytes.
    expect(s.vaultSizeBytes).toBeGreaterThan(0);
    // The breakdown must account for the whole total — it is what tells the
    // user that covers, not the database, are what grows.
    const st = s.vaultStorage;
    expect(st.databaseBytes).toBeGreaterThan(0);
    expect(st.databaseBytes + st.coversBytes + st.backupsBytes).toBe(
      st.totalBytes,
    );
    expect(st.totalBytes).toBe(s.vaultSizeBytes);

    expect(s.bySourceApp[sourceApp]).toBe(3);
    // Every status band is present, even the empty ones.
    expect(Object.keys(s.byStatus)).toContain('publishing_finished');
    expect(s.byStatus.ongoing).toBeGreaterThanOrEqual(2);
    expect(s.byStatus.completed).toBeGreaterThanOrEqual(1);
  });

  it('reports per-source-app backup health with freshness', async () => {
    const rows = await get<BackupHealthDto[]>('/stats/backup-health');
    const mine = rows.find((r) => r.sourceApp === sourceApp);

    expect(mine).toBeDefined();
    expect(mine!.lastImportAt).toBe(runId);
    expect(mine!.importCount).toBe(1);
    expect(mine!.titleCount).toBe(3);
    expect(mine!.staleness).toBe('fresh');
  });

  it('lists recently added titles newest first', async () => {
    const items = await get<MangaListItemDto[]>(
      '/stats/recently-added?limit=40',
    );
    expect(items.length).toBeGreaterThan(0);
    expect(items.map((i) => i.title)).toContain(resumeTitle);
  });

  it('resumes only titles with progress and an unread chapter', async () => {
    const items = await get<ResumeItemDto[]>('/stats/resume-reading?limit=40');
    const mine = items.find((i) => i.id === resumeId);

    expect(mine).toBeDefined();
    expect(mine!.chapterCount).toBe(3);
    expect(mine!.readCount).toBe(2);
    expect(mine!.unreadCount).toBe(1);
    expect(mine!.lastReadAt).toBe(runId);
    expect(mine!.nextChapter).toMatchObject({ name: 'Chapter 3', number: 3 });

    // Fully-read and never-opened titles from this run are excluded.
    const titles = items.map((i) => i.title);
    expect(titles).not.toContain(`Finished ${runId}`);
    expect(titles).not.toContain(`Untouched ${runId}`);
  });

  it('clamps the shelf limit', async () => {
    const items = await get<MangaListItemDto[]>(
      '/stats/recently-added?limit=2',
    );
    expect(items).toHaveLength(2);
  });
});
