#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>
#include <windows.h>

#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\LexPDF.SingleInstance.2026";
constexpr ULONG_PTR kLexPdfCopyDataId = 0x4C505044;  // 'LPPD'

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

bool LooksLikePdf(const std::wstring& value) {
  if (value.size() < 4) return false;
  std::wstring tail = value.substr(value.size() - 4);
  for (auto& ch : tail) ch = static_cast<wchar_t>(std::towlower(ch));
  return tail == L".pdf";
}

std::wstring FirstPdfCommandLineArgument() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return std::wstring();

  std::wstring result;
  for (int index = 1; index < argc; ++index) {
    const std::wstring candidate(argv[index]);
    if (LooksLikePdf(candidate)) {
      result = candidate;
      break;
    }
  }
  ::LocalFree(argv);
  return result;
}

void ForwardToExistingInstance() {
  HWND existing = nullptr;
  // The mutex is created before the primary window. Allow a short startup race
  // so a double-click during cold start is not silently lost.
  for (int attempt = 0; attempt < 50 && existing == nullptr; ++attempt) {
    existing = ::FindWindowW(nullptr, L"LexPDF");
    if (existing == nullptr) ::Sleep(100);
  }
  if (existing == nullptr) return;

  const std::wstring pdf = FirstPdfCommandLineArgument();
  if (!pdf.empty()) {
    COPYDATASTRUCT data = {};
    data.dwData = kLexPdfCopyDataId;
    data.cbData = static_cast<DWORD>((pdf.size() + 1) * sizeof(wchar_t));
    data.lpData = const_cast<wchar_t*>(pdf.c_str());
    DWORD_PTR ignored = 0;
    ::SendMessageTimeoutW(existing, WM_COPYDATA, 0,
                          reinterpret_cast<LPARAM>(&data),
                          SMTO_ABORTIFHUNG | SMTO_BLOCK, 3000, &ignored);
  }

  if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
  ::SetForegroundWindow(existing);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ForwardToExistingInstance();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  ConfigureWindowsRenderer();

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"LexPDF", origin, size)) {
    if (single_instance_mutex != nullptr) ::CloseHandle(single_instance_mutex);
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
  if (single_instance_mutex != nullptr) ::CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
