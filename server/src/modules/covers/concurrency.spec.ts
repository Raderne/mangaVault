import { runPool } from './concurrency';

const tick = (ms = 5): Promise<void> => new Promise((r) => setTimeout(r, ms));

describe('runPool', () => {
  it('processes every item exactly once', async () => {
    const items = Array.from({ length: 25 }, (_, i) => `h${i % 4}:${i}`);
    const seen: string[] = [];
    await runPool(
      items,
      { globalLimit: 5, perKeyLimit: 2, keyOf: (s) => s.split(':')[0] },
      async (s) => {
        await tick(1);
        seen.push(s);
      },
    );
    expect(seen.sort()).toEqual([...items].sort());
  });

  it('honours the global and per-host limits', async () => {
    const items = Array.from({ length: 30 }, (_, i) => `host${i % 3}:${i}`);
    let global = 0;
    let maxGlobal = 0;
    const perHost = new Map<string, number>();
    const maxPerHost = new Map<string, number>();

    await runPool(
      items,
      { globalLimit: 4, perKeyLimit: 2, keyOf: (s) => s.split(':')[0] },
      async (s) => {
        const host = s.split(':')[0];
        global++;
        maxGlobal = Math.max(maxGlobal, global);
        const n = (perHost.get(host) ?? 0) + 1;
        perHost.set(host, n);
        maxPerHost.set(host, Math.max(maxPerHost.get(host) ?? 0, n));
        await tick(5);
        global--;
        perHost.set(host, (perHost.get(host) ?? 1) - 1);
      },
    );

    expect(maxGlobal).toBeLessThanOrEqual(4);
    for (const n of maxPerHost.values()) expect(n).toBeLessThanOrEqual(2);
  });

  it('finishes even when a worker throws', async () => {
    const items = [1, 2, 3, 4];
    const done: number[] = [];
    await runPool(
      items,
      { globalLimit: 2, perKeyLimit: 2, keyOf: () => 'x' },
      async (n) => {
        await Promise.resolve();
        if (n === 2) throw new Error('boom');
        done.push(n);
      },
    );
    expect(done.sort()).toEqual([1, 3, 4]);
  });
});
