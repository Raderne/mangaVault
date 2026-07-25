import {
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Query,
} from '@nestjs/common';

import type { PublicationStatus } from '../../entities/manga.entity';
import {
  LIBRARY_SORT_FIELDS,
  PUBLICATION_STATUSES,
  type CategoryDto,
  type LibraryPageDto,
  type LibraryQueryDto,
  type LibrarySortField,
  type VaultMangaDto,
} from './library.dto';
import { LibraryService } from './library.service';

const DEFAULT_LIMIT = 40;
const MAX_LIMIT = 100;

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

  return {
    text: raw.text?.trim() || undefined,
    status,
    categoryIds: csv(raw.categoryIds),
    sourceIds: csv(raw.sourceIds),
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

  @Get('categories')
  categories(): Promise<CategoryDto[]> {
    return this.library.listCategories();
  }
}
