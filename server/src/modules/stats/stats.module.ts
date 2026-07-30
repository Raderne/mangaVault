import { Module } from '@nestjs/common';

import { LibraryModule } from '../library/library.module';
import { StatsController } from './stats.controller';
import { StatsService } from './stats.service';

@Module({
  // LibraryModule exports LibraryService, which already produces the paged
  // MangaListItemDto rows the "recently added" shelf needs.
  imports: [LibraryModule],
  controllers: [StatsController],
  providers: [StatsService],
})
export class StatsModule {}
