import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

import type { ContentWarning } from '../extrepo';

export interface CoverFetchHint {
  referer?: string;
  userAgent?: string;
}

/**
 * Whether any repository still publishes this source.
 *
 * `delisted` is the signal the migration feature is built on: the id is still
 * all over the vault, but no repository offers an extension for it any more, so
 * nobody can read those titles from that source again. `unknown` is the honest
 * third state — a fork's private source, or one that predates every repository
 * we sync — and must never be presented as "removed".
 */
export type SourceRegistryState = 'listed' | 'delisted' | 'unknown';

/**
 * Result of the last reachability check.
 *
 * `degraded` exists because a homepage answering 200 is not the same as a
 * working source: a site that has moved its images behind a new CDN answers
 * fine while every cover fetch 403s.
 */
export type SourceHealth =
  | 'ok'
  | 'degraded'
  | 'blocked'
  | 'unreachable'
  | 'removed'
  | 'unknown';

/**
 * A source the vault has seen — from a backup's `backupSources` list, from an
 * extension repository index, or both.
 *
 * The row predates the registry: it existed to carry a display name and the
 * per-source cover fetch overrides `CoverService` reads. The registry columns
 * were added onto it rather than into a new table because the primary key was
 * already right, and because a source known only from a backup and a source
 * known only from an index are the same thing to everything downstream.
 */
@Entity('known_source')
export class KnownSourceEntity {
  /** Mihon 64-bit source id as a decimal string. Matches `manga.source_id`. */
  @PrimaryColumn({ name: 'source_id', type: 'text' })
  sourceId: string;

  /** Display name — from the index when listed, else from a backup. */
  @Column({ type: 'text' })
  name: string;

  /** Site home page. Written by the registry sync; the health check reads it. */
  @Column({ name: 'base_url', type: 'text', nullable: true })
  baseUrl: string | null;

  @Column({ name: 'fetch_hint', type: 'jsonb', nullable: true })
  fetchHint: CoverFetchHint | null;

  // ---- registry ----

  @Column({ name: 'repo_id', type: 'uuid', nullable: true })
  repoId: string | null;

  /**
   * Owning extension package. One package publishes many source ids (MangaDex
   * ships 61, one per language), so this — not the id — is what a search
   * adapter binds to.
   */
  @Column({ name: 'package_name', type: 'text', nullable: true })
  packageName: string | null;

  /** Language tag as the repository writes it (`en`, `pt-BR`, `all`). */
  @Column({ type: 'text', default: '' })
  lang: string;

  /** Alternate domains the extension also accepts. */
  @Column({ name: 'mirror_urls', type: 'jsonb', nullable: true })
  mirrorUrls: string[] | null;

  @Column({ name: 'icon_url', type: 'text', nullable: true })
  iconUrl: string | null;

  @Column({ name: 'content_warning', type: 'text', nullable: true })
  contentWarning: ContentWarning | null;

  @Index('idx_known_source_state')
  @Column({ name: 'registry_state', type: 'text', default: 'unknown' })
  registryState: SourceRegistryState;

  @Column({
    name: 'first_listed_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  firstListedAt: number | null;

  /** Last sync that saw this id. Older than the repo's sync ⇒ delisted. */
  @Column({
    name: 'last_listed_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  lastListedAt: number | null;

  // ---- health ----

  @Column({ type: 'text', default: 'unknown' })
  health: SourceHealth;

  @Column({ name: 'health_http_status', type: 'integer', nullable: true })
  healthHttpStatus: number | null;

  @Column({ name: 'health_latency_ms', type: 'integer', nullable: true })
  healthLatencyMs: number | null;

  @Column({
    name: 'health_checked_at',
    type: 'bigint',
    nullable: true,
    transformer: bigIntToNumber,
  })
  healthCheckedAt: number | null;

  /** Short human-readable reason, shown under the verdict in the app. */
  @Column({ name: 'health_note', type: 'text', nullable: true })
  healthNote: string | null;
}
