# Library API (M3)

Created: 2026-07-25

Related: [[index]] · [[backend]] · [[flutter-app]] · [[import-pipeline]] · [[database]]

The read side of the archive: browse the imported library and open a title. Backs the
`library_archive` and `title_details` mockups. Endpoints under `/api/v1`, bearer-guarded like the
rest.

## Server — `server/src/modules/library/`

```
library.dto.ts        # LibraryQueryDto, MangaListItemDto, LibraryPageDto,
                      # VaultMangaDto, CategoryDto, ChapterRefDto, ArchiveEntryDto …
library.service.ts    # LibraryService: query / get / listCategories
library.controller.ts # GET /library, GET /library/:id, GET /categories
library.module.ts     # TypeOrmModule.forFeature(ALL_ENTITIES)
```

Registered in `app.module.ts`. Read-only in M3 — mutations from the interface spec
(`updateNotes`, `setCategories`, `remove`) are deferred (the mockups are display-only).

### Endpoints

| Endpoint | Returns |
|---|---|
| `GET /library?…` | `LibraryPageDto { items: MangaListItemDto[]; total; offset; limit }` |
| `GET /library/:id` | `VaultMangaDto` (full record + progress + archive history), 404 if unknown, 400 if id not a uuid |
| `GET /categories` | `CategoryDto[]` (id, name, sort, **count** of titles) |

### `GET /library` query params (parsed in the controller, all optional)

- `text` — FTS: `search_tsv @@ plainto_tsquery('simple', …)` **OR** `title ILIKE %text%` (trigram).
- `status` — CSV of `PublicationStatus`; invalid values dropped.
- `categoryIds` — CSV of uuids (`EXISTS` against `manga_category`, cast `::uuid[]`).
- `sourceIds` — CSV of decimal source-id strings.
- `favorite` — `true` / `false` (also accepts `1`/`0`); when set, `m.favorite = …`.
  Omitted → no favorite filter (whole library).
- `sortBy` ∈ `title | dateAdded | lastReadAt | chapterCount | unreadCount` (default `title`);
  `sortDir` ∈ `asc | desc` (default: `asc` for title, `desc` otherwise).
- `offset` (≥0), `limit` (1..**100**, default **40**).

### Query design (gotchas)

- **One grouped chapter aggregate, joined back per title** — a `LEFT JOIN (SELECT manga_id,
  COUNT(*) chapter_count, COUNT(*) FILTER (WHERE NOT read) unread_count, MAX(last_read_at)
  last_read_at FROM chapter GROUP BY manga_id)` gives chapter/unread counts + last-read for both
  display **and** sorting without an N+1. Fine at the current scale (≈124k chapter rows).
- Computed columns are sorted by their **output aliases** (`chapter_count`, `unread_count`,
  `last_read_at`); `title`/`date_added` sort by the qualified input column. `NULLS LAST` +
  `m.id ASC` tiebreaker for a stable order.
- `total` is a separate `COUNT(*)` with the same `WHERE` (no aggregate join needed).
- **int64 discipline:** `last_read_at`/`date_added` are BIGINT → arrive as **strings** from raw
  `dataSource.query`; converted with `Number(...)` in the mapper. Source ids stay strings.
- Raw SQL is typed via `dataSource.query<Row[]>(…)` so ESLint's no-unsafe rules pass.
- `get()` uses the TypeORM repo (`relations: categories/tracking/imports`) for the entity, then 3
  small chapter queries for `{total, readCount, lastReadAt}`, the most-recently-read chapter
  (`ORDER BY last_read_at DESC`), and the next unread (`ORDER BY chapter_number ASC NULLS LAST`).
- **Favorite filter** — optional `favorite=true|false` on `GET /library`. The Flutter grid defaults
  to `favorite=true` (library favorites); tapping the star pill next to sort flips to non-favorites.

### Tests — `test/library.e2e-spec.ts` (Postgres 5433)

Seeds a run-unique source's titles/chapters/category/import **via SQL** (deterministic even against
the real 1.2k-title DB) and scopes every assertion by `sourceIds`. Covers pagination, status filter,
FTS, favorite filter, sort-by-chapter-count, `get` (progress + archive), 404/400, categories, 401.
10 tests.

## Flutter — `app/lib/data/library/` + `app/lib/features/library` + `title_details`

```
data/library/library_models.dart      # MangaListItem, LibraryPage, VaultManga, Category,
                                       # CategoryRef, ChapterRef, ArchiveEntry (manual fromJson)
data/library/library_repository.dart   # query / get / categories; static coverUrl()
features/library/library_controller.dart  # NotifierProvider<LibraryController, LibraryState>
                                       # + categoriesProvider + mangaDetailsProvider.family
features/library/library_screen.dart   # ConsumerStatefulWidget: filter bar, sort sheet, search,
                                       # infinite-scroll CustomScrollView + SliverGrid
features/title_details/title_details_screen.dart  # stacked bento cells from mangaDetailsProvider
```

- **Paging:** `LibraryController` holds `LibraryState {items,total,filters,status,loadingMore}`.
  `build()` schedules the first `refresh()`; a scroll listener calls `loadMore()` ~600px before the
  end (page size 40). Filter/sort/search/favorite setters reset to page 0. A stale-response guard
  drops a page whose filters changed while it was in flight. `LibraryFilters.favorite` defaults to
  `true`; the sort-row star pill toggles it.
- **coverUrl** returns `null` until `coverState == 'archived'` (covers are **M4**) → cells render a
  placeholder. The URL shape is `${baseUrl}/api/v1/covers/:id` for when M4 lands.
- **Details** button "Continue reading" is informational (SnackBar) — no in-app reader in v1.
- Metadata cell adapts the mockup's "Release Year" (not in our data) → **Source** instead.

## Animation language (M3) — see [[flutter-app]] §Animations

`EntranceFade` (staggered fade+slide, `Cubic(0.22,1,0.36,1)`, reduce-motion aware), `Pressable`
press-scale, a shared-element **Hero** on the cover (`manga-cover-<id>`) grid→details, an animated
`GlowProgressBar`, and a fade route transition for the details page.
