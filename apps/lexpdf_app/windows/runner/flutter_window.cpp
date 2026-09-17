#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <algorithm>
#include <cctype>
#include <cwctype>
#include <filesystem>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "render_core2_pdfium_channel.h"
#include "render_core2_production_pdfium_channel.h"
#include "utils.h"
#include "windows_native_pdf_surface.h"

namespace {

constexpr ULONG_PTR kLexPdfOpenPathMessage = 0x4C585044;  // 'LXPD'

bool IsPdfPath(const std::filesystem::path& path) {
  std::wstring extension = path.extension().wstring();
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t value) { return static_cast<wchar_t>(std::towlower(value)); });
  return extension == L".pdf";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());

  const auto core_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("LexPDFRenderCore2");
  if (core_registrar == nullptr) {
    return false;
  }
  render_core2_registrar_ =
      std::make_unique<flutter::PluginRegistrarWindows>(core_registrar);
  RegisterRenderCore2PdfiumChannel(
      render_core2_registrar_->messenger(),
      render_core2_registrar_->texture_registrar());
  RegisterRenderCore2ProductionPdfiumChannel(
      render_core2_registrar_->messenger(),
      render_core2_registrar_->texture_registrar());

  native_pdf_open_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lexpdf/native_pdf_open",
          &flutter::StandardMethodCodec::GetInstance());

  // Windows Explorer can drop one or many files/folders directly on LexPDF.
  // Directories are expanded recursively and every PDF is forwarded to Dart,
  // where the normal multi-tab workspace opens it.
  ::DragAcceptFiles(GetHandle(), TRUE);

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterWindowsNativePdfSurfaceChannel(
      render_core2_registrar_->messenger(), GetHandle(),
      flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ::DragAcceptFiles(GetHandle(), FALSE);
  ShutdownWindowsNativePdfSurfaceChannel();
  native_pdf_open_channel_.reset();
  render_core2_registrar_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

void FlutterWindow::DispatchOpenPath(const std::wstring& path) {
  if (!native_pdf_open_channel_ || path.empty()) {
    return;
  }
  const std::string utf8 = Utf8FromUtf16(path.c_str());
  if (utf8.empty()) {
    return;
  }
  native_pdf_open_channel_->InvokeMethod(
      "openPdfPath", std::make_unique<flutter::EncodableValue>(utf8));
}

void FlutterWindow::DispatchDroppedPath(const std::wstring& path) {
  if (path.empty()) {
    return;
  }

  std::error_code error;
  const std::filesystem::path item(path);
  if (std::filesystem::is_regular_file(item, error)) {
    if (IsPdfPath(item)) {
      DispatchOpenPath(item.wstring());
    }
    return;
  }

  error.clear();
  if (!std::filesystem::is_directory(item, error)) {
    return;
  }

  std::filesystem::recursive_directory_iterator iterator(
      item, std::filesystem::directory_options::skip_permission_denied, error);
  const std::filesystem::recursive_directory_iterator end;
  while (iterator != end) {
    if (error) {
      error.clear();
      iterator.increment(error);
      continue;
    }
    const auto& entry = *iterator;
    if (entry.is_regular_file(error) && !error && IsPdfPath(entry.path())) {
      DispatchOpenPath(entry.path().wstring());
    }
    error.clear();
    iterator.increment(error);
  }
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_DROPFILES: {
      const HDROP drop = reinterpret_cast<HDROP>(wparam);
      const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
      for (UINT index = 0; index < count; ++index) {
        const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
        std::wstring path(static_cast<size_t>(length) + 1, L'\0');
        ::DragQueryFileW(drop, index, path.data(), length + 1);
        path.resize(length);
        DispatchDroppedPath(path);
      }
      ::DragFinish(drop);
      return 0;
    }
    case WM_COPYDATA: {
      const auto* payload = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (payload != nullptr && payload->dwData == kLexPdfOpenPathMessage &&
          payload->lpData != nullptr && payload->cbData >= sizeof(wchar_t)) {
        const auto* raw = static_cast<const wchar_t*>(payload->lpData);
        const size_t max_characters = payload->cbData / sizeof(wchar_t);
        size_t length = 0;
        while (length < max_characters && raw[length] != L'\0') {
          ++length;
        }
        DispatchDroppedPath(std::wstring(raw, length));
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
