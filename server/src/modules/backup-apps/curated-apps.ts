/**
 * The reading apps MangaVault ships knowledge of.
 *
 * Seeded into `backup_app` on boot (not in a migration), so correcting a name
 * or adding a fork is a one-line edit here. An app that isn't listed still
 * works: the first import carrying its id registers it automatically, and the
 * user can add one by hand in the import picker.
 *
 * **Ids must be the real Android `applicationId`** — it is what the backup
 * filename carries (`<applicationId>_<timestamp>.tachibk`), so a wrong id here
 * silently fails to match real backups and shows the wrong name if it ever
 * does. Only add an entry once its id is confirmed from the fork's source or
 * from a real backup filename.
 */
export interface CuratedApp {
  id: string;
  displayName: string;
  /** Hex accent for the app's chip; the theme's default is used when null. */
  accent: string | null;
}

export const CURATED_APPS: readonly CuratedApp[] = [
  // Confirmed: MihonApp/mihon `BuildConfig.APPLICATION_ID`.
  { id: 'app.mihon', displayName: 'Mihon', accent: '#3B82F6' },
  // Confirmed: this vault's own first Komikku import.
  { id: 'app.komikku', displayName: 'Komikku', accent: '#EC4899' },
  // Confirmed: the package namespace Mihon forked from.
  { id: 'eu.kanade.tachiyomi', displayName: 'Tachiyomi', accent: '#F97316' },
];
