#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // F11. See the note at its use.
  void ToggleFullscreen(HWND window);

  // The close handshake. See the long note in flutter_window.cpp.
  void BeginClose(HWND window);
  void FinishClose();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // `prototype/desktop`, the channel the app answers `willClose` on.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> desktop_;

  // Where the window was before F11, so unfullscreen puts it back exactly.
  WINDOWPLACEMENT placement_ = {sizeof(WINDOWPLACEMENT)};
  LONG_PTR style_before_fullscreen_ = 0;
  bool fullscreen_ = false;

  // A close is in flight: the WM_CLOSE was refused and the app is being asked.
  bool closing_ = false;
  // The window has been told to go; ignore whichever of reply/timeout is second.
  bool close_done_ = false;
  HWND closing_window_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
