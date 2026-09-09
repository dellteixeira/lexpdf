# LexPDF 1.0.0 RC1 — Acceptance Manifest

This manifest is the release-candidate gate for `1.0.0-rc.1+1`.

The distribution scope for this release is **Android + Windows**. macOS remains a source/CI compatibility target, but it is not an official RC1 or `v1.0.0` distribution target and does not block acceptance.

CI and artifact generation are necessary but are not substitutes for real-device/runtime validation. The stable `v1.0.0` must not be promoted until every required item below has recorded evidence.

## Build identity

- [ ] Source commit recorded.
- [ ] App version is `1.0.0-rc.1+1`.
- [ ] Backend Foundation green on the candidate source.
- [ ] Flutter Foundation green on the candidate source.
- [ ] Release Hardening green on the candidate source.
- [ ] Phase 3 Exit Gate green on the candidate source.

## Distribution artifacts

### Android

- [ ] Signed release APK produced.
- [ ] Signed release AAB produced.
- [ ] `apksigner verify --verbose --print-certs` succeeds.
- [ ] SHA-256 checksums recorded for APK and AAB.
- [ ] APK installs and launches on a supported physical Android device.

### Windows

- [ ] Release executable produced.
- [ ] Windows installer produced.
- [ ] Windows signing mode is recorded as `signed` or `unsigned` in `WINDOWS_SIGNING_STATUS.txt`.
- [ ] If Windows signing mode is `signed`, Authenticode signature for executable is `Valid`.
- [ ] If Windows signing mode is `signed`, Authenticode signature for installer is `Valid`.
- [ ] If Windows signing mode is `unsigned`, the unsigned status is explicit and any unknown-publisher/SmartScreen warning is treated as expected behavior for this controlled distribution.
- [ ] SHA-256 checksum recorded for installer.
- [ ] Installer installs, launches and uninstalls cleanly on a supported Windows host.

## Functional parity — real runtime

Android and Windows must validate the same user-visible path where applicable:

- [ ] Open local PDF.
- [ ] Open PDF from native OS entry point / Open With.
- [ ] Reopen the same PDF after closing the reader.
- [ ] Search within PDF.
- [ ] Highlight text.
- [ ] Underline text.
- [ ] Strike out text.
- [ ] Draw ink and erase ink.
- [ ] Save, close and reopen with annotations preserved.
- [ ] Restore last reading page.
- [ ] Notebook opens and edits persist.
- [ ] Offline documents remain usable without network connectivity.

## Large-PDF runtime validation

The existing CI test physically creates and parses a 1600-page PDF. RC acceptance additionally requires native viewer validation on Android and Windows:

- [ ] 1600+ page PDF opens in the actual pdfrx viewer.
- [ ] First usable page appears without gray-screen deadlock.
- [ ] Rapid jumps across distant pages remain responsive.
- [ ] Continuous zoom remains stable.
- [ ] Search remains usable on large documents.
- [ ] Annotations remain usable on large documents.
- [ ] Background/resume does not corrupt reader state.
- [ ] No unbounded memory growth observed during an extended session.
- [ ] Image-heavy PDF validated separately from text-heavy PDF.

## Performance evidence

For each release platform, record:

- candidate commit;
- OS/device model;
- PDF page count and file size;
- time to viewer-ready;
- observed time to first usable rendered page;
- representative RAM/RSS/working-set measurement;
- any crash, rendering failure or gray-screen occurrence.

## Promotion rule

`v1.0.0` is allowed only when:

1. every required checkbox above is satisfied or explicitly documented as not applicable;
2. no open blocker or critical defect remains;
3. all release artifacts come from the same accepted candidate source;
4. Android signature evidence, Windows signing-mode evidence and SHA-256 checksums are retained;
5. final regression passes after any RC fix.
