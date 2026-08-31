import { BackupAppEntity } from './backup-app.entity';
import { CategoryEntity } from './category.entity';
import { ChapterEntity } from './chapter.entity';
import { CoverJobEntity } from './cover-job.entity';
import { DeletedMangaEntity } from './deleted-manga.entity';
import { ExtensionEntity } from './extension.entity';
import { ExtensionRepoEntity } from './extension-repo.entity';
import { ImportRecordEntity } from './import-record.entity';
import { KnownSourceEntity } from './known-source.entity';
import { MangaEntity } from './manga.entity';
import { SourceHealthJobEntity } from './source-health-job.entity';
import {
  SourceMigrationItemEntity,
  SourceMigrationJobEntity,
} from './source-migration.entity';
import { TrackingEntity } from './tracking.entity';

export {
  BackupAppEntity,
  CategoryEntity,
  ChapterEntity,
  CoverJobEntity,
  DeletedMangaEntity,
  ExtensionEntity,
  ExtensionRepoEntity,
  ImportRecordEntity,
  KnownSourceEntity,
  MangaEntity,
  SourceHealthJobEntity,
  SourceMigrationItemEntity,
  SourceMigrationJobEntity,
  TrackingEntity,
};

export const ALL_ENTITIES = [
  BackupAppEntity,
  CategoryEntity,
  ChapterEntity,
  CoverJobEntity,
  DeletedMangaEntity,
  ExtensionEntity,
  ExtensionRepoEntity,
  ImportRecordEntity,
  KnownSourceEntity,
  MangaEntity,
  SourceHealthJobEntity,
  SourceMigrationItemEntity,
  SourceMigrationJobEntity,
  TrackingEntity,
];
