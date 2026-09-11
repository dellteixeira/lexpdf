#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool ForceSoftwareRenderingRequested() {
  wchar_t value[8] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      L"LEXPDF_FORCE_SOFTWARE_RENDERING", value,
      static_cast<DWORD>(sizeof(value) / sizeof(value[0])));
  if (length == 0 || length >= sizeof(value) / sizeof(value[0])) {
    return false;
  }
  return value[0] == L'1';
}

void ConfigureWindowsRenderer() {
  // Keep Impeller disabled on Windows because LexPDF's PDF pages are large
  // raster surfaces with independent vector/stylus overlays. Skia is the
  // validated compositor for that path.
  //
  // IMPORTANT: do not select software rendering automatically by Windows
  // version. A PDF page rendered by PDFium is uploaded/scaled by Flutter as a
  // large image. Forcing Flutter's software backend on Windows 10 can leave
  // those page bitmaps soft or geometrically corrupted while ordinary Flutter
  // widgets and vector overlays remain sharp. That symptom matches the real
  // Win10 failures observed in LexPDF.
  //
  // Hardware-accelerated Skia is therefore the default on both Windows 10 and
  // Windows 11, matching the strategy used by mature PDF viewers that prefer
  // accelerated 2D composition when the GPU is available. A software fallback
  // remains available only as an explicit diagnostic escape hatch:
  //   LEXPDF_FORCE_SOFTWARE_RENDERING=1
  if (ForceSoftwareRenderingRequested()) {
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", L"2");
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCH_1",
                              L"enable-impeller=false");
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCH_2",
                              L"enable-software-rendering");
    return;
  }

  ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", L"1");
  ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCH_1",
                            L"enable-impeller=false");
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ConfigureWindowsRenderer();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"LexPDF", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
