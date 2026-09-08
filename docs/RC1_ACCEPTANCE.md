# LexPDF 1.0.0 RC1 — Acceptance Manifest

This manifest is the release-candidate gate for `1.0.0-rc.1+1`.

CI and signed-artifact generation are necessary but are not substitutes for real-device/runtime validation. The stable `v1.0.0` must not be promoted until every required item below has recorded evidence.

## Build identity

- [ ] Source commit recorded.
- [ ] App version is `1.0.0-rc.1+1`.
- [ ] Backend Foundation green on the candidate source.
- [ ] Flutter Foundation green on the candidate source.
- [ ] Release Hardening green on the candidate source.
- [ ] Phase 3 Exit Gate green on the candidate source.

## Signed distribution artifacts

### Android

- [ ] Signed release APK produced.
- [ ] Signed release AAB produced.
- [ ] `apksigner verify --verbose --print-certs` succeeds.
- [ ] SHA-256 checksums recorded for APK and AAB.
- [ ] APK installs and launches on a supported physical Android device.

### Windows

- [ ] Release executable produced.
- [ ] Windows installer produced.
- [ ] Authenticode signature for executable is `Valid`.
- [ ] Authenticode signature for installer is `Valid`.
- [ ] SHA-256 checksum recorded for installer.
- [ ] Installer installs, launches and uninstalls cleanly on a supported Windows host.

### macOS

- [ ] Signed `.app` produced.
- [ ] Signed DMG produced.
- [ ] Developer ID signature verification succeeds.
- [ ] Apple notarization succeeds.
- [ ] Stapler validation succeeds.
- [ ] Gatekeeper assessment succeeds.
- [ ] SHA-256 checksum recorded for DMG.
- [ ] DMG installs and launches on a supported macOS host.

## Functional parity — real runtime

Each platform must validate the same user-visible path where applicable:

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

The existing CI test physically creates and parses a 1600-page PDF. RC acceptance additionally requires native viewer validation:

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

For each native platform, record:

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
4. checksums and signing/notarization evidence are retained;
5. final regression passes after any RC fix.
