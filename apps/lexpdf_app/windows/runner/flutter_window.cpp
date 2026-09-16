#include "flutter_window.h"

#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <optional>
#include <system_error>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "render_core2_pdfium_channel.h"
#include "render_core2_production_pdfium_channel.h"
#include "utils.h"
#include "windows_native_pdf_surface.h"

namespace {

constexpr ULONG_PTR kLexPdfCopyDataId = 0x4C505044;  // 'LPPD'
constexpr size_t kMaxNativePdfBatch = 10;

bool LooksLikePdf(const std::filesystem::path& path) {
  std::wstring extension = path.extension().wstring();
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
  return extension == L".pdf";
}

void CollectPdfPaths(const std::filesystem::path& input,
                     std::vector<std::wstring>* output) {
  if (output == nullptr || output->size() >= kMaxNativePdfBatch) return;

  std::error_code error;
  if (std::filesystem::is_regular_file(input, error)) {
    if (!error && LooksLikePdf(input)) output->push_back(input.wstring());
    return;
  }
  if (error || !std::filesystem::is_directory(input, error) || error) return;

  std::filesystem::recursive_directory_iterator iterator(
      input, std::filesystem::directory_options::skip_permission_denied, error);
  const std::filesystem::recursive_directory_iterator end;
  while (!error && iterator != end && output->size() < kMaxNativePdfBatch) {
    const auto& entry = *iterator;
    std::error_code entry_error;
    if (entry.is_regular_file(entry_error) && !entry_error &&
        LooksLikePdf(entry.path())) {
      output->push_back(entry.path().wstring());
    }
    iterator.increment(error);
  }
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

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
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
          render_core2_registrar_->messenger(), "lexpdf/native_pdf_open",
          &flutter::StandardMethodCodec::GetInstance());
  native_pdf_open_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getInitialPdfPath") {
          // The initial command-line PDF is already delivered through Dart
          // entrypoint arguments. Runtime opens arrive through openPdfPaths.
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterWindowsNativePdfSurfaceChannel(
      render_core2_registrar_->messenger(), GetHandle(),
      flutter_controller_->view()->GetNativeWindow());

  // Accept Explorer file/folder drops on the top-level LexPDF window. Folders
  // are recursively scanned (permission failures are skipped) and at most ten
  // PDFs are forwarded, matching the workspace tab limit.
  ::DragAcceptFiles(GetHandle(), TRUE);

  if (!pending_pdf_paths_.empty()) {
    SendPdfPathsToDart(pending_pdf_paths_);
    pending_pdf_paths_.clear();
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });
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

void FlutterWindow::QueueOrSendPdfPaths(
    const std::vector<std::wstring>& paths) {
  if (paths.empty()) return;
  if (!native_pdf_open_channel_) {
    for (const auto& path : paths) {
      if (pending_pdf_paths_.size() >= kMaxNativePdfBatch) break;
      pending_pdf_paths_.push_back(path);
    }
    return;
  }
  SendPdfPathsToDart(paths);
}

void FlutterWindow::SendPdfPathsToDart(
    const std::vector<std::wstring>& paths) {
  if (!native_pdf_open_channel_ || paths.empty()) return;

  flutter::EncodableList encoded_paths;
  encoded_paths.reserve(std::min(paths.size(), kMaxNativePdfBatch));
  for (const auto& path : paths) {
    if (encoded_paths.size() >= kMaxNativePdfBatch) break;
    encoded_paths.emplace_back(Utf8FromUtf16(path.c_str()));
  }
  native_pdf_open_channel_->InvokeMethod(
      "openPdfPaths",
      std::make_unique<flutter::EncodableValue>(encoded_paths));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA) {
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data != nullptr && data->dwData == kLexPdfCopyDataId &&
        data->lpData != nullptr && data->cbData >= sizeof(wchar_t)) {
      const auto* path = static_cast<const wchar_t*>(data->lpData);
      std::vector<std::wstring> pdfs;
      CollectPdfPaths(std::filesystem::path(path), &pdfs);
      QueueOrSendPdfPaths(pdfs);
      ::ShowWindow(hwnd, SW_RESTORE);
      ::SetForegroundWindow(hwnd);
      return TRUE;
    }
  }

  if (message == WM_DROPFILES) {
    const HDROP drop = reinterpret_cast<HDROP>(wparam);
    std::vector<std::wstring> pdfs;
    const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT index = 0; index < count && pdfs.size() < kMaxNativePdfBatch;
         ++index) {
      const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
      if (length == 0) continue;
      std::wstring path(length + 1, L'\0');
      if (::DragQueryFileW(drop, index, path.data(), length + 1) == 0) continue;
      path.resize(length);
      CollectPdfPaths(std::filesystem::path(path), &pdfs);
    }
    ::DragFinish(drop);
    QueueOrSendPdfPaths(pdfs);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
