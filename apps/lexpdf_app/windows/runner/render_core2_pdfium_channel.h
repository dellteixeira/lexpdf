#ifndef RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_
#define RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/texture_registrar.h>

// Registers the experimental Render Core 2 PDFium channel on Windows.
//
// The implementation loads pdfium.dll dynamically at runtime so the runner
// does not take a new static link dependency during the prototype phase. The
// texture registrar is supplied so Phase 6 can present PDFium frames through a
// native Flutter Texture rather than Dart ui.Image/RawImage composition.
void RegisterRenderCore2PdfiumChannel(
    flutter::BinaryMessenger* messenger,
    flutter::TextureRegistrar* texture_registrar);

#endif  // RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_
