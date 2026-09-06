# Roadmap

## Phase 1 — Foundation
- Flutter shell for Android, Windows and macOS
- local filesystem abstraction
- SQLite schema
- app settings and secure credential storage abstraction

## Phase 2 — PDF Reader
- local PDF open/render
- thumbnails
- zoom and navigation
- text search and selection
- reading progress persistence

## Phase 3 — Text annotations
- highlight with color and opacity
- underline
- strikeout
- comments and annotation panel
- PDF-compatible persistence where supported

## Phase 4 — Vector Ink / Stylus
- pen, pencil, highlighter
- vector strokes
- pressure/tilt/hover capability detection
- palm rejection strategy
- eraser modes
- lasso, transform and copy/paste

## Phase 5 — Digital notebooks
- notebooks/pages
- paper templates
- layers
- infinite canvas
- shapes, ruler and image insertion

## Phase 6 — PDF editing
- text/image insertion
- page add/delete/reorder/rotate/extract
- merge/split
- safe save and crash recovery

## Phase 7 — OCR / Search
- local OCR
- searchable PDF layer
- SQLite FTS5 global library search

## Phase 8 — Printing
- Android print framework
- Windows printing
- macOS printing/AirPrint-compatible system flow
- print annotations and selected ranges

## Phase 9 — Cloud providers
- Google Drive
- OneDrive
- Apple File Provider / iCloud
- offline availability cache

## Phase 10 — Sync
- sync queue
- retry policy
- checksums and revisions
- conflict resolution

## Phase 11 — Backup / Migration
- .lexnote
- .lexbackup
- validation and restore
- Squid import pipeline with safe fallback

## Phase 12 — Backend
- Supabase Auth/Postgres/RLS
- Cloudflare Workers/R2/Queues

## Phase 13 — AI (optional)
- selected-text actions
- summaries
- flashcards
- questions
- future local model support

## First acceptance milestone
A 500+ page PDF must open, scroll smoothly, support text selection, highlight/underline/strikeout and stylus ink, save locally, close and reopen with all annotations intact.
