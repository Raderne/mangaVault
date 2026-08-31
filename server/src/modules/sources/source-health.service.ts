import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';

import type { SourceHealth } from '../../entities/known-source.entity';
import type { SourceHealthJobTrigger } from '../../entities/source-health-job.entity';
import { runPool } from '../covers/concurrency';
import { SourceHealthJobStore } from './source-health-job.store';
import type { SourceHealthJobDto, SourceHealthStartedDto } from './source.dto';

/** How often the background pass re-checks sources. */
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;

/** Boot delay — after the registry's, so delisting is known before we probe. */
const BOOT_DELAY_MS = 90_000;

/**
 * Share of a source's titles whose cover fetch has failed before we call an
 * otherwise-healthy source `degraded`. Set high on purpose: a handful of dead
 * thumbnail urls is normal in any old backup, but a source that has moved its
 * images behind a new CDN fails essentially all of them.
 */
const DEGRADED_COVER_FAILURE_RATIO = 0.8;

/** Below this many titles the cover ratio is noise, so it is not applied. */
const DEGRADED_MIN_TITLES = 5;

/** A source we would otherwise probe, plus the signals we already hold. */
interface Candidate {
  sourceId: string;
  name: string;
  homeUrl: string | null;
  registryState: string;
  titleCount: number;
  coverFailedCount: number;
  coverAttemptedCount: number;
}

interface Verdict {
  health: SourceHealth;
  httpStatus: number | null;
  latencyMs: number | null;
  note: string | null;
}

/**
 * Decides whether the sources the vault depends on still work.
 *
 * Structurally a sibling of `CoverService`: a durable job, a bounded pool, and
 * an abortable run that survives a restart as an `interrupted` row. What differs
 * is the ladder it applies, which leans on facts we already have before it
 * spends a request:
 *
 *   1. **Delisted** — no repository publishes an extension for this id any more.
 *      Nothing to probe: whatever the site answers, nobody can read those
 *      titles from it again. This is the verdict the migration flow acts on.
 *   2. **Reachability** — a browser-shaped GET of the source's home page.
 *      403/451 (and Cloudflare's 503) read as `blocked` rather than
 *      `unreachable`, because they mean something different to the user: the
 *      site is alive and refusing us.
 *   3. **Cover corroboration** — a source can answer 200 on its home page while
 *      every cover it serves 403s. We already record that per title, so an `ok`
 *      whose covers are failing wholesale is downgraded to `degraded` instead of
 *      being reported as fine.
 */
