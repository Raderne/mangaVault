import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { withSyncLock } from '../../common/sync-lock';
import {
  ExtensionEntity,
  ExtensionRepoEntity,
  KnownSourceEntity,
} from '../../entities';
import type { ParsedRepoIndex } from '../../extrepo';
import { CURATED_REPOS, normalizeRepoUrl } from './curated-repos';
import { titleSimilarity } from './match/title-match';
import { RepoIndexClient } from './repo-index.client';
import type {
  ExtensionDto,
  ExtensionPageDto,
  ExtensionRepoDto,
  RepoSyncResultDto,
  SourceDto,
  SourceSuggestionDto,
} from './source.dto';

/** Rows per INSERT when reconciling an index (~2,150 sources per repo). */
const UPSERT_CHUNK = 500;

/** How often the background refresh runs. */
const SYNC_INTERVAL_MS = 24 * 60 * 60 * 1000;

/** Delay before the boot-time refresh, so it never competes with startup. */
const BOOT_DELAY_MS = 30_000;

/**
 * Name similarity before one source is offered as another's replacement. Set
 * above the migration matcher's own bar on purpose: suggesting the wrong
 * successor for a source carrying hundreds of titles is worse than suggesting
 * nothing and letting the user pick.
 */
const REPLACEMENT_SIMILARITY = 0.75;

/** Score given to a name that is a prefix of the other ("KaliScan.io"). */
const PREFIX_MATCH_SCORE = 0.95;

/** Replacements offered per unlisted source. */
const MAX_SUGGESTIONS = 3;

/**
 * The source registry: what every `manga.source_id` in the vault actually is.
 *
 * An extension repository publishes a static index of the extensions it hosts
 * and the sources each provides. That index is metadata only — no code — which
 * is what makes it usable from a Node server that can never run an Android
 * extension. Syncing it gives three things the vault could not have otherwise:
 *
 *   1. a real name, language, icon and home page for every source id;
 *   2. a **delisting signal** — a source that stops appearing has been
 *      withdrawn, which is the trigger for the whole migration feature; and
 *   3. the package that owns a source, which is what a search adapter binds to
 *      (one package publishes dozens of language-variant ids).
 *
 * All of it runs in the background: on a delay after boot, then daily, or on
 * demand. Nothing here is ever on a request path the app blocks on.
 */
