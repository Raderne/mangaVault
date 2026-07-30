import { Controller, Get, Query } from '@nestjs/common';

import {
  SYNC_DEFAULT_LIMIT,
  type SyncMetaDto,
  type SyncPageDto,
} from './sync.dto';
import { SyncService } from './sync.service';

/**
 * Parse a cursor into a non-negative decimal integer string. Cursors are int64
 * and must stay strings end-to-end (they exceed Number.MAX_SAFE_INTEGER in
 * principle); anything malformed restarts from the beginning rather than
 * erroring, since a client with a corrupt cursor wants a full resync anyway.
 */
const parseCursor = (raw?: string): string =>
  raw !== undefined && /^\d+$/.test(raw) ? raw : '0';

const parseLimit = (raw?: string): number => {
  const n = Number(raw);
  return Number.isInteger(n) && n > 0 ? n : SYNC_DEFAULT_LIMIT;
};

/**
 * Delta feed for the on-device library mirror. Bearer-guarded like every other
 * route (no `@Public()`).
 */
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Get('library')
  changes(
    @Query('since') since?: string,
    @Query('limit') limit?: string,
  ): Promise<SyncPageDto> {
    return this.sync.changesSince(parseCursor(since), parseLimit(limit));
  }

  @Get('meta')
  meta(): Promise<SyncMetaDto> {
    return this.sync.meta();
  }
}
