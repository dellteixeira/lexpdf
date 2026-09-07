# Phase 12 — Backend

Phase 12 completes the remote backend foundation without changing the offline-first contract of LexPDF.

## Supabase

Supabase is responsible for authentication, user-owned metadata and backend audit persistence.

### Auth

- Flutter clients use the Supabase publishable key only.
- A database trigger creates `public.profiles` after a new `auth.users` row is inserted.
- The profile bootstrap function lives in the non-exposed `private` schema and is not executable by `public`, `anon` or `authenticated`.

### Postgres / RLS

- Every client-facing table has RLS enabled.
- `anon` has no table privileges for LexPDF user data.
- `authenticated` receives explicit CRUD grants; RLS still decides which rows are accessible.
- Existing owner policies restrict rows to `(select auth.uid())`.
- Restrictive Phase 12 policies additionally require referenced parent records to belong to the same authenticated user, preventing cross-user parent/child references.
- `backend_events` is server-only: RLS is enabled, app roles have no grants, and trusted backend infrastructure writes through a server-side Supabase secret key.

## Cloudflare Workers / R2 / Queues

The Worker is the authenticated R2 gateway for LexPDF Cloud.

### Request security

1. The Worker receives the Supabase access token from the native app.
2. The token is validated against Supabase Auth using the publishable key.
3. Every R2 object key is namespaced as `<user id>/<account id>/<file id>`.
4. Client-provided path components are normalized and never used as arbitrary R2 paths.

### R2 operations

- authenticated list/get/upload/replace/rename/delete
- paginated listing with bounded page size
- PDF/octet-stream media validation
- configurable upload-size ceiling
- `If-Match` optimistic concurrency for content replacement
- private/no-store responses for downloaded document content
- request IDs returned in responses for diagnostics

### Queues

R2 mutations emit compact queue messages. The consumer persists trusted audit records into `backend_events` when `SUPABASE_SECRET_KEY` is configured.

Queue configuration includes bounded batches, retry delay, maximum retries and a dead-letter queue so repeatedly failing events are not silently discarded.

## Required secrets

Never commit these values:

- `SUPABASE_PUBLISHABLE_KEY` — Worker-side Auth validation only; the Flutter build receives its own publishable key through compile-time environment configuration.
- `SUPABASE_SECRET_KEY` — Worker/Queue only; never place this in Flutter, GitHub source files or public configuration.

## Deployment order

1. Apply all Supabase migrations in `backend/supabase/migrations/` to the dedicated LexPDF Supabase project.
2. Run Supabase security/performance advisors and resolve new findings.
3. Create the R2 bucket `lexpdf-files`.
4. Create the Queue `lexpdf-sync`; the configured DLQ is `lexpdf-sync-dlq`.
5. Copy `backend/cloudflare/wrangler.toml.example` to a local/non-committed deployment configuration.
6. Configure the two Supabase Worker secrets with Wrangler.
7. Deploy the Worker.
8. Set Flutter `LEXPDF_CLOUD_GATEWAY_URL`, `LEXPDF_SUPABASE_URL` and `LEXPDF_SUPABASE_PUBLISHABLE_KEY` through the release environment.

## Acceptance criteria

- Flutter static analysis and test suite pass.
- Cloudflare Worker TypeScript passes strict type checking.
- Backend CI verifies the security invariants of the Phase 12 migration.
- The client never contains a Supabase secret/service credential.
- User A cannot address User B's R2 namespace through the Worker.
- Cross-user parent references are rejected by restrictive RLS policies.
- Failed Queue processing is retried and can reach a DLQ instead of disappearing silently.
