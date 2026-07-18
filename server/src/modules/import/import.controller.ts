import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Sse,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { map, Observable } from 'rxjs';

import { BackupParseError } from '../../tachibk';
import type {
  CommitStartedDto,
  ImportJobSnapshotDto,
  ImportRecordDto,
  StagedImportDto,
} from './import.dto';
import { ImportJobRegistry } from './import-job.registry';
import { ImportService } from './import.service';

/** 200 MB cap — real libraries with thousands of titles are a few MB gzipped. */
const MAX_UPLOAD_BYTES = 200 * 1024 * 1024;

@Controller('imports')
export class ImportController {
  constructor(
    private readonly imports: ImportService,
    private readonly jobs: ImportJobRegistry,
  ) {}

  @Post('stage')
  @UseInterceptors(
    FileInterceptor('file', { limits: { fileSize: MAX_UPLOAD_BYTES } }),
  )
  async stage(
    @UploadedFile() file?: Express.Multer.File,
  ): Promise<StagedImportDto> {
    if (!file) {
      throw new BadRequestException(
        'no file uploaded (expected multipart field "file")',
      );
    }
    try {
      return await this.imports.stage(file.buffer, file.originalname);
    } catch (err) {
      if (err instanceof BackupParseError) {
        throw new BadRequestException(
          `could not parse backup (${err.stage}): ${err.message}`,
        );
      }
      throw err;
    }
  }

  /** Start the streaming commit; returns the job id to open the SSE stream with. */
  @Post('stage/:id/commit')
  commit(@Param('id', ParseUUIDPipe) id: string): CommitStartedDto {
    return this.imports.startCommit(id);
  }

  /**
   * Live commit progress as Server-Sent Events. The `data` of each message is an
   * `ImportEvent`; the stream completes on the terminal `done`/`error` event.
   * Guarded by the global bearer token — the Dio client sends the header on GET.
   */
  @Sse('jobs/:jobId/events')
  jobEvents(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Observable<{ data: object }> {
    return this.jobs.stream(jobId).pipe(map((event) => ({ data: event })));
  }

  /** Point-in-time snapshot of a commit job (reconnect / polling fallback). */
  @Get('jobs/:jobId')
  jobSnapshot(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): ImportJobSnapshotDto {
    return this.jobs.snapshot(jobId);
  }

  @Delete('stage/:id')
  @HttpCode(204)
  discard(@Param('id', ParseUUIDPipe) id: string): void {
    this.imports.discard(id);
  }

  @Get()
  history(): Promise<ImportRecordDto[]> {
    return this.imports.history();
  }
}
