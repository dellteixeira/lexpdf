#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "render_core2_pdfium_channel.h"
#include "render_core2_production_pdfium_channel.h"
#include "windows_native_pdf_surface.h"

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
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());

  // FlutterEngine intentionally exposes plugin registrars, not the
  // client-wrapper TextureRegistrar directly. Build and retain a Windows
  // plugin registrar so Render Core 2 receives messenger/texture wrappers with
  // the correct lifetime for the running engine.
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

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Phase 7E: a completely separate Windows PDF path. Windows.Data.Pdf renders
  // into a native child HWND painted by GDI/WIC, so the page pixels never pass
  // through pdfrx, PDFium, ui.Image, Flutter Texture, Skia, or Impeller.
  RegisterWindowsNativePdfSurfaceChannel(
      render_core2_registrar_->messenger(),
      flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ShutdownWindowsNativePdfSurfaceChannel();

  // The registrar wraps engine-owned messenger and texture APIs, so destroy it
  // before tearing down the Flutter engine/controller.
  render_core2_registrar_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
