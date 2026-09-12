# Render Core 2 — Windows 10 physical failure: root cause and remediation

## Physical finding

The 2026-09-12 physical Windows 10 screenshot at 75% is a hard failure. The Flutter chrome and the blue LexPDF ink are sharp while the PDF page is severely blurred/smeared. This isolates the defect to the visible PDF page surface rather than the monitor, DPI awareness, Flutter window as a whole, or the annotation layer.

## Primary root cause

Phase 6 proved and compiled a native PDFium -> Flutter Texture diagnostic, but that renderer was never installed into the production `PdfWorkspaceScreen` visual path. The production Windows 10 workspace still instantiated `Windows10PdfTileOverlay`, whose implementation continued to execute:

`PdfPage.render -> PdfImage BGRA -> decodeImageFromPixels -> ui.Image -> RawImage(FilterQuality.low)`

Therefore the user's production screenshot could not demonstrate any improvement from the Phase 6 native Texture work: it was not executing that renderer.

The old path also introduces a second sampling stage. Flutter documents `FilterQuality.low` as bilinear filtering. Even when the requested raster dimensions are mathematically correct, decoding a page/tile to `ui.Image` and then sampling it again through `RawImage` is exactly the path that must be removed from the Windows 10 critical visual surface.

## External evidence

- pdfrx issue #7 documents softer text on Flutter Windows versus Edge and explicitly raises PDFium render options and Flutter antialiasing/sampling as likely contributors: https://github.com/espresso3389/pdfrx/issues/7
- Flutter documents that `FilterQuality.low` performs bilinear sampling and that `Texture` sampling can be configured explicitly: https://api.flutter.dev/flutter/dart-ui/FilterQuality.html and https://api.flutter.dev/flutter/widgets/Texture/filterQuality.html
- PDFium's public API defines `FPDF_LCD_TEXT` (`0x02`) as LCD-optimized text rendering. PDFium's implementation maps this flag to its ClearType rendering option: https://pdfium.googlesource.com/pdfium/+/main/public/fpdfview.h
- pdfrx 2.6.x uses PDFium on Windows and packages PDFium through Flutter/Dart native assets. Flutter Windows copies native assets beside the application executable, so the production native bridge can resolve the already-bundled `pdfium.dll` rather than shipping a second rendering engine.

## Definitive production path

Windows 10 now uses the existing workspace overlay hook, but the implementation behind `Windows10PdfTileOverlay` is replaced completely:

`PDFium native render -> native RGBA frame -> flutter::PixelBufferTexture -> Texture(FilterQuality.none)`

Properties of the new path:

1. one independent native texture per visible PDF page;
2. exact target raster = `pageRect logical size * devicePixelRatio`;
3. viewer zoom is diagnostic only and is never multiplied a second time;
4. no page-sized pixel payload crosses the Dart method channel;
5. no `decodeImageFromPixels`, `ui.Image`, or `RawImage` exists in the Windows 10 production page path;
6. `FilterQuality.none` prevents a bilinear resampling stage;
7. PDFium renders with `FPDF_LCD_TEXT` for LCD/ClearType-oriented text plus `FPDF_ANNOT` for source-PDF annotations;
8. the old low-DPI pdfrx backing page remains only as layout/navigation/text-selection infrastructure and is hidden by an opaque native surface;
9. failure is explicit: if native rendering fails, the workspace shows a Render Core 2 error instead of silently exposing the known-bad blurry backing raster;
10. debug builds show an `RC2 native WIDTH×HEIGHT` badge and emit `[LexPDF][RenderCore2][production]` logs, proving which renderer is actually active during physical validation.

## Alternatives investigated

### Windows.Data.Pdf

Microsoft's Windows PDF API is available on Windows 10 and can render pages to image streams. It is a credible Windows-only fallback and does not require a third-party PDF engine. It remains a raster API, however, and would require a parallel document/text/search integration. Keep it as fallback A/B renderer if native PDFium still fails after the production path is physically verified.

### WebView2 / Edge PDF viewer

WebView2 can display PDFs with Edge/Chromium rendering quality. It is not the preferred LexPDF core because Microsoft documents PDF drawing/ink/highlight annotations as disabled in WebView2. Integrating LexPDF's own stylus, selection, search, overlays, coordinate transforms, and persistence over a WebView2 composition surface would be substantially more complex.

### MuPDF

MuPDF is technically strong, but its open-source license is AGPL; closed-source/product embedding requires AGPL compliance or a commercial license. It is therefore not the default replacement for LexPDF.

### Syncfusion Flutter PDF Viewer

Syncfusion's current Windows compatibility material explicitly lists the Flutter PDF Viewer as the exception that is not available on Windows. It cannot solve this Windows desktop renderer problem.

## Gate

This remediation is not considered successful because CI passes. It must be rebuilt and physically tested on the affected Windows 10 machine at 75%, 100%, 125%, 200%, 300%, and 400%. The first required proof is 75% with the visible `RC2 native` debug badge and sharp page text. Only then can Phase 7 be reopened for the complete physical matrix.
