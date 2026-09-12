#ifndef RUNNER_WINDOWS_PDF_COMPAT_NORMALIZER_H_
#define RUNNER_WINDOWS_PDF_COMPAT_NORMALIZER_H_

#include <flutter/binary_messenger.h>

void RegisterWindowsPdfCompatNormalizerChannel(
    flutter::BinaryMessenger* messenger);

void ShutdownWindowsPdfCompatNormalizerChannel();

#endif  // RUNNER_WINDOWS_PDF_COMPAT_NORMALIZER_H_
