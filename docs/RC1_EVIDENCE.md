# LexPDF 1.0.0 RC1 — Evidence Record

This record accompanies `docs/RC1_ACCEPTANCE.md`. It stores concrete evidence for the candidate that may later be promoted to `v1.0.0`.

The distribution scope for this release is **Android + Windows**. macOS remains outside the distributed RC/stable artifact scope.

**Rule:** do not replace `PENDING` with `PASS`, `signed`, `unsigned`, a concrete hash, or any runtime result unless the stated command, artifact inspection, installation, or real-device/runtime validation was actually performed against the recorded candidate.

## Candidate identity

- Candidate version: `1.0.0-rc.1+1`
- Candidate source SHA: `PENDING`
- Release Candidate Distribution run ID: `PENDING`
- Distribution run conclusion: `PENDING`
- Evidence recorded by: `PENDING`
- Evidence date/time (UTC): `PENDING`

## CI evidence

| Gate | Run | Candidate SHA | Result |
| --- | --- | --- | --- |
| Backend Foundation | `PENDING` | `PENDING` | `PENDING` |
| Flutter Foundation | `PENDING` | `PENDING` | `PENDING` |
| Release Hardening | `PENDING` | `PENDING` | `PENDING` |
| Phase 3 Exit Gate | `PENDING` | `PENDING` | `PENDING` |

## Android signed artifacts

- APK artifact name/path: `PENDING`
- APK SHA-256: `PENDING`
- AAB artifact name/path: `PENDING`
- AAB SHA-256: `PENDING`
- `apksigner verify --verbose --print-certs`: `PENDING`
- Signing certificate digest/identity: `PENDING`
- Physical device model: `PENDING`
- Android version: `PENDING`
- APK install: `PENDING`
- Cold launch: `PENDING`
- Open local PDF: `PENDING`
- Native Open With / intent: `PENDING`
- Reopen same PDF: `PENDING`
- Background/resume: `PENDING`
- Offline use: `PENDING`

## Windows artifacts

- Installer artifact name/path: `PENDING`
- Installer SHA-256: `PENDING`
- Windows signing mode (`signed` or `unsigned`): `PENDING`
- Executable Authenticode status: `PENDING`
- Installer Authenticode status: `PENDING`
- Signing certificate subject/thumbprint: `PENDING`
- `WINDOWS_SIGNING_STATUS.txt` captured: `PENDING`
- Windows version/build: `PENDING`
- Host hardware summary: `PENDING`
- Installer install: `PENDING`
- Cold launch: `PENDING`
- PDF Open With / file association: `PENDING`
- Reopen same PDF: `PENDING`
- Clean uninstall: `PENDING`
- Offline use: `PENDING`

When Windows signing mode is `unsigned`, the Authenticode and certificate fields must record the observed unsigned state or `N/A` as appropriate after inspection; they must not be reported as `Valid` or signed. Unknown-publisher/SmartScreen warnings are expected for an unsigned controlled-distribution build and must be noted in the installation evidence.

## Functional parity — real runtime

Record `PASS`, `FAIL`, or `N/A` for Android and Windows only after execution.

| Scenario | Android | Windows |
| --- | --- | --- |
| Search | `PENDING` | `PENDING` |
| Highlight | `PENDING` | `PENDING` |
| Underline | `PENDING` | `PENDING` |
| Strikeout | `PENDING` | `PENDING` |
| Ink + erase | `PENDING` | `PENDING` |
| Annotation persistence after reopen | `PENDING` | `PENDING` |
| Last reading page restored | `PENDING` | `PENDING` |
| Notebook edit persistence | `PENDING` | `PENDING` |
| Offline document use | `PENDING` | `PENDING` |

## Large-PDF and performance evidence

Use at least one text-heavy 1600+ page PDF and one image-heavy PDF. `viewer-ready` telemetry is not a substitute for first usable pixels.

### Android

- Test PDF page count / size: `PENDING`
- Image-heavy PDF page count / size: `PENDING`
- Time to viewer-ready: `PENDING`
- Observed time to first usable rendered page: `PENDING`
- Rapid distant-page jumps: `PENDING`
- Continuous zoom: `PENDING`
- Search on large PDF: `PENDING`
- Annotations on large PDF: `PENDING`
- Peak/representative memory measurement: `PENDING`
- Gray-screen occurrence: `PENDING`
- Crash/ANR occurrence: `PENDING`

### Windows

- Test PDF page count / size: `PENDING`
- Image-heavy PDF page count / size: `PENDING`
- Time to viewer-ready: `PENDING`
- Observed time to first usable rendered page: `PENDING`
- Rapid distant-page jumps: `PENDING`
- Continuous zoom: `PENDING`
- Search on large PDF: `PENDING`
- Annotations on large PDF: `PENDING`
- Representative working set: `PENDING`
- Gray-screen occurrence: `PENDING`
- Crash/hang occurrence: `PENDING`

## Defects and disposition

- Blockers: `PENDING`
- Critical defects: `PENDING`
- Non-blocking defects accepted for v1.0.0: `PENDING`
- RC2 required: `PENDING`

## Promotion evidence

Stable promotion remains blocked until:

1. `docs/RC1_ACCEPTANCE.md` has no unchecked required item;
2. this record contains the exact accepted RC source SHA and distribution run ID;
3. Android signing evidence, Windows signing mode and all distribution artifact checksums are recorded;
4. real-device/runtime results are recorded for Android and Windows;
5. large-PDF and image-heavy-PDF evidence is recorded for Android and Windows;
6. no blocker or critical defect remains;
7. the Stable Promotion Gate succeeds against the accepted RC SHA.
