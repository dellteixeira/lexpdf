# LexPDF — Acceptance & Stabilization Gate

## Automated release gate

A candidate build is acceptable only when all of the following pass in CI:

- `flutter pub get`
- `flutter analyze`
- full `flutter test`
- `large_pdf_acceptance_test.dart`

The large-document acceptance test must verify:

1. a PDF with at least 500 pages can be generated, written to disk, reopened and parsed structurally in the headless runner (current fixture: 520);
2. page 1, a middle page and the final page remain present after file reopen;
3. text annotations persist across all 520 pages;
4. vector ink persists across all 520 pages, including pressure/tilt/timestamps;
5. reading progress persists on the final page with zoom/scroll/view mode;
6. the SQLite file is physically closed and reopened before the final verification;
7. `PRAGMA integrity_check` returns `ok`;
8. `PRAGMA foreign_key_check` returns no violations.

The structural PDF check intentionally uses a pure-Dart parser. `flutter test` is a headless unit-test runner and does not package the Linux PDFium native asset used by the installed LexPDF application. Native PDFium opening/rendering therefore belongs to the platform acceptance gate below rather than being simulated or silently skipped in CI.

## Device-level acceptance

Headless CI cannot truthfully validate native PDFium packaging, human-perceived scroll fluidity or stylus latency. Before a production release, Android, Windows and macOS builds must therefore be exercised with a real 500+ page PDF and verify:

- the installed app loads PDFium and opens the document without crash;
- page count and navigation reach the first, middle and final pages;
- continuous scroll from early to late pages without runaway memory growth;
- zoom and text selection remain responsive;
- highlight, underline and strikeout render correctly;
- stylus/mouse ink remains aligned during zoom/navigation;
- close/reopen restores page position and all annotations;
- original PDF remains unchanged unless an explicit Save/Export operation is chosen.

## Failure rule

A failed automated acceptance test blocks merge/release. A device-level regression blocks a production release even when unit tests are green.
