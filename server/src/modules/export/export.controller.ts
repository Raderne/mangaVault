import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  Post,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';

import { PUBLICATION_STATUSES } from '../library/library.dto';
import type { PublicationStatus } from '../../entities/manga.entity';
import { BACKUP_APP_ID_RE } from '../backup-apps/backup-apps.service';
import {
  EXPORT_MODES,
  type ExportFacetsDto,
  type ExportFilterDto,
  type ExportIncludeDto,
  type ExportMode,
  type ExportPreviewDto,
  type ExportScopeDto,
} from './export.dto';
import { ExportService } from './export.service';

/** Ceiling on a hand-picked selection, matching the bulk-delete limit. */
const MAX_EXPORT_IDS = 5000;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const strings = (raw: unknown): string[] =>
  Array.isArray(raw)
    ? raw.filter((v): v is string => typeof v === 'string' && v.length > 0)
    : [];

const bool = (raw: unknown, fallback: boolean): boolean =>
  typeof raw === 'boolean' ? raw : fallback;

/** Tri-state: only an explicit boolean sets the filter; anything else leaves it off. */
const triBool = (raw: unknown): boolean | undefined =>
  typeof raw === 'boolean' ? raw : undefined;

function parseFilter(raw: unknown): ExportFilterDto {
  const f = (raw ?? {}) as Record<string, unknown>;
  const text = typeof f.text === 'string' ? f.text.trim() : '';
  const ids = strings(f.categoryIds);
  if (ids.some((id) => !UUID_RE.test(id))) {
    throw new BadRequestException('filter.categoryIds must all be uuids');
  }
  return {
    text: text || undefined,
    status: strings(f.status).filter((s): s is PublicationStatus =>
      PUBLICATION_STATUSES.includes(s as PublicationStatus),
    ),
    categoryIds: ids,
    // Source ids are 64-bit decimal strings, never numbers — they exceed 2^53.
    sourceIds: strings(f.sourceIds).filter((s) => /^\d{1,20}$/.test(s)),
    sourceApps: strings(f.sourceApps).map((s) => s.trim().toLowerCase()),
    favorite: triBool(f.favorite),
    unreadOnly: bool(f.unreadOnly, false),
    startedOnly: bool(f.startedOnly, false),
  };
}

function parseInclude(raw: unknown): ExportIncludeDto {
  const i = (raw ?? {}) as Record<string, unknown>;
  const chapters = bool(i.chapters, true);
  return {
    chapters,
    // Progress lives on chapter rows, so it cannot outlive them. Normalized
    // here rather than in the service so preview and build can never disagree.
    readProgress: chapters && bool(i.readProgress, true),
    categories: bool(i.categories, true),
    tracking: bool(i.tracking, true),
  };
}

/**
 * Validate a loosely-typed request body into a scope.
 *
 * Everything defaults to "the whole vault, losslessly": a body of `{}` is a
 * complete backup, which is the one request that must never need ceremony.
 */
function parseScope(raw: unknown): ExportScopeDto {
  const body = (raw ?? {}) as Record<string, unknown>;
  const mode: ExportMode = EXPORT_MODES.includes(body.mode as ExportMode)
    ? (body.mode as ExportMode)
    : 'all';

  const ids = strings(body.ids);
  if (mode === 'ids') {
    if (ids.length > MAX_EXPORT_IDS) {
      throw new BadRequestException(`at most ${MAX_EXPORT_IDS} ids per export`);
    }
    if (ids.some((id) => !UUID_RE.test(id))) {
      throw new BadRequestException('ids must all be uuids');
    }
  }

  // The app id becomes the filename prefix, and the filename is what a future
  // re-import reads app identity from — so a malformed one is rejected rather
  // than silently producing an unattributable backup.
  const targetApp =
    typeof body.targetApp === 'string'
      ? body.targetApp.trim().toLowerCase()
      : '';
  if (targetApp && !BACKUP_APP_ID_RE.test(targetApp)) {
    throw new BadRequestException(
      `"${targetApp}" is not a valid application id`,
    );
  }

  return {
    mode,
    filter: parseFilter(body.filter),
    ids,
    include: parseInclude(body.include),
    targetApp,
  };
}

/**
 * Creating `.tachibk` backups from the vault.
 *
 * Files are built per request and streamed straight back — nothing is stored
 * server-side, so there is no export history to prune and no stale copy that
 * could outlive a deleted title.
 */
@Controller('exports')
export class ExportController {
  constructor(private readonly exports: ExportService) {}

  /** Selectable values with live title counts, for the scope builder. */
  @Get('facets')
  facets(): Promise<ExportFacetsDto> {
    return this.exports.facets();
  }

  /** What a scope would produce — counts, filename and size — without building it. */
  @Post('preview')
  @HttpCode(200)
  preview(@Body() body: unknown): Promise<ExportPreviewDto> {
    return this.exports.preview(parseScope(body));
  }

  /**
   * Build and stream the backup.
   *
   * `POST` because the scope is a body, not a URL — a filter with hundreds of
   * hand-picked ids has no business in a query string. The counts are echoed in
   * `X-Export-*` headers so the client can report what it received without a
   * second round trip.
   */
  @Post('build')
  @HttpCode(200)
  @Header('Content-Type', 'application/gzip')
  @Header('Cache-Control', 'no-store')
  async build(@Body() body: unknown, @Res() res: Response): Promise<void> {
    const { fileName, bytes, titles } = await this.exports.build(
      parseScope(body),
    );
    res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
    res.setHeader('Content-Length', bytes.byteLength);
    res.setHeader('X-Export-File-Name', fileName);
    res.setHeader('X-Export-Titles', String(titles));
    // Exposed explicitly: without this a browser client can read neither the
    // filename nor the counts off a cross-origin response.
    res.setHeader(
      'Access-Control-Expose-Headers',
      'Content-Disposition, Content-Length, X-Export-File-Name, X-Export-Titles',
    );
    res.end(Buffer.from(bytes));
  }
}