@Injectable()
export class SourceHealthService
  implements OnApplicationBootstrap, OnModuleDestroy
{
  private readonly logger = new Logger(SourceHealthService.name);
  private timer: NodeJS.Timeout | null = null;
  private pendingStart: Promise<SourceHealthStartedDto> | null = null;

  constructor(
    private readonly dataSource: DataSource,
    private readonly config: ConfigService,
    private readonly jobs: SourceHealthJobStore,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    const reclaimed = await this.jobs.reclaimInterrupted();
    if (reclaimed > 0) {
      // Not resumed: a health pass is cheap and the scheduled one will redo it
      // shortly, so there is nothing to be gained by racing startup for it.
      this.logger.log(`closed ${reclaimed} interrupted health job(s)`);
    }
    if (!this.autoCheckEnabled()) return;
    this.timer = setTimeout(() => {
      void this.checkStale();
      this.timer = setInterval(() => void this.checkStale(), CHECK_INTERVAL_MS);
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

  /**
   * Start a health run, or join the one already going.
   *
   * `pendingStart` covers the window between deciding to start and the job row
   * existing: two taps in quick succession must produce one run, not two
   * competing ones (`uq_source_health_job_running` would reject the second, but
   * loudly and after work had begun).
   */
  async checkAll(params: {
    trigger: SourceHealthJobTrigger;
    /** Skip sources checked within this many ms. 0 re-checks everything. */
    maxAgeMs?: number;
  }): Promise<SourceHealthStartedDto> {
    if (this.pendingStart) return this.pendingStart;
    const active = await this.jobs.active();
    if (active) {
      return { jobId: active.jobId, total: active.total, alreadyRunning: true };
    }

    this.pendingStart = this.beginRun(params).finally(() => {
      this.pendingStart = null;
    });
    return this.pendingStart;
  }

  async jobStatus(jobId: string): Promise<SourceHealthJobDto> {
    return this.jobs.status(jobId);
  }

  async activeJob(): Promise<SourceHealthJobDto | null> {
    return this.jobs.active();
  }

  async cancelJob(jobId: string): Promise<SourceHealthJobDto> {
    return this.jobs.cancel(jobId);
  }

  // ---- run ----

  private async beginRun(params: {
    trigger: SourceHealthJobTrigger;
    maxAgeMs?: number;
  }): Promise<SourceHealthStartedDto> {
    const candidates = await this.candidates(params.maxAgeMs ?? 0);
    if (candidates.length === 0) {
      const job = await this.jobs.start({ total: 0, trigger: params.trigger });
      await this.jobs.finish(job.jobId, 'finished');
      return { jobId: job.jobId, total: 0, alreadyRunning: false };
    }

    const job = await this.jobs.start({
      total: candidates.length,
      trigger: params.trigger,
    });
    // Not awaited: the caller gets a job id to poll, the run proceeds behind it.
    void this.run(job.jobId, candidates);
    return { jobId: job.jobId, total: candidates.length, alreadyRunning: false };
  }

  private async run(jobId: string, candidates: Candidate[]): Promise<void> {
    const signal = this.jobs.signal(jobId);
    try {
      await runPool(
        candidates,
        {
          globalLimit: this.intFromEnv('SOURCE_HEALTH_CONCURRENCY', 4),
          // One request per host at a time: several sources can share a domain,
          // and a health check that looks like a burst is a health check that
          // gets blocked.
          perKeyLimit: 1,
          keyOf: (c) => hostOf(c.homeUrl) ?? c.sourceId,
          signal,
        },
        async (candidate) => {
          const verdict = await this.judge(candidate);
          await this.persist(candidate.sourceId, verdict);
          this.jobs.record(jobId, verdict.health);
        },
      );
      await this.jobs.finish(
        jobId,
        signal?.aborted === true ? 'cancelled' : 'finished',
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(`health run ${jobId} failed: ${message}`);
      await this.jobs.finish(jobId, 'failed', message);
    }
  }

  /** Background pass over sources whose verdict has gone stale. */
  private async checkStale(): Promise<void> {
    if (!this.autoCheckEnabled()) return;
    try {
      await this.checkAll({ trigger: 'schedule', maxAgeMs: CHECK_INTERVAL_MS });
    } catch (err) {
      this.logger.warn(
        `scheduled health check failed: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }
  }

  // ---- the ladder ----

  private async judge(candidate: Candidate): Promise<Verdict> {
    // 1. Withdrawn from every repository — no request needed, and none would
    //    change the answer.
    if (candidate.registryState === 'delisted') {
      return {
        health: 'removed',
        httpStatus: null,
        latencyMs: null,
        note: 'no extension repository lists this source any more',
      };
    }

    if (!candidate.homeUrl) {
      return {
        health: 'unknown',
        httpStatus: null,
        latencyMs: null,
        note:
          candidate.registryState === 'unknown'
            ? 'not listed by any repository, so there is no address to check'
            : 'no home page recorded',
      };
    }

    // 2. Reachability.
    const probe = await this.probe(candidate.homeUrl);
    if (probe.health !== 'ok') return probe;

    // 3. Corroborate with what the cover archiver has already learned.
    if (
      candidate.coverAttemptedCount >= DEGRADED_MIN_TITLES &&
      candidate.coverFailedCount / candidate.coverAttemptedCount >=
        DEGRADED_COVER_FAILURE_RATIO
    ) {
      const pct = Math.round(
        (candidate.coverFailedCount / candidate.coverAttemptedCount) * 100,
      );
      return {
        ...probe,
        health: 'degraded',
        note: `site answers, but ${pct}% of its covers fail to download`,
      };
    }
    return probe;
  }

  /**
   * One browser-shaped GET of the source's home page.
   *
   * Uses the same header set as the cover fetcher for the same reason: a plain
   * Node request is refused by a large share of these sites, and a false
   * `blocked` here would push the user to migrate a source that works fine.
   */
  private async probe(homeUrl: string): Promise<Verdict> {
    const timeoutMs = this.intFromEnv('SOURCE_HEALTH_TIMEOUT_MS', 10_000);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const startedAt = Date.now();
    try {
      const res = await fetch(homeUrl, {
        method: 'GET',
        headers: {
          'User-Agent':
            this.config.get<string>('COVER_USER_AGENT') ?? DEFAULT_USER_AGENT,
          Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
        },
        redirect: 'follow',
        signal: controller.signal,
      });
      const latencyMs = Date.now() - startedAt;
      // The body is never read — we only need the status line, and some of
      // these pages are megabytes.
      void res.body?.cancel();

      if (res.ok || (res.status >= 300 && res.status < 400)) {
        return { health: 'ok', httpStatus: res.status, latencyMs, note: null };
      }
      if (res.status === 403 || res.status === 451 || res.status === 503) {
        return {
          health: 'blocked',
          httpStatus: res.status,
          latencyMs,
          note:
            res.status === 451
              ? 'blocked for legal reasons'
              : 'the site is up but refusing automated requests',
        };
      }
      return {
        health: 'unreachable',
        httpStatus: res.status,
        latencyMs,
        note: `home page answered HTTP ${res.status}`,
      };
    } catch (err) {
      const latencyMs = Date.now() - startedAt;
      const message = err instanceof Error ? err.message : String(err);
      return {
        health: 'unreachable',
        httpStatus: null,
        latencyMs,
        note: controller.signal.aborted
          ? `no answer within ${timeoutMs / 1000}s`
          : shortenCause(message),
      };
    } finally {
      clearTimeout(timer);
    }
  }

  // ---- data ----

  /**
   * Sources worth checking: those the vault actually holds titles from. A
   * registry of 2,156 sources is not something to probe — 30-odd are what this
   * library depends on.
   */
  private async candidates(maxAgeMs: number): Promise<Candidate[]> {
    const args: unknown[] = [];
    let staleClause = '';
    if (maxAgeMs > 0) {
      args.push(Date.now() - maxAgeMs);
      staleClause = `AND (ks.health_checked_at IS NULL OR ks.health_checked_at < $1)`;
    }
    return (await this.dataSource.query(
      `SELECT ks.source_id       AS "sourceId",
              ks.name            AS name,
              ks.base_url        AS "homeUrl",
              ks.registry_state  AS "registryState",
              t.title_count::int AS "titleCount",
              t.cover_failed::int AS "coverFailedCount",
              t.cover_attempted::int AS "coverAttemptedCount"
         FROM known_source ks
         JOIN (
             SELECT source_id,
                    COUNT(*) AS title_count,
                    COUNT(*) FILTER (WHERE cover_state = 'failed') AS cover_failed,
                    COUNT(*) FILTER (
                      WHERE cover_state IN ('failed', 'archived')
                    ) AS cover_attempted
               FROM manga
              WHERE thumbnail_url IS NOT NULL AND btrim(thumbnail_url) <> ''
              GROUP BY source_id
         ) t ON t.source_id = ks.source_id
        WHERE TRUE ${staleClause}
        ORDER BY t.title_count DESC`,
      args,
    )) as Candidate[];
  }

  /**
   * Store one verdict.
   *
   * `known_source` is not part of the library delta, so this needs no sync lock
   * — nothing here touches `manga`, and the app reads source state from the
   * registry snapshot in `/sync/meta` rather than from a row version.
   */
  private async persist(sourceId: string, verdict: Verdict): Promise<void> {
    await this.dataSource.query(
      `UPDATE known_source
          SET health = $2,
              health_http_status = $3,
              health_latency_ms = $4,
              health_checked_at = $5,
              health_note = $6
        WHERE source_id = $1`,
      [
        sourceId,
        verdict.health,
        verdict.httpStatus,
        verdict.latencyMs,
        Date.now(),
        verdict.note,
      ],
    );
  }

  private autoCheckEnabled(): boolean {
    const raw = this.config.get<string>('SOURCE_HEALTH_AUTO_CHECK');
    return raw === undefined || !/^(0|false|no)$/i.test(String(raw).trim());
  }

  private intFromEnv(key: string, fallback: number): number {
    const n = Number(this.config.get(key));
    return Number.isFinite(n) && n > 0 ? Math.trunc(n) : fallback;
  }
}

const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

function hostOf(url: string | null): string | null {
  if (!url) return null;
  try {
    return new URL(url).host;
  } catch {
    return null;
  }
}

/** Node's fetch errors are verbose; the app shows this under the verdict. */
function shortenCause(message: string): string {
  if (/ENOTFOUND|EAI_AGAIN|getaddrinfo/i.test(message)) {
    return 'domain no longer resolves';
  }
  if (/ECONNREFUSED/i.test(message)) return 'connection refused';
  if (/certificate|CERT_|SSL/i.test(message)) return 'TLS certificate problem';
  if (/ECONNRESET|socket hang up/i.test(message)) return 'connection reset';
  return message.slice(0, 120);
}
