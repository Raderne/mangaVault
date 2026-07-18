import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ApiTokenGuard } from './auth/api-token.guard';
import { buildDataSourceOptions } from './database/data-source';
import { HealthController } from './health/health.controller';
import { ImportModule } from './modules/import/import.module';

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
    ImportModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: ApiTokenGuard }],
})
export class AppModule {}
