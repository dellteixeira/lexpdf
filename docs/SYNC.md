# LexPDF Sync — Phase 10

The sync layer is offline-first. SQLite remains the local source of truth and network work is represented by durable queue items.

## Durable queue

`LocalSyncStore` persists upload, download, delete and metadata jobs with these states:

- `pending`
- `running`
- `retry`
- `done`
- `failed`

Equivalent active jobs are coalesced. A process interruption never leaves a job permanently stuck in `running`: the next sync bootstrap returns interrupted jobs to `pending`.

## Retry policy

`SyncEngine` serializes drains so only one queue consumer runs at a time. Failed jobs use bounded backoff:

1. 5 seconds
2. 15 seconds
3. 60 seconds
4. 5 minutes
5. terminal failure after the configured maximum attempts

A user can explicitly reset a terminal failure with **Tentar novamente**.

## Revisions and checksums

The local catalog persists:

- `local_version`
- local SHA-256 checksum
- provider remote revision

Provider metadata is used when available:

- Google Drive: `modifiedTime` + `md5Checksum`
- OneDrive: `eTag`/`lastModifiedDateTime` + file hash
- LexPDF Cloud/R2: object ETag

A separate `local_sync_checkpoints` table stores the last confirmed local and remote state. Conflict detection compares current state against that checkpoint, not local and remote hashes directly (providers may use different hash algorithms).

## Decisions

For a document with a checkpoint:

| Local changed | Remote changed | Decision |
| --- | --- | --- |
| no | no | no transfer |
| yes | no | upload/replace remote content |
| no | yes | download remote content |
| yes | yes | conflict |

A remote deletion after a prior checkpoint is treated as a conflict rather than silently recreating or deleting local data.

## Stable remote identity

Sync updates existing cloud objects instead of creating duplicates:

- Google Drive uses media update on the existing file ID.
- OneDrive replaces `/items/{id}/content`.
- R2 uses `PUT /v1/cloud/r2/files/{id}/content` and preserves the object key/ID.

## Account binding

Each managed cloud document is bound to its exact provider/account in `local_sync_bindings`. This is required when a user connects multiple accounts for the same provider.

## Conflict resolution

The UI applies the selected policy; it does not merely mark the conflict resolved:

- **Manter local** — local content replaces the remote file.
- **Manter remoto** — remote content replaces the local cached file.
- **Manter ambos** — a local-only conflict copy is created, then the bound cloud document is refreshed from remote.

After a successful resolution, a fresh checkpoint is written and the conflict is marked resolved.

## iCloud / File Provider

Apple File Provider documents imported through the native picker are treated as local/offline copies. Managed bidirectional API sync in Phase 10 applies to Google Drive, OneDrive and LexPDF Cloud/R2; File Provider lifecycle and coordination remain under the operating system.
