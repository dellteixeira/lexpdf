#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that hosts Flutter plus the small amount of native Windows desktop
// integration that must live above the Flutter view (single-instance intake and
// Explorer drag/drop).
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void QueueOrSendPdfPaths(const std::vector<std::wstring>& paths);
  void SendPdfPathsToDart(const std::vector<std::wstring>& paths);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Owns the client-wrapper registrar used by Render Core 2. Keeping this
  // alive for the same lifetime as the Flutter engine keeps its BinaryMessenger
  // and TextureRegistrar wrappers valid while the native PDF texture exists.
  std::unique_ptr<flutter::PluginRegistrarWindows> render_core2_registrar_;

  // Receives PDFs forwarded by a second LexPDF process and PDFs/folders dropped
  // from Explorer. Pending paths are buffered during the very small startup
  // window before the Dart method channel exists.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_pdf_open_channel_;
  std::vector<std::wstring> pending_pdf_paths_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
