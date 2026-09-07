# Cloud providers — Phase 9

LexPDF remains offline-first. Cloud access is optional and downloaded files are copied into the local offline cache before normal reading/editing.

## Google Drive

The Flutter app talks directly to Drive API v3 using OAuth 2.0 + PKCE.

Build-time configuration:

```text
--dart-define=LEXPDF_GOOGLE_CLIENT_ID=<installed/public OAuth client id>
--dart-define=LEXPDF_OAUTH_CALLBACK_SCHEME=lexpdf
```

Register the callback used by the native runners:

```text
lexpdf:/oauth2redirect
```

The app requests the Drive scope because the Phase 9 provider supports list, download, upload, rename, move and delete. Access tokens are stored only through `flutter_secure_storage`; they are never stored in SQLite.

## OneDrive

The Flutter app talks directly to Microsoft Graph with OAuth 2.0 + PKCE.

```text
--dart-define=LEXPDF_MICROSOFT_CLIENT_ID=<public client id>
--dart-define=LEXPDF_MICROSOFT_TENANT=common
--dart-define=LEXPDF_OAUTH_CALLBACK_SCHEME=lexpdf
```

The delegated permission is `Files.ReadWrite`, plus `openid profile offline_access` for the authorization flow.

## Apple File Provider / iCloud

LexPDF uses the operating-system file picker (`file_selector`). On Apple platforms the system document picker exposes iCloud Drive and installed File Providers. The selected PDF is copied into LexPDF's local cache, so later reading remains offline.

When native macOS runners are committed, enable the appropriate user-selected file entitlement (`com.apple.security.files.user-selected.read-write` when read/write export is required). iOS/macOS URL scheme configuration is also required for OAuth providers.

## LexPDF Cloud / Cloudflare R2

R2 remains behind the authenticated LexPDF Cloudflare Worker. Configure:

```text
--dart-define=LEXPDF_CLOUD_GATEWAY_URL=https://<worker-host>
```

The Worker validates the Supabase bearer token and isolates R2 objects by authenticated user/account prefix.

## Offline cache

`cloud_cache_entries` stores only cache metadata: document/provider/account IDs, local path, size, pin state and last-access time.

- downloaded provider files are registered as offline;
- pinned files are protected from automatic cache cleanup;
- unpinned files use LRU eviction;
- the current UI exposes a 1 GiB cleanup target;
- missing files are pruned from cache metadata automatically.

Secrets and OAuth access tokens are never persisted in this table.
