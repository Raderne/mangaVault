import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  type OnModuleInit,
} from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

import { BackupAppEntity } from '../../entities';
import type { BackupAppDto } from './backup-apps.dto';
import { CURATED_APPS } from './curated-apps';

/**
 * A valid Android application id, loosely: lower-case, no whitespace. Kept
 * permissive because the id is only ever compared to the filename prefix, and
 * a fork is free to use something unusual.
 */
export const BACKUP_APP_ID_RE = /^[a-z0-9][a-z0-9._-]{1,99}$/;

/** Bucket key for backups whose producing app is unknown. */
export const UNKNOWN_SOURCE_APP = 'unknown';

interface AppCountRow {
  id: string;
  display_name: string;
  accent: string | null;
  curated: boolean;
  import_count: number;
  title_count: number;
  last_import_at: string | null;
}

/**
 * The registry of reading apps a backup can come from.
 *
 * `import_record.source_app` stores the id alone; this is what gives it a
 * display name, and what the import picker lists when a filename carries no
 * app prefix. It also plans ahead: the auto-backup watcher will hang a watched
 * folder off one of these ids.
 */
@Injectable()
export class BackupAppsService implements OnModuleInit {
  private readonly logger = new Logger(BackupAppsService.name);

  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  /**
   * Seed the curated apps. Idempotent and re-run on every boot, so editing
   * `curated-apps.ts` ships the change without a migration. Only the curated
   * columns are overwritten — a user-added row that later becomes curated keeps
   * its id and gains the shipped name.
   */
  async onModuleInit(): Promise<void> {
    if (CURATED_APPS.length === 0) return;
    const now = Date.now();
    await this.dataSource
      .getRepository(BackupAppEntity)
      .createQueryBuilder()
      .insert()
      .values(
        CURATED_APPS.map((a) => ({
          id: a.id,
          displayName: a.displayName,
          accent: a.accent,
          curated: true,
          createdAt: now,
        })),
      )
      .orUpdate(['display_name', 'accent', 'curated'], ['id'])
      .execute();
    this.logger.log(`seeded ${CURATED_APPS.length} curated backup apps`);
  }

  /**
   * Every known app with how much of the vault it fed, the ones actually used
   * first — the picker offers "imported from before" ahead of the rest.
   */
  async list(): Promise<BackupAppDto[]> {
    const rows = await this.dataSource.query<AppCountRow[]>(
      // FULL JOIN, not LEFT: an import can name an app that is not (or is no
      // longer) in the registry, and that app must still be listable and
      // filterable. Such a row falls back to its id as the display name.
      `SELECT COALESCE(ba.id, u.source_app)           AS id,
              COALESCE(ba.display_name, u.source_app) AS display_name,
              ba.accent                               AS accent,
              COALESCE(ba.curated, FALSE)             AS curated,
              COALESCE(u.import_count, 0)             AS import_count,
              COALESCE(u.title_count, 0)              AS title_count,
              u.last_import_at                        AS last_import_at
       FROM backup_app ba
       FULL JOIN (
         SELECT ir.source_app                   AS source_app,
                COUNT(DISTINCT ir.id)::int      AS import_count,
                COUNT(DISTINCT mi.manga_id)::int AS title_count,
                MAX(ir.imported_at)             AS last_import_at
         FROM import_record ir
         LEFT JOIN manga_import mi ON mi.import_id = ir.id
         WHERE ir.source_app <> ''
         GROUP BY ir.source_app
       ) u ON u.source_app = ba.id
       ORDER BY import_count DESC, title_count DESC, display_name ASC`,
    );

    return rows.map((r) => ({
      id: r.id,
      displayName: r.display_name,
      accent: r.accent,
      curated: r.curated,
      importCount: r.import_count,
      titleCount: r.title_count,
      lastImportAt: r.last_import_at === null ? 0 : Number(r.last_import_at),
    }));
  }

  /**
   * Register an app id if it isn't known yet, and return the id as stored.
   *
   * Called whenever an id is *used* — a filename prefix at commit time, or the
   * user's choice in the picker — so the registry always covers everything the
   * library can be filtered by. Never overwrites an existing display name: the
   * user's own spelling, or a curated one, wins over a derived guess.
   *
   * `''` is a legal input and means "unknown"; it registers nothing.
   */
  async ensure(rawId: string, displayName?: string): Promise<string> {
    const id = rawId.trim().toLowerCase();
    if (!id) return '';
    if (!BACKUP_APP_ID_RE.test(id)) {
      throw new ConflictException(
        `"${rawId}" is not a valid application id (lower-case letters, digits, dots, dashes and underscores)`,
      );
    }

    await this.dataSource
      .getRepository(BackupAppEntity)
      .createQueryBuilder()
      .insert()
      .values({
        id,
        displayName: displayName?.trim() || id,
        accent: null,
        curated: false,
        createdAt: Date.now(),
      })
      .orIgnore()
      .execute();
    return id;
  }

  /**
   * Add an app the user named themselves. Idempotent on the id, but unlike
   * {@link ensure} an explicit display name replaces the stored one — the user
   * is correcting it on purpose.
   */
  async create(
    rawId: string,
    rawDisplayName: string,
    accent?: string | null,
  ): Promise<BackupAppDto> {
    const id = rawId.trim().toLowerCase();
    const displayName = rawDisplayName.trim();
    if (!BACKUP_APP_ID_RE.test(id)) {
      throw new ConflictException(
        `"${rawId}" is not a valid application id (lower-case letters, digits, dots, dashes and underscores)`,
      );
    }
    if (!displayName) {
      throw new ConflictException('displayName must not be empty');
    }

    await this.dataSource
      .getRepository(BackupAppEntity)
      .createQueryBuilder()
      .insert()
      .values({
        id,
        displayName,
        accent: accent ?? null,
        curated: false,
        createdAt: Date.now(),
      })
      .orUpdate(['display_name', 'accent'], ['id'])
      .execute();

    const app = (await this.list()).find((a) => a.id === id);
    if (!app) throw new NotFoundException(`backup app "${id}" not found`);
    return app;
  }

  /**
   * Remove a user-added app. Curated entries and apps that already label an
   * import are refused — deleting the latter would orphan the filter chip its
   * titles are found under.
   */
  async remove(rawId: string): Promise<void> {
    const id = rawId.trim().toLowerCase();
    const repo = this.dataSource.getRepository(BackupAppEntity);
    const existing = await repo.findOne({ where: { id } });
    if (!existing) throw new NotFoundException(`backup app "${id}" not found`);
    if (existing.curated) {
      throw new ConflictException(
        `"${id}" is a built-in app and cannot be removed`,
      );
    }

    const [used] = await this.dataSource.query<{ n: number }[]>(
      `SELECT COUNT(*)::int AS n FROM import_record WHERE source_app = $1`,
      [id],
    );
    if ((used?.n ?? 0) > 0) {
      throw new ConflictException(
        `"${id}" labels ${used.n} import(s) and cannot be removed`,
      );
    }

    await repo.delete({ id });
  }
}
