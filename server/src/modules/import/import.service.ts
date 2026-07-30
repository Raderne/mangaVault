import { createHash, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource, EntityManager } from 'typeorm';

import { ImportJobRegistry } from './import-job.registry';

import { acquireSyncLock } from '../../common/sync-lock';
import {
  CategoryEntity,
  ChapterEntity,
  ImportRecordEntity,
  KnownSourceEntity,
  MangaEntity,
  TrackingEntity,
} from '../../entities';
import {
  BackupNormalizer,
  BackupParser,
  type NormalizedBackup,
  type NormalizedChapter,
  type NormalizedManga,
  type NormalizedTracking,
} from '../../tachibk';
import type {
  CommitStartedDto,
  ImportFileMetaDto,
  ImportRecordDto,
  ImportSummaryDto,
  MergeResultDto,
  StagedImportDto,
} from './import.dto';
import { MergeableManga, MergeEngine } from './merge.engine';

/** How long a staged import lives in memory before it is evicted. */
const STAGED_TTL_MS = 30 * 60 * 1000; // 30 minutes

/** Default titles committed per transaction (override via IMPORT_BATCH_SIZE env). */
const DEFAULT_IMPORT_BATCH_SIZE = 100;

interface StagedEntry {
  id: string;
  fileBytes: Buffer;
  fileMeta: ImportFileMetaDto;
  normalized: NormalizedBackup;
  preview: MergeResultDto[];
  summary: ImportSummaryDto;
  duplicateOf?: ImportRecordDto;
  createdAt: number;
}

