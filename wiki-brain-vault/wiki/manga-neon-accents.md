# Manga Neon accents

Created: 2026-08-09

Related: [[index]] · [[flutter-app]] · [[dashboard-stats]] · [[backup-apps]]

The five-hue accent layer over the Minimalist Slate theme, added so the bento grid on the Dashboard
and Backups screens reads as compartments rather than one grey sheet.

## Why it exists

The design tokens in `App design/minimalist_slate/DESIGN.md` are near-monochrome, and — the detail
that actually caused the flatness — **`secondary` and `tertiary` carry the same hex** (`#c2c1ff`).
So the entire app had exactly *one* accent hue. That already forced a workaround before this change:
`_HealthRow` had to reach for `onTertiaryContainer` to make "Aging" look different from "Fresh".

A bento layout's whole premise is that each cell is its own compartment. With one hue, nothing
distinguished them.

## The system

`app/lib/theme/app_accents.dart`:

```dart
enum VaultAccent { violet, cyan, amber, emerald, rose }   // .color + .wash
abstract final class AccentAlpha { wash=0.12, border=0.28, fill=0.16, glow=0.45 }
LinearGradient accentWash(VaultAccent)   // top-left → transparent, 3 stops
```

**Two colors per accent, and this is the load-bearing decision.** `.color` is the foreground
(figures, icons, dots, arcs, CTAs), lightened until it clears WCAG AA against the worst surface it
can land on — a `surfaceContainerHigh` cell *already carrying its own 12% wash*. `.wash` is the
saturated form, used only at low alpha for the tint. One color can't do both jobs: a 12% veil of the
light foreground reads grey, not coloured. Violet needed `#8b7cff → #a79cff` and rose
`#ff6b8a → #ff7e99` specifically to survive the washed-high case (3.73:1 and 4.43:1 before).

| Accent | `.color` | `.wash` | Carries |
| --- | --- | --- | --- |
| violet | `#a79cff` | `#6d5bf0` | Titles, archive hero, import (way in), backup-health cell |
| cyan | `#4cc9e8` | `#14a5c7` | Chapters, merges, in-flight work, recently added |
| amber | `#f5a524` | `#e08700` | Covers, storage, history, needs-attention |
| emerald | `#35d0a5` | `#12a87f` | Reading progress, fresh, success, export (way out) |
| rose | `#ff7e99` | `#f0426a` | Stale, cancelled, failed |

## Rules

- **Surfaces never change.** The slate ladder (`BentoTone.low/mid/high`) is untouched; the accent is
  a veil over it. That's what keeps cover art dominant, which is the point of the dark theme.
- Diagonal gradient, never a flat fill — at 12% a flat fill just looks like a slightly wrong surface
  color; the fade reads as light falling on the cell.
- One hue per cell; **no two vertically adjacent cells share a hue** (cells stack in one column on
  the phone, so adjacency is the only thing that matters).
- **Rose is reserved for genuine alerts.** Backup health takes violet, not rose, because its *rows*
  carry the verdict — a rose cell would shout "problem" even when every source is fresh.
- Body/muted text stays `onSurface` / `onSurfaceVariant`. Only figures, icons, indicators and CTAs
  take a hue.

## Widget plumbing

`accent:` is optional everywhere and **null reproduces the old rendering exactly**, so nothing
outside the two target screens moved:

- `BentoCell` — uses **`Ink`**, not a `DecoratedBox`. Ink paints its decoration onto the Material
  itself so the `InkWell` splash still lands *above* the wash; a DecoratedBox between the two
  swallows every ripple.
- `AccentIconWell` / `NestedWell` — accent fill + border, else the original `primaryContainer`.
- `StatusChip` — accent ranks **below** `selected` (a chip the user chose must still read as chosen)
  and above `emphasized`. Accented chips get a hairline, since a translucent fill needs it to hold
  shape against a cell washed in a different hue.
- `PillButton` — solid accent fill with `foregroundColor: scheme.surface` (near-black), not white;
  that's what stops a saturated pill glaring on a dark screen. `styleFrom` merges with
  `filledButtonTheme`, so the stadium shape/padding/text style survive.
- `GlowProgressBar` / `ProgressRing` — accent fill plus bloom. The ring draws a blurred underlay arc
  first (`MaskFilter.blur`) so the crisp arc sits on its own glow.

## Where each hue landed

**Dashboard** (top → bottom): hero violet · chapters cyan + covers amber (rose if any cover failed) ·
reading progress emerald · backup health violet · resume shelf emerald · recently added cyan · vault
amber. The vault's storage bar segments deliberately match the cells those bytes belong to (covers
amber, database cyan, backups violet) so the bar reads as a legend for the screen.

Status semantics gained real hues now that there are five: health rows are a true traffic light
(fresh emerald / aging amber / stale rose), and the status mix is ongoing emerald / completed cyan /
hiatus amber / cancelled rose.

**Backups**: import CTA violet · export CTA emerald (paired opposites — different hues is what makes
the pairing read) · staging/review/committing cyan · needs-app amber · done emerald · failed rose ·
history amber. Outcome badges share hues with the review chips that filter to them
(`_actionAccent`): NEW emerald, MERGED cyan, SKIPPED amber.

## Testing

`app/test/app_accents_test.dart` asserts contrast rather than trusting the eye:

- every accent as foreground on **its own washed surface**, across all three tones, ≥ 4.5:1
- `onSurface` and `onSurfaceVariant` on every washed surface ≥ 4.5:1 (this is what bounds
  `AccentAlpha.wash` — raise it and this test is what fails)
- the five hues are not near-identical to each other
- `BentoCell` paints a gradient + tinted border with an accent, and nothing without one

Worst ratio in the whole matrix is **5.30:1**. Adding a sixth hue means passing these or lightening
it until it does.

## Not touched

Library grid, Title Details, filter sheet and the bottom nav still render from the base scheme — the
accent enum is available to them whenever that's wanted.
