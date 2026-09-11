#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool IsWindows10Build() {
  using RtlGetVersionFn = LONG(WINAPI *)(OSVERSIONINFOW *);

  HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return false;
  }

  const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
      ::GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return false;
  }

  OSVERSIONINFOW version_info{};
  version_info.dwOSVersionInfoSize = sizeof(version_info);
  if (rtl_get_version(&version_info) != 0) {
    return false;
  }

  // Windows 11 keeps major version 10. Build 22000 is the first Windows 11
  // release, so use the build number to distinguish the two systems.
  return version_info.dwMajorVersion == 10 &&
         version_info.dwBuildNumber < 22000;
}

void ConfigureWindowsRenderer() {
  // Flutter 3.47 enables Impeller on Windows. LexPDF already disables it to
  // avoid compositor corruption while panning/zooming large PDF pages.
  //
  // On some Windows 10 systems, particularly hybrid-GPU notebooks, the
  // remaining Skia/ANGLE accelerated path can still smear or stretch page
  // bitmaps while the view is moving. Use Skia software rendering only on
  // Windows 10 to remove ANGLE/GPU composition from that path. Windows 11
  // remains GPU accelerated because it is already validated there.
  if (IsWindows10Build()) {
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
