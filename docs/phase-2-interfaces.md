# Phase 2 — Interfaces & API Stubs

All types referenced here are defined in `docs/phase-1-data-structures.md`. These interfaces are
the seams of the app: UI components depend only on these, implementations live behind them.
Planned source layout: `src/services/*` (implementations), `src/services/contracts.ts` (these
interfaces), `src/lib/tachibk/*` (parsing).

```ts
// ============================================================
// 1. Backup parsing (pure, no I/O side effects — unit-testable)
// ============================================================

/** Sniffs container framing from the first bytes of the file. */
export interface ContainerDetector {
  detect(head: Uint8Array): BackupContainer['kind'];
}

/** Decodes a .tachibk (or legacy .json) file into the raw wire model. */
export interface BackupParser {
  /**
   * @throws BackupParseError with { stage: 'gunzip' | 'protobuf' | 'json', cause }
   * Unknown protobuf fields are ignored; missing optionals get Mihon defaults
   * (notably favorite=true). Never partially throws: either a Backup or an error.
   */
  parse(file: Uint8Array, fileName: string): Promise<ParsedBackup>;
}

export interface ParsedBackup {
  wire: WireBackup;              // 1:1 protobuf model (§1 of phase-1 doc)
  container: BackupContainer['kind'];
  sourceApp: string;             // from filename prefix, '' if unrecognized
  warnings: string[];
}

/** Normalizes a wire backup into domain objects (still pure). */
export interface BackupNormalizer {
  normalize(parsed: ParsedBackup): NormalizedBackup;
}

export interface NormalizedBackup {
  manga: Omit<VaultManga, 'id' | 'importIds' | 'categories' | 'updatedAt'
              & { categoryNames: string[] }>[];
  categories: Array<Pick<VaultCategory, 'name' | 'order'>>;
  sources: KnownSource[];
}

// ============================================================
// 2. Import pipeline
// ============================================================

export interface ImportService {
  /** Hash file, reject exact duplicates, parse, normalize, preview merge. */
  stage(file: File): Promise<StagedImport>;
  /** Apply a staged import inside one DB transaction; archives the original file. */
  commit(staged: StagedImport): Promise<ImportRecord>;
  discard(staged: StagedImport): void;
  history(): Promise<ImportRecord[]>;
}

export interface StagedImport {
  id: string;
  normalized: NormalizedBackup;
  fileMeta: Pick<ImportRecord, 'fileName' | 'fileSize' | 'sha256' | 'sourceApp' | 'container'>;
  preview: MergeResult[];        // computed against current DB, before commit
  duplicateOf?: ImportRecord;    // set when sha256 already imported
}

/** Pure merge logic — rules in phase-1 §2. */
export interface MergeEngine {
  planMerge(incoming: NormalizedBackup, existingKeys: Map<string, VaultManga>): MergeResult[];
  applyMerge(existing: VaultManga, incoming: NormalizedBackup['manga'][number]): VaultManga;
}

// ============================================================
// 3. Library queries (backs Library Archive + Title Details)
// ============================================================

export interface LibraryQuery {
  text?: string;                 // FTS over title/author/genres
  status?: PublicationStatus[];
  categoryIds?: VaultId[];
  sourceIds?: string[];
  sort: { by: 'title' | 'dateAdded' | 'lastReadAt' | 'chapterCount' | 'unreadCount';
          dir: 'asc' | 'desc' };
  page: { offset: number; limit: number };
}

export interface LibraryService {
  query(q: LibraryQuery): Promise<{ items: MangaListItem[]; total: number }>;
  get(id: VaultId): Promise<VaultManga | null>;
  updateNotes(id: VaultId, notes: string): Promise<void>;
  setCategories(id: VaultId, categoryIds: VaultId[]): Promise<void>;
  listCategories(): Promise<VaultCategory[]>;
  /** Archive semantics: soft-remove only, with confirm; original imports untouched. */
  remove(id: VaultId): Promise<void>;
}

/** Slim projection for virtualized grid cells. */
export interface MangaListItem {
  id: VaultId;
  title: string;
  author?: string;
  status: PublicationStatus;
  coverPath?: string;
  coverState: VaultManga['coverState'];
  sourceName: string;
  chapterCount: number;
  unreadCount: number;
  lastReadAt?: number;
}

// ============================================================
// 4. Cover archiving
// ============================================================

export interface CoverService {
  /** Enqueue all 'none'/'failed' covers; emits progress events. */
  archiveMissing(): Promise<CoverRunSummary>;
  archiveOne(mangaId: VaultId): Promise<CoverResult>;
  setCustomCover(mangaId: VaultId, image: Blob): Promise<void>;
  events: TypedEventTarget<{
    progress: { done: number; total: number; current?: string };
    result: CoverResult;
  }>;
}

export interface CoverResult {
  mangaId: VaultId;
  outcome: 'archived' | 'failed' | 'skipped';
  error?: { status?: number; message: string };
}
export interface CoverRunSummary { archived: number; failed: number; skipped: number }

/**
 * Low-level fetch with Mihon-style header strategy:
 * try (browser UA + Referer=origin(thumbnailUrl)), then per-source coverFetchHint,
 * exponential backoff, per-host concurrency limit of 2.
 */
export interface CoverFetcher {
  fetch(url: string, hint?: KnownSource['coverFetchHint']): Promise<{ bytes: Uint8Array; mime: string }>;
}

// ============================================================
// 5. Dashboard / stats
// ============================================================

export interface StatsService {
  libraryStats(): Promise<LibraryStats>;
  backupHealth(): Promise<BackupHealth[]>;
  recentlyAdded(limit: number): Promise<MangaListItem[]>;
  resumeReading(limit: number): Promise<Array<MangaListItem & { nextChapter: string }>>;
}

// ============================================================
// 6. Vault management & export
// ============================================================

export interface VaultService {
  currentPath(): Promise<string | null>;
  open(path: string): Promise<void>;       // runs migrations
  create(path: string): Promise<void>;
  /** Verifies DB integrity, cover files present, archived imports hash-match. */
  checkIntegrity(): Promise<IntegrityReport>;
  sizeOnDisk(): Promise<{ db: number; covers: number; imports: number }>;
}

export interface IntegrityReport {
  ok: boolean;
  issues: Array<{ kind: 'missing-cover' | 'orphan-file' | 'hash-mismatch' | 'db-corruption';
                  detail: string }>;
}

export interface ExportService {
  /** MangaVault's own lossless format: zip(vault.json + covers/). */
  exportVault(destination: string): Promise<void>;
  /** Round-trip back to a Mihon-compatible .tachibk (gzip+proto, Mihon field numbers). */
  exportTachibk(destination: string, filter?: LibraryQuery): Promise<void>;
}

// ============================================================
// 7. Future seam — full content archiving (post-v1, not implemented)
// ============================================================

/** Adapter per source site; enables chapter page downloads later without redesign. */
export interface SourceAdapter {
  sourceId: string;
  getPageImageUrls(chapter: VaultChapter): Promise<string[]>;
}
```

## UI ↔ service wiring (which screen uses what)

| Screen (mockup) | Services |
|---|---|
| Archive Dashboard | `StatsService`, `VaultService.sizeOnDisk` |
| Library Archive | `LibraryService.query` (virtualized), `CoverService.events` |
| Title Details | `LibraryService.get/updateNotes/setCategories`, `CoverService.archiveOne/setCustomCover` |
| Backup & Sources | `ImportService`, `VaultService`, `ExportService`, `StatsService.backupHealth` |
