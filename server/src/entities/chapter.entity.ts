import {
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  Unique,
} from 'typeorm';

import { bigIntToNumber } from '../common/transformers';
import { MangaEntity } from './manga.entity';

@Entity('chapter')
@Unique(['mangaId', 'url'])
export class ChapterEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index('idx_chapter_manga')
  @Column({ name: 'manga_id', type: 'uuid' })
  mangaId: string;

  @ManyToOne(() => MangaEntity, (manga) => manga.chapters, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'manga_id' })
  manga: MangaEntity;

  @Column({ type: 'text' })
  url: string;

  @Column({ type: 'text' })
  name: string;

  @Column({ name: 'chapter_number', type: 'double precision', default: -1 })
  chapterNumber: number;

  @Column({ type: 'text', nullable: true })
  scanlator: string | null;

  @Column({ type: 'boolean', default: false })
  read: boolean;

  @Column({ type: 'boolean', default: false })
  bookmark: boolean;

  @Column({ name: 'last_page_read', type: 'bigint', default: 0, transformer: bigIntToNumber })
  lastPageRead: number;

  @Column({ name: 'date_upload', type: 'bigint', default: 0, transformer: bigIntToNumber })
  dateUpload: number;

  @Column({ name: 'date_fetch', type: 'bigint', default: 0, transformer: bigIntToNumber })
  dateFetch: number;

  @Column({ name: 'source_order', type: 'bigint', default: 0, transformer: bigIntToNumber })
  sourceOrder: number;

  @Column({ name: 'last_read_at', type: 'bigint', nullable: true, transformer: bigIntToNumber })
  lastReadAt: number | null;

  @Column({ name: 'read_duration', type: 'bigint', default: 0, transformer: bigIntToNumber })
  readDuration: number;
}
