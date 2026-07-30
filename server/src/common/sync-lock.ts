import type { DataSource, EntityManager } from 'typeorm';

/**
 * Advisory-lock key guarding library write ordering. Arbitrary but must be
 * stable and unique within this database.
 */
const SYNC_LOCK_KEY = 834221;

/**
 * Serialize library writes so `manga.row_version` order equals *commit* order.
 *
 * `nextval()` hands out a version when a row is written, not when its
 * transaction commits. Without this lock two concurrent writers can interleave:
 * txn A stamps v100, txn B stamps v101 and commits first, a client syncs and
 * records cursor 101, then A commits — and A's row is never delivered, because
 * v100 is already below the client's high-water mark.
 *
 * Real exposure: `CoverService.archiveMissing` runs up to `COVER_CONCURRENCY`
 * workers, each issuing its own `UPDATE manga`. Holding a transaction-scoped
 * advisory lock makes version order match commit order, so a cursor is never
 * advanced past an uncommitted write.
 *
 * The lock is released automatically when the transaction ends. It must
 * therefore be taken *inside* a transaction — on a bare statement it would be
 * released immediately and protect nothing. Keep slow work (HTTP fetches, file
 * writes) outside the transaction so the lock is held only for the DB write.
 */
export async function acquireSyncLock(mgr: EntityManager): Promise<void> {
  await mgr.query('SELECT pg_advisory_xact_lock($1)', [SYNC_LOCK_KEY]);
}

/**
 * Run `work` in a transaction that holds the sync lock for its whole duration.
 * Convenience wrapper for the single-statement write sites.
 */
export async function withSyncLock<T>(
  dataSource: DataSource,
  work: (mgr: EntityManager) => Promise<T>,
): Promise<T> {
  return dataSource.transaction(async (mgr) => {
    await acquireSyncLock(mgr);
    return work(mgr);
  });
}
