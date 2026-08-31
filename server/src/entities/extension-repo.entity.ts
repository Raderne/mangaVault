import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

import type { RepoIndexFormat } from '../extrepo';

/**
 * An extension repository we read source metadata from.
 *
 * Identity is `base_url`, because that is what the user pastes and what Mihon
 * keys its own `extension_repos` table on. Curated rows (keiyoushi) are seeded
 * on boot from `curated-repos.ts` — same convention as `backup_app`, so adding
 * a well-known repo is a code edit rather than a migration.
 *
 * `index_etag` is the whole reason a daily sync is cheap: the index is ~1.4 MB,
 * and GitHub answers a conditional request for it with a 304 and no body on
 * every day nothing changed.
 */
@Entity('extension_repo')
export class ExtensionRepoEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** Index base url, no trailing slash, e.g. `https://…/extensions/repo`. */
  @Column({ name: 'base_url', type: 'text', unique: true })
  baseUrl: string;

  @Column({ type: 'text' })
  name: string;

  @Column({ name: 'short_name', type: 'text', nullable: true })
  shortName: string | null;

  @Column({ type: 'text', default: '' })
  website: string;

  /**
   * SHA-256 of the certificate every extension here is signed with. We do not
   * install anything, so this is not a trust decision — but a change to it means
   * the repository changed hands, which is worth showing the user.
   */
  @Column({ name: 'signing_key_fingerprint', type: 'text', nullable: true })
  signingKeyFingerprint: string | null;

  /** The index url that actually answered last time, so we retry it first. */
  @Column({ name: 'index_url', type: 'text', nullable: true })
  indexUrl: string | null;

  @Column({ name: 'index_etag', type: 'text', nullable: true })
  indexEtag: string | null;

  @Column({ name: 'index_format', type: 'text', nullable: true })
  indexFormat: RepoIndexFormat | null;

  /** A disabled repo is kept (and keeps its sources named) but never synced. */
  @Column({ type: 'boolean', default: true })
  enabled: boolean;

  /** True for repos shipped in `curated-repos.ts`; those can't be deleted. */
  @Column({ type: 'boolean', default: false })
  curated: boolean;

  @Column({ name: 'extension_count', type: 'integer', default: 0 })
  extensionCount: number;

  @Column({ name: 'source_count', type: 'integer', default: 0 })
  sourceCount: number;

  @Column({
    name: 'last_synced_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  lastSyncedAt: number | null;

  /**
   * Why the last sync failed, or null. Held rather than thrown: one unreachable
   * repository must never stop the others from refreshing (Mihon does the same).
   */
  @Column({ name: 'last_error', type: 'text', nullable: true })
  lastError: string | null;

  @Column({ name: 'created_at', type: 'bigint', transformer: bigIntToNumber })
  createdAt: number;
}
