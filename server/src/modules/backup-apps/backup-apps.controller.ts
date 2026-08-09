import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
} from '@nestjs/common';

import type { BackupAppDto } from './backup-apps.dto';
import { BackupAppsService } from './backup-apps.service';

@Controller('backup-apps')
export class BackupAppsController {
  constructor(private readonly apps: BackupAppsService) {}

  /** The import picker's list and the library filter's chips. */
  @Get()
  list(): Promise<BackupAppDto[]> {
    return this.apps.list();
  }

  /** Add an app MangaVault doesn't ship knowledge of. */
  @Post()
  create(@Body() body: Record<string, unknown>): Promise<BackupAppDto> {
    const id = body.id;
    const displayName = body.displayName;
    if (typeof id !== 'string' || typeof displayName !== 'string') {
      throw new BadRequestException('id and displayName must be strings');
    }
    const accent = typeof body.accent === 'string' ? body.accent : null;
    return this.apps.create(id, displayName, accent);
  }

  @Delete(':id')
  @HttpCode(204)
  remove(@Param('id') id: string): Promise<void> {
    return this.apps.remove(id);
  }
}
