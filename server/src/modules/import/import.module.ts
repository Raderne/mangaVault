import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { BackupAppsModule } from '../backup-apps/backup-apps.module';
import { CoverModule } from '../covers/cover.module';
import { LibraryModule } from '../library/library.module';
import { ImportController } from './import.controller';
import { ImportJobRegistry } from './import-job.registry';
import { ImportService } from './import.service';

@Module({
  // LibraryModule provides DeletedTitlesService: an import must skip titles the
  // user deleted rather than recreating them. No cycle — the library module
  // knows nothing about imports.
  // CoverModule provides CoverService: a finished import kicks off cover
  // archiving for the titles it just added. (LibraryModule already imports
  // CoverModule for cover-file cleanup on delete; still no cycle.)
  // BackupAppsModule provides BackupAppsService: every app id an import is
  // tagged with has to exist in the registry the library filter reads.
  imports: [
    TypeOrmModule.forFeature(ALL_ENTITIES),
    LibraryModule,
    CoverModule,
    BackupAppsModule,
  ],
  controllers: [ImportController],
  providers: [ImportService, ImportJobRegistry],
  exports: [ImportService],
})
export class ImportModule {}
