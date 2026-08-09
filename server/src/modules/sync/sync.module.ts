import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { BackupAppsModule } from '../backup-apps/backup-apps.module';
import { LibraryModule } from '../library/library.module';
import { StatsModule } from '../stats/stats.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({
  // LibraryModule supplies the category list; StatsModule the vault size;
  // BackupAppsModule the app registry — all already computed there, so the sync
  // payload reuses them rather than duplicating the queries.
  imports: [
    TypeOrmModule.forFeature(ALL_ENTITIES),
    LibraryModule,
    StatsModule,
    BackupAppsModule,
  ],
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
