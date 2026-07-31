import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { LibraryModule } from '../library/library.module';
import { ImportController } from './import.controller';
import { ImportJobRegistry } from './import-job.registry';
import { ImportService } from './import.service';

@Module({
  // LibraryModule provides DeletedTitlesService: an import must skip titles the
  // user deleted rather than recreating them. No cycle — the library module
  // knows nothing about imports.
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES), LibraryModule],
  controllers: [ImportController],
  providers: [ImportService, ImportJobRegistry],
  exports: [ImportService],
})
export class ImportModule {}
