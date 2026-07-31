import type { BackupContainerKind } from '../../tachibk';
import type { FieldConflict } from './merge.engine';

/** Per-title merge outcome shown in the import-review UI. */
export interface MergeResultDto {
  title: string;
  sourceId: string;
  mangaUrl: string;
  /**
   * `skipped` = the title is in the deletion registry, so the import will leave
   * it out rather than recreating what the user deleted.
   */
  action: 'created' | 'merged' | 'skipped';
  conflicts: FieldConflict[];
}

export interface ImportFileMetaDto {
  fileName: string;
  fileSize: number;
  sha256: string;
  sourceApp: string;
  container: BackupContainerKind;
}

export interface ImportSummaryDto {
  titlesTotal: number;
  titlesNew: number;
  titlesMerged: number;
  /** Titles left out because they are in the deletion registry. */
  titlesSkipped: number;
  chaptersTotal: number;
  categoriesTotal: number;
  warnings: string[];
}

export interface ImportRecordDto {
  id: string;
  fileName: string;
  fileSize: number;
  sha256: string;
  sourceApp: string;
  container: BackupContainerKind;
  importedAt: number;
  stats: Partial<ImportSummaryDto>;
}

/**
 * Result of staging an upload — held server-side until commit/discard. The full
 * normalized library is kept in the server-side cache (not sent to the client);
 * the client gets the per-title `preview` and aggregate `summary` it needs to
 * render the review screen.
 */
export interface StagedImportDto {
  id: string;
  fileMeta: ImportFileMetaDto;
  summary: ImportSummaryDto;
  preview: MergeResultDto[];
  duplicateOf?: ImportRecordDto;
  expiresAt: number;
}

/** Returned by `POST /imports/stage/:id/commit` — the id of the streaming job. */
export interface CommitStartedDto {
  jobId: string;
}

/**
 * Real-time commit progress, pushed over SSE (`GET /imports/jobs/:id/events`).
 * A discriminated union on `type`; the Flutter client mirrors this exactly.
 * Ordering per job: `start` → `phase`(categories/sources) → many `manga` +
 * `batch` → `phase`(done) → `done` (or a terminal `error`).
 */
export type ImportEvent =
  | { type: 'start'; fileName: string; total: number }
  | {
      type: 'phase';
      phase: 'categories' | 'sources' | 'manga' | 'archiving' | 'done';
      detail?: string;
    }
  | {
      type: 'manga';
      title: string;
      action: 'created' | 'merged' | 'skipped';
      processed: number;
      total: number;
    }
  | { type: 'batch'; committed: number; total: number }
  | { type: 'done'; record: ImportRecordDto }
  | { type: 'error'; message: string; processed: number };

/** Snapshot of a commit job (for reconnect/debug via `GET /imports/jobs/:id`). */
export interface ImportJobSnapshotDto {
  jobId: string;
  finished: boolean;
  processed: number;
  total: number;
  phase: string;
  lastEvent?: ImportEvent;
  record?: ImportRecordDto;
  error?: string;
}
