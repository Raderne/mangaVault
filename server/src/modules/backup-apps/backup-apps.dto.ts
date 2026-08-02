/** A reading app backups can come from, plus how much of the vault it fed. */
export interface BackupAppDto {
  /** Android application id, lower-cased, e.g. `app.mihon`. */
  id: string;
  displayName: string;
  accent: string | null;
  /** Shipped in `curated-apps.ts` — cannot be deleted. */
  curated: boolean;
  /** Imports recorded against this app. */
  importCount: number;
  /** Distinct titles that came from at least one of those imports. */
  titleCount: number;
  /** Newest `import_record.imported_at` for this app, 0 when never used. */
  lastImportAt: number;
}

/** Body of `POST /backup-apps`. */
export interface CreateBackupAppDto {
  id: string;
  displayName: string;
  accent?: string | null;
}
