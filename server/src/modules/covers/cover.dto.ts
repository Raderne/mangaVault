import type {
  CoverJobStatus,
  CoverJobTrigger,
} from '../../entities/cover-job.entity';
import type { CoverState } from '../../entities/manga.entity';

/** Returned by `POST /covers/archive-missing` — the job to poll. */
export interface CoverArchiveStartedDto {
  jobId: string;
  /** Number of titles this run will attempt (0 if nothing was missing). */
  total: number;
  /** True when an archive run was already in progress and was joined instead. */
  alreadyRunning: boolean;
}

/**
 * A cover-archiving run: the poll response for `GET /covers/jobs/:jobId`, the
 * body of `GET /covers/jobs/active`, and each entry of `GET /covers/jobs`.
 */
export interface CoverJobDto {
  jobId: string;
  status: CoverJobStatus;
  /** What started the run — manual tap, an import, or a post-restart resume. */
  trigger: CoverJobTrigger;
  total: number;
  done: number;
  archived: number;
  failed: number;
  skipped: number;
  /** Convenience for pollers: any status other than `running`. */
  finished: boolean;
  /** A cancel was requested; in-flight downloads are draining. */
  cancelRequested: boolean;
  /** Why the run itself failed (not an individual cover). */
  error: string | null;
  startedAt: number;
  finishedAt: number | null;
}

/** Result of archiving a single cover (`POST /covers/:mangaId/retry`). */
export interface CoverResultDto {
  mangaId: string;
  outcome: 'archived' | 'failed' | 'skipped';
  coverState: CoverState;
  error?: string;
}
