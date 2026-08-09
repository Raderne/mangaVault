# App — MangaVault client (Flutter)

Guidance for work under `app/`. See the repo root `CLAUDE.md` for project-wide rules.

## Design conventions

- Dark-only "Minimalist Slate" theme; build the Flutter `ThemeData`/`ColorScheme` from the exact
  tokens in `App design/minimalist_slate/DESIGN.md` (surface tiers for bento cells, 24px cell
  radius, 12px cover radius, pill buttons, Inter everywhere, uppercase micro-labels).
  That file is the source of truth for all UI work.
- **Bento cells carry a "Manga Neon" accent** (`lib/theme/app_accents.dart` — `VaultAccent`
  violet/cyan/amber/emerald/rose). Pass `accent:` to `BentoCell` and it gets a 12% diagonal wash
  plus a tinted border; the same enum feeds `AccentIconWell`, `NestedWell`, `StatusChip`,
  `PillButton`, `GlowProgressBar` and `ProgressRing`. Surfaces themselves never change. Rules
  (hue per cell, no adjacent repeats, rose = alerts only) are in DESIGN.md; contrast is pinned by
  `test/app_accents_test.dart` — add a hue there and it must clear 4.5:1 or the suite fails.
- **A cell never resizes because of its own live content.** Streamed content renders into a
  fixed-height well sized from the *text scale*; overflow vanishes rather than pushing the layout.
  The reference implementation is `features/backups/import_ticker.dart` (four slots, dimming by
  depth, the stream sampled at ~7/sec). See DESIGN.md §Motion.
- Layout is a bento grid; on the phone, cells stack in a single column (mockups' mobile rule),
  16px gutters, ≥24px cell padding. The four `code.html` mockups are the visual reference —
  match them, but rebuild as Flutter widgets; don't mimic the HTML structure.
- Library views must stay smooth at 1,000+ titles: paginate/lazy-load from the API and use
  builder-based lists/grids.
- **Picking or saving a file goes through MangaVault's own browser**, not a platform dialog:
  `features/files/file_browser_route.dart` (`openFileBrowser` / `openSaveBrowser`). It needs
  all-files access; the `file_picker` dialogs remain only as the fallback when that is denied.
  Filesystem work goes through `VaultFileSystem` (`core/files/`) so it stays testable, and always
  with `p.posix`, never bare `p`. See `wiki-brain-vault/wiki/file-selector.md`.

## Structure notes

- `lib/theme/` holds the Minimalist Slate tokens; shared widgets (BentoCell, MangaCard, …) live
  in `lib/widgets/`; screens are grouped under `lib/features/<screen>/`.
- Routing is go_router with a `StatefulShellRoute` over 4 tabs; state is Riverpod.
