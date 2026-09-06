# LexPDF Architecture

## Product model

LexPDF is an offline-first, multiplatform PDF and digital notebook workspace.

### Primary workspaces

1. PDF Workspace
   - render, search, navigate, annotate and edit PDFs
   - highlight, underline, strikeout
   - comments, bookmarks, page operations
   - OCR, printing and export

2. Notes Workspace
   - vector ink engine
   - pen, pencil, highlighter, eraser and lasso
   - stylus pressure, tilt, hover and palm rejection when supported
   - notebooks, templates, layers and infinite canvas

## High-level architecture

```text
Flutter UI
  |
Application Core
  |-- Document Core
  |-- PDF Reader / Editor
  |-- Annotation Engine
  |-- Ink Engine
  |-- Notebook Engine
  |-- OCR
  |-- Search
  |-- Printing
  |-- Backup / Restore
  |-- Sync Engine
  |-- Cloud Providers
  |
SQLite + Local File Storage
  |
Optional cloud layer
  |-- Google Drive
  |-- OneDrive
  |-- Apple File Provider / iCloud
  |-- Supabase
  `-- Cloudflare Workers / R2
```

## Offline-first rules

- The user must be able to open, edit, annotate, save, search, print and back up local documents without Internet.
- Cloud documents are cached locally before editing.
- Local save completes before sync begins.
- Sync failure never blocks local editing.
- Conflicts are explicit and recoverable.
- Original files are protected with working copies and atomic replacement.

## Data layers

### Local
- SQLite: metadata, library, annotations, reading state, notebooks, sync queue, backup metadata.
- Filesystem: PDFs, notebook assets, thumbnails, OCR artifacts and local backups.
- Secure storage: OAuth and session credentials.

### Supabase
- Auth
- PostgreSQL metadata
- RLS policies
- synchronized user metadata
- device state and preferences

### Cloudflare
- Workers API gateway
- R2 object storage
- Queues for asynchronous workloads
- WAF / rate limiting / DNS as needed

## Provider abstraction

All remote and local sources implement a common document-provider contract:

- list
- open/read
- write
- download
- upload
- rename
- move
- delete
- metadata
- version

Initial providers:
- local
- Google Drive
- OneDrive
- Apple File Provider
- Cloudflare R2

## Security baseline

- no private secrets committed to Git
- RLS enabled for user-owned data
- least-privilege OAuth scopes
- short-lived signed URLs for object access
- local credential storage via platform keystores
- backup validation before rotation
- checksum-based integrity verification

## Initial milestones

1. Foundation and local storage
2. PDF reader
3. Text selection + highlight/underline/strikeout
4. Vector ink + stylus
5. Notebooks and canvas
6. PDF editing and page tools
7. OCR and search
8. Printing
9. Cloud providers and sync
10. Backup / restore and Squid migration
11. Supabase / Cloudflare integration
12. Optional AI