@Injectable()
export class ImportService {
  private readonly logger = new Logger(ImportService.name);
  private readonly parser = new BackupParser();
  private readonly normalizer = new BackupNormalizer();
  private readonly merge = new MergeEngine();
  private readonly staged = new Map<string, StagedEntry>();
  private readonly storageDir: string;
  private readonly batchSize: number;

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly jobs: ImportJobRegistry,
    config: ConfigService,
  ) {
    this.storageDir = config.get<string>('STORAGE_DIR') ?? './storage';
    // env values arrive as strings — coerce, and ignore junk/<=0.
    const configured = Number(config.get('IMPORT_BATCH_SIZE'));
    this.batchSize =
      Number.isInteger(configured) && configured > 0
        ? configured
        : DEFAULT_IMPORT_BATCH_SIZE;
  }

  /** Hash, parse, normalize, and preview a merge — without touching the DB. */
  async stage(file: Buffer, fileName: string): Promise<StagedImportDto> {
    this.evictExpired();

    const sha256 = createHash('sha256').update(file).digest('hex');
    const parsed = await this.parser.parse(file, fileName);
    const normalized = this.normalizer.normalize(parsed);

    const fileMeta: ImportFileMetaDto = {
      fileName,
      fileSize: file.length,
      sha256,
      sourceApp: parsed.sourceApp,
      container: parsed.container,
    };

    const existing = await this.dataSource
      .getRepository(ImportRecordEntity)
      .findOne({
        where: { sha256 },
      });
    const duplicateOf = existing ? toRecordDto(existing) : undefined;

    const preview = await this.buildPreview(normalized);
    const summary: ImportSummaryDto = {
      titlesTotal: normalized.manga.length,
      titlesNew: preview.filter((p) => p.action === 'created').length,
      titlesMerged: preview.filter((p) => p.action === 'merged').length,
      chaptersTotal: normalized.manga.reduce(
        (n, m) => n + m.chapters.length,
        0,
      ),
      categoriesTotal: normalized.categories.length,
      warnings: parsed.warnings,
    };

    const id = randomUUID();
    const entry: StagedEntry = {
      id,
      fileBytes: file,
      fileMeta,
      normalized,
      preview,
      summary,
      duplicateOf,
      createdAt: Date.now(),
    };
    this.staged.set(id, entry);

    return {
      id,
      fileMeta,
      summary,
      preview,
      duplicateOf,
      expiresAt: entry.createdAt + STAGED_TTL_MS,
    };
  }

  discard(stagedId: string): void {
    this.staged.delete(stagedId);
  }

  async history(): Promise<ImportRecordDto[]> {
    const rows = await this.dataSource.getRepository(ImportRecordEntity).find({
      order: { importedAt: 'DESC' },
    });
    return rows.map(toRecordDto);
  }

  /**
   * Start a streaming commit. Validates the staged entry, registers a job, and
   * runs the commit in the background — progress is streamed as {@link ImportEvent}s
   * over SSE (see the registry / controller). Returns the job id immediately.
   */
  startCommit(stagedId: string): CommitStartedDto {
    this.evictExpired();
    const entry = this.staged.get(stagedId);
    if (!entry) {
      throw new NotFoundException(
        'staged import not found or expired; re-upload the file',
      );
    }
    if (entry.duplicateOf) {
      throw new ConflictException('this exact file was already imported');
    }

    const jobId = this.jobs.create();
    // Kick off after returning the jobId so the client can open the SSE stream.
    // (The ReplaySubject buffers events regardless, so no event is missed.)
    setImmediate(() => {
      void this.runCommit(jobId, stagedId, entry);
    });
    return { jobId };
  }

  /**
   * Execute the commit in batches of {@link IMPORT_BATCH_SIZE}, each its own
   * transaction, emitting progress events. On failure, already-committed batches
   * remain (the import_record keeps running stats) and an `error` event is sent.
   */
  private async runCommit(
    jobId: string,
    stagedId: string,
    entry: StagedEntry,
  ): Promise<void> {
    const manga = entry.normalized.manga;
    const total = manga.length;
    const stats: ImportSummaryDto = {
      titlesTotal: total,
      titlesNew: 0,
      titlesMerged: 0,
      chaptersTotal: 0,
      categoriesTotal: entry.normalized.categories.length,
      warnings: entry.summary.warnings,
    };
    let processed = 0;
    let importRecord: ImportRecordEntity | undefined;

    try {
      // File is safe regardless of DB outcome — archive it first.
      await this.archiveFile(entry.fileBytes, entry.fileMeta.sha256);
      this.jobs.emit(jobId, {
        type: 'start',
        fileName: entry.fileMeta.fileName,
        total,
      });

      // Categories + sources + the import_record header, in one small transaction.
      let categoryIdByName = new Map<string, string>();
      await this.dataSource.transaction(async (mgr) => {
        await acquireSyncLock(mgr);
        this.jobs.emit(jobId, {
          type: 'phase',
          phase: 'categories',
          detail: `Applying ${entry.normalized.categories.length} categories`,
        });
        categoryIdByName = await this.upsertCategories(mgr, entry.normalized);

        this.jobs.emit(jobId, {
          type: 'phase',
          phase: 'sources',
          detail: `Registering ${entry.normalized.sources.length} sources`,
        });
        await this.upsertSources(mgr, entry.normalized);

        importRecord = mgr.create(ImportRecordEntity, {
          fileName: entry.fileMeta.fileName,
          fileSize: entry.fileMeta.fileSize,
          sha256: entry.fileMeta.sha256,
          sourceApp: entry.fileMeta.sourceApp,
          container: entry.fileMeta.container,
          importedAt: Date.now(),
          stats: { ...stats },
        });
        await mgr.save(importRecord);
      });

      this.jobs.emit(jobId, { type: 'phase', phase: 'manga' });
      for (let start = 0; start < total; start += this.batchSize) {
        const batch = manga.slice(start, start + this.batchSize);
        await this.dataSource.transaction(async (mgr) => {
          // Keeps row_version order == commit order for the sync cursor.
          await acquireSyncLock(mgr);
          for (const m of batch) {
            const { mangaId, created } = await this.upsertManga(mgr, m);
            if (created) stats.titlesNew++;
            else stats.titlesMerged++;
            stats.chaptersTotal += m.chapters.length;
            await this.linkCategories(
              mgr,
              mangaId,
              m.categoryNames,
              categoryIdByName,
            );
            await this.linkImport(mgr, mangaId, importRecord!.id);
            processed++;
            this.jobs.emit(jobId, {
              type: 'manga',
              title: m.title,
              action: created ? 'created' : 'merged',
              processed,
              total,
            });
          }
        });
        // Persist running stats after each committed batch.
        importRecord!.stats = { ...stats };
        await this.dataSource
          .getRepository(ImportRecordEntity)
          .save(importRecord!);
        this.jobs.emit(jobId, { type: 'batch', committed: processed, total });
      }

      this.jobs.emit(jobId, { type: 'phase', phase: 'done' });
      const record = toRecordDto(importRecord!);
      this.jobs.emit(jobId, { type: 'done', record });
      this.staged.delete(stagedId);
      this.logger.log(
        `import ${record.id}: ${stats.titlesNew} new, ${stats.titlesMerged} merged, ${stats.chaptersTotal} chapters`,
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : 'commit failed';
      this.logger.error(
        `import job ${jobId} failed after ${processed}/${total}: ${message}`,
      );
      this.jobs.emit(jobId, { type: 'error', message, processed });
    } finally {
      this.jobs.complete(jobId);
    }
  }

  // ---- preview ----

  private async buildPreview(
    normalized: NormalizedBackup,
  ): Promise<MergeResultDto[]> {
    const repo = this.dataSource.getRepository(MangaEntity);
    const preview: MergeResultDto[] = [];
    for (const m of normalized.manga) {
      const existing = await repo.findOne({
        where: { sourceId: m.key.sourceId, mangaUrl: m.key.mangaUrl },
      });
      if (!existing) {
        preview.push({
          title: m.title,
          sourceId: m.key.sourceId,
          mangaUrl: m.key.mangaUrl,
          action: 'created',
          conflicts: [],
        });
        continue;
      }
      // Scalar/notes conflicts only for the preview (children merge at commit).
      const { conflicts } = this.merge.applyMerge(projectScalars(existing), m);
      preview.push({
        title: m.title,
        sourceId: m.key.sourceId,
        mangaUrl: m.key.mangaUrl,
        action: 'merged',
        conflicts,
      });
    }
    return preview;
  }

  // ---- commit helpers ----

  private async upsertCategories(
    mgr: EntityManager,
    backup: NormalizedBackup,
  ): Promise<Map<string, string>> {
    const repo = mgr.getRepository(CategoryEntity);
    const map = new Map<string, string>();
    for (const c of backup.categories) {
      if (!c.name) continue;
      let row = await repo.findOne({ where: { name: c.name } });
      if (!row) {
        row = await repo.save(repo.create({ name: c.name, sort: c.order }));
      }
      map.set(c.name, row.id);
    }
    // Categories referenced by manga but absent from the categories list.
    for (const m of backup.manga) {
      for (const name of m.categoryNames) {
        if (map.has(name)) continue;
        const existing = await repo.findOne({ where: { name } });
        const row =
          existing ?? (await repo.save(repo.create({ name, sort: 0 })));
        map.set(name, row.id);
      }
    }
    return map;
  }

  private async upsertSources(
    mgr: EntityManager,
    backup: NormalizedBackup,
  ): Promise<void> {
    const repo = mgr.getRepository(KnownSourceEntity);
    for (const s of backup.sources) {
      if (!s.sourceId) continue;
      const existing = await repo.findOne({ where: { sourceId: s.sourceId } });
      if (!existing) {
        await repo.save(
          repo.create({
            sourceId: s.sourceId,
            name: s.name,
            baseUrl: null,
            fetchHint: null,
          }),
        );
      } else if (s.name && existing.name !== s.name) {
        existing.name = s.name;
        await repo.save(existing);
      }
    }
  }

  private async upsertManga(
    mgr: EntityManager,
    m: NormalizedManga,
  ): Promise<{ mangaId: string; created: boolean }> {
    const repo = mgr.getRepository(MangaEntity);
    const existing = await repo.findOne({
      where: { sourceId: m.key.sourceId, mangaUrl: m.key.mangaUrl },
      relations: { chapters: true, tracking: true, categories: true },
    });

    if (!existing) {
      const fresh = this.merge.fromNormalized(m);
      const saved = await repo.save(
        repo.create(
          mergeableToEntity(
            m.key.sourceId,
            m.key.mangaUrl,
            m.sourceName,
            fresh,
          ),
        ),
      );
      await this.writeChapters(mgr, saved.id, fresh.chapters);
      await this.writeTracking(mgr, saved.id, fresh.tracking);
      return { mangaId: saved.id, created: true };
    }

    const { merged } = this.merge.applyMerge(entityToMergeable(existing), m);
    Object.assign(existing, mergeableScalars(merged));
    await repo.save(existing);
    await this.writeChapters(mgr, existing.id, merged.chapters);
    await this.writeTracking(mgr, existing.id, merged.tracking);
    return { mangaId: existing.id, created: false };
  }

  private async writeChapters(
    mgr: EntityManager,
    mangaId: string,
    chapters: NormalizedChapter[],
  ): Promise<void> {
    if (chapters.length === 0) return;
    const rows = chapters.map((c) => ({
      mangaId,
      url: c.url,
      name: c.name,
      chapterNumber: c.chapterNumber,
      scanlator: c.scanlator ?? null,
      read: c.read,
      bookmark: c.bookmark,
      lastPageRead: c.lastPageRead,
      dateUpload: c.dateUpload,
      dateFetch: c.dateFetch,
      sourceOrder: c.sourceOrder,
      lastReadAt: c.lastReadAt ?? null,
      readDuration: c.readDuration,
    }));
    await mgr.upsert(ChapterEntity, rows, ['mangaId', 'url']);
  }

  private async writeTracking(
    mgr: EntityManager,
    mangaId: string,
    tracking: NormalizedTracking[],
  ): Promise<void> {
    if (tracking.length === 0) return;
    const rows = tracking.map((t) => ({
      mangaId,
      tracker: t.tracker,
      remoteId: t.remoteId,
      trackingUrl: t.trackingUrl,
      title: t.title,
      lastChapterRead: t.lastChapterRead,
      totalChapters: t.totalChapters,
      score: t.score,
      status: t.status,
      startedAt: t.startedAt ?? null,
      finishedAt: t.finishedAt ?? null,
    }));
    await mgr.upsert(TrackingEntity, rows, ['mangaId', 'tracker']);
  }

  private async linkCategories(
    mgr: EntityManager,
    mangaId: string,
    names: string[],
    idByName: Map<string, string>,
  ): Promise<void> {
    const values = names
      .map((n) => idByName.get(n))
      .filter((id): id is string => !!id)
      .map((categoryId) => ({ manga_id: mangaId, category_id: categoryId }));
    if (values.length === 0) return;
    await mgr
      .createQueryBuilder()
      .insert()
      .into('manga_category')
      .values(values)
      .orIgnore()
      .execute();
  }

  private async linkImport(
    mgr: EntityManager,
    mangaId: string,
    importId: string,
  ): Promise<void> {
    await mgr
      .createQueryBuilder()
      .insert()
      .into('manga_import')
      .values({ manga_id: mangaId, import_id: importId })
      .orIgnore()
      .execute();
  }

  private async archiveFile(bytes: Buffer, sha256: string): Promise<void> {
    const dir = join(this.storageDir, 'imports');
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, `${sha256}.tachibk`), bytes);
  }

  private evictExpired(): void {
    const cutoff = Date.now() - STAGED_TTL_MS;
    for (const [id, e] of this.staged) {
      if (e.createdAt < cutoff) this.staged.delete(id);
    }
  }
}

