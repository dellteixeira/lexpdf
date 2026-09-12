# Render Core 2 — Phase 4: Minimal Windows PDFium Backend

## Goal

Create the smallest real native Windows rendering path behind the Phase 3 boundary without switching the production workspace to it yet.

## Implemented

- Dart `RenderCore2WindowsPdfiumBackend` implementing `LexPdfRenderSurface`.
- Method channel: `lexpdf/render_core2_pdfium`.
- Native Windows channel registration in `FlutterWindow`.
- Dynamic loading of `pdfium.dll` with `LoadLibraryW`.
- Required PDFium exports are resolved with `GetProcAddress`.
- Document open/close through PDFium.
- Full-page render to a BGRA8888 bitmap at the exact requested physical pixel width/height.
- Native buffer stride is returned and validated on the Dart side.
- Generation token is round-tripped for future stale-render cancellation.
- Defensive limits reject invalid or extreme dimensions above 32768 pixels per axis.

## Why dynamic loading

The prototype intentionally avoids adding a second statically linked PDFium distribution. The app already depends on a PDFium-backed PDF stack through pdfrx. Phase 4 therefore establishes a runtime boundary first and expects `pdfium.dll` to be available in the Windows runtime environment. If the DLL or required exports are unavailable, the backend fails explicitly instead of silently falling back.

## Not enabled in production yet

The current `PdfViewer` workspace is unchanged. This backend is not selected by default and no `RawImage`/Texture presentation path is changed in Phase 4.

## Exit criteria

1. Windows runner compiles with the native channel source.
2. Existing Flutter/backend/release-hardening checks stay green.
3. Contract tests confirm exact physical-pixel dimensions and PDFium entry points.
4. Only after this gate passes should Phase 5 wire a single diagnostic page through this backend and verify exact physical-pixel full-page rendering.
