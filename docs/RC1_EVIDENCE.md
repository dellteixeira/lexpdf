# LexPDF 1.0.0 RC1 — Evidence Record

This record accompanies `docs/RC1_ACCEPTANCE.md`. It stores concrete evidence for the candidate that may later be promoted to `v1.0.0`.

**Rule:** do not replace `PENDING` with `PASS` unless the stated command, artifact inspection, installation, or real-device/runtime validation was actually performed against the recorded candidate.

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

## Windows signed artifacts

- Installer artifact name/path: `PENDING`
- Installer SHA-256: `PENDING`
- Executable Authenticode status: `PENDING`
- Installer Authenticode status: `PENDING`
- Signing certificate subject/thumbprint: `PENDING`
- Windows version/build: `PENDING`
- Host hardware summary: `PENDING`
- Installer install: `PENDING`
- Cold launch: `PENDING`
- PDF Open With / file association: `PENDING`
- Reopen same PDF: `PENDING`
- Clean uninstall: `PENDING`
- Offline use: `PENDING`

## macOS signed artifacts

- DMG artifact name/path: `PENDING`
- DMG SHA-256: `PENDING`
- Developer ID signature: `PENDING`
- Notarytool result / submission ID: `PENDING`
- Stapler validation: `PENDING`
- Gatekeeper assessment: `PENDING`
- macOS version/build: `PENDING`
- Mac model/architecture: `PENDING`
- DMG install: `PENDING`
- Cold launch: `PENDING`
- Finder Open With / native document open: `PENDING`
- Reopen same PDF after relaunch: `PENDING`
- iCloud/external-file case: `PENDING`
- Offline use: `PENDING`

## Functional parity — real runtime

Record `PASS`, `FAIL`, or `N/A` for each native platform only after execution.

| Scenario | Android | Windows | macOS |
| --- | --- | --- | --- |
| Search | `PENDING` | `PENDING` | `PENDING` |
| Highlight | `PENDING` | `PENDING` | `PENDING` |
| Underline | `PENDING` | `PENDING` | `PENDING` |
| Strikeout | `PENDING` | `PENDING` | `PENDING` |
| Ink + erase | `PENDING` | `PENDING` | `PENDING` |
| Annotation persistence after reopen | `PENDING` | `PENDING` | `PENDING` |
| Last reading page restored | `PENDING` | `PENDING` | `PENDING` |
| Notebook edit persistence | `PENDING` | `PENDING` | `PENDING` |
| Offline document use | `PENDING` | `PENDING` | `PENDING` |

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

### macOS

- Test PDF page count / size: `PENDING`
- Image-heavy PDF page count / size: `PENDING`
- Time to viewer-ready: `PENDING`
- Observed time to first usable rendered page: `PENDING`
- Rapid distant-page jumps: `PENDING`
- Continuous zoom: `PENDING`
- Search on large PDF: `PENDING`
- Annotations on large PDF: `PENDING`
- Representative RSS/memory measurement: `PENDING`
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
3. every signed artifact checksum and signing/notarization result is recorded;
4. real-device/runtime results are recorded for Android, Windows, and macOS;
5. large-PDF and image-heavy-PDF evidence is recorded;
6. no blocker or critical defect remains;
7. the Stable Promotion Gate succeeds against the accepted RC SHA.