// ---- entity <-> mergeable projections ----

function projectScalars(e: MangaEntity): MergeableManga {
  return {
    title: e.title,
    author: e.author ?? undefined,
    artist: e.artist ?? undefined,
    description: e.description ?? undefined,
    thumbnailUrl: e.thumbnailUrl ?? undefined,
    status: e.status,
    genres: e.genres ?? [],
    favorite: e.favorite,
    notes: e.notes,
    dateAdded: e.dateAdded,
    updatedAt: e.updatedAt,
    categoryNames: [],
    chapters: [],
    tracking: [],
  };
}

function entityToMergeable(e: MangaEntity): MergeableManga {
  return {
    ...projectScalars(e),
    categoryNames: (e.categories ?? []).map((c) => c.name),
    chapters: (e.chapters ?? []).map((c) => ({
      url: c.url,
      name: c.name,
      chapterNumber: c.chapterNumber,
      scanlator: c.scanlator ?? undefined,
      read: c.read,
      bookmark: c.bookmark,
      lastPageRead: c.lastPageRead,
      dateUpload: c.dateUpload,
      dateFetch: c.dateFetch,
      sourceOrder: c.sourceOrder,
      lastReadAt: c.lastReadAt ?? undefined,
      readDuration: c.readDuration,
    })),
    tracking: (e.tracking ?? []).map((t) => ({
      tracker: t.tracker as NormalizedTracking['tracker'],
      remoteId: t.remoteId,
      trackingUrl: t.trackingUrl,
      title: t.title,
      lastChapterRead: t.lastChapterRead,
      totalChapters: t.totalChapters,
      score: t.score,
      status: t.status,
      startedAt: t.startedAt ?? undefined,
      finishedAt: t.finishedAt ?? undefined,
    })),
  };
}

function mergeableScalars(m: MergeableManga) {
  return {
    title: m.title,
    author: m.author ?? null,
    artist: m.artist ?? null,
    description: m.description ?? null,
    thumbnailUrl: m.thumbnailUrl ?? null,
    status: m.status,
    genres: m.genres,
    favorite: m.favorite,
    notes: m.notes,
    dateAdded: m.dateAdded,
    updatedAt: m.updatedAt || Date.now(),
  };
}

function mergeableToEntity(
  sourceId: string,
  mangaUrl: string,
  sourceName: string,
  m: MergeableManga,
): Partial<MangaEntity> {
  return {
    sourceId,
    mangaUrl,
    sourceName,
    coverState: 'none',
    ...mergeableScalars(m),
  };
}

function toRecordDto(e: ImportRecordEntity): ImportRecordDto {
  return {
    id: e.id,
    fileName: e.fileName,
    fileSize: e.fileSize,
    sha256: e.sha256,
    sourceApp: e.sourceApp,
    container: e.container,
    importedAt: e.importedAt,
    stats: e.stats ?? {},
  };
}
