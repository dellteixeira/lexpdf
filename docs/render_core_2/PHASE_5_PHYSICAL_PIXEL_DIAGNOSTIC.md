# Render Core 2 — Phase 5 physical-pixel diagnostic

Phase 5 proves one real PDF page through the native Windows PDFium backend before the production workspace is changed.

## Diagnostic target

Run from `apps/lexpdf_app`:

```bash
flutter run -d windows -t lib/render_core2_diagnostic_main.dart --dart-define=LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE=true
```

The diagnostic is intentionally a separate Flutter entrypoint. It cannot replace the production reader accidentally.

## Render contract

For a PDF page whose native PDFium size is `widthPoints x heightPoints`:

```text
logicalWidth  = widthPoints  * viewerZoom
logicalHeight = heightPoints * viewerZoom
pixelWidth    = ceil(logicalWidth  * devicePixelRatio)
pixelHeight   = ceil(logicalHeight * devicePixelRatio)
```

Zoom is applied exactly once. DPR is applied exactly once.

PDFium receives `pixelWidth x pixelHeight` and the Dart bridge rejects a frame whose returned dimensions differ from those requested.

## Required physical matrix

Use the same reproducer PDF and Windows 10 machine at:

- 75%
- 100%
- 125%
- 200%
- 300%
- 400%

At each zoom record the diagnostic footer values for PDF points, DPR, requested physical pixels, returned physical pixels and rowBytes. Requested and returned dimensions must match exactly.

## Visual acceptance

The page must be compared side-by-side with Adobe Reader or Edge on the same monitor. Text and vector edges must remain sharp after the render settles. No persistent low-resolution bitmap is acceptable.

## Stop rule

Phase 6 (native Texture/surface presentation) does not start until:

1. CI is green on the exact Phase 5 head SHA.
2. The diagnostic opens the reproducer PDF through native PDFium.
3. Requested and returned raster dimensions match at every required zoom.
4. The physical Windows 10 comparison demonstrates that the native raster itself is sharp.

If the raster is sharp but the on-screen diagnostic is blurred, the defect is in the Flutter presentation/compositor path and Phase 6 becomes the direct fix target.
