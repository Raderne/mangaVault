import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { CoverController } from './cover.controller';
import { CoverFetcher, type CoverFetcherOptions } from './cover.fetcher';
import { CoverJobRegistry } from './cover-job.registry';
import { CoverService } from './cover.service';

/** Build fetcher overrides from env, leaving unset values at their defaults. */
function fetcherOptions(config: ConfigService): Partial<CoverFetcherOptions> {
  const opts: Partial<CoverFetcherOptions> = {};
  const timeout = Number(config.get('COVER_FETCH_TIMEOUT_MS'));
  if (Number.isFinite(timeout) && timeout > 0) opts.timeoutMs = timeout;
  const maxBytes = Number(config.get('COVER_MAX_BYTES'));
  if (Number.isFinite(maxBytes) && maxBytes > 0) opts.maxBytes = maxBytes;
  const attempts = Number(config.get('COVER_MAX_ATTEMPTS'));
  if (Number.isInteger(attempts) && attempts > 0) opts.maxAttempts = attempts;
  const ua = config.get<string>('COVER_USER_AGENT');
  if (typeof ua === 'string' && ua.length > 0) opts.userAgent = ua;
  return opts;
}

@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES)],
  controllers: [CoverController],
  providers: [
    CoverService,
    CoverJobRegistry,
    {
      provide: CoverFetcher,
      useFactory: (config: ConfigService) =>
        new CoverFetcher(fetcherOptions(config)),
      inject: [ConfigService],
    },
  ],
  exports: [CoverService],
})
export class CoverModule {}
