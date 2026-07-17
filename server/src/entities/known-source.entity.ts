import { Column, Entity, PrimaryColumn } from 'typeorm';

export interface CoverFetchHint {
  referer?: string;
  userAgent?: string;
}

@Entity('known_source')
export class KnownSourceEntity {
  /** Mihon 64-bit source id as a decimal string. */
  @PrimaryColumn({ name: 'source_id', type: 'text' })
  sourceId: string;

  @Column({ type: 'text' })
  name: string;

  @Column({ name: 'base_url', type: 'text', nullable: true })
  baseUrl: string | null;

  @Column({ name: 'fetch_hint', type: 'jsonb', nullable: true })
  fetchHint: CoverFetchHint | null;
}
