import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { CoverService } from './cover.service';
import { CoverJobRegistry } from './cover-job.registry';

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(32),
]);

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));

async function waitFinished(
  jobs: CoverJobRegistry,
  jobId: string,
): Promise<void> {
  const start = Date.now();
  while (!jobs.status(jobId).finished) {
    if (Date.now() - start > 3000) throw new Error('job did not finish');
    await sleep(10);
  }
}

/**
 * Unit tests for the archive-missing orchestration with a mocked DataSource /
 * repo / fetcher — so the whole-library candidate scan and concurrency run are
 * exercised without touching Postgres or the network (and without the real DB's
 * thousands of un-archived covers).
 */
describe('CoverService.archiveMissing', () => {
  let storageDir: string;
  let jobs: CoverJobRegistry;

  const makeService = (
    candidates: unknown[],
    fetchImpl: (url: string) => Promise<{ bytes: Buffer; mime: string }>,
  ) => {
    const mangaRepo = { findOne: jest.fn(), update: jest.fn() };
    // Cover writes go through withSyncLock → dataSource.transaction, so the
    // fake manager forwards `update(Entity, id, patch)` to the repo mock the
    // assertions below inspect.
    const dataSource = {
      query: jest.fn((sql: string) =>
        sql.includes('known_source')
          ? Promise.resolve([])
          : Promise.resolve(candidates),
      ),
      transaction: jest.fn((work: (mgr: unknown) => Promise<unknown>) =>
        work({
          query: jest.fn(() => Promise.resolve([])), // pg_advisory_xact_lock
          update: (_entity: unknown, id: string, patch: unknown): void => {
            mangaRepo.update(id, patch);
          },
        }),
      ),
    };
    const fetcher = { fetch: jest.fn((url: string) => fetchImpl(url)) };
    const config = {
      get: (key: string) => (key === 'STORAGE_DIR' ? storageDir : undefined),
    };
    const service = new CoverService(
      dataSource as never,
      mangaRepo as never,
      fetcher as never,
      jobs,
      config as never,
    );
    return { service, mangaRepo, fetcher };
  };

  beforeEach(async () => {
    storageDir = await mkdtemp(join(tmpdir(), 'mv-covers-'));
    jobs = new CoverJobRegistry();
  });

  afterEach(async () => {
    await rm(storageDir, { recursive: true, force: true });
  });

  it('archives fetchable covers, marks the rest failed, and writes files', async () => {
    const candidates = [
      {
        id: 'id-a',
        sourceId: 's1',
        thumbnailUrl: 'http://a.test/1.png',
        coverPath: null,
      },
      {
        id: 'id-b',
        sourceId: 's1',
        thumbnailUrl: 'http://b.test/2.png',
        coverPath: null,
      },
    ];
    const { service, mangaRepo } = makeService(candidates, (url) =>
      url.includes('a.test')
        ? Promise.resolve({ bytes: PNG, mime: 'image/png' })
        : Promise.reject(new Error('HTTP 403')),
    );

    const started = await service.archiveMissing();
    expect(started).toMatchObject({ total: 2, alreadyRunning: false });
    await waitFinished(jobs, started.jobId);

    const status = jobs.status(started.jobId);
    expect(status).toMatchObject({ archived: 1, failed: 1, done: 2 });

    expect(mangaRepo.update).toHaveBeenCalledWith('id-a', {
      coverPath: 'covers/id-a.png',
      coverState: 'archived',
    });
    expect(mangaRepo.update).toHaveBeenCalledWith('id-b', {
      coverState: 'failed',
    });

    const files = await readdir(join(storageDir, 'covers'));
    expect(files).toEqual(['id-a.png']);
  });

  it('joins the in-flight run instead of starting a second', async () => {
    const candidates = [
      {
        id: 'id-x',
        sourceId: 's1',
        thumbnailUrl: 'http://a.test/x.png',
        coverPath: null,
      },
    ];
    // Fetch never settles, so the first run stays active across both calls.
    const { service } = makeService(candidates, () => new Promise(() => {}));

    const first = await service.archiveMissing();
    const second = await service.archiveMissing();

    expect(second.alreadyRunning).toBe(true);
    expect(second.jobId).toBe(first.jobId);
  });

  it('finishes immediately when nothing is missing', async () => {
    const { service, fetcher } = makeService([], () =>
      Promise.resolve({ bytes: PNG, mime: 'image/png' }),
    );
    const started = await service.archiveMissing();
    expect(started.total).toBe(0);
    expect(jobs.status(started.jobId).finished).toBe(true);
    expect(fetcher.fetch).not.toHaveBeenCalled();
  });
});
