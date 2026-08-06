import { Module } from '@nestjs/common';

import { ExportController } from './export.controller';
import { ExportService } from './export.service';

/**
 * Backup creation — the inverse of {@link ImportModule}.
 *
 * Reads only, writes nothing: no entities are registered because every query is
 * hand-written SQL over the existing schema, and no file is persisted.
 */
@Module({
  controllers: [ExportController],
  providers: [ExportService],
  exports: [ExportService],
})
export class ExportModule {}
