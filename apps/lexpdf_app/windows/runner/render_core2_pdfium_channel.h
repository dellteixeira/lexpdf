#ifndef RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_
#define RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_

#include <flutter/binary_messenger.h>

// Registers the experimental Render Core 2 PDFium channel on Windows.
//
// The implementation loads pdfium.dll dynamically at runtime so the runner
// does not take a new static link dependency during the prototype phase.
void RegisterRenderCore2PdfiumChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_RENDER_CORE2_PDFIUM_CHANNEL_H_
