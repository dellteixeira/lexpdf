#ifndef RUNNER_RENDER_CORE2_PRODUCTION_PDFIUM_CHANNEL_H_
#define RUNNER_RENDER_CORE2_PRODUCTION_PDFIUM_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/texture_registrar.h>

// Registers the production Windows 10 Render Core 2 channel. Unlike the
// diagnostic bridge, this channel owns a pool of independent Flutter textures
// so every visible PDF page can be rendered at its exact physical pixel size.
void RegisterRenderCore2ProductionPdfiumChannel(
    flutter::BinaryMessenger* messenger,
    flutter::TextureRegistrar* texture_registrar);

#endif  // RUNNER_RENDER_CORE2_PRODUCTION_PDFIUM_CHANNEL_H_
