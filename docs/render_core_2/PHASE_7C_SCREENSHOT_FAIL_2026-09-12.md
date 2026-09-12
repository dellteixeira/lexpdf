# Phase 7C — Windows physical screenshot result

Status: **FAIL at 75%**.

The physical Windows screenshot taken from the PR #149 release artifact still shows severe PDF blur and vertical smear while Flutter chrome and ink remain sharp.

A decisive diagnostic observation is that the always-on `RC2 fullpage ...` badge is absent from the visible PDF page. In PR #149 that badge is rendered in the same `Windows10PdfTileOverlay` stack as the full-page raster and defaults to enabled in release builds. Its absence means the replacement surface did not execute for this run; the screenshot therefore still represents the underlying pdfrx visual path.

Next action: remove the fragile Windows-build-number gate from the Phase 7 test path and force the replacement surface on every native Windows build unless explicitly opted out by environment variable. Re-test 75% before any wider zoom matrix.
