# App — MangaVault client (Flutter)

Guidance for work under `app/`. See the repo root `CLAUDE.md` for project-wide rules.

## Design conventions

- Dark-only "Minimalist Slate" theme; build the Flutter `ThemeData`/`ColorScheme` from the exact
  tokens in `App design/minimalist_slate/DESIGN.md` (surface tiers for bento cells, 24px cell
  radius, 12px cover radius, pill buttons, Inter everywhere, uppercase micro-labels).
  That file is the source of truth for all UI work.
- Layout is a bento grid; on the phone, cells stack in a single column (mockups' mobile rule),
  16px gutters, ≥24px cell padding. The four `code.html` mockups are the visual reference —
  match them, but rebuild as Flutter widgets; don't mimic the HTML structure.
- Library views must stay smooth at 1,000+ titles: paginate/lazy-load from the API and use
  builder-based lists/grids.

## Structure notes

- `lib/theme/` holds the Minimalist Slate tokens; shared widgets (BentoCell, MangaCard, …) live
  in `lib/widgets/`; screens are grouped under `lib/features/<screen>/`.
- Routing is go_router with a `StatefulShellRoute` over 4 tabs; state is Riverpod.
