import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import type { CoverJobEntity } from '../../entities';
import { CoverOptimizer } from './cover.optimizer';
import { CoverService } from './cover.service';
import { CoverJobStore } from './cover-job.store';

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(32),
]);

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));

async function waitFinished(jobs: CoverJobStore, jobId: string): Promise<void> {
  const start = Date.now();
  for (;;) {
    if ((await jobs.status(jobId)).finished) return;
    if (Date.now() - start > 3000) throw new Error('job did not finish');
    await sleep(5);
  }
}

/**
 * Minimal in-memory stand-in for the `cover_job` repository — enough of the
 * TypeORM surface that {@link CoverJobStore} exercises its real logic (id
 * assignment, status filtering, newest-first history) without Postgres.
 */
function fakeJobRepo() {
  const rows = new Map<string, CoverJobEntity>();
  let seq = 0;
  const matches = (row: CoverJobEntity, where: Record<string, unknown>) =>
    Object.entries(where).every(
      ([k, v]) => (row as unknown as Record<string, unknown>)[k] === v,
    );
  return {
    rows,
    create: (data: Partial<CoverJobEntity>) => ({ ...data }) as CoverJobEntity,
    save: (row: CoverJobEntity) => {
      row.id ??= `job-${++seq}`;
      rows.set(row.id, { ...row });
      return Promise.resolve(row);
    },
    update: (
      target: string | Record<string, unknown>,
      patch: Partial<CoverJobEntity>,
    ) => {
      const targets =
        typeof target === 'string'
          ? [rows.get(target)].filter(Boolean)
          : [...rows.values()].filter((r) => matches(r, target));
      for (const row of targets) Object.assign(row!, patch);
      return Promise.resolve({ affected: targets.length });
    },
    findOne: (opts: { where: Record<string, unknown> }) =>
      Promise.resolve(
        [...rows.values()].find((r) => matches(r, opts.where)) ?? null,
      ),
    find: (opts?: { where?: Record<string, unknown>; take?: number }) => {
      let list = [...rows.values()];
      if (opts?.where) list = list.filter((r) => matches(r, opts.where!));
      list.sort((a, b) => b.startedAt - a.startedAt);
      return Promise.resolve(opts?.take ? list.slice(0, opts.take) : list);
    },
  };
}

/**
 * Unit tests for the archive-missing orchestration with a mocked DataSource /
 * repo / fetcher — so the whole-library candidate scan, the concurrency run,
 * cancellation and the boot resume are exercised without touching Postgres or
 * the network (and without the real DB's thousands of un-archived covers).
 */
