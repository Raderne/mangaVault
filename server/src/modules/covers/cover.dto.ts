import type { CoverState } from '../../entities/manga.entity';

/** Returned by `POST /covers/archive-missing` — the job to poll. */
export interface CoverArchiveStartedDto {
  jobId: string;
  /** Number of titles this run will attempt (0 if nothing was missing). */
  total: number;
  /** True when an archive run was already in progress and was joined instead. */
  alreadyRunning: boolean;
}

/** Poll response for `GET /covers/jobs/:jobId`. */
export interface CoverJobStatusDto {
  jobId: string;
  total: number;
  done: number;
  archived: number;
  failed: number;
  skipped: number;
  finished: boolean;
}

/** Result of archiving a single cover (`POST /covers/:mangaId/retry`). */
export interface CoverResultDto {
  mangaId: string;
  outcome: 'archived' | 'failed' | 'skipped';
  coverState: CoverState;
  error?: string;
}
