import { createReadStream } from 'node:fs';

import {
  BadRequestException,
  Controller,
  Get,
  Header,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';

import type {
  CoverArchiveStartedDto,
  CoverJobDto,
  CoverResultDto,
} from './cover.dto';
import { CoverService } from './cover.service';

/** 15 MB cap for a user-uploaded custom cover. */
const MAX_COVER_BYTES = 15 * 1024 * 1024;

/**
 * Route order matters here: `jobs`, `jobs/active` and `jobs/:jobId` must all be
 * declared before the catch-all `:mangaId` routes, or `ParseUUIDPipe` rejects
 * them as malformed manga ids.
 */
@Controller('covers')
export class CoverController {
  constructor(private readonly covers: CoverService) {}

  /** Start (or join) the background job that archives all missing covers. */
  @Post('archive-missing')
  archiveMissing(): Promise<CoverArchiveStartedDto> {
    return this.covers.archiveMissing({ trigger: 'manual', retryFailed: true });
  }

  /** Recent archiving runs, newest first. */
  @Get('jobs')
  jobHistory(): Promise<CoverJobDto[]> {
    return this.covers.jobHistory();
  }

  /**
   * The run currently in progress, or `null`. Lets the app show live progress
   * for a run it didn't start — one triggered by an import, or resumed after a
   * server restart.
   */
  @Get('jobs/active')
  activeJob(): Promise<CoverJobDto | null> {
    return this.covers.activeJob();
  }

  /** Poll a cover-archiving job's progress. */
  @Get('jobs/:jobId')
  jobStatus(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Promise<CoverJobDto> {
    return this.covers.jobStatus(jobId);
  }

  /**
   * Ask a running job to stop. Downloads already in flight are left to finish,
   * so the run ends `cancelled` a moment later; covers not yet attempted stay
   * `none` and are picked up by the next run.
   */
  @Post('jobs/:jobId/cancel')
  cancelJob(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Promise<CoverJobDto> {
    return this.covers.cancel(jobId);
  }

  /** Retry archiving one title's cover (e.g. after a transient failure). */
  @Post(':mangaId/retry')
  retry(
    @Param('mangaId', ParseUUIDPipe) mangaId: string,
  ): Promise<CoverResultDto> {
    return this.covers.archiveOne(mangaId);
  }

  /** Replace a title's cover with an uploaded image (multipart field `file`). */
  @Put(':mangaId/custom')
  @UseInterceptors(
    FileInterceptor('file', { limits: { fileSize: MAX_COVER_BYTES } }),
  )
  setCustom(
    @Param('mangaId', ParseUUIDPipe) mangaId: string,
    @UploadedFile() file?: Express.Multer.File,
  ): Promise<CoverResultDto> {
    if (!file) {
      throw new BadRequestException(
        'no file uploaded (expected multipart field "file")',
      );
    }
    return this.covers.setCustomCover(mangaId, file.buffer);
  }

  /**
   * Serve the archived cover image. Guarded like every route — the Flutter
   * client passes the bearer token via `Image.network(headers:)`. 404 until the
   * cover has been archived.
   */
  @Get(':mangaId')
  @Header('Cache-Control', 'private, max-age=86400')
  async serve(
    @Param('mangaId', ParseUUIDPipe) mangaId: string,
  ): Promise<StreamableFile> {
    const resolved = await this.covers.resolveCoverFile(mangaId);
    if (!resolved) throw new NotFoundException('cover not archived');
    return new StreamableFile(createReadStream(resolved.absPath), {
      type: resolved.mime,
    });
  }
}