@Injectable()
export class SourceRegistryService
  implements OnApplicationBootstrap, OnModuleDestroy
{
  private readonly logger = new Logger(SourceRegistryService.name);
  private timer: NodeJS.Timeout | null = null;
  /** In-flight sync, so a manual refresh joins rather than duplicating one. */
  private inFlight: Promise<RepoSyncResultDto[]> | null = null;
  /**
   * Repositories being reconciled right now.
   *
   * The guard has to live at this level, not on `syncAll`, because the
   * scheduled pass reaches `syncRepo` directly. Two concurrent reconciliations
   * of the same repo each stamp their own `seenAt`, and the later one's delist
   * pass sees the earlier one's rows as stale — transiently marking live
   * sources as withdrawn, which is exactly the signal the migration flow acts
   * on. Cheaper to refuse the second run than to make delisting timestamp-safe.
   */
  private readonly syncing = new Set<string>();

  constructor(
    private readonly dataSource: DataSource,
    private readonly config: ConfigService,
    private readonly client: RepoIndexClient,
    @InjectRepository(ExtensionRepoEntity)
    private readonly repos: Repository<ExtensionRepoEntity>,
    @InjectRepository(ExtensionEntity)
    private readonly extensions: Repository<ExtensionEntity>,
    @InjectRepository(KnownSourceEntity)
    private readonly sources: Repository<KnownSourceEntity>,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    await this.seedCuratedRepos();
    if (!this.syncEnabled()) {
      this.logger.log('registry sync disabled (EXT_REPO_SYNC_ENABLED=false)');
      return;
    }
    // Deliberately not awaited: boot must not wait on the network, and a
    // failure here is recorded per repo rather than escalated.
    this.timer = setTimeout(() => {
      void this.syncStale();
      this.timer = setInterval(() => void this.syncStale(), SYNC_INTERVAL_MS);
    }, BOOT_DELAY_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  // ---- repositories ----

  async listRepos(): Promise<ExtensionRepoDto[]> {
    const rows = await this.repos.find({ order: { name: 'ASC' } });
    return rows.map(toRepoDto);
  }

  /**
   * Register a repository from a url the user pasted. The url is normalized the
   * way Mihon does (a full index url is accepted and reduced to its base), and
   * `repo.json` must answer before the row is created — a repo that cannot
   * identify itself would just fail silently on every later sync.
   */
  async addRepo(input: string): Promise<ExtensionRepoDto> {
    const baseUrl = normalizeRepoUrl(input);
    if (!baseUrl) {
      throw new BadRequestException('repository url must be https');
    }
    const existing = await this.repos.findOne({ where: { baseUrl } });
    if (existing) throw new ConflictException('repository already added');

    const meta = await this.client.fetchMeta(baseUrl).catch((err: unknown) => {
      throw new BadRequestException(
        `not an extension repository: ${err instanceof Error ? err.message : String(err)}`,
      );
    });

    const row = await this.repos.save(
      this.repos.create({
        baseUrl: meta.baseUrl,
        name: meta.name,
        shortName: meta.shortName,
        website: meta.website,
        signingKeyFingerprint: meta.signingKeyFingerprint,
        enabled: true,
        curated: false,
        createdAt: Date.now(),
      }),
    );
    await this.syncRepo(row);
    const fresh = await this.repos.findOneOrFail({ where: { id: row.id } });
    return toRepoDto(fresh);
  }

  async removeRepo(id: string): Promise<void> {
    const row = await this.repos.findOne({ where: { id } });
    if (!row) throw new NotFoundException('repository not found');
    if (row.curated) {
      throw new BadRequestException(
        'a curated repository can be disabled but not removed',
      );
    }
    // Sources keep their names and their vault rows; they simply stop being
    // listed by anyone. `known_source.repo_id` is ON DELETE SET NULL, so the
    // next sync leaves them at whatever state they had.
    await this.sources.update(
      { repoId: id },
      { repoId: null, registryState: 'unknown' },
    );
    await this.repos.delete({ id });
  }

  async setRepoEnabled(
    id: string,
    enabled: boolean,
  ): Promise<ExtensionRepoDto> {
    const row = await this.repos.findOne({ where: { id } });
    if (!row) throw new NotFoundException('repository not found');
    row.enabled = enabled;
    await this.repos.save(row);
    return toRepoDto(row);
  }

  // ---- sync ----

  /** Refresh every enabled repository. Joins a sync already in flight. */
  async syncAll(): Promise<RepoSyncResultDto[]> {
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.runSyncAll().finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }

  /** Background pass: only repos that have not synced within the interval. */
  private async syncStale(): Promise<void> {
    if (!this.syncEnabled()) return;
    const cutoff = Date.now() - SYNC_INTERVAL_MS;
    const rows = await this.repos.find({ where: { enabled: true } });
    const stale = rows.filter((r) => (r.lastSyncedAt ?? 0) < cutoff);
    if (stale.length === 0) return;
    for (const repo of stale) {
      await this.syncRepo(repo);
    }
    await this.backfillSourceNames();
  }

  private async runSyncAll(): Promise<RepoSyncResultDto[]> {
    const rows = await this.repos.find({ order: { name: 'ASC' } });
    const results: RepoSyncResultDto[] = [];
    for (const repo of rows) {
      if (!repo.enabled) {
        results.push({
          repoId: repo.id,
          name: repo.name,
          outcome: 'skipped',
          extensions: 0,
          sources: 0,
          delisted: 0,
          namesBackfilled: 0,
          warnings: [],
          error: null,
        });
        continue;
      }
      results.push(await this.syncRepo(repo));
    }
    // One backfill for the whole pass rather than one per repo: the second repo
    // may be what finally names a source the first one never listed.
    const namesBackfilled = await this.backfillSourceNames();
    if (results.length > 0) results[0].namesBackfilled = namesBackfilled;
    return results;
  }

  /**
   * Refresh one repository.
   *
   * Never throws: a repository that is down, moved or serving nonsense records
   * its reason in `last_error` and leaves every existing row untouched. Mihon
   * takes the same line — one bad repo must not cost the user the others, and
   * here it must never cost them their source names.
   */
  async syncRepo(repo: ExtensionRepoEntity): Promise<RepoSyncResultDto> {
    const base: RepoSyncResultDto = {
      repoId: repo.id,
      name: repo.name,
      outcome: 'failed',
      extensions: 0,
      sources: 0,
      delisted: 0,
      namesBackfilled: 0,
      warnings: [],
      error: null,
    };
    if (this.syncing.has(repo.id)) {
      return { ...base, outcome: 'skipped', error: null };
    }
    this.syncing.add(repo.id);

    try {
      const meta = await this.client.fetchMeta(repo.baseUrl);
      if (
        repo.signingKeyFingerprint &&
        meta.signingKeyFingerprint &&
        repo.signingKeyFingerprint !== meta.signingKeyFingerprint
      ) {
        // Mihon refuses the update outright here. We are not making a trust
        // decision (nothing gets installed), but the user should be told.
        base.warnings.push(
          'repository signing key changed since it was added — it may have changed hands',
        );
      }

      const fetched = await this.client.fetchIndex(
        repo.baseUrl,
        repo.indexUrl,
        repo.indexEtag,
      );

      if (fetched.kind === 'unchanged') {
        repo.name = meta.name;
        repo.lastSyncedAt = Date.now();
        repo.lastError = null;
        await this.repos.save(repo);
        return { ...base, outcome: 'unchanged' };
      }

      const applied = await this.applyIndex(repo, fetched.index);

      repo.name = meta.name;
      repo.shortName = meta.shortName;
      repo.website = meta.website;
      repo.signingKeyFingerprint = meta.signingKeyFingerprint;
      repo.indexUrl = fetched.url;
      repo.indexEtag = fetched.etag;
      repo.indexFormat = fetched.index.format;
      repo.extensionCount = fetched.index.extensions.length;
      repo.sourceCount = fetched.index.sources.length;
      repo.lastSyncedAt = Date.now();
      repo.lastError = null;
      await this.repos.save(repo);

      this.logger.log(
        `${repo.name}: ${fetched.index.extensions.length} extensions, ` +
          `${fetched.index.sources.length} sources, ${applied.delisted} delisted`,
      );
      return {
        ...base,
        outcome: 'synced',
        extensions: fetched.index.extensions.length,
        sources: fetched.index.sources.length,
        delisted: applied.delisted,
        warnings: [...base.warnings, ...fetched.index.warnings.slice(0, 20)],
      };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      repo.lastError = message;
      repo.lastSyncedAt = Date.now();
      await this.repos.save(repo).catch(() => undefined);
      this.logger.warn(`${repo.name}: sync failed — ${message}`);
      return { ...base, error: message };
    } finally {
      this.syncing.delete(repo.id);
    }
  }

  /**
   * Reconcile one parsed index into `extension` and `known_source`.
   *
   * Everything is stamped with a single `seenAt`, and rows this repo owns that
   * were not stamped are the ones it has withdrawn. That is cheaper and far more
   * robust than diffing: a source that moved to another repository is claimed by
   * its new owner (its `repo_id` changes), so the old repo's delist pass leaves
   * it alone.
   */
  private async applyIndex(
    repo: ExtensionRepoEntity,
    index: ParsedRepoIndex,
  ): Promise<{ delisted: number }> {
    const seenAt = Date.now();

    return this.dataSource.transaction(async (mgr) => {
      for (const chunk of chunked(index.extensions, UPSERT_CHUNK)) {
        await mgr.query(
          `INSERT INTO extension (repo_id, package_name, name, version_name,
             version_code, extension_lib, content_warning, apk_url, icon_url,
             source_count, last_seen_at)
           SELECT $1, u.package_name, u.name, u.version_name, u.version_code,
                  u.extension_lib, u.content_warning, u.apk_url, u.icon_url,
                  u.source_count, $2
           FROM unnest($3::text[], $4::text[], $5::text[], $6::int[], $7::text[],
                       $8::text[], $9::text[], $10::text[], $11::int[])
             AS u(package_name, name, version_name, version_code, extension_lib,
                  content_warning, apk_url, icon_url, source_count)
           ON CONFLICT (repo_id, package_name) DO UPDATE SET
             name = EXCLUDED.name,
             version_name = EXCLUDED.version_name,
             version_code = EXCLUDED.version_code,
             extension_lib = EXCLUDED.extension_lib,
             content_warning = EXCLUDED.content_warning,
             apk_url = EXCLUDED.apk_url,
             icon_url = EXCLUDED.icon_url,
             source_count = EXCLUDED.source_count,
             last_seen_at = EXCLUDED.last_seen_at`,
          [
            repo.id,
            seenAt,
            chunk.map((e) => e.packageName),
            chunk.map((e) => e.name),
            chunk.map((e) => e.versionName),
            chunk.map((e) => e.versionCode),
            chunk.map((e) => e.extensionLib),
            chunk.map((e) => e.contentWarning),
            chunk.map((e) => e.apkUrl),
            chunk.map((e) => e.iconUrl),
            chunk.map((e) => e.sourceIds.length),
          ],
        );
      }

      // An extension this repo no longer publishes.
      await mgr.query(
        `DELETE FROM extension WHERE repo_id = $1 AND last_seen_at < $2`,
        [repo.id, seenAt],
      );

      for (const chunk of chunked(index.sources, UPSERT_CHUNK)) {
        await mgr.query(
          `INSERT INTO known_source (source_id, name, base_url, lang, mirror_urls,
             icon_url, content_warning, repo_id, package_name, registry_state,
             first_listed_at, last_listed_at)
           SELECT u.source_id, u.name, NULLIF(u.home_url, ''), u.lang,
                  u.mirror_urls::jsonb, NULLIF(u.icon_url, ''),
                  u.content_warning, $1, u.package_name, 'listed', $2, $2
           FROM unnest($3::text[], $4::text[], $5::text[], $6::text[], $7::text[],
                       $8::text[], $9::text[], $10::text[])
             AS u(source_id, name, home_url, lang, mirror_urls, icon_url,
                  content_warning, package_name)
           ON CONFLICT (source_id) DO UPDATE SET
             name = EXCLUDED.name,
             base_url = EXCLUDED.base_url,
             lang = EXCLUDED.lang,
             mirror_urls = EXCLUDED.mirror_urls,
             icon_url = EXCLUDED.icon_url,
             content_warning = EXCLUDED.content_warning,
             repo_id = EXCLUDED.repo_id,
             package_name = EXCLUDED.package_name,
             registry_state = 'listed',
             -- Kept from the existing row: the first time we ever saw it
             -- listed, and fetch_hint, which is a manual per-source override
             -- the index knows nothing about.
             first_listed_at = COALESCE(known_source.first_listed_at, EXCLUDED.first_listed_at),
             last_listed_at = EXCLUDED.last_listed_at,
             -- A source that is listed again is no longer 'removed'; force a
             -- re-check rather than leaving a stale verdict on screen.
             health = CASE WHEN known_source.health = 'removed' THEN 'unknown'
                           ELSE known_source.health END`,
          [
            repo.id,
            seenAt,
            chunk.map((s) => s.sourceId),
            chunk.map((s) => s.name),
            chunk.map((s) => s.homeUrl),
            chunk.map((s) => s.lang),
            chunk.map((s) => JSON.stringify(s.mirrorUrls)),
            chunk.map(
              (s) =>
                index.extensions.find((e) => e.packageName === s.packageName)
                  ?.iconUrl ?? '',
            ),
            chunk.map(
              (s) =>
                index.extensions.find((e) => e.packageName === s.packageName)
                  ?.contentWarning ?? 'safe',
            ),
            chunk.map((s) => s.packageName),
          ],
        );
      }

      // Withdrawn: this repo used to list it and no longer does. The row stays
      // — the vault is full of titles pointing at it — but it is now marked,
      // and the health checker will call it `removed` without a request.
      const delisted = await mgr.query<unknown[]>(
        `UPDATE known_source
            SET registry_state = 'delisted'
          WHERE repo_id = $1
            AND last_listed_at < $2
            AND registry_state <> 'delisted'
          RETURNING source_id`,
        [repo.id, seenAt],
      );

      return { delisted: delisted.length };
    });
  }

  /**
   * Fill in blank `manga.source_name` values from the registry.
   *
   * Two long-standing holes leave those blank: a legacy JSON backup carries no
   * source list at all, and the import merge path never wrote `source_name`
   * after row creation, so a title created from a nameless backup stayed
   * nameless even when a later backup named it. The registry can answer both.
   *
   * The write is behind the sync lock because it touches `manga`: the update
   * re-fires `mv_stamp_manga`, which is exactly what carries the new names out
   * to the device on the next delta — no new sync surface needed.
   */
  async backfillSourceNames(): Promise<number> {
    return withSyncLock(this.dataSource, async (mgr) => {
      const rows = await mgr.query<unknown[]>(
        `UPDATE manga m
            SET source_name = ks.name
           FROM known_source ks
          WHERE ks.source_id = m.source_id
            AND btrim(COALESCE(m.source_name, '')) = ''
            AND btrim(ks.name) <> ''
          RETURNING m.id`,
      );
      if (rows.length > 0) {
        this.logger.log(`backfilled ${rows.length} blank source names`);
      }
      return rows.length;
    });
  }

  // ---- reads ----

  /**
   * Every source the vault holds titles from, plus every source any repository
   * lists that the vault also knows. Ordered the way the screen shows them:
   * trouble first, then by how much of the library depends on the source.
   */
  async listSources(): Promise<SourceDto[]> {
    const rows = await this.querySources();
    await this.attachReplacementSuggestions(rows);
    return rows;
  }

  private async querySources(): Promise<SourceDto[]> {
    return await this.dataSource.query<SourceDto[]>(
      `SELECT ks.source_id                              AS "sourceId",
              COALESCE(NULLIF(ks.name, ''), ks.source_id) AS name,
              COALESCE(ks.lang, '')                     AS lang,
              ks.base_url                               AS "homeUrl",
              ks.icon_url                               AS "iconUrl",
              ks.package_name                           AS "packageName",
              r.name                                    AS "repoName",
              ks.content_warning                        AS "contentWarning",
              ks.registry_state                         AS "registryState",
              ks.health                                 AS health,
              ks.health_note                            AS "healthNote",
              ks.health_checked_at                      AS "healthCheckedAt",
              COALESCE(t.title_count, 0)::int           AS "titleCount",
              COALESCE(t.cover_failed_count, 0)::int    AS "coverFailedCount"
         FROM known_source ks
         LEFT JOIN extension_repo r ON r.id = ks.repo_id
         LEFT JOIN (
             SELECT source_id,
                    COUNT(*) AS title_count,
                    COUNT(*) FILTER (WHERE cover_state = 'failed') AS cover_failed_count
               FROM manga
              GROUP BY source_id
         ) t ON t.source_id = ks.source_id
        WHERE COALESCE(t.title_count, 0) > 0
        ORDER BY CASE ks.health
                   WHEN 'removed'     THEN 0
                   WHEN 'unreachable' THEN 1
                   WHEN 'blocked'     THEN 2
                   WHEN 'degraded'    THEN 3
                   WHEN 'unknown'     THEN 4
                   ELSE 5
                 END,
                 COALESCE(t.title_count, 0) DESC,
                 lower(ks.name) ASC`,
    );
  }

  /**
   * For every source no repository lists, find listed sources whose name looks
   * like a later identity of it.
   *
   * Cheap enough to do inline: a vault depends on a few dozen sources, the
   * index holds a couple of thousand, and the comparison is the same string
   * matcher the migration planner uses. Doing it here means the sources screen
   * can offer a target the moment it opens, without a search.
   */
  private async attachReplacementSuggestions(rows: SourceDto[]): Promise<void> {
    const orphans = rows.filter(
      (r) => r.registryState !== 'listed' && r.name.trim().length > 0,
    );
    for (const row of rows) row.suggestedReplacements = [];
    if (orphans.length === 0) return;

    // When an orphan has no recorded language — the common case, since a
    // nameless legacy backup carries none — ties are broken towards the
    // language the rest of this vault is in. "Comick (Unoriginal)" exists in 18
    // languages at identical name similarity, and only one of them is the one
    // the user actually reads.
    const preferredLang = this.dominantLang(rows);

    const listed = await this.dataSource.query<
      Array<Omit<SourceSuggestionDto, 'similarity'>>
    >(
      `SELECT ks.source_id AS "sourceId", ks.name, COALESCE(ks.lang, '') AS lang,
              ks.base_url AS "homeUrl", ks.icon_url AS "iconUrl",
              COALESCE(t.n, 0)::int AS "titleCount"
         FROM known_source ks
         LEFT JOIN (
             SELECT source_id, COUNT(*) AS n FROM manga GROUP BY source_id
         ) t ON t.source_id = ks.source_id
        WHERE ks.registry_state = 'listed'`,
    );

    for (const orphan of orphans) {
      // A numeric "name" is really a missing name — the id printed as a
      // fallback — and would match nothing but noise.
      if (/^\d+$/.test(orphan.name.trim())) continue;

      orphan.suggestedReplacements = listed
        .map((candidate) => ({
          ...candidate,
          similarity: replacementScore(orphan.name, candidate.name),
        }))
        .filter(
          (candidate) =>
            candidate.similarity >= REPLACEMENT_SIMILARITY &&
            candidate.sourceId !== orphan.sourceId &&
            // A language mismatch is decisive: "MangaK" in English is not the
            // same source as "MangaK" in Turkish, and migrating between them
            // would leave the user with titles they cannot read.
            (orphan.lang === '' ||
              candidate.lang === orphan.lang ||
              candidate.lang === 'all'),
        )
        .sort(
          (a, b) =>
            b.similarity - a.similarity ||
            langRank(a.lang, preferredLang) - langRank(b.lang, preferredLang) ||
            b.titleCount - a.titleCount ||
            a.name.localeCompare(b.name),
        )
        .slice(0, MAX_SUGGESTIONS);
    }
  }

  /** The language most of this vault's identified sources are in. */
  private dominantLang(rows: SourceDto[]): string {
    const weight = new Map<string, number>();
    for (const row of rows) {
      if (row.registryState !== 'listed' || !row.lang || row.lang === 'all') {
        continue;
      }
      weight.set(row.lang, (weight.get(row.lang) ?? 0) + row.titleCount);
    }
    let best = 'en';
    let bestWeight = -1;
    for (const [lang, n] of weight) {
      if (n > bestWeight) {
        best = lang;
        bestWeight = n;
      }
    }
    return best;
  }

  /** One source, or null. */
  async getSource(sourceId: string): Promise<SourceDto | null> {
    const all = await this.listSources();
    return all.find((s) => s.sourceId === sourceId) ?? null;
  }

  /**
   * The extensions browser. Server-paged rather than mirrored to the device:
   * ~1,380 rows per repo is not vault data, it changes daily, and the screen is
   * opened rarely.
   */
  async listExtensions(params: {
    text?: string;
    lang?: string;
    includeNsfw?: boolean;
    offset: number;
    limit: number;
  }): Promise<ExtensionPageDto> {
    const where: string[] = [];
    const args: unknown[] = [];

    if (params.text) {
      args.push(`%${params.text.trim().toLowerCase()}%`);
      where.push(`lower(e.name) LIKE $${args.length}`);
    }
    if (params.lang) {
      args.push(params.lang.trim());
      where.push(
        `EXISTS (SELECT 1 FROM known_source s
                  WHERE s.repo_id = e.repo_id
                    AND s.package_name = e.package_name
                    AND s.lang = $${args.length})`,
      );
    }
    if (!params.includeNsfw) {
      where.push(`e.content_warning <> 'nsfw'`);
    }
    const clause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

    const totalRows = await this.dataSource.query<Array<{ n: number }>>(
      `SELECT COUNT(*)::int AS n FROM extension e ${clause}`,
      args,
    );

    const items = await this.dataSource.query<ExtensionDto[]>(
      `SELECT e.package_name    AS "packageName",
              e.name            AS name,
              e.version_name    AS "versionName",
              e.extension_lib   AS "extensionLib",
              e.content_warning AS "contentWarning",
              e.apk_url         AS "apkUrl",
              e.icon_url        AS "iconUrl",
              r.name            AS "repoName",
              e.source_count    AS "sourceCount",
              COALESCE((
                SELECT COUNT(*)::int FROM manga m
                  JOIN known_source s ON s.source_id = m.source_id
                 WHERE s.package_name = e.package_name
              ), 0)             AS "titleCount"
         FROM extension e
         JOIN extension_repo r ON r.id = e.repo_id
         ${clause}
        ORDER BY lower(e.name) ASC
        LIMIT $${args.length + 1} OFFSET $${args.length + 2}`,
      [...args, params.limit, params.offset],
    );

    return {
      items,
      total: totalRows[0]?.n ?? 0,
      offset: params.offset,
      limit: params.limit,
    };
  }

  // ---- internals ----

  private syncEnabled(): boolean {
    const raw = this.config.get<string>('EXT_REPO_SYNC_ENABLED');
    return raw === undefined || !/^(0|false|no)$/i.test(String(raw).trim());
  }

  /** Insert curated repositories that are not registered yet. */
  private async seedCuratedRepos(): Promise<void> {
    for (const curated of CURATED_REPOS) {
      const existing = await this.repos.findOne({
        where: { baseUrl: curated.baseUrl },
      });
      if (existing) {
        if (!existing.curated) {
          existing.curated = true;
          await this.repos.save(existing);
        }
        continue;
      }
      await this.repos.save(
        this.repos.create({
          baseUrl: curated.baseUrl,
          name: curated.name,
          shortName: null,
          website: '',
          signingKeyFingerprint: null,
          enabled: true,
          curated: true,
          createdAt: Date.now(),
        }),
      );
      this.logger.log(`seeded curated repository ${curated.name}`);
    }
  }
}

/**
 * How likely one source name is a later identity of another.
 *
 * Plain edit distance is not enough here, in both directions. It **misses** the
 * most common rename shape — a name that gained or lost a suffix, like
 * "KaliScan" → "KaliScan.io" — because a short name plus four characters scores
 * poorly. And it **invents** matches between unrelated short names: "Taadd" and
 * "Niadd" differ by two letters out of five and score 0.6, which is meaningless.
 *
 * So a name that is a prefix of the other is treated as near-certain, and the
 * bar for everything else is set high enough that coincidental short-name
 * collisions do not clear it.
 */
function replacementScore(from: string, to: string): number {
  const similarity = titleSimilarity(from, to);
  const a = from.trim().toLowerCase();
  const b = to.trim().toLowerCase();
  const shorter = a.length <= b.length ? a : b;
  const longer = a.length <= b.length ? b : a;
  if (shorter.length >= 4 && longer.startsWith(shorter)) {
    return Math.max(similarity, PREFIX_MATCH_SCORE);
  }
  return similarity;
}

/** Sort key preferring the vault's own language, then the neutral `all`. */
function langRank(lang: string, preferred: string): number {
  if (lang === preferred) return 0;
  if (lang === 'all') return 1;
  return 2;
}

function toRepoDto(row: ExtensionRepoEntity): ExtensionRepoDto {
  return {
    id: row.id,
    baseUrl: row.baseUrl,
    name: row.name,
    website: row.website,
    enabled: row.enabled,
    curated: row.curated,
    extensionCount: row.extensionCount,
    sourceCount: row.sourceCount,
    lastSyncedAt: row.lastSyncedAt,
    lastError: row.lastError,
  };
}

function* chunked<T>(items: readonly T[], size: number): Generator<T[]> {
  for (let i = 0; i < items.length; i += size) {
    yield items.slice(i, i + size);
  }
}
