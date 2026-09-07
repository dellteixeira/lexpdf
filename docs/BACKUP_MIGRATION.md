# Phase 11 — Backup / Migration

## Scope

Phase 11 completes LexPDF data portability and safe migration while preserving the offline-first model.

### `.lexbackup`

- ZIP container with `manifest.json`, `database.json` and bundled offline PDFs.
- SHA-256 validation for the database snapshot and each bundled document.
- Schema compatibility checks before restore.
- Archive-path validation to reject traversal/duplicate paths.
- Transactional database replacement with foreign-key verification.
- Bundled PDFs are restored to collision-resistant names; files created by a failed restore are cleaned up.
- SQLite BLOB values are encoded in JSON and decoded on restore.

### `.lexnote`

- Portable editable notebook format.
- Version 2 envelope includes SHA-256 checksum around a base64 payload.
- Exports notebook metadata, pages, vector strokes, notebook objects, layers and layer items.
- Validator checks format/version and cross-references before import.
- Import creates a new notebook with remapped IDs so the source notebook is never overwritten.
- Legacy version 1 payloads remain importable; missing layers receive a safe default layer.

### Squid migration

- A PDF selected directly is copied as a flattened import.
- ZIP/Squid-like containers are inspected only for embedded PDFs.
- Proprietary Squid layers are never guessed or mutated.
- Duplicate filenames receive unique destination names instead of overwriting existing files.
- Unsupported/corrupt containers fail without modifying the source.
- Partial destination files are removed if an import operation fails.

## Acceptance criteria

1. A generated `.lexbackup` validates before it can be restored.
2. Corrupted backups are rejected before database mutation.
3. Backup restore reproduces database state and bundled offline PDF content.
4. A generated `.lexnote` validates and round-trips into a new editable notebook.
5. `.lexnote` import preserves page/object/stroke/layer relationships and passes SQLite foreign-key checks.
6. Corrupted `.lexnote` data is rejected before import.
7. Squid fallback imports only safely recognizable PDFs and preserves the source container.
8. Duplicate imported filenames do not overwrite one another.
9. `flutter analyze` and `flutter test` pass in CI.
