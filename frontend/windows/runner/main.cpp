// Prototype — the Win32 entry point.
//
// Kept as close to `flutter create`'s runner as it can be, so a future Flutter
// upgrade is a diff against a template rather than an archaeology exercise.
// Everything this app adds is marked and explained, here and in
// flutter_window.cpp — the same discipline the GTK runner is written under.
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

// The iPad Pro 13" in landscape, in logical points. Not a round desktop number
// on purpose: every layout constant in this app was chosen against that stage,
// so a window that size is the one place the desktop build is pixel-for-pixel
// the iPad build. It is a DEFAULT — the window is freely resizable and the
// layout is responsive; it is simply where it starts.
constexpr unsigned int kDefaultWidth = 1376;
constexpr unsigned int kDefaultHeight = 1032;

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins. The file dialogs in native_menu are IFileDialog, which is COM,
  // and they run on this thread — so this call is load-bearing rather than
  // boilerplate here.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // FLUTTER GPU, which the 3D viewport is drawn with.
  //
  // Impeller is already the renderer; this is the separate switch that lets
  // Dart reach it directly (flutter_gpu / flutter_scene). It is per-PROJECT on
  // desktop rather than per-platform, so without this line the app builds, the
  // engine starts, and `GpuView.probe()` fails at the first buffer allocation
  // — the viewport then falls back to the CPU painter and says so in the log,
  // which is the one failure mode that looks like a rendering bug rather than
  // a missing flag.
  //
  // The command line has `--enable-flutter-gpu` for `flutter run`, and a
  // RELEASE build compiles the engine's environment switches out, so a shipped
  // build has no way to get this except from here. (linux/runner does the same
  // thing through fl_dart_project_set_enable_flutter_gpu.)
  project.set_enable_flutter_gpu(true);

  // A document double-clicked in Explorer arrives here, as argv[1]. The
  // template already drops argv[0] for us; Dart picks it up in
  // `main(List<String> args)` — see DesktopLaunch in lib/platform/.
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // THE DEFAULT SIZE IS A DEFAULT, not a demand. 1376 x 1032 is taller than a
  // 1366 x 768 laptop's work area, and Win32 — unlike GTK — will happily
  // create a window bigger than the screen and leave the user with a title bar
  // they cannot reach. So it is clamped to what the monitor actually has, and
  // centred in it.
  Win32Window::Size size(kDefaultWidth, kDefaultHeight);
  Win32Window::Point origin(10, 10);
  RECT work_area{};
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0)) {
    // The work area is in PHYSICAL pixels and the size below is logical, so
    // the comparison is only right at 100% scaling. Win32Window::Create scales
    // the size by the monitor's DPI, which is why the margin is generous
    // rather than exact: this is a "does it obviously not fit" guard, not a
    // layout calculation.
    const unsigned int max_w =
        static_cast<unsigned int>(std::max<LONG>(work_area.right - work_area.left, 640));
    const unsigned int max_h =
        static_cast<unsigned int>(std::max<LONG>(work_area.bottom - work_area.top, 480));
    size = Win32Window::Size(std::min(kDefaultWidth, max_w),
                             std::min(kDefaultHeight, max_h));
    origin = Win32Window::Point(
        static_cast<unsigned int>(work_area.left + (max_w - size.width) / 2),
        static_cast<unsigned int>(work_area.top + (max_h - size.height) / 2));
  }

  if (!window.Create(L"Prototype", origin, size)) {
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
