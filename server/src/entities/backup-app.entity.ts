import { Column, Entity, PrimaryColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

/**
 * A reading app a backup can come from — the registry behind
 * `import_record.source_app`. Curated rows are seeded on boot from
 * `curated-apps.ts`; anything the user adds in the import picker is stored here
 * with `curated = false`.
 */
@Entity('backup_app')
export class BackupAppEntity {
  /** Android application id, lower-cased, e.g. `app.mihon`. */
  @PrimaryColumn({ type: 'text' })
  id: string;

  @Column({ name: 'display_name', type: 'text' })
  displayName: string;

  /** Optional hex accent for the app's chip; null falls back to the theme. */
  @Column({ type: 'text', nullable: true })
  accent: string | null;

  /** True for entries shipped in `curated-apps.ts` — those can't be deleted. */
  @Column({ type: 'boolean', default: false })
  curated: boolean;

  @Column({ name: 'created_at', type: 'bigint', transformer: bigIntToNumber })
  createdAt: number;
}
