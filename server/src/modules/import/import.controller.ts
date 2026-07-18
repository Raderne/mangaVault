import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';

import { BackupParseError } from '../../tachibk';
import type { ImportRecordDto, StagedImportDto } from './import.dto';
import { ImportService } from './import.service';

/** 200 MB cap — real libraries with thousands of titles are a few MB gzipped. */
const MAX_UPLOAD_BYTES = 200 * 1024 * 1024;

@Controller('imports')
export class ImportController {
  constructor(private readonly imports: ImportService) {}

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

  @Post('stage/:id/commit')
  commit(@Param('id', ParseUUIDPipe) id: string): Promise<ImportRecordDto> {
    return this.imports.commit(id);
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
