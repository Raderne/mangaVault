import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

export type BackupContainerKind = 'gzip-proto' | 'raw-proto' | 'legacy-json';

export interface ImportStats {
  titlesTotal: number;
  titlesNew: number;
  titlesMerged: number;
  chaptersTotal: number;
  categoriesTotal: number;
  warnings: string[];
}

@Entity('import_record')
export class ImportRecordEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'file_name', type: 'text' })
  fileName: string;

  @Column({ name: 'file_size', type: 'bigint', transformer: bigIntToNumber })
  fileSize: number;

  @Column({ type: 'text', unique: true })
  sha256: string;

  /** App-id prefix from the backup filename, e.g. "app.mihon". */
  @Column({ name: 'source_app', type: 'text', default: '' })
  sourceApp: string;

  @Column({ type: 'text' })
  container: BackupContainerKind;

  @Column({ name: 'imported_at', type: 'bigint', transformer: bigIntToNumber })
  importedAt: number;

  @Column({ type: 'jsonb', default: () => `'{}'` })
  stats: Partial<ImportStats>;
}
