import type {
  MigrationItemState,
  MigrationJobStatus,
  MigrationMethod,
  StoredCandidate,
} from '../../entities/source-migration.entity';

/** Body of `POST /sources/migrations/plan`. */
export interface PlanMigrationRequest {
  /** The source to move titles off. */
  fromSourceId: string;
  /** Titles to include; omitted or empty means every title on that source. */
  mangaIds?: string[];
  /** Target sources in preference order. */
  toSourceIds: string[];
}

/** One title in a plan, as the review screen renders it. */
export interface MigrationItemDto {
  id: string;
  mangaId: string;
  title: string;
  fromSourceId: string;
  fromMangaUrl: string;
  toSourceId: string | null;
  toSourceName: string | null;
  toMangaUrl: string | null;
  toTitle: string | null;
  toThumbnailUrl: string | null;
  /** 0..1, or null for a url the user pasted (nothing to score it against). */
  score: number | null;
  method: MigrationMethod | null;
  state: MigrationItemState;
  /** Why the score is what it is — "same author", "42 chapters vs 210". */
  reasons: string[];
  /** Ranked alternatives, so switching match needs no new search. */
  candidates: StoredCandidate[];
  /** For `conflict`: the title already in the vault that blocks this one. */
  conflictMangaId: string | null;
  conflictTitle: string | null;
  error: string | null;
  /** True once applied and not undone — enables the Undo action. */
  undoable: boolean;
}

/** A migration plan and its progress. */
export interface MigrationJobDto {
  jobId: string;
  status: MigrationJobStatus;
  fromSourceId: string;
  fromSourceName: string;
  toSourceIds: string[];
  total: number;
  planned: number;
  matched: number;
  applied: number;
  skipped: number;
  failed: number;
  finished: boolean;
  cancelRequested: boolean;
  error: string | null;
  startedAt: number;
  finishedAt: number | null;
}

/** `GET /sources/migrations/:jobId` — the plan plus every title in it. */
export interface MigrationPlanDto {
  job: MigrationJobDto;
  items: MigrationItemDto[];
  /**
   * Target sources that could not be searched automatically, with the reason.
   * Surfaced up front so "no match found" never looks like "nothing exists" —
   * it usually means we have no adapter for that source.
   */
  unsearchable: Array<{ sourceId: string; name: string; reason: string }>;
  /**
   * Score at or above which a match is safe to pre-select. The app uses the
   * server's value rather than its own constant so the tick boxes it shows and
   * the set `apply` would default to can never disagree.
   */
  autoAcceptScore: number;
}

/** Body of `PUT /sources/migrations/:jobId/items/:mangaId`. */
export interface UpdateMigrationItemRequest {
  /** Pick one of the stored candidates by index. */
  candidateIndex?: number;
  /** Or point the title at a url the user supplied. */
  toSourceId?: string;
  toMangaUrl?: string;
  /** Or take it out of the plan. */
  skip?: boolean;
}

/** Body of `POST /migrations/:jobId/apply`. */
export interface ApplyMigrationRequest {
  /**
   * Titles to migrate. Omit to apply only confident matches — see
   * `MigrationService.apply`.
   */
  mangaIds?: string[];
}

/** Result of applying a plan. */
export interface ApplyMigrationResultDto {
  jobId: string;
  applied: number;
  conflicts: number;
  failed: number;
}
