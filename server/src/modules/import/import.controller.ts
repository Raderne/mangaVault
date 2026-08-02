import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
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

  /**
   * Tag a staged import with the app it came from, before committing it.
   *
   * A `PATCH` on the staged entry rather than a body on `commit`: the review UI
   * re-renders from the returned DTO, correcting a wrong pick is the same call
   * again, and `commit` stays bodyless.
   */
  @Patch('stage/:id')
  setSourceApp(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: Record<string, unknown>,
  ): Promise<StagedImportDto> {
    const sourceApp = body.sourceApp;
    if (typeof sourceApp !== 'string') {
      throw new BadRequestException('sourceApp must be a string');
    }
    return this.imports.setSourceApp(id, sourceApp);
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
