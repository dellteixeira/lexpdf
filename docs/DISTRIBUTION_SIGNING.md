# LexPDF distribution signing

Official beta artifacts are built only by `.github/workflows/beta-distribution.yml`.

## Reproducible inputs

- Flutter is pinned to `3.47.2` in CI and distribution workflows.
- Dart/package resolution is pinned by `apps/lexpdf_app/pubspec.lock`.
- Android uses the persistent release keystore supplied through GitHub Actions secrets.
- Official builds set `LEXPDF_ENVIRONMENT=production` explicitly.
- Every distribution job emits a SHA-256 checksum manifest for its final artifact(s).

Cryptographic signatures use trusted timestamp/notarization services, so signed binary bytes are intentionally not expected to be bit-for-bit identical across separate release runs. Reproducibility here means pinned source/tool/dependency inputs plus independently verifiable artifact signatures and checksums.

## Required GitHub Actions secrets

### Android

- `LEXPDF_ANDROID_KEYSTORE_BASE64`
- `LEXPDF_ANDROID_KEY_ALIAS`
- `LEXPDF_ANDROID_KEY_PASSWORD`
- `LEXPDF_ANDROID_STORE_PASSWORD`

### Windows Authenticode

- `LEXPDF_WINDOWS_CERTIFICATE_BASE64`: base64 encoded PFX containing an Authenticode code-signing certificate and private key.
- `LEXPDF_WINDOWS_CERTIFICATE_PASSWORD`: PFX password.

The workflow signs both `lexpdf_app.exe` and the final Inno Setup installer using SHA-256 plus RFC3161 timestamping, then requires `Get-AuthenticodeSignature` to report `Valid`.

### macOS Developer ID + notarization

- `LEXPDF_MACOS_CERTIFICATE_BASE64`: base64 encoded Developer ID Application `.p12`.
- `LEXPDF_MACOS_CERTIFICATE_PASSWORD`: certificate password.
- `LEXPDF_APPLE_ID`: Apple account used by notarytool.
- `LEXPDF_APPLE_APP_PASSWORD`: app-specific Apple password.
- `LEXPDF_APPLE_TEAM_ID`: Apple Developer Team ID.

The workflow imports the Developer ID certificate into a temporary keychain, signs the `.app` with hardened runtime and the release entitlements, signs the DMG, submits it to Apple Notary Service, staples the ticket and validates Gatekeeper/notarization before publishing the artifact.

## Release rule

Do not distribute an unsigned Windows installer or an unnotarized macOS DMG as an official LexPDF beta/release. The release workflow fails closed when required signing material is absent.
