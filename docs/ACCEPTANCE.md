# LexPDF — Acceptance & Stabilization Gate

## Automated release gate

A candidate build is acceptable only when all of the following pass in CI:

- `flutter pub get`
- `flutter analyze`
- full `flutter test`
- `large_pdf_acceptance_test.dart`

The large-document acceptance test must verify:

1. the PDF engine can create, encode, reopen and address a PDF with at least 500 pages (current fixture: 520);
2. page 1, a middle page and the final page remain addressable after reopen;
3. text annotations persist across all 520 pages;
4. vector ink persists across all 520 pages, including pressure/tilt/timestamps;
5. reading progress persists on the final page with zoom/scroll/view mode;
6. the SQLite file is physically closed and reopened before the final verification;
7. `PRAGMA integrity_check` returns `ok`;
8. `PRAGMA foreign_key_check` returns no violations.

## Device-level acceptance

Headless CI cannot truthfully measure human-perceived scroll fluidity or stylus latency. Before a production release, Android, Windows and macOS builds must therefore be exercised with a real 500+ page PDF and verify:

- open without crash;
- continuous scroll from early to late pages without runaway memory growth;
- zoom and text selection remain responsive;
- highlight, underline and strikeout render correctly;
- stylus/mouse ink remains aligned during zoom/navigation;
- close/reopen restores page position and all annotations;
- original PDF remains unchanged unless an explicit Save/Export operation is chosen.

## Failure rule

A failed automated acceptance test blocks merge/release. A device-level regression blocks a production release even when unit tests are green.
