import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import { DataSource } from 'typeorm';

import { MangaDexAdapter } from './mangadex.adapter';
import {
  SourceSearchError,
  type SearchableSource,
  type SourceCandidate,
  type SourceSearchAdapter,
} from './source-search.port';

/** DI token for the adapter list, so tests can supply their own. */
export const SOURCE_SEARCH_ADAPTERS = Symbol('SOURCE_SEARCH_ADAPTERS');

/**
 * Resolves a source id to the adapter that can search it, if any.
 *
 * The honest centre of the feature: most sources have no adapter and never
 * will, so this answers "can I search this automatically?" as a first-class
 * question rather than failing at the point of use. The migration planner asks
 * it up front and tells the user plainly which target sources can be searched
 * and which will need a title already in the vault or a pasted url.
 */
@Injectable()
export class SourceSearchRegistry {
  private readonly logger = new Logger(SourceSearchRegistry.name);
  private readonly byPackage = new Map<string, SourceSearchAdapter>();

  constructor(
    private readonly dataSource: DataSource,
    @Optional()
    @Inject(SOURCE_SEARCH_ADAPTERS)
    adapters?: SourceSearchAdapter[],
  ) {
    for (const adapter of adapters ?? []) {
      this.byPackage.set(adapter.packageName, adapter);
    }
  }

  /** Adapter for a package, or null when we cannot search it. */
  adapterFor(packageName: string | null): SourceSearchAdapter | null {
    if (!packageName) return null;
    return this.byPackage.get(packageName) ?? null;
  }

  /** Every package we can search — used to mark target sources in the UI. */
  searchablePackages(): string[] {
    return [...this.byPackage.keys()];
  }

  /** Registry facts about a source id, or null if we have never seen it. */
  async describe(sourceId: string): Promise<SearchableSource | null> {
    const rows = (await this.dataSource.query(
      `SELECT source_id AS "sourceId", package_name AS "packageName",
              name, COALESCE(lang, '') AS lang, base_url AS "homeUrl"
         FROM known_source WHERE source_id = $1`,
      [sourceId],
    )) as SearchableSource[];
    return rows[0] ?? null;
  }

  /**
   * Search one source, or return `[]` when it has no adapter.
   *
   * Adapter failures are swallowed to an empty result and logged: a plan run
   * covers hundreds of titles across several target sources, and one source
   * rate-limiting must degrade that title to "no match found" — which the user
   * can resolve by hand — rather than abort the whole run.
   */
  async search(
    source: SearchableSource,
    query: string,
    signal?: AbortSignal,
  ): Promise<SourceCandidate[]> {
    const adapter = this.adapterFor(source.packageName);
    if (!adapter) return [];
    try {
      return await adapter.search(source, query, signal);
    } catch (err) {
      if (err instanceof SourceSearchError) {
        this.logger.debug(`${source.name}: ${err.message}`);
      } else if ((err as { name?: string })?.name === 'AbortError') {
        // Cancelled plan; not a failure.
        return [];
      } else {
        this.logger.warn(
          `${source.name}: search failed — ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
      return [];
    }
  }
}

/** Adapters shipped with the server. */
export const BUILT_IN_ADAPTERS = [MangaDexAdapter];
