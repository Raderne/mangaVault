import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { CoverController } from './cover.controller';
import { CoverFetcher, type CoverFetcherOptions } from './cover.fetcher';
import { CoverOptimizer, type CoverOptimizerOptions } from './cover.optimizer';
import { CoverJobStore } from './cover-job.store';
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

/**
 * Storage-profile overrides from env. Shared with the `covers:optimize` script
 * via {@link optimizerOptionsFromEnv} so a re-encode run and the ingest path can
 * never drift into producing different-looking archives.
 */
export function optimizerOptionsFromEnv(
  get: (key: string) => unknown,
): Partial<CoverOptimizerOptions> {
  const opts: Partial<CoverOptimizerOptions> = {};
  const maxEdge = Number(get('COVER_MAX_EDGE'));
  if (Number.isInteger(maxEdge) && maxEdge > 0) opts.maxEdge = maxEdge;
  const quality = Number(get('COVER_QUALITY'));
  if (Number.isInteger(quality) && quality > 0 && quality <= 100) {
    opts.quality = quality;
  }
  const effort = Number(get('COVER_ENCODE_EFFORT'));
  if (Number.isInteger(effort) && effort >= 0 && effort <= 6) {
    opts.effort = effort;
  }
  return opts;
}

@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES)],
  controllers: [CoverController],
  providers: [
    CoverService,
    CoverJobStore,
    {
      provide: CoverFetcher,
      useFactory: (config: ConfigService) =>
        new CoverFetcher(fetcherOptions(config)),
      inject: [ConfigService],
    },
    {
      provide: CoverOptimizer,
      useFactory: (config: ConfigService) =>
        new CoverOptimizer(optimizerOptionsFromEnv((key) => config.get(key))),
      inject: [ConfigService],
    },
  ],
  exports: [CoverService],
})
export class CoverModule {}
