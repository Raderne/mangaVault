import type { ValueTransformer } from 'typeorm';

/**
 * Postgres BIGINT comes back as a string; our epoch-millis values fit safely
 * in a JS number (< 2^53), so convert at the column boundary.
 * Note: int64 *identifiers* (source ids, tracker media ids) must stay strings
 * end-to-end — never apply this transformer to them.
 */
export const bigIntToNumber: ValueTransformer = {
  to: (value?: number | null) => value,
  from: (value: string | null) => (value === null ? null : Number(value)),
};
