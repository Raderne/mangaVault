# Project Brief: Manga & Manhwa Library Archive

## Project Overview
A centralized archival platform designed to aggregate, store, and manage library backups from various reading applications (e.g., Tachiyomi, Mihon). The app serves as a "fail-safe" for readers, ensuring that curated collections, reading progress, and metadata are preserved regardless of the status of individual source apps.

## Design Vision
- **Theme:** "Minimalist Slate" – A premium, professional dark aesthetic.
- **Color Palette:** 
  - Background: Deep slate/navy (#1a1e2e).
  - Typography: Premium off-white for high legibility.
  - Accents: Muted variations of the background and subtle contrasting dark tones for container depth.
- **Layout Strategy:** **Bento Box Layout**. Modular, grid-based compartments that organize complex data into visually distinct, scannable "cells."

## Core Features & User Stories
- **Multi-Source Import:** Users can upload `.json` or `.tachibk` backup files from various sources to a unified archive.
- **Consolidated Dashboard:** A high-level overview of total library size, backup health (stability), and recently added titles.
- **Library Management:** A searchable, sortable archive of all titles with metadata (Author, Status, Source Attribution).
- **Granular Record Keeping:** Detailed title views featuring synopsis, chapter logs, and reading progress history.
- **Storage Monitoring:** Visual tracking of metadata capacity and local/cloud storage usage.

## Screen Architecture
1. **Archive Dashboard (Home):** The primary hub featuring bento cells for library statistics, backup health monitoring, and quick-access "Resume Reading" actions.
2. **Library Archive:** A comprehensive grid view of the entire collection with category filtering (All Titles, Ongoing, Completed).
3. **Title Details:** A granular, modular view for individual titles, grouping synopsis, metadata, archive history, and reading progress.
4. **Backup & Sources:** The technical management hub for file imports, cloud synchronization settings, and integration status for external apps.

## Technical Goals
- **Consistency:** Maintain a unified visual language across all modules.
- **Scalability:** Ensure the bento grid remains legible even with libraries exceeding 1,000+ titles.
- **Fidelity:** Precise representation of source metadata while providing a superior, "archival-grade" UI.
