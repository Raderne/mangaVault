import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';

import type { PublicationStatus } from '../../entities/manga.entity';
import { DeletedTitlesService } from './deleted-titles.service';
import {
  LIBRARY_SORT_FIELDS,
  PUBLICATION_STATUSES,
  type CategoryDto,
  type DeletedTitlesPageDto,
  type DeleteTitlesResultDto,
  type LibraryPageDto,
  type LibraryQueryDto,
  type LibrarySortField,
  type RestoreResultDto,
  type VaultMangaDto,
} from './library.dto';
import { LibraryService } from './library.service';

const DEFAULT_LIMIT = 40;
const MAX_LIMIT = 100;

/** Ceiling on one bulk delete; clients chunk larger selections. */
const MAX_DELETE_IDS = 1000;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Validate a `{ ids: [...] }` body into a uuid list.
 *
 * Validated here rather than left to Postgres: one malformed value would fail
 * the whole `::uuid[]` cast (or an `In([...])`) with an opaque 500.
 */
function parseIdList(raw: unknown): string[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new BadRequestException('ids must be a non-empty array');
  }
  if (raw.length > MAX_DELETE_IDS) {
    throw new BadRequestException(`at most ${MAX_DELETE_IDS} ids per request`);
  }
  const ids = raw.filter(
    (v): v is string => typeof v === 'string' && UUID_RE.test(v),
  );
  if (ids.length !== raw.length) {
    throw new BadRequestException('ids must all be uuids');
  }
  return ids;
}

const csv = (value?: string): string[] =>
  value
    ? value
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
    : [];

const clamp = (n: number, lo: number, hi: number): number =>
  Math.min(hi, Math.max(lo, n));

/** Parse and validate the loosely-typed query string into a [LibraryQueryDto]. */
function parseLibraryQuery(raw: Record<string, string>): LibraryQueryDto {
  const status = csv(raw.status).filter((s): s is PublicationStatus =>
    PUBLICATION_STATUSES.includes(s as PublicationStatus),
  );
  const sortBy: LibrarySortField = LIBRARY_SORT_FIELDS.includes(
    raw.sortBy as LibrarySortField,
  )
    ? (raw.sortBy as LibrarySortField)
    : 'title';
  // Title reads best A→Z; every other field (dates, counts) reads best desc.
  const sortDir: 'asc' | 'desc' =
    raw.sortDir === 'asc' || raw.sortDir === 'desc'
      ? raw.sortDir
      : sortBy === 'title'
        ? 'asc'
        : 'desc';

  const limit = clamp(
    Number.parseInt(raw.limit, 10) || DEFAULT_LIMIT,
    1,
    MAX_LIMIT,
  );
  const offset = Math.max(0, Number.parseInt(raw.offset, 10) || 0);

  // Accept "true"/"false" (and "1"/"0"); anything else leaves the filter unset.
  const favoriteRaw = raw.favorite?.trim().toLowerCase();
  const favorite =
    favoriteRaw === 'true' || favoriteRaw === '1'
      ? true
      : favoriteRaw === 'false' || favoriteRaw === '0'
        ? false
        : undefined;

  return {
    text: raw.text?.trim() || undefined,
    status,
    categoryIds: csv(raw.categoryIds),
    sourceIds: csv(raw.sourceIds),
    favorite,
    sortBy,
    sortDir,
    offset,
    limit,
  };
}

@Controller()
export class LibraryController {
  constructor(
    private readonly library: LibraryService,
    private readonly deletedTitles: DeletedTitlesService,
  ) {}

  @Get('library')
  list(@Query() query: Record<string, string>): Promise<LibraryPageDto> {
    return this.library.query(parseLibraryQuery(query));
  }

  // ---- deletion registry (recycle bin / import block list) ----
  //
  // Declared **before** `library/:id`: Nest matches routes in declaration
  // order, so a later `library/deleted` would be swallowed by the uuid param
  // route and 400 on the ParseUUIDPipe.

  /**
   * Titles that were deleted and are therefore **skipped by every import**
   * until they're restored or purged from here.
   */
  @Get('library/deleted')
  deleted(): Promise<DeletedTitlesPageDto> {
    return this.deletedTitles.list();
  }

  /** Put deleted titles back (ids are *registry* ids, not old manga ids). */
  @Post('library/deleted/restore')
  @HttpCode(200)
  restore(@Body() body: { ids?: unknown }): Promise<RestoreResultDto> {
    return this.deletedTitles.restore(parseIdList(body?.ids));
  }

  /**
   * Drop registry entries without restoring. The titles stay gone, but they are
   * no longer blocked — a future backup import will add them again.
   */
  @Post('library/deleted/purge')
  @HttpCode(200)
  async purge(@Body() body: { ids?: unknown }): Promise<{ purged: number }> {
    return { purged: await this.deletedTitles.purge(parseIdList(body?.ids)) };
  }

  @Get('library/:id')
  async get(@Param('id', ParseUUIDPipe) id: string): Promise<VaultMangaDto> {
    const manga = await this.library.get(id);
    if (!manga) throw new NotFoundException(`manga ${id} not found`);
    return manga;
  }

  /** Permanently remove one title. 404 when it was already gone. */
  @Delete('library/:id')
  @HttpCode(204)
  async remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    const { deleted } = await this.library.deleteMany([id]);
    if (deleted === 0) throw new NotFoundException(`manga ${id} not found`);
  }

  /**
   * Bulk delete, for the grid's multi-select.
   *
   * A `POST` rather than `DELETE /library` with a body: request bodies on
   * DELETE are inconsistently supported across clients and proxies, and this
   * one carries a screenful of ids.
   *
   * Unknown ids are ignored rather than rejected — a selection can race a sync,
   * and the caller only cares that the titles are gone.
   */
  @Post('library/delete')
  @HttpCode(200)
  removeMany(@Body() body: { ids?: unknown }): Promise<DeleteTitlesResultDto> {
    return this.library.deleteMany(parseIdList(body?.ids));
  }

  @Get('categories')
  categories(): Promise<CategoryDto[]> {
    return this.library.listCategories();
  }
}
