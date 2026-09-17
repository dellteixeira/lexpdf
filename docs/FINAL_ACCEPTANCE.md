# LexPDF — Final Acceptance / Hardening

This document is the final integration gate after roadmap Phases 1–13.

## Product scope

LexPDF is an offline-first PDF reader/editor and digital notebook for Android and Windows. Core local functionality must remain usable without Internet access. Cloud sync and remote AI are optional extensions.

## Mandatory acceptance gates

1. `flutter analyze` passes with no issues.
2. The complete Flutter test suite passes.
3. The 500+ page PDF acceptance test passes, including persistence after close/reopen.
4. Text selection, highlight, underline, strikeout and vector ink remain locally persistent.
5. Notebook pages, objects, layers and ink remain locally persistent.
6. Local OCR/search infrastructure remains available without cloud credentials.
7. `.lexbackup` validation/restore and `.lexnote` import/export tests pass.
8. Cloud sync queue/conflict tests pass while local state remains primary.
9. AI local study actions work without network; remote AI stays opt-in.
10. Supabase migration security invariants pass.
11. Cloudflare Worker typecheck passes.
12. Android release APK builds successfully.
13. Windows release application builds successfully.
14. Release artifacts are produced by CI for both target platforms.

## Cross-platform host generation

The repository keeps the Flutter application source compact. The release workflow uses the versioned host wrappers for each supported target platform.

The release build commands are equivalent to:

- Android: `flutter build apk --release`
- Windows: `flutter build windows --release`

## Release readiness rules

A release candidate is ready only if every mandatory job in `Release Hardening` is green. A failed platform build blocks release even when unit tests pass. A backend gate failure also blocks release.

Signing and distribution credentials are intentionally outside repository source control. CI artifacts validate compilability and packaging; production signing follows the policies documented for each supported platform.

## Offline-first invariants

- Opening local PDFs must not require Supabase, Cloudflare or AI connectivity.
- Reading progress, annotations, ink, notebooks, OCR metadata, search indexes and backup state are persisted locally.
- Cloud providers and remote AI fail closed when not configured.
- A network outage must not make local documents or local notebooks inaccessible.

## Exit criterion

The final hardening milestone is complete when the final PR is merged after `Flutter Foundation`, `Backend Foundation` where applicable, and `Release Hardening` all report success.
