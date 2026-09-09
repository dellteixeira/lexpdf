# LexPDF distribution signing

Official RC artifacts are built only by `.github/workflows/beta-distribution.yml`.

## Release distribution scope

The `1.0.0-rc.1` / `v1.0.0` distribution scope is:

- Android
- Windows

macOS source and CI compatibility remain in the repository, but macOS is not a distribution target for this release and therefore does not participate in RC acceptance or stable-promotion evidence.

## Reproducible inputs

- Flutter is pinned to `3.47.2` in CI and distribution workflows.
- Dart/package resolution is pinned by `apps/lexpdf_app/pubspec.lock`.
- Android uses the persistent release keystore supplied through GitHub Actions secrets.
- Official builds set `LEXPDF_ENVIRONMENT=production` explicitly.
- Every distribution job emits a SHA-256 checksum manifest for its final artifact(s).
- Windows emits `WINDOWS_SIGNING_STATUS.txt` so the accepted candidate records whether Authenticode was enabled.

## Required GitHub Actions secrets

### Android — required

- `LEXPDF_ANDROID_KEYSTORE_BASE64`
- `LEXPDF_ANDROID_KEY_ALIAS`
- `LEXPDF_ANDROID_KEY_PASSWORD`
- `LEXPDF_ANDROID_STORE_PASSWORD`

The Android APK and AAB must be signed with the project release keystore. The workflow verifies the APK signature with `apksigner` and publishes SHA-256 checksums.

### Windows Authenticode — optional

The following secrets are optional, but they must be supplied together when Windows Authenticode signing is desired:

- `LEXPDF_WINDOWS_CERTIFICATE_BASE64`: base64 encoded PFX containing a code-signing certificate and private key.
- `LEXPDF_WINDOWS_CERTIFICATE_PASSWORD`: PFX password.

When both secrets are present, the workflow signs `lexpdf_app.exe` and the final Inno Setup installer and requires `Get-AuthenticodeSignature` to report `Valid`.

When both secrets are absent, the workflow deliberately produces an unsigned Windows installer. This is permitted for the current controlled/personal distribution scope, but Windows may show an unknown-publisher or SmartScreen warning during installation. The unsigned state must be recorded in `WINDOWS_SIGNING_STATUS.txt`; it must never be presented as a signed artifact.

A partial Windows signing configuration is invalid: supplying only one of the two secrets fails the workflow.

## macOS

No macOS signing, notarization, DMG generation, or Apple Developer credentials are required for the current RC/stable distribution scope. macOS compatibility CI may still build the app from source, but that build is not an official distributed artifact for `v1.0.0`.

## Release rule

An official LexPDF RC/stable candidate must:

1. come from one exact accepted source SHA;
2. contain signed Android APK/AAB artifacts with verified SHA-256 checksums;
3. contain a Windows installer with verified SHA-256 checksum;
4. explicitly record Windows signing mode as `signed` or `unsigned`;
5. pass real installation/runtime validation on Android and Windows before stable promotion.

Unsigned Windows artifacts are acceptable only under the explicit policy above. Android signing remains mandatory.
