#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view and Windows-native document intake.
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
  void SetFullScreen(bool enabled);
  void DispatchOpenPath(const std::wstring& path);
  void DispatchDroppedPath(const std::wstring& path);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::PluginRegistrarWindows> render_core2_registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_pdf_open_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_mode_channel_;
  bool full_screen_ = false;
  WINDOWPLACEMENT windowed_placement_{sizeof(WINDOWPLACEMENT)};
  LONG_PTR windowed_style_ = 0;
  LONG_PTR windowed_ex_style_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
