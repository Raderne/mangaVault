import { Controller, Get, Query } from '@nestjs/common';

import type { MangaListItemDto } from '../library/library.dto';
import { StatsService } from './stats.service';
import type {
  BackupHealthDto,
  LibraryStatsDto,
  ResumeItemDto,
} from './stats.dto';

const DEFAULT_SHELF_LIMIT = 10;
const MAX_SHELF_LIMIT = 40;

/** Clamp a shelf `limit` query param into a sane range. */
const shelfLimit = (raw?: string): number => {
  const n = Number.parseInt(raw ?? '', 10) || DEFAULT_SHELF_LIMIT;
  return Math.min(MAX_SHELF_LIMIT, Math.max(1, n));
};

@Controller('stats')
export class StatsController {
  constructor(private readonly stats: StatsService) {}

  @Get('library')
  libraryStats(): Promise<LibraryStatsDto> {
    return this.stats.libraryStats();
  }

  @Get('backup-health')
  backupHealth(): Promise<BackupHealthDto[]> {
    return this.stats.backupHealth();
  }

  @Get('recently-added')
  recentlyAdded(@Query('limit') limit?: string): Promise<MangaListItemDto[]> {
    return this.stats.recentlyAdded(shelfLimit(limit));
  }

  @Get('resume-reading')
  resumeReading(@Query('limit') limit?: string): Promise<ResumeItemDto[]> {
    return this.stats.resumeReading(shelfLimit(limit));
  }
}
