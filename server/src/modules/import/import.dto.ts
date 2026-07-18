import type { BackupContainerKind } from '../../tachibk';
import type { FieldConflict } from './merge.engine';

/** Per-title merge outcome shown in the import-review UI. */
export interface MergeResultDto {
  title: string;
  sourceId: string;
  mangaUrl: string;
  action: 'created' | 'merged';
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
