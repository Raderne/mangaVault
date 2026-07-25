import {
  Column,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  Unique,
} from 'typeorm';

import { bigIntToNumber } from '../common/transformers';
import { MangaEntity } from './manga.entity';

@Entity('tracking')
@Unique(['mangaId', 'tracker'])
export class TrackingEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'manga_id', type: 'uuid' })
  mangaId: string;

  @ManyToOne(() => MangaEntity, (manga) => manga.tracking, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'manga_id' })
  manga: MangaEntity;

  /** e.g. 'myanimelist', 'anilist', or 'unknown:<syncId>'. */
  @Column({ type: 'text' })
  tracker: string;

  /** Remote media id, int64-safe decimal string. */
  @Column({ name: 'remote_id', type: 'text' })
  remoteId: string;

  @Column({ name: 'tracking_url', type: 'text', default: '' })
  trackingUrl: string;

  @Column({ type: 'text', default: '' })
  title: string;

  @Column({ name: 'last_chapter_read', type: 'double precision', default: 0 })
  lastChapterRead: number;

  @Column({ name: 'total_chapters', type: 'integer', default: 0 })
  totalChapters: number;

  @Column({ type: 'double precision', default: 0 })
  score: number;

  @Column({ type: 'integer', default: 0 })
  status: number;

  @Column({
    name: 'started_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  startedAt: number | null;

  @Column({
    name: 'finished_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  finishedAt: number | null;
}
