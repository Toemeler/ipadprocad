#include "flutter_window.h"

#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The channel the app answers `willClose` on. See lib/platform/desktop_shell.dart.
constexpr char kDesktopChannel[] = "prototype/desktop";

// How long the close waits for the app to finish writing before going ahead.
// A window that cannot be closed is a worse bug than a document that was not
// saved, and this is the number that guarantees the first can never happen.
constexpr UINT kCloseTimeoutMs = 2500;

// Any id will do; it is scoped to the window.
constexpr UINT_PTR kCloseTimerId = 1;

// Below this the ribbon has to wrap and the model browser has nowhere to go.
// The app still runs; it stops being the app the screenshots are of.
constexpr LONG kMinWidth = 1024;
constexpr LONG kMinHeight = 700;

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
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The close handshake's channel, on the engine this window owns: it lives
  // exactly as long as the thing whose closing it is about.
  desktop_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kDesktopChannel,
      &flutter::StandardMethodCodec::GetInstance());

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
  desktop_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// F11 toggles fullscreen, which is what this app is on the device and what a
// desktop user expects of a canvas. Handled here rather than in Dart because
// the window is not Flutter's to resize: `SystemChrome.setEnabledSystemUIMode`
// is an iOS/Android call and does nothing on a Win32 window, so a Dart-side
// implementation would be a shortcut that silently never fires.
//
// The classic Win32 recipe: remember the placement and the style, strip the
// frame, fill the monitor, and put both back. Remembering the PLACEMENT rather
// than the rect is what makes a maximised window come back maximised.
void FlutterWindow::ToggleFullscreen(HWND window) {
  if (!fullscreen_) {
    MONITORINFO mi = {sizeof(MONITORINFO)};
    if (!::GetWindowPlacement(window, &placement_) ||
        !::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY),
                          &mi)) {
      return;
    }
    style_before_fullscreen_ = ::GetWindowLongPtr(window, GWL_STYLE);
    ::SetWindowLongPtr(window, GWL_STYLE,
                       style_before_fullscreen_ & ~WS_OVERLAPPEDWINDOW);
    ::SetWindowPos(window, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = true;
    return;
  }
  ::SetWindowLongPtr(window, GWL_STYLE, style_before_fullscreen_);
  ::SetWindowPlacement(window, &placement_);
  ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  fullscreen_ = false;
}

// ---------------------------------------------------------------------------
// Closing the window without losing the open document.
//
// The app writes the document it has open whenever it leaves one — Home, close
// tab, and on iOS when the system suspends it. Closing a DESKTOP window is a
// fourth way out and the only one nobody can be told about in time: the window
// is destroyed, the engine is torn down, and the lifecycle event the app would
// have saved on arrives with no time left to act on it. Measured on the GTK
// build, not assumed: the save started there got as far as writing the DXF and
// the process was gone before the document file was packed.
//
// So the close is BLOCKED — WM_CLOSE returns without reaching DefWindowProc —
// the app is asked `willClose`, and the window is destroyed in the reply. The
// timeout is not optional: an app that is wedged, or a build with no handler
// for the method, must not produce a window that refuses to close.
// ---------------------------------------------------------------------------
void FlutterWindow::BeginClose(HWND window) {
  closing_ = true;
  close_done_ = false;
  closing_window_ = window;

  ::SetTimer(window, kCloseTimerId, kCloseTimeoutMs, nullptr);

  // Hide it now. The save takes a few milliseconds on any real document, and a
  // window that visibly lingers after the close button reads as a hang.
  ::ShowWindow(window, SW_HIDE);

  if (desktop_ == nullptr) {
    FinishClose();
    return;
  }
  desktop_->InvokeMethod(
      "willClose", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          // Answered, errored, or not implemented — all three mean the same
          // thing here. This handshake buys a save; it does not gate the
          // window on one.
          [this](const flutter::EncodableValue*) { FinishClose(); },
          [this](const std::string&, const std::string&,
                 const flutter::EncodableValue*) { FinishClose(); },
          [this]() { FinishClose(); }));
}

void FlutterWindow::FinishClose() {
  if (close_done_) return;
  close_done_ = true;
  if (closing_window_ != nullptr) {
    ::KillTimer(closing_window_, kCloseTimerId);
  }
  closing_window_ = nullptr;
  // WM_CLOSE was refused and nothing else will take this window down, so it
  // has to be done here, and exactly once.
  Destroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    // BEFORE the controller sees it: F11 must never reach Dart as a key event
    // as well, which is what the GTK runner's `return TRUE` buys there.
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (wparam == VK_F11) {
        ToggleFullscreen(hwnd);
        return 0;
      }
      break;

    // The minimum size, which Win32 asks for rather than being told once.
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      // The same helper the template's own window uses, for the same reason:
      // this has to be right on a mixed-DPI desktop, and GetDpiForWindow needs
      // a newer SDK than the runner otherwise asks for.
      const UINT dpi = FlutterDesktopGetDpiForMonitor(
          ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
      const double scale = dpi / 96.0;
      info->ptMinTrackSize.x = static_cast<LONG>(kMinWidth * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(kMinHeight * scale);
      return 0;
    }

    case WM_CLOSE:
      // A second click on the close button while the first is still in flight
      // is not a reason to start again.
      if (!closing_) BeginClose(hwnd);
      return 0;

    case WM_TIMER:
      if (wparam == kCloseTimerId) {
        OutputDebugStringW(
            L"prototype: the app did not answer willClose in time — closing\n");
        FinishClose();
        return 0;
      }
      break;
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
