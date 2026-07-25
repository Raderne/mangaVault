import type { BackupContainerKind } from '../../entities/import-record.entity';
import type {
  CoverState,
  PublicationStatus,
} from '../../entities/manga.entity';

/** Whitelisted sort fields for `GET /library`. */
export const LIBRARY_SORT_FIELDS = [
  'title',
  'dateAdded',
  'lastReadAt',
  'chapterCount',
  'unreadCount',
] as const;
export type LibrarySortField = (typeof LIBRARY_SORT_FIELDS)[number];

/** All valid publication statuses (mirrors the entity union). */
export const PUBLICATION_STATUSES: readonly PublicationStatus[] = [
  'unknown',
  'ongoing',
  'completed',
  'licensed',
  'publishing_finished',
  'cancelled',
  'on_hiatus',
];

/** Parsed, validated query for the paginated library endpoint. */
export interface LibraryQueryDto {
  text?: string;
  status: PublicationStatus[];
  categoryIds: string[];
  sourceIds: string[];
  sortBy: LibrarySortField;
  sortDir: 'asc' | 'desc';
  offset: number;
  limit: number;
}

/** Slim projection for the virtualized library grid. */
export interface MangaListItemDto {
  id: string;
  title: string;
  author: string | null;
  status: PublicationStatus;
  coverPath: string | null;
  coverState: CoverState;
  sourceName: string;
  sourceId: string;
  chapterCount: number;
  unreadCount: number;
  lastReadAt: number | null;
}

export interface LibraryPageDto {
  items: MangaListItemDto[];
  total: number;
  offset: number;
  limit: number;
}

/** A category with the number of titles assigned to it (for filter chips). */
export interface CategoryDto {
  id: string;
  name: string;
  sort: number;
  count: number;
}

/** Slim category reference attached to a title. */
export interface CategoryRefDto {
  id: string;
  name: string;
}

/** A single chapter pointer (progress / continue-reading targets). */
export interface ChapterRefDto {
  name: string;
  number: number;
}

/** One backup that contributed this title — the Title Details archive history. */
export interface ArchiveEntryDto {
  id: string;
  fileName: string;
  sourceApp: string;
  container: BackupContainerKind;
  importedAt: number;
}

export interface TrackingRefDto {
  tracker: string;
  title: string;
  trackingUrl: string;
  lastChapterRead: number;
  totalChapters: number;
  score: number;
}

/** Full title record backing the Title Details screen. */
export interface VaultMangaDto {
  id: string;
  sourceId: string;
  mangaUrl: string;
  sourceName: string;
  title: string;
  author: string | null;
  artist: string | null;
  description: string | null;
  genres: string[];
  status: PublicationStatus;
  thumbnailUrl: string | null;
  coverPath: string | null;
  coverState: CoverState;
  notes: string;
  favorite: boolean;
  dateAdded: number;
  updatedAt: number;
  chapterCount: number;
  readCount: number;
  unreadCount: number;
  lastReadAt: number | null;
  /** Most recently read chapter (drives the progress readout), if any. */
  lastReadChapter: ChapterRefDto | null;
  /** Lowest-numbered unread chapter (the "continue reading" target), if any. */
  nextChapter: ChapterRefDto | null;
  categories: CategoryRefDto[];
  tracking: TrackingRefDto[];
  archive: ArchiveEntryDto[];
}
