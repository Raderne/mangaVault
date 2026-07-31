import { Column, Entity, Index, PrimaryGeneratedColumn, Unique } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';
import type { ChapterEntity } from './chapter.entity';
import type { MangaEntity } from './manga.entity';
import type { TrackingEntity } from './tracking.entity';

/** Manga scalars worth restoring — everything except identity and derived columns. */
export type DeletedMangaScalars = Omit<
  MangaEntity,
  'id' | 'chapters' | 'tracking' | 'categories' | 'imports'
>;

export type DeletedChapter = Omit<ChapterEntity, 'id' | 'manga' | 'mangaId'>;
export type DeletedTracking = Omit<TrackingEntity, 'id' | 'manga' | 'mangaId'>;

/**
 * Everything needed to put a deleted title back exactly as it was.
 *
 * Deliberately a snapshot rather than "re-import it from the archived backup":
 * reading progress in the vault can be *newer* than any backup on disk (the
 * user may have imported once and read since), and the backup that introduced
 * the title may have been imported months ago.
 */
export interface DeletedMangaSnapshot {
  manga: DeletedMangaScalars;
  chapters: DeletedChapter[];
  tracking: DeletedTracking[];
  /** Category names, not ids — categories can be recreated between delete and restore. */
  categoryNames: string[];
  /** Import records that contributed the title; re-linked if they still exist. */
  importIds: string[];
}

/**
 * One deleted title: a recycle-bin entry *and* an import block list row.
 *
 * The merge engine keys titles on `(source_id, manga_url)`, so without this
 * table the next backup import simply recreates whatever was deleted. Import
 * skips any key registered here; the user restores explicitly.
 */
@Entity('deleted_manga')
@Unique('uq_deleted_manga_key', ['sourceId', 'mangaUrl'])
export class DeletedMangaEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'source_id', type: 'text' })
  sourceId: string;

  @Column({ name: 'manga_url', type: 'text' })
  mangaUrl: string;

  @Column({ name: 'source_name', type: 'text', default: '' })
  sourceName: string;

  @Column({ type: 'text' })
  title: string;

  @Column({ name: 'thumbnail_url', type: 'text', nullable: true })
  thumbnailUrl: string | null;

  @Column({ name: 'chapter_count', type: 'integer', default: 0 })
  chapterCount: number;

  @Column({ name: 'read_count', type: 'integer', default: 0 })
  readCount: number;

  @Index('idx_deleted_manga_deleted_at')
  @Column({ name: 'deleted_at', type: 'bigint', transformer: bigIntToNumber })
  deletedAt: number;

  /** Last time an import offered this title again (null = never since). */
  @Column({
    name: 'last_seen_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  lastSeenAt: number | null;

  /** How many imports have been blocked from re-adding it. */
  @Column({ name: 'seen_count', type: 'integer', default: 0 })
  seenCount: number;

  @Column({ type: 'jsonb' })
  snapshot: DeletedMangaSnapshot;
}
