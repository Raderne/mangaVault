import type { PublicationStatus } from '../../entities/manga.entity';

/**
 * How a title is picked for an export.
 *
 * - `all`    — the whole vault, filters ignored.
 * - `filter` — the facet query below. Facets **AND** together, values within a
 *   facet **OR** — the same semantics as the library grid's filter, so a
 *   selection the user already understands means the same thing here.
 * - `ids`    — an explicit hand-picked list, for "export exactly these".
 */
export type ExportMode = 'all' | 'filter' | 'ids';

export const EXPORT_MODES: readonly ExportMode[] = ['all', 'filter', 'ids'];

export interface ExportFilterDto {
  text?: string;
  status: PublicationStatus[];
  categoryIds: string[];
  /** Mihon 64-bit source ids, as decimal strings. */
  sourceIds: string[];
  /** Backup-app ids (`app.mihon`, …) plus the `'unknown'` bucket. */
  sourceApps: string[];
  /** `true` = favorites only, `false` = non-favorites only, unset = both. */
  favorite?: boolean;
  /** Only titles with at least one unread chapter. */
  unreadOnly?: boolean;
  /** Only titles with at least one read chapter (i.e. actually started). */
  startedOnly?: boolean;
}

/**
 * What travels with each exported title. Everything defaults to on: an archive
 * export is lossless unless the user deliberately narrows it (e.g. a clean
 * library with no progress to seed a second device).
 */
export interface ExportIncludeDto {
  chapters: boolean;
  /** Read flags, page position and reading history. Requires `chapters`. */
  readProgress: boolean;
  categories: boolean;
  tracking: boolean;
}

export interface ExportScopeDto {
  mode: ExportMode;
  filter: ExportFilterDto;
  /** Manga uuids, used only when `mode === 'ids'`. */
  ids: string[];
  include: ExportIncludeDto;
  /**
   * The app id the file is named for (`app.mihon` → `app.mihon_<stamp>.tachibk`).
   * Empty means the generic `mangavault` prefix.
   */
  targetApp: string;
}

/** One selectable value plus how many titles it covers. */
export interface ExportFacetOptionDto {
  id: string;
  label: string;
  count: number;
}

/**
 * Everything the scope builder needs to render its choices, with live counts so
 * the user can see the size of a selection before making it. One call rather
 * than four, because the wizard needs all of them on its first frame.
 */
export interface ExportFacetsDto {
  totalTitles: number;
  favoriteTitles: number;
  totalChapters: number;
  apps: ExportFacetOptionDto[];
  sources: ExportFacetOptionDto[];
  categories: ExportFacetOptionDto[];
  statuses: ExportFacetOptionDto[];
}

/** A title in the preview list — enough to recognise it, nothing more. */
export interface ExportPreviewItemDto {
  id: string;
  title: string;
  sourceName: string;
  chapterCount: number;
  readCount: number;
  favorite: boolean;
}

/**
 * What a given scope would produce, without producing it. Lets the review step
 * state the outcome in full before the user commits to a download.
 */
export interface ExportPreviewDto {
  titles: number;
  chapters: number;
  readChapters: number;
  categories: number;
  sources: number;
  trackedTitles: number;
  fileName: string;
  /** Rough gzipped size in bytes — an estimate, shown with a `~`. */
  estimatedBytes: number;
  /** First few titles, so the scope is verifiable at a glance. */
  sample: ExportPreviewItemDto[];
}
