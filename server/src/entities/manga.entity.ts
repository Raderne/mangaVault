import {
  Column,
  Entity,
  Index,
  JoinTable,
  ManyToMany,
  OneToMany,
  PrimaryGeneratedColumn,
  Unique,
} from 'typeorm';

import { bigIntToNumber } from '../common/transformers';
import { CategoryEntity } from './category.entity';
import { ChapterEntity } from './chapter.entity';
import { ImportRecordEntity } from './import-record.entity';
import { TrackingEntity } from './tracking.entity';

export type PublicationStatus =
  | 'unknown'
  | 'ongoing'
  | 'completed'
  | 'licensed'
  | 'publishing_finished'
  | 'cancelled'
  | 'on_hiatus';

export type CoverState = 'none' | 'pending' | 'archived' | 'failed';

@Entity('manga')
@Unique(['sourceId', 'mangaUrl'])
export class MangaEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** Mihon 64-bit source id, kept as a decimal string. */
  @Column({ name: 'source_id', type: 'text' })
  sourceId: string;

  /** Relative URL within the source, exactly as found in backups. */
  @Column({ name: 'manga_url', type: 'text' })
  mangaUrl: string;

  @Column({ name: 'source_name', type: 'text', default: '' })
  sourceName: string;

  @Column({ type: 'text' })
  title: string;

  @Column({ type: 'text', nullable: true })
  author: string | null;

  @Column({ type: 'text', nullable: true })
  artist: string | null;

  @Column({ type: 'text', nullable: true })
  description: string | null;

  @Column({ type: 'jsonb', default: () => `'[]'` })
  genres: string[];

  @Index('idx_manga_status')
  @Column({ type: 'text', default: 'unknown' })
  status: PublicationStatus;

  @Column({ name: 'thumbnail_url', type: 'text', nullable: true })
  thumbnailUrl: string | null;

  @Column({ name: 'cover_path', type: 'text', nullable: true })
  coverPath: string | null;

  @Column({ name: 'cover_state', type: 'text', default: 'none' })
  coverState: CoverState;

  /**
   * When the last cover fetch failed. Lets a resumed archive run skip covers it
   * already tried in the interrupted run — the candidate set is re-derived from
   * `cover_state`, which alone can't tell "failed just now" from "failed weeks
   * ago". Null once a cover archives successfully.
   */
  @Column({
    name: 'cover_failed_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  coverFailedAt: number | null;

  @Column({ type: 'text', default: '' })
  notes: string;

  @Column({ type: 'boolean', default: true })
  favorite: boolean;

  @Column({
    name: 'date_added',
    type: 'bigint',
    default: 0,
    transformer: bigIntToNumber,
  })
  dateAdded: number;

  @Column({ name: 'updated_at', type: 'bigint', transformer: bigIntToNumber })
  updatedAt: number;

  // search_tsv is a generated tsvector column managed in the initial
  // migration; it is intentionally not mapped here.

  // row_version (BIGINT) is stamped by a database trigger on every write —
  // see the sync-row-version migration. Deliberately NOT mapped: TypeORM must
  // never write it, and the sync module reads it via raw SQL. Like search_tsv,
  // `migration:generate` may propose dropping it — always review the diff.

  @OneToMany(() => ChapterEntity, (chapter) => chapter.manga)
  chapters: ChapterEntity[];

  @OneToMany(() => TrackingEntity, (tracking) => tracking.manga)
  tracking: TrackingEntity[];

  @ManyToMany(() => CategoryEntity)
  @JoinTable({
    name: 'manga_category',
    joinColumn: { name: 'manga_id', referencedColumnName: 'id' },
    inverseJoinColumn: { name: 'category_id', referencedColumnName: 'id' },
  })
  categories: CategoryEntity[];

  @ManyToMany(() => ImportRecordEntity)
  @JoinTable({
    name: 'manga_import',
    joinColumn: { name: 'manga_id', referencedColumnName: 'id' },
    inverseJoinColumn: { name: 'import_id', referencedColumnName: 'id' },
  })
  imports: ImportRecordEntity[];
}
