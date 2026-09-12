# Render Core 2 — Phase 6: Native Texture presentation

## Objective

Remove the Dart `ui.Image` / `RawImage` presentation path from the Render Core 2 diagnostic and keep page-sized raster data in native Windows memory until Flutter samples it as an external `Texture`.

## Data path

Phase 5 diagnostic path:

`PDFium -> BGRA vector -> MethodChannel byte payload -> Dart Uint8List -> ui.decodeImageFromPixels -> ui.Image -> RawImage`

Phase 6 diagnostic path:

`PDFium -> native BGRA vector -> native RGBA texture frame -> Flutter PixelBufferTexture -> Texture widget`

The production workspace is still unchanged. This is intentionally a diagnostic-only native presentation path.

## Native texture contract

The Windows runner registers a `flutter::PixelBufferTexture` through the engine texture registrar. PDFium renders at the exact requested physical width and height. The native presenter then:

1. validates PDFium stride and buffer size;
2. converts BGRA to tightly packed RGBA8888 in native memory;
3. retains the current frame behind a ref-counted object;
4. calls `MarkTextureFrameAvailable`;
5. supplies the buffer from the Flutter render-thread callback;
6. keeps each callback lease alive until Flutter invokes its release callback;
7. unregisters the texture explicitly when the diagnostic is disposed.

No page-sized pixel buffer is sent to Dart in the Texture path.

## Physical-pixel rule

The target dimensions remain:

`PDF points * viewer zoom * devicePixelRatio`

Each factor is applied exactly once. The diagnostic still displays requested and returned pixel sizes and retains the mandatory zoom matrix:

- 75%
- 100%
- 125%
- 200%
- 300%
- 400%

## Safety boundary

The diagnostic still requires:

`--dart-define=LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE=true`

The main LexPDF workspace continues to use the existing viewer until the native Texture path passes CI and physical Windows 10 sharpness validation.

## Exit criteria

Phase 6 is technically ready for physical validation only when:

- Windows build succeeds;
- Flutter analyzer and tests are green;
- the diagnostic contains no `RawImage` or `decodeImageFromPixels` path;
- texture registration, frame notification and disposal are covered by contract tests;
- the diagnostic runs on the target Windows 10 machine with the reproducer PDF.

Physical approval still requires visual comparison at 75%, 100%, 125%, 200%, 300% and 400%. A green CI is necessary but not sufficient.
