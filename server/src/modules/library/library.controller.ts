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
import {
  LIBRARY_SORT_FIELDS,
  PUBLICATION_STATUSES,
  type CategoryDto,
  type DeleteTitlesResultDto,
  type LibraryPageDto,
  type LibraryQueryDto,
  type LibrarySortField,
  type VaultMangaDto,
} from './library.dto';
import { LibraryService } from './library.service';

const DEFAULT_LIMIT = 40;
const MAX_LIMIT = 100;

/** Ceiling on one bulk delete; clients chunk larger selections. */
const MAX_DELETE_IDS = 1000;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  constructor(private readonly library: LibraryService) {}

  @Get('library')
  list(@Query() query: Record<string, string>): Promise<LibraryPageDto> {
    return this.library.query(parseLibraryQuery(query));
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
  removeMany(
    @Body() body: { ids?: unknown },
  ): Promise<DeleteTitlesResultDto> {
    const raw = Array.isArray(body?.ids) ? body.ids : null;
    if (!raw || raw.length === 0) {
      throw new BadRequestException('ids must be a non-empty array');
    }
    if (raw.length > MAX_DELETE_IDS) {
      throw new BadRequestException(
        `at most ${MAX_DELETE_IDS} ids per request`,
      );
    }
    // Validated here, not by Postgres: a single malformed value would fail the
    // whole ::uuid[] cast with an opaque 500.
    const ids = raw.filter(
      (v): v is string => typeof v === 'string' && UUID_RE.test(v),
    );
    if (ids.length !== raw.length) {
      throw new BadRequestException('ids must all be uuids');
    }
    return this.library.deleteMany(ids);
  }

  @Get('categories')
  categories(): Promise<CategoryDto[]> {
    return this.library.listCategories();
  }
}
