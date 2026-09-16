#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <chrono>
#include <string>
#include <thread>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kLexPdfWindowTitle[] = L"LexPDF";
constexpr wchar_t kLexPdfSingleInstanceMutex[] = L"Local\\LexPDF.SingleInstance.v1";
constexpr ULONG_PTR kLexPdfOpenPathMessage = 0x4C585044;  // 'LXPD'

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
  // widgets and vector overlays remain sharp.
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

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int required = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
      nullptr, 0);
  if (required <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(required), L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), required);
  return result;
}

bool SendOpenPath(HWND target, const std::wstring& path) {
  if (target == nullptr || path.empty()) {
    return false;
  }
  COPYDATASTRUCT payload = {};
  payload.dwData = kLexPdfOpenPathMessage;
  payload.cbData = static_cast<DWORD>((path.size() + 1) * sizeof(wchar_t));
  payload.lpData = const_cast<wchar_t*>(path.c_str());
  return ::SendMessageW(target, WM_COPYDATA, 0,
                        reinterpret_cast<LPARAM>(&payload)) != 0;
}

HWND WaitForPrimaryWindow() {
  for (int attempt = 0; attempt < 50; ++attempt) {
    if (HWND window = ::FindWindowW(nullptr, kLexPdfWindowTitle)) {
      return window;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return nullptr;
}

bool ForwardToExistingInstance(const std::vector<std::string>& arguments) {
  HWND existing = WaitForPrimaryWindow();
  if (existing == nullptr) {
    return false;
  }

  for (const auto& argument : arguments) {
    const std::wstring path = Utf16FromUtf8(argument);
    if (!path.empty()) {
      SendOpenPath(existing, path);
    }
  }

  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::ShowWindow(existing, SW_SHOW);
  ::SetForegroundWindow(existing);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  ConfigureWindowsRenderer();

  const std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // LexPDF is intentionally single-instance on Windows. Explorer file opens,
  // file associations and subsequent launches are forwarded to the already
  // running window using WM_COPYDATA, where they become tabs in the same
  // workspace instead of spawning competing app/database instances.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kLexPdfSingleInstanceMutex);
  const bool already_running =
      single_instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running && ForwardToExistingInstance(command_line_arguments)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(command_line_arguments);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kLexPdfWindowTitle, origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
