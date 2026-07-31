import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { CoverModule } from '../covers/cover.module';
import { DeletedTitlesService } from './deleted-titles.service';
import { LibraryController } from './library.controller';
import { LibraryService } from './library.service';

// CoverModule is imported for CoverService.deleteCoverFiles — deleting a title
// must take its archived cover with it. Safe from a cycle: covers never import
// the library.
@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES), CoverModule],
  controllers: [LibraryController],
  providers: [LibraryService, DeletedTitlesService],
  // DeletedTitlesService is exported for ImportModule, which must skip titles
  // the user deleted instead of recreating them.
  exports: [LibraryService, DeletedTitlesService],
})
export class LibraryModule {}
