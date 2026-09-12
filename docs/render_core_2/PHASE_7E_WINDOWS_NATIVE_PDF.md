# Render Core 2 — Phase 7E: Windows native PDF surface

## Why this phase exists

The physical Windows 10 machine continued to show severe blur/smear after the
following independent experiments:

1. corrected pdfrx tile scaling;
2. native PDFium pixel-buffer texture;
3. hardened pixel-buffer lifetime/stride/alpha handling;
4. supersampled full-page `ui.Image` / `RawImage` presentation.

Phase 7E stops iterating on that family of solutions.

## New rendering boundary

The visible Windows PDF page now uses the operating-system PDF stack:

`Windows.Data.Pdf -> RenderToStreamAsync -> WIC BGRA -> native child HWND/GDI`

The PDF pixels do **not** traverse:

- pdfrx page rendering;
- PDFium rendering;
- `ui.decodeImageFromPixels`;
- `ui.Image`;
- Flutter `RawImage`;
- Flutter `Texture`;
- Skia/Impeller PDF page composition.

pdfrx remains temporarily underneath the native surface only to provide page
layout, navigation and page rectangles during the physical rendering proof.

## Why Windows.Data.Pdf

`Windows.Data.Pdf` is a Microsoft platform PDF API available on Windows 10 and
exposes page rendering independently of Flutter's renderer. Microsoft also
provides `IPdfRendererNative` for Direct2D/DirectX paths when higher-performance
native composition is needed. The initial Phase 7E proof intentionally chooses
`RenderToStreamAsync` plus WIC/GDI because it removes the maximum number of
variables from the failing Flutter graphics path.

## Physical proof marker

Every native page child window paints the badge:

`WINPDF NATIVE`

A screenshot without that badge is not evidence for Phase 7E.

## Phase 7E exit gate

Test the same affected PDF on the same Windows 10 machine at 75% first.

PASS requires:

- `WINPDF NATIVE` visible;
- normal page geometry;
- no vertical smear/stretch;
- readable text comparable to a native Windows/Edge PDF viewer;
- no page-sized Flutter PDF image involved in the visible path.

Do not proceed to the broader zoom matrix until 75% passes.

## Deliberate temporary limitations

This is a renderer-isolation phase. Because a native child HWND has Windows
"airspace" semantics, Flutter annotation widgets cannot visually sit above the
native page surface. Existing annotation data is not deleted; annotation visual
reintegration is deferred until the page-rendering defect is physically solved.
