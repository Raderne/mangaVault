---
name: Minimalist Slate
colors:
  surface: '#111415'
  surface-dim: '#111415'
  surface-bright: '#37393b'
  surface-container-lowest: '#0c0f10'
  surface-container-low: '#191c1e'
  surface-container: '#1d2022'
  surface-container-high: '#282a2c'
  surface-container-highest: '#323537'
  on-surface: '#e1e2e4'
  on-surface-variant: '#c7c6cd'
  inverse-surface: '#e1e2e4'
  inverse-on-surface: '#2e3132'
  outline: '#909097'
  outline-variant: '#46464c'
  surface-tint: '#c2c5db'
  primary: '#c2c5db'
  on-primary: '#2c3040'
  primary-container: '#1a1e2e'
  on-primary-container: '#828599'
  inverse-primary: '#5a5d70'
  secondary: '#c2c1ff'
  on-secondary: '#1800a7'
  secondary-container: '#3630bf'
  on-secondary-container: '#b1b1ff'
  tertiary: '#c2c1ff'
  on-tertiary: '#272475'
  tertiary-container: '#140d64'
  on-tertiary-container: '#7f7ed2'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#dee1f8'
  primary-fixed-dim: '#c2c5db'
  on-primary-fixed: '#171b2b'
  on-primary-fixed-variant: '#424658'
  secondary-fixed: '#e2dfff'
  secondary-fixed-dim: '#c2c1ff'
  on-secondary-fixed: '#0c006b'
  on-secondary-fixed-variant: '#332dbc'
  tertiary-fixed: '#e2dfff'
  tertiary-fixed-dim: '#c2c1ff'
  on-tertiary-fixed: '#100761'
  on-tertiary-fixed-variant: '#3e3d8c'
  background: '#111415'
  on-background: '#e1e2e4'
  surface-variant: '#323537'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  container-padding: 24px
  gutter: 16px
  module-padding: 20px
  radius-lg: 24px
  radius-xl: 32px
---

## Brand & Style

The design system is engineered for a premium Manga and Manhwa library backup experience, prioritizing organizational clarity and visual immersion. The brand personality is disciplined, sophisticated, and archival. It targets power users who value their digital collections as a curated gallery rather than a chaotic feed.

The design style is a refined **Bento-box Minimalism**. It utilizes modularity to compartmentalize metadata, reading progress, and cover art into distinct, high-clarity containers. This approach minimizes cognitive load by grouping related information into "cells," creating an interface that feels structured, permanent, and tactile. The emotional response is one of calm control and professional-grade reliability.

## Colors

The palette is anchored in a deep **Dark Slate** (#1a1e2e), providing a high-contrast foundation for vibrant manga cover art. The secondary and tertiary colors are low-saturation indigos and purples, used sparingly for interactive states and status indicators to avoid distracting from the content.

- **Primary Background:** The base layer is a solid slate.
- **Surface Tiers:** Three levels of grey-blue surfaces (`surface-low`, `surface-medium`, `surface-high`) are used to create the Bento cells, with higher elevation surfaces receiving lighter hex values.
- **Accents:** Low-saturation blues are reserved for progress bars, primary buttons, and active toggle states.
- **Text:** An off-white (#f8f9fb) is used for primary text to reduce eye strain compared to pure white, while mid-tones are used for secondary metadata.

## Typography

This design system utilizes **Inter** exclusively to maintain a systematic, utilitarian aesthetic that feels contemporary and neutral. The typography focuses on a clear hierarchy to handle dense metadata (author names, chapter counts, genres).

- **Headlines:** Use tighter letter spacing and heavier weights to anchor the Bento modules.
- **Labels:** Use uppercase for small metadata labels (e.g., "STATUS: COMPLETED") to distinguish them from body text.
- **Reading Comfort:** Body text uses a generous line height (1.5x) to ensure legibility when reading long synopses or changelogs.

## Layout & Spacing

The layout follows a **Fluid Bento Grid** model. Content is organized into modular "cells" that adapt to the screen width while maintaining consistent internal padding.

- **The Bento Grid:** On desktop, a 12-column grid is used. Cells should span 3, 4, 6, or 12 columns. On mobile, cells stack vertically into a single column.
- **Module Spacing:** Every Bento cell has a minimum internal padding of `24px` (`container-padding`) to ensure the content within feels premium and uncrowded.
- **Gutters:** A consistent `16px` gap exists between all modules, creating a clear visual rhythm.
- **Alignment:** All elements within a module must align to the top-left or be centered vertically, never floating haphazardly.

## Elevation & Depth

Hierarchy is established through **Tonal Layering** and **Soft Shadows**, rather than heavy gradients.

1.  **Base Layer:** The darkest slate background (#1a1e2e).
2.  **Module Layer:** Surfaces (#24293d) with a 1px stroke (#353c5a) to define edges.
3.  **Interaction Layer:** When a cell or button is hovered, it moves to a lighter surface tone and gains a soft, diffused ambient shadow (Color: #000000, Alpha: 0.3, Blur: 20px).
4.  **Glassmorphism:** Navigation bars and modal overlays use a background blur (20px) with a semi-transparent version of the surface color to maintain context of the library behind them.

## Shapes

The shape language is defined by oversized, generous curves that soften the "technical" feel of a backup app.

- **Primary Modules:** Use a `24px` (radius-lg) corner radius.
- **Images/Covers:** Manga covers within modules should use a slightly smaller `12px` radius to sit harmoniously within the parent container.
- **Buttons:** Use a `radius-xl` (32px) or full pill shape to provide a distinct contrast against the rectangular grid of the Bento layout.

## Components

- **Bento Cells:** The core component. Includes a background, border, and internal padding. These can contain "Mini-stats" (e.g., Total Volumes) or "Gallery Views."
- **Primary Buttons:** High-saturation indigo backgrounds with off-white text. No border, pill-shaped.
- **Progress Bars:** Thin, 4px height tracks with a subtle glow effect on the filled portion to indicate reading progress.
- **Status Chips:** Small, low-contrast capsules used for genres or tags. Backgrounds are only 10% more saturated than the surface they sit on.
- **Inputs:** Darker than the surface layer, with a 1px focus border in the accent indigo.
- **Manga Cards:** Vertical containers with a fixed aspect ratio for the cover art, featuring an overlay for the chapter count in the bottom-right corner.