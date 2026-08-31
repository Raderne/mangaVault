import type { ContentWarning } from '../../extrepo';
import type {
  SourceHealth,
  SourceRegistryState,
} from '../../entities/known-source.entity';
import type {
  SourceHealthJobStatus,
  SourceHealthJobTrigger,
} from '../../entities/source-health-job.entity';

/**
 * A source as the app sees it: registry facts, the last health verdict, and how
 * much of the vault depends on it.
 */
export interface SourceDto {
  /** Mihon 64-bit source id as a decimal string. */
  sourceId: string;
  name: string;
  lang: string;
  homeUrl: string | null;
  iconUrl: string | null;
  packageName: string | null;
  /** Display name of the repository that lists it, when one does. */
  repoName: string | null;
  contentWarning: ContentWarning | null;
  registryState: SourceRegistryState;
  health: SourceHealth;
  healthNote: string | null;
  healthCheckedAt: number | null;
  /** Titles in the vault on this source. The reason it matters. */
  titleCount: number;
  /** Of those, how many have a cover that failed to archive. */
  coverFailedCount: number;
  /**
   * Sources that look like this one under a new identity.
   *
   * Only populated for a source no repository lists. An extension that is
   * renamed or re-published gets **new source ids** — the id is derived from
   * the source's name, so "Comick" and "Comick (Unoriginal)" cannot share one.
   * The vault is then full of titles on an id nothing publishes any more, with
   * nothing to say about it beyond "unknown". Matching the stored name back
   * against the index turns that dead end into the one thing the user actually
   * needs: where those titles should go now.
   */
  suggestedReplacements: SourceSuggestionDto[];
}

/** A listed source that may be the current identity of an unlisted one. */
export interface SourceSuggestionDto {
  sourceId: string;
  name: string;
  lang: string;
  homeUrl: string | null;
  iconUrl: string | null;
  /** Name similarity in [0, 1]. */
  similarity: number;
  /** Titles the vault already holds on the suggested source. */
  titleCount: number;
}

/** One repository, for the repo management list. */
export interface ExtensionRepoDto {
  id: string;
  baseUrl: string;
  name: string;
  website: string;
  enabled: boolean;
  /** Curated repos ship with the app and can be disabled but not deleted. */
  curated: boolean;
  extensionCount: number;
  sourceCount: number;
  lastSyncedAt: number | null;
  lastError: string | null;
}

/** Outcome of a registry refresh, per repository. */
export interface RepoSyncResultDto {
  repoId: string;
  name: string;
  outcome: 'synced' | 'unchanged' | 'failed' | 'skipped';
  extensions: number;
  sources: number;
  /** Sources that stopped being listed by this repo in this sync. */
  delisted: number;
  /** Vault rows whose blank `source_name` this sync filled in. */
  namesBackfilled: number;
  warnings: string[];
  error: string | null;
}

/** One entry of the extensions browser. */
export interface ExtensionDto {
  packageName: string;
  name: string;
  versionName: string;
  extensionLib: string;
  contentWarning: ContentWarning;
  apkUrl: string;
  iconUrl: string;
  repoName: string;
  sourceCount: number;
  /** Sources of this extension the vault actually holds titles from. */
  titleCount: number;
}

export interface ExtensionPageDto {
  items: ExtensionDto[];
  total: number;
  offset: number;
  limit: number;
}

/** Returned by `POST /sources/health-check` — the job to poll. */
export interface SourceHealthStartedDto {
  jobId: string;
  total: number;
  /** True when a run was already in progress and was joined instead. */
  alreadyRunning: boolean;
}

/** Progress of a health-check run. */
export interface SourceHealthJobDto {
  jobId: string;
  status: SourceHealthJobStatus;
  trigger: SourceHealthJobTrigger;
  total: number;
  done: number;
  ok: number;
  degraded: number;
  unhealthy: number;
  finished: boolean;
  cancelRequested: boolean;
  error: string | null;
  startedAt: number;
  finishedAt: number | null;
}
