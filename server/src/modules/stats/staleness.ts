import type { Staleness } from './stats.dto';

const DAY_MS = 24 * 60 * 60 * 1000;

/** Boundaries (in days) between the freshness bands. */
export const FRESH_DAYS = 30;
export const AGING_DAYS = 90;

/**
 * Classify a backup's age: `fresh` under 30 days, `aging` under 90, `stale`
 * beyond that. A missing/zero timestamp counts as stale — an archive with no
 * known import date is the worst case, not the best.
 */
export function stalenessOf(lastImportAt: number, now: number): Staleness {
  if (!lastImportAt || lastImportAt <= 0) return 'stale';
  const ageDays = (now - lastImportAt) / DAY_MS;
  if (ageDays < FRESH_DAYS) return 'fresh';
  if (ageDays < AGING_DAYS) return 'aging';
  return 'stale';
}
