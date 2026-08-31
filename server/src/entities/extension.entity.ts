import { Column, Entity, PrimaryColumn } from 'typeorm';

import { bigIntToNumber } from '../common/transformers';

import type { ContentWarning } from '../extrepo';

/**
 * One extension published by a repository.
 *
 * MangaVault never installs or runs these — it cannot; they are Android APKs
 * containing Kotlin classes. The row exists for two reasons: it names the
 * package that owns a source (so a search adapter can bind to a package rather
 * than to one of the dozens of language-variant ids it publishes), and it backs
 * the extensions browser, where the payoff is an APK link the user can install
 * in Mihon itself.
 *
 * `last_seen_at` is the delisting clock: a sync stamps every row it saw, and a
 * row left behind is one the repository has withdrawn.
 */
@Entity('extension')
export class ExtensionEntity {
  @PrimaryColumn({ name: 'repo_id', type: 'uuid' })
  repoId: string;

  /** Android package id, e.g. `eu.kanade.tachiyomi.extension.all.mangadex`. */
  @PrimaryColumn({ name: 'package_name', type: 'text' })
  packageName: string;

  @Column({ type: 'text' })
  name: string;

  @Column({ name: 'version_name', type: 'text', default: '' })
  versionName: string;

  @Column({ name: 'version_code', type: 'integer', default: 0 })
  versionCode: number;

  /** extensions-lib API level (`1.4`, `1.6`) as the repository publishes it. */
  @Column({ name: 'extension_lib', type: 'text', default: '' })
  extensionLib: string;

  @Column({ name: 'content_warning', type: 'text', default: 'safe' })
  contentWarning: ContentWarning;

  @Column({ name: 'apk_url', type: 'text', default: '' })
  apkUrl: string;

  @Column({ name: 'icon_url', type: 'text', default: '' })
  iconUrl: string;

  @Column({ name: 'source_count', type: 'integer', default: 0 })
  sourceCount: number;

  @Column({ name: 'last_seen_at', type: 'bigint', transformer: bigIntToNumber })
  lastSeenAt: number;
}