describe('CoverService.archiveMissing', () => {
  let storageDir: string;
  let jobRepo: ReturnType<typeof fakeJobRepo>;
  let jobs: CoverJobStore;

  const makeService = (
    candidates: unknown[],
    fetchImpl: (url: string) => Promise<{ bytes: Buffer; mime: string }>,
    env: Record<string, string> = {},
  ) => {
    // Typed so the assertions can read the recorded patch without `any`.
    const mangaRepo = {
      findOne: jest.fn(),
      update: jest.fn<void, [string, Record<string, unknown>]>(),
    };
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
          update: (
            _entity: unknown,
            id: string,
            patch: Record<string, unknown>,
          ): void => {
            mangaRepo.update(id, patch);
          },
        }),
      ),
    };
    const fetcher = { fetch: jest.fn((url: string) => fetchImpl(url)) };
    const config = {
      get: (key: string) => (key === 'STORAGE_DIR' ? storageDir : env[key]),
    };
    const service = new CoverService(
      dataSource as never,
      mangaRepo as never,
      fetcher as never,
      // The real optimizer: these tests feed it 1×1 PNGs, which it correctly
      // declines to "optimise" (no saving), so the stored bytes stay the
      // fixture bytes and every existing assertion still means what it did.
      new CoverOptimizer(),
      jobs,
      config as never,
    );
    return { service, mangaRepo, fetcher, dataSource };
  };

  const candidate = (id: string, host: string) => ({
    id,
    sourceId: 's1',
    thumbnailUrl: `http://${host}/${id}.png`,
    coverPath: null,
  });

  beforeEach(async () => {
    storageDir = await mkdtemp(join(tmpdir(), 'mv-covers-'));
    jobRepo = fakeJobRepo();
    jobs = new CoverJobStore(jobRepo as never);
  });

  afterEach(async () => {
    await rm(storageDir, { recursive: true, force: true });
  });

  it('archives fetchable covers, marks the rest failed, and writes files', async () => {
    const candidates = [
      candidate('id-a', 'a.test'),
      candidate('id-b', 'b.test'),
    ];
    const { service, mangaRepo } = makeService(candidates, (url) =>
      url.includes('a.test')
        ? Promise.resolve({ bytes: PNG, mime: 'image/png' })
        : Promise.reject(new Error('HTTP 403')),
    );

    const started = await service.archiveMissing();
    expect(started).toMatchObject({ total: 2, alreadyRunning: false });
    await waitFinished(jobs, started.jobId);

    const status = await jobs.status(started.jobId);
    expect(status).toMatchObject({
      archived: 1,
      failed: 1,
      done: 2,
      status: 'finished',
    });

    expect(mangaRepo.update).toHaveBeenCalledWith('id-a', {
      coverPath: 'covers/id-a.png',
      coverState: 'archived',
      coverFailedAt: null,
    });
    // The failure is timestamped so a resumed run can skip it.
    const failed = mangaRepo.update.mock.calls.find(
      ([id]) => id === 'id-b',
    )?.[1];
    expect(failed?.coverState).toBe('failed');
    expect(typeof failed?.coverFailedAt).toBe('number');

    const files = await readdir(join(storageDir, 'covers'));
    expect(files).toEqual(['id-a.png']);
  });

  it('joins the in-flight run instead of starting a second', async () => {
    const candidates = [candidate('id-x', 'a.test')];
    // Fetch never settles, so the first run stays active across both calls.
    const { service } = makeService(candidates, () => new Promise(() => {}));

    const first = await service.archiveMissing();
    const second = await service.archiveMissing();

    expect(second.alreadyRunning).toBe(true);
    expect(second.jobId).toBe(first.jobId);
  });

  it('joins a run whose start is still in flight', async () => {
    const candidates = [candidate('id-x', 'a.test')];
    const { service } = makeService(candidates, () => new Promise(() => {}));

    // Both callers land before either has a job row — without the pending-start
    // guard each would start a run and every cover would be fetched twice.
    const [first, second] = await Promise.all([
      service.archiveMissing(),
      service.archiveMissing(),
    ]);

    expect(second.jobId).toBe(first.jobId);
    expect(first.alreadyRunning !== second.alreadyRunning).toBe(true);
    expect(jobRepo.rows.size).toBe(1);
  });

  it('finishes immediately when nothing is missing', async () => {
    const { service, fetcher } = makeService([], () =>
      Promise.resolve({ bytes: PNG, mime: 'image/png' }),
    );
    const started = await service.archiveMissing();
    expect(started.total).toBe(0);
    const status = await jobs.status(started.jobId);
    expect(status).toMatchObject({ finished: true, status: 'finished' });
    expect(fetcher.fetch).not.toHaveBeenCalled();
    // The slot is free again, so the next trigger isn't told "already running".
    expect(jobs.activeJobId()).toBeNull();
  });

  it('stops dispatching once cancelled and ends the run as cancelled', async () => {
    // One host, so the per-host cap (2) means at most two fetches are in flight
    // when the cancel lands — the remaining eight are never dispatched.
    const candidates = Array.from({ length: 10 }, (_, i) =>
      candidate(`id-${i}`, 'a.test'),
    );
    let jobId = '';
    const { service, fetcher } = makeService(candidates, async () => {
      await service.cancel(jobId);
      return { bytes: PNG, mime: 'image/png' };
    });

    const started = await service.archiveMissing();
    jobId = started.jobId;
    await waitFinished(jobs, jobId);

    const status = await jobs.status(jobId);
    expect(status.status).toBe('cancelled');
    expect(status.cancelRequested).toBe(true);
    expect(fetcher.fetch.mock.calls.length).toBeLessThan(candidates.length);
    // Covers already in flight when the cancel landed still counted.
    expect(status.done).toBe(fetcher.fetch.mock.calls.length);
  });

  it('scopes an automatic run to covers that were never tried', async () => {
    const { service, dataSource } = makeService([], () =>
      Promise.resolve({ bytes: PNG, mime: 'image/png' }),
    );
    await service.archiveMissing({ trigger: 'import', retryFailed: false });

    const sql = dataSource.query.mock.calls[0][0];
    expect(sql).toContain(`cover_state = 'none'`);
    expect(sql).not.toContain(`'failed'`);
  });

  it('resumes an interrupted run on boot, skipping what it already tried', async () => {
    const interruptedAt = Date.now() - 60_000;
    jobRepo.rows.set('job-old', {
      id: 'job-old',
      status: 'running',
      trigger: 'manual',
      total: 10,
      done: 4,
      archived: 3,
      failed: 1,
      skipped: 0,
      retryFailed: true,
      cancelRequested: false,
      error: null,
      startedAt: interruptedAt,
      updatedAt: interruptedAt,
      finishedAt: null,
    });

    const { service, dataSource } = makeService([], () =>
      Promise.resolve({ bytes: PNG, mime: 'image/png' }),
    );
    await service.onApplicationBootstrap();

    // The abandoned row is closed out rather than left running forever.
    expect(jobRepo.rows.get('job-old')!.status).toBe('interrupted');

    // The resumed run re-derives candidates but excludes covers that failed
    // during the interrupted run.
    const [sql, params] = dataSource.query.mock.calls[0] as unknown as [
      string,
      unknown[],
    ];
    expect(sql).toContain('cover_failed_at');
    expect(params).toEqual([interruptedAt]);

    const history = await jobs.list();
    expect(history[0]).toMatchObject({ trigger: 'resume' });
  });

  it('queues a follow-up pass when an import lands mid-run', async () => {
    // The running job took its candidates before the import committed, so the
    // new titles need a pass of their own once it finishes.
    const candidates = [candidate('id-1', 'a.test')];
    let release = (): void => {};
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const { service } = makeService(candidates, async () => {
      await gate;
      return { bytes: PNG, mime: 'image/png' };
    });

    const first = await service.archiveMissing();
    const queued = await service.archiveAfterImport();
    expect(queued).toMatchObject({
      jobId: first.jobId,
      alreadyRunning: true,
    });

    release();
    await waitFinished(jobs, first.jobId);
    // Settle the follow-up run kicked off from runArchive's tail.
    await sleep(20);

    const history = await jobs.list();
    expect(history).toHaveLength(2);
    expect(history[0]).toMatchObject({ trigger: 'import' });
  });

  it('makes automatic runs no-ops when COVER_AUTO_ARCHIVE is false', async () => {
    const { service, dataSource } = makeService(
      [candidate('id-1', 'a.test')],
      () => Promise.resolve({ bytes: PNG, mime: 'image/png' }),
      { COVER_AUTO_ARCHIVE: 'false' },
    );

    expect(await service.archiveAfterImport()).toBeNull();
    await service.onApplicationBootstrap();
    expect(dataSource.query).not.toHaveBeenCalled();

    // The manual trigger is untouched by the flag.
    const started = await service.archiveMissing();
    expect(started.total).toBe(1);
    await waitFinished(jobs, started.jobId);
  });

  it('does nothing on boot when no run was interrupted', async () => {
    const { service, dataSource } = makeService([], () =>
      Promise.resolve({ bytes: PNG, mime: 'image/png' }),
    );
    await service.onApplicationBootstrap();
    expect(dataSource.query).not.toHaveBeenCalled();
    expect(jobRepo.rows.size).toBe(0);
  });
});
