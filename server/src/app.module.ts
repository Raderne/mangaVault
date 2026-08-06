import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ApiTokenGuard } from './auth/api-token.guard';
import { buildDataSourceOptions } from './database/data-source';
import { HealthController } from './health/health.controller';
import { BackupAppsModule } from './modules/backup-apps/backup-apps.module';
import { CoverModule } from './modules/covers/cover.module';
import { ExportModule } from './modules/export/export.module';
import { ImportModule } from './modules/import/import.module';
import { LibraryModule } from './modules/library/library.module';
import { StatsModule } from './modules/stats/stats.module';
import { SyncModule } from './modules/sync/sync.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // server/.env first, repo-root .env as fallback (shared with docker-compose)
      envFilePath: ['.env', '../.env'],
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        buildDataSourceOptions(config.getOrThrow<string>('DATABASE_URL')),
    }),
    BackupAppsModule,
    ImportModule,
    ExportModule,
    LibraryModule,
    CoverModule,
    StatsModule,
    SyncModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: ApiTokenGuard }],
})
export class AppModule {}
