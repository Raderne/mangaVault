import { CategoryEntity } from './category.entity';
import { ChapterEntity } from './chapter.entity';
import { DeletedMangaEntity } from './deleted-manga.entity';
import { ImportRecordEntity } from './import-record.entity';
import { KnownSourceEntity } from './known-source.entity';
import { MangaEntity } from './manga.entity';
import { TrackingEntity } from './tracking.entity';

export {
  CategoryEntity,
  ChapterEntity,
  DeletedMangaEntity,
  ImportRecordEntity,
  KnownSourceEntity,
  MangaEntity,
  TrackingEntity,
};

export const ALL_ENTITIES = [
  CategoryEntity,
  ChapterEntity,
  DeletedMangaEntity,
  ImportRecordEntity,
  KnownSourceEntity,
  MangaEntity,
  TrackingEntity,
];
