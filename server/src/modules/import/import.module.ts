import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ALL_ENTITIES } from '../../entities';
import { ImportController } from './import.controller';
import { ImportJobRegistry } from './import-job.registry';
import { ImportService } from './import.service';

@Module({
  imports: [TypeOrmModule.forFeature(ALL_ENTITIES)],
  controllers: [ImportController],
  providers: [ImportService, ImportJobRegistry],
  exports: [ImportService],
})
export class ImportModule {}
