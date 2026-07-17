# Phase 2 — Interfaces & API Stubs

All types referenced here are defined in `docs/phase-1-data-structures.md`. These are **NestJS
backend contracts** — controllers depend only on these interfaces, implementations live behind
them as injectable providers. Planned layout: `server/src/tachibk/*` (pure parsing lib, no Nest
deps), `server/src/modules/<import|library|covers|stats|storage|export>/*` (Nest modules
implementing one contract each). The Flutter app never sees these — it consumes the REST API in
§8, mirrored as Dart models + a repository layer (`app/lib/data/`).

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
  stage(file: Buffer, fileName: string): Promise<StagedImport>;
  /** Apply a staged import inside one DB transaction; archives the original file. */
  commit(stagedId: string): Promise<ImportRecord>;
  discard(stagedId: string): void;
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
  /** Enqueue all 'none'/'failed' covers; runs as a background job. */
  archiveMissing(): Promise<{ jobId: string }>;
  jobStatus(jobId: string): Promise<{ done: number; total: number; finished: boolean }>;
  archiveOne(mangaId: VaultId): Promise<CoverResult>;
  setCustomCover(mangaId: VaultId, image: Buffer, mime: string): Promise<void>;
}

export interface CoverResult {
  mangaId: VaultId;
  outcome: 'archived' | 'failed' | 'skipped';
  error?: { status?: number; message: string };
}
export interface CoverRunSummary { archived: number; failed: number; skipped: number }

/**
 * Low-level fetch with Mihon-style header strategy (Node http via undici/axios):
 * try (browser UA + Referer=origin(thumbnailUrl)), then per-source coverFetchHint,
 * exponential backoff, per-host concurrency limit of 2.
 */
export interface CoverFetcher {
  fetch(url: string, hint?: KnownSource['coverFetchHint']): Promise<{ bytes: Buffer; mime: string }>;
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
// 6. Storage management & export
// ============================================================

export interface StorageService {
  /** Verifies FK integrity, cover files present, archived imports hash-match. */
  checkIntegrity(): Promise<IntegrityReport>;
  sizeOnDisk(): Promise<{ db: number; covers: number; imports: number }>;
}

export interface IntegrityReport {
  ok: boolean;
  issues: Array<{ kind: 'missing-cover' | 'orphan-file' | 'hash-mismatch' | 'db-corruption';
                  detail: string }>;
}

export interface ExportService {
  /** MangaVault's own lossless format: zip(vault.json + covers/). Returns file for download. */
  exportVault(): Promise<{ path: string; fileName: string }>;
  /** Round-trip back to a Mihon-compatible .tachibk (gzip+proto, Mihon field numbers). */
  exportTachibk(filter?: LibraryQuery): Promise<{ path: string; fileName: string }>;
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

## 8. REST API surface (NestJS controllers → Flutter client)

All endpoints under `/api/v1`, JSON, `Authorization: Bearer <static token>`.

| Endpoint | Method | Backs | Contract |
|---|---|---|---|
| `/imports/stage` | POST (multipart) | upload `.tachibk`/`.json`, returns `StagedImport` | `ImportService.stage` |
| `/imports/stage/:id/commit` | POST | apply staged import | `ImportService.commit` |
| `/imports/stage/:id` | DELETE | discard staged import | `ImportService.discard` |
| `/imports` | GET | import history | `ImportService.history` |
| `/library` | GET (query params) | paginated `MangaListItem[]` + total | `LibraryService.query` |
| `/library/:id` | GET | full `VaultManga` | `LibraryService.get` |
| `/library/:id/notes` | PUT | update notes | `LibraryService.updateNotes` |
| `/library/:id/categories` | PUT | assign categories | `LibraryService.setCategories` |
| `/library/:id` | DELETE | soft-remove | `LibraryService.remove` |
| `/categories` | GET | list categories | `LibraryService.listCategories` |
| `/covers/archive-missing` | POST | start background job | `CoverService.archiveMissing` |
| `/covers/jobs/:jobId` | GET | poll job progress | `CoverService.jobStatus` |
| `/covers/:mangaId/retry` | POST | retry one cover | `CoverService.archiveOne` |
| `/covers/:mangaId/custom` | PUT (multipart) | upload custom cover | `CoverService.setCustomCover` |
| `/covers/:mangaId` | GET | serve cover image (static, cacheable) | file from `storage/covers/` |
| `/stats/library` | GET | dashboard stats | `StatsService.libraryStats` |
| `/stats/backup-health` | GET | staleness per source app | `StatsService.backupHealth` |
| `/stats/recently-added` | GET | dashboard shelf | `StatsService.recentlyAdded` |
| `/stats/resume-reading` | GET | dashboard shelf | `StatsService.resumeReading` |
| `/storage/integrity` | POST | run integrity check | `StorageService.checkIntegrity` |
| `/storage/size` | GET | disk usage | `StorageService.sizeOnDisk` |
| `/exports/vault` | POST → GET download | lossless zip export | `ExportService.exportVault` |
| `/exports/tachibk` | POST → GET download | Mihon-compatible re-export | `ExportService.exportTachibk` |

## Screen ↔ API wiring (Flutter)

| Screen (mockup) | Endpoints |
|---|---|
| Archive Dashboard | `/stats/*`, `/storage/size` |
| Library Archive | `/library` (paged), `/covers/:id` (images), `/covers/jobs/:jobId` (progress) |
| Title Details | `/library/:id` (+notes/categories), `/covers/:mangaId/retry`, `/covers/:mangaId/custom` |
| Backup & Sources | `/imports/*`, `/storage/*`, `/exports/*`, `/stats/backup-health` |

Flutter data layer: Dart models mirroring the response DTOs (`json_serializable`), one
repository per module (`ImportRepository`, `LibraryRepository`, `CoverRepository`,
`StatsRepository`), HTTP via `dio` with the base-url + token injected from app settings.
