#ifndef RUNNER_WINDOWS_NATIVE_PDF_SURFACE_H_
#define RUNNER_WINDOWS_NATIVE_PDF_SURFACE_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

// Registers a Windows-only PDF presentation channel that renders PDF pages
// through Windows.Data.Pdf into a native child HWND. The PDF pixels never pass
// through Flutter's image, texture, Skia, Impeller, or pdfrx presentation path.
void RegisterWindowsNativePdfSurfaceChannel(
    flutter::BinaryMessenger* messenger,
    HWND flutter_view_window);

// Destroys all native PDF child windows owned by the channel.
void ShutdownWindowsNativePdfSurfaceChannel();

#endif  // RUNNER_WINDOWS_NATIVE_PDF_SURFACE_H_
