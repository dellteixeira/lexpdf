# Supabase backend

This directory will contain reproducible Supabase infrastructure for LexPDF.

Planned contents:

- `migrations/` — schema, indexes, triggers, grants and RLS policies
- `functions/` — authenticated Edge Functions when required
- `seed/` — non-sensitive development seed data

## Security rules

- RLS enabled for all user-owned tables.
- New public tables are not automatically exposed without explicit grants.
- No service-role keys, database passwords or private tokens are stored in Git.
- App clients use publishable credentials only.

## Planned tables

- profiles
- documents
- folders
- notebooks
- notebook_pages
- annotations
- ink_strokes
- bookmarks
- reading_progress
- device_state
- cloud_accounts_metadata
- sync_metadata
- sync_conflicts
- backup_history

The authoritative schema will be added as versioned migrations after the dedicated LexPDF Supabase project is created.
