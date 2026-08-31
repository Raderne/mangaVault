import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { LibraryModule } from '../library/library.module';
import { MigrationController } from './migration.controller';
import { MigrationService } from './migration.service';
import {
  RepoIndexClient,
  type RepoIndexClientOptions,
} from './repo-index.client';
import { MangaDexAdapter } from './search/mangadex.adapter';
import {
  SOURCE_SEARCH_ADAPTERS,
  SourceSearchRegistry,
} from './search/source-search.registry';
import { SourceHealthJobStore } from './source-health-job.store';
import { SourceHealthService } from './source-health.service';
import { SourceRegistryService } from './source-registry.service';
import { ExtensionController, SourceController } from './source.controller';

function clientOptions(config: ConfigService): Partial<RepoIndexClientOptions> {
  const opts: Partial<RepoIndexClientOptions> = {};
  const timeout = Number(config.get('EXT_REPO_TIMEOUT_MS'));
  if (Number.isFinite(timeout) && timeout > 0) opts.timeoutMs = timeout;
  return opts;
}

/**
 * The source registry, its health checker, live search, and migration.
 *
 * Nothing here is on a path the app blocks on: the registry syncs on a timer,
 * health and migration planning are durable jobs the client polls, and the two
 * background passes can be switched off entirely (`EXT_REPO_SYNC_ENABLED`,
 * `SOURCE_HEALTH_AUTO_CHECK`) so an offline vault behaves exactly as before.
 *
 * `LibraryModule` is imported for one thing: resolving a migration conflict
 * ends by removing the now-redundant title, and that has to go through the
 * library's own delete path so it is snapshotted into the recycle bin and
 * blocked from being re-imported — not deleted behind its back.
 */
@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES), LibraryModule],
  controllers: [SourceController, ExtensionController, MigrationController],
  providers: [
    SourceRegistryService,
    SourceHealthService,
    SourceHealthJobStore,
    MigrationService,
    SourceSearchRegistry,
    MangaDexAdapter,
    {
      // The adapter list is a provider so tests can replace it wholesale and so
      // adding a source family is one line here rather than an edit inside the
      // registry.
      provide: SOURCE_SEARCH_ADAPTERS,
      useFactory: (mangadex: MangaDexAdapter) => [mangadex],
      inject: [MangaDexAdapter],
    },
    {
      provide: RepoIndexClient,
      useFactory: (config: ConfigService) =>
        new RepoIndexClient(clientOptions(config)),
      inject: [ConfigService],
    },
  ],
  exports: [SourceRegistryService, SourceHealthService, MigrationService],
})
export class SourcesModule {}
