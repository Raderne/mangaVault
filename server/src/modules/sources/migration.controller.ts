import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';

import { MigrationService } from './migration.service';
import type {
  ApplyMigrationRequest,
  ApplyMigrationResultDto,
  MigrationItemDto,
  MigrationJobDto,
  MigrationPlanDto,
  PlanMigrationRequest,
  UpdateMigrationItemRequest,
} from './migration.dto';

/**
 * Source migration.
 *
 * Split in two on purpose, and the split is the safety property: `plan` only
 * ever writes to its own tables, so a plan can be built, reviewed, edited and
 * thrown away without the library changing at all. `apply` is the single call
 * that touches `manga`, and everything it does is individually undoable.
 *
 * Mounted under `/migrations` rather than `/sources/migrations` so it never
 * competes with `SourceController`'s `:sourceId` catch-all.
 */
@Controller('migrations')
export class MigrationController {
  constructor(private readonly migrations: MigrationService) {}

  /** Recent plans, newest first. */
  @Get()
  list(@Query('limit') limit?: string): Promise<MigrationJobDto[]> {
    const n = Number(limit);
    return this.migrations.listJobs(
      Number.isInteger(n) && n > 0 ? Math.min(n, 50) : 20,
    );
  }

  /** Start building a plan. Returns immediately; poll the job for progress. */
  @Post('plan')
  plan(@Body() body: PlanMigrationRequest): Promise<MigrationJobDto> {
    return this.migrations.plan(body);
  }

  /** The plan and every title in it — what the review screen renders. */
  @Get(':jobId')
  get(@Param('jobId', ParseUUIDPipe) jobId: string): Promise<MigrationPlanDto> {
    return this.migrations.getPlan(jobId);
  }

  /** Stop a plan that is still searching. */
  @Post(':jobId/cancel')
  cancel(
    @Param('jobId', ParseUUIDPipe) jobId: string,
  ): Promise<MigrationJobDto> {
    return this.migrations.cancel(jobId);
  }

  /** Choose a different match for one title, enter a url, or skip it. */
  @Put(':jobId/items/:mangaId')
  updateItem(
    @Param('jobId', ParseUUIDPipe) jobId: string,
    @Param('mangaId', ParseUUIDPipe) mangaId: string,
    @Body() body: UpdateMigrationItemRequest,
  ): Promise<MigrationItemDto> {
    return this.migrations.updateItem(jobId, mangaId, body);
  }

  /** Apply every matched title. The one call that writes to the library. */
  @Post(':jobId/apply')
  apply(
    @Param('jobId', ParseUUIDPipe) jobId: string,
    @Body() body?: ApplyMigrationRequest,
  ): Promise<ApplyMigrationResultDto> {
    return this.migrations.apply(jobId, body?.mangaIds);
  }

  /** Put one migrated title back where it was. */
  @Post('items/:itemId/undo')
  undo(
    @Param('itemId', ParseUUIDPipe) itemId: string,
  ): Promise<MigrationItemDto> {
    return this.migrations.undo(itemId);
  }

  /**
   * Fold a conflicting title into the copy the vault already holds on the
   * target source, carrying its read state over.
   */
  @Post('items/:itemId/merge')
  merge(
    @Param('itemId', ParseUUIDPipe) itemId: string,
  ): Promise<MigrationItemDto> {
    return this.migrations.resolveConflict(itemId);
  }
}
