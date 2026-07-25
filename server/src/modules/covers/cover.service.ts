import { mkdir, stat, unlink, writeFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { MangaEntity } from '../../entities';
import type { CoverFetchHint } from '../../entities/known-source.entity';
import { runPool } from './concurrency';
import type {
  CoverArchiveStartedDto,
  CoverJobStatusDto,
  CoverResultDto,
} from './cover.dto';
import { CoverFetcher } from './cover.fetcher';
import { CoverJobRegistry } from './cover-job.registry';
import { extForMime, mimeForExt, sniffImage } from './image-sniff';

/** A title that still needs its cover archived. */
interface Candidate {
  id: string;
  sourceId: string;
  thumbnailUrl: string;
  coverPath: string | null;
}

const posInt = (value: unknown, fallback: number): number => {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};

const hostOf = (url: string): string => {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
};

/**
 * Downloads and permanently archives manga covers into `STORAGE_DIR/covers/`.
 * Thumbnail URLs rot, so covers are pulled into local storage; the archived
 * file (not the remote URL) is what the app renders. `archiveMissing` runs as a
 * bounded background job (poll its progress via {@link CoverJobRegistry}); a
 * single run at a time is enforced so a second trigger just joins the first.
 */
@Injectable()
export class CoverService {
  private readonly logger = new Logger(CoverService.name);
  private readonly storageDir: string;
  private readonly coversDir: string;
  private readonly globalConcurrency: number;
  private readonly perHostConcurrency: number;
  private activeJobId: string | null = null;

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(MangaEntity)
    private readonly mangaRepo: Repository<MangaEntity>,
    private readonly fetcher: CoverFetcher,
    private readonly jobs: CoverJobRegistry,
    config: ConfigService,
  ) {
    this.storageDir = config.get<string>('STORAGE_DIR') ?? './storage';
    this.coversDir = join(this.storageDir, 'covers');
    this.globalConcurrency = posInt(config.get('COVER_CONCURRENCY'), 6);
    this.perHostConcurrency = posInt(config.get('COVER_PER_HOST'), 2);
  }

  /**
   * Kick off archiving every title whose cover is still `none`/`failed` and has
   * a thumbnail URL. Returns immediately with the job id; if a run is already in
   * flight, that job is returned instead of starting a second one.
   */
  async archiveMissing(): Promise<CoverArchiveStartedDto> {
    if (this.activeJobId) {
      const status = this.jobs.status(this.activeJobId);
      return {
        jobId: status.jobId,
        total: status.total,
        alreadyRunning: true,
      };
    }

    const candidates = await this.loadCandidates();
    const jobId = this.jobs.create(candidates.length);
    if (candidates.length === 0) {
      return { jobId, total: 0, alreadyRunning: false };
    }

    this.activeJobId = jobId;
    const hints = await this.loadHints();
    setImmediate(() => void this.runArchive(jobId, candidates, hints));
    return { jobId, total: candidates.length, alreadyRunning: false };
  }

  /** Archive (or re-archive) a single title's cover synchronously. */
  async archiveOne(mangaId: string): Promise<CoverResultDto> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m) throw new NotFoundException('manga not found');
    const hint = await this.loadHint(m.sourceId);
    return this.archiveCandidate(
      {
        id: m.id,
        sourceId: m.sourceId,
        thumbnailUrl: m.thumbnailUrl ?? '',
        coverPath: m.coverPath,
      },
      hint,
    );
  }

  /**
   * Replace a title's cover with a user-supplied image. The bytes are sniffed
   * (not trusted from the upload's declared MIME) to pick the stored format.
   */
  async setCustomCover(
    mangaId: string,
    bytes: Buffer,
  ): Promise<CoverResultDto> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m) throw new NotFoundException('manga not found');
    const sniffed = sniffImage(bytes);
    if (!sniffed) {
      throw new BadRequestException('uploaded file is not a recognised image');
    }
    const relPath = await this.writeCoverFile(
      mangaId,
      bytes,
      sniffed.ext,
      m.coverPath,
    );
    await this.mangaRepo.update(mangaId, {
      coverPath: relPath,
      coverState: 'archived',
    });
    return { mangaId, outcome: 'archived', coverState: 'archived' };
  }

  /**
   * Resolve the on-disk cover for serving, or `null` when the title has no
   * archived cover (or the file went missing) — the caller returns 404.
   */
  async resolveCoverFile(
    mangaId: string,
  ): Promise<{ absPath: string; mime: string } | null> {
    const m = await this.mangaRepo.findOne({ where: { id: mangaId } });
    if (!m || m.coverState !== 'archived' || !m.coverPath) return null;
    const absPath = join(this.storageDir, m.coverPath);
    try {
      await stat(absPath);
    } catch {
      return null;
    }
    return { absPath, mime: mimeForExt(extname(m.coverPath).slice(1)) };
  }

  jobStatus(jobId: string): CoverJobStatusDto {
    return this.jobs.status(jobId);
  }

  // ---- internals ----

  private async runArchive(
    jobId: string,
    candidates: Candidate[],
    hints: Map<string, CoverFetchHint>,
  ): Promise<void> {
    try {
      await mkdir(this.coversDir, { recursive: true });
      await runPool(
        candidates,
        {
          globalLimit: this.globalConcurrency,
          perKeyLimit: this.perHostConcurrency,
          keyOf: (c) => hostOf(c.thumbnailUrl),
        },
        async (c) => {
          const result = await this.archiveCandidate(
            c,
            hints.get(c.sourceId) ?? null,
          );
          this.jobs.record(jobId, result.outcome);
        },
      );
      const status = this.jobs.status(jobId);
      this.logger.log(
        `cover archive ${jobId}: ${status.archived} archived, ${status.failed} failed, ${status.skipped} skipped of ${status.total}`,
      );
    } catch (err) {
      this.logger.error(
        `cover archive ${jobId} aborted: ${err instanceof Error ? err.message : err}`,
      );
    } finally {
      this.jobs.finish(jobId);
      this.activeJobId = null;
    }
  }

  private async archiveCandidate(
    c: Candidate,
    hint: CoverFetchHint | null,
  ): Promise<CoverResultDto> {
    const url = c.thumbnailUrl?.trim();
    if (!url) {
      return { mangaId: c.id, outcome: 'skipped', coverState: 'none' };
    }
    try {
      const { bytes, mime } = await this.fetcher.fetch(url, hint);
      const relPath = await this.writeCoverFile(
        c.id,
        bytes,
        extForMime(mime),
        c.coverPath,
      );
      await this.mangaRepo.update(c.id, {
        coverPath: relPath,
        coverState: 'archived',
      });
      return { mangaId: c.id, outcome: 'archived', coverState: 'archived' };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'cover fetch failed';
      await this.mangaRepo.update(c.id, { coverState: 'failed' });
      this.logger.debug(`cover ${c.id} failed: ${message}`);
      return {
        mangaId: c.id,
        outcome: 'failed',
        coverState: 'failed',
        error: message,
      };
    }
  }

  /**
   * Write cover bytes to `covers/<mangaId>.<ext>` (relative path stored, forward
   * slashes for portability) and drop any previous file whose extension differed.
   */
  private async writeCoverFile(
    mangaId: string,
    bytes: Buffer,
    ext: string,
    oldRelPath: string | null,
  ): Promise<string> {
    await mkdir(this.coversDir, { recursive: true });
    const relPath = `covers/${mangaId}.${ext}`;
    await writeFile(join(this.storageDir, relPath), bytes);
    if (oldRelPath && oldRelPath !== relPath) {
      await unlink(join(this.storageDir, oldRelPath)).catch(() => undefined);
    }
    return relPath;
  }

  private async loadCandidates(): Promise<Candidate[]> {
    return this.dataSource.query<Candidate[]>(
      `SELECT id,
              source_id     AS "sourceId",
              thumbnail_url AS "thumbnailUrl",
              cover_path    AS "coverPath"
       FROM manga
       WHERE cover_state IN ('none', 'failed')
         AND thumbnail_url IS NOT NULL
         AND btrim(thumbnail_url) <> ''`,
    );
  }

  private async loadHints(): Promise<Map<string, CoverFetchHint>> {
    const rows = await this.dataSource.query<
      { source_id: string; fetch_hint: CoverFetchHint | null }[]
    >(
      `SELECT source_id, fetch_hint FROM known_source WHERE fetch_hint IS NOT NULL`,
    );
    const map = new Map<string, CoverFetchHint>();
    for (const r of rows) {
      if (r.fetch_hint) map.set(r.source_id, r.fetch_hint);
    }
    return map;
  }

  private async loadHint(sourceId: string): Promise<CoverFetchHint | null> {
    const rows = await this.dataSource.query<
      { fetch_hint: CoverFetchHint | null }[]
    >(`SELECT fetch_hint FROM known_source WHERE source_id = $1`, [sourceId]);
    return rows[0]?.fetch_hint ?? null;
  }
}
