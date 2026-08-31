import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';

import { SourceHealthService } from './source-health.service';
import { SourceRegistryService } from './source-registry.service';
import type {
  ExtensionPageDto,
  ExtensionRepoDto,
  RepoSyncResultDto,
  SourceDto,
  SourceHealthJobDto,
  SourceHealthStartedDto,
} from './source.dto';

/** Page size ceiling for the extensions browser. */
const MAX_EXTENSION_LIMIT = 100;

const truthy = (v: unknown): boolean =>
  typeof v === 'string' && /^(1|true|yes)$/i.test(v.trim());

/**
 * Route order matters: every static segment (`repos`, `health-check`,
 * `health-jobs`) is declared before `:sourceId`, which otherwise swallows them.
 * The same trap `CoverController` documents, minus the UUID pipe — a source id
 * is a decimal string, not a UUID.
 */
@Controller('sources')
export class SourceController {
  constructor(
    private readonly registry: SourceRegistryService,
    private readonly health: SourceHealthService,
  ) {}

  /** Every source the vault holds titles from, worst health first. */
  @Get()
  list(): Promise<SourceDto[]> {
    return this.registry.listSources();
  }

  // ---- repositories ----

  @Get('repos')
  listRepos(): Promise<ExtensionRepoDto[]> {
    return this.registry.listRepos();
  }

  /** Add a repository. Accepts a base url or a full index url. */
  @Post('repos')
  addRepo(@Body() body: { url?: string }): Promise<ExtensionRepoDto> {
    if (!body?.url) throw new BadRequestException('url is required');
    return this.registry.addRepo(body.url);
  }

  /** Refresh every enabled repository; joins a refresh already running. */
  @Post('repos/sync')
  syncRepos(): Promise<RepoSyncResultDto[]> {
    return this.registry.syncAll();
  }

  @Put('repos/:id/enabled')
  setRepoEnabled(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: { enabled?: boolean },
  ): Promise<ExtensionRepoDto> {
    if (typeof body?.enabled !== 'boolean') {
      throw new BadRequestException('enabled must be a boolean');
    }
    return this.registry.setRepoEnabled(id, body.enabled);
  }

  @Delete('repos/:id')
  removeRepo(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    return this.registry.removeRepo(id);
  }

  // ---- health ----

  /** Start (or join) a run that re-checks every source the vault depends on. */
  @Post('health-check')
  checkHealth(): Promise<SourceHealthStartedDto> {
    return this.health.checkAll({ trigger: 'manual' });
  }

  /**
   * The run in progress, or null — lets the app attach to a scheduled run it
   * did not start, the way the cover banner does.
   */
  @Get('health-jobs/active')
  activeHealthJob(): Promise<SourceHealthJobDto | null> {
    return this.health.activeJob();
  }

  @Get('health-jobs/:jobId')
  healthJob(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Promise<SourceHealthJobDto> {
    return this.health.jobStatus(jobId);
  }

  @Post('health-jobs/:jobId/cancel')
  cancelHealthJob(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Promise<SourceHealthJobDto> {
    return this.health.cancelJob(jobId);
  }

  // ---- one source ----

  @Get(':sourceId')
  async get(@Param('sourceId') sourceId: string): Promise<SourceDto> {
    const source = await this.registry.getSource(sourceId);
    if (!source) throw new NotFoundException('source not found');
    return source;
  }
}

/**
 * The extensions browser is its own resource: it lists what repositories
 * publish, not what the vault contains, and it is paged over the server rather
 * than mirrored to the device.
 */
@Controller('extensions')
export class ExtensionController {
  constructor(private readonly registry: SourceRegistryService) {}

  @Get()
  list(
    @Query('q') text?: string,
    @Query('lang') lang?: string,
    @Query('nsfw') nsfw?: string,
    @Query('offset') offset?: string,
    @Query('limit') limit?: string,
  ): Promise<ExtensionPageDto> {
    const parsedOffset = Number(offset);
    const parsedLimit = Number(limit);
    return this.registry.listExtensions({
      text: text?.trim() || undefined,
      lang: lang?.trim() || undefined,
      includeNsfw: truthy(nsfw),
      offset:
        Number.isInteger(parsedOffset) && parsedOffset > 0 ? parsedOffset : 0,
      limit:
        Number.isInteger(parsedLimit) && parsedLimit > 0
          ? Math.min(parsedLimit, MAX_EXTENSION_LIMIT)
          : 40,
    });
  }
}
