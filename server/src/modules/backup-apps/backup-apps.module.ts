import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { BackupAppsController } from './backup-apps.controller';
import { BackupAppsService } from './backup-apps.service';

// Exported for ImportModule (registers the app a backup was tagged with) and
// SyncModule (ships the registry to the device mirror).
@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES)],
  controllers: [BackupAppsController],
  providers: [BackupAppsService],
  exports: [BackupAppsService],
})
export class BackupAppsModule {}
