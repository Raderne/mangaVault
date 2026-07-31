/**
 * A small async work pool that bounds concurrency two ways at once: a global
 * cap and a per-key (per-host) cap. Cover downloads hit many hosts; we want
 * throughput across hosts but politeness towards any single one (Mihon uses a
 * per-host limit of 2). The worker owns its own error handling — a rejected
 * worker is swallowed here so one bad item never sinks the batch.
 */
export interface PoolOptions<T> {
  /** Max items in flight across all keys. */
  globalLimit: number;
  /** Max items in flight for any single key. */
  perKeyLimit: number;
  /** Bucket key for an item (e.g. the URL host). */
  keyOf: (item: T) => string;
  /**
   * Stop dispatching new items when aborted. Work already in flight is left to
   * finish rather than torn down — a cover download that is mid-write should
   * complete or fail on its own terms, not leave a truncated file behind — so
   * the returned promise settles once the pool has drained.
   */
  signal?: AbortSignal;
}

export async function runPool<T>(
  items: readonly T[],
  opts: PoolOptions<T>,
  worker: (item: T) => Promise<void>,
): Promise<void> {
  if (items.length === 0) return;
  const globalLimit = Math.max(1, opts.globalLimit);
  const perKeyLimit = Math.max(1, opts.perKeyLimit);

  // Per-key FIFO queues, preserving original order within a host.
  const queues = new Map<string, T[]>();
  for (const item of items) {
    const key = opts.keyOf(item);
    const q = queues.get(key);
    if (q) q.push(item);
    else queues.set(key, [item]);
  }

  const inFlight = new Map<string, number>();
  let active = 0;
  let remaining = items.length;

  return new Promise<void>((resolve) => {
    const aborted = () => opts.signal?.aborted === true;

    const settle = (key: string) => {
      active--;
      inFlight.set(key, (inFlight.get(key) ?? 1) - 1);
      remaining--;
      if (remaining === 0) {
        resolve();
        return;
      }
      // Cancelled: the queue is abandoned, so the pool is done once the last
      // in-flight item has landed.
      if (aborted() && active === 0) {
        resolve();
        return;
      }
      pump();
    };

    /** Pick the eligible key with the least in-flight work (spreads load). */
    const nextKey = (): string | undefined => {
      let best: string | undefined;
      let bestInFlight = Infinity;
      for (const [key, q] of queues) {
        if (q.length === 0) continue;
        const n = inFlight.get(key) ?? 0;
        if (n >= perKeyLimit) continue;
        if (n < bestInFlight) {
          best = key;
          bestInFlight = n;
        }
      }
      return best;
    };

    const pump = (): void => {
      if (aborted()) return;
      while (active < globalLimit) {
        const key = nextKey();
        if (key === undefined) break;
        const q = queues.get(key)!;
        const item = q.shift()!;
        if (q.length === 0) queues.delete(key);
        active++;
        inFlight.set(key, (inFlight.get(key) ?? 0) + 1);
        void Promise.resolve()
          .then(() => worker(item))
          .catch(() => undefined)
          .then(() => settle(key));
      }
    };

    pump();

    // `settle` only sees an abort that arrives while work is in flight. An
    // already-aborted signal, or one that fires with an idle pool, settles here.
    if (aborted()) {
      if (active === 0) resolve();
    } else {
      opts.signal?.addEventListener(
        'abort',
        () => {
          if (active === 0) resolve();
        },
        { once: true },
      );
    }
  });
}
