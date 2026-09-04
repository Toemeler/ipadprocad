// Windows only — the window's own titlebar, replacing the standard one.
//
// flutter_window.cpp answers WM_NCCALCSIZE by handing the whole window back
// as client area, so Windows draws no caption at all: no title text, no
// system icon, no min/max/close buttons, no bar. What is left is exactly
// what this file draws — a thin invisible drag strip across the top, with
// three small buttons in the corner it leaves for them — and nothing else,
// which is the point: the app should not have "a top bar like standard
// Windows apps", it should have a full window of its own drawing with just
// enough chrome that the window is still a window.
//
// The drag and the buttons both go through `prototype/desktop`
// (desktop_shell.dart's channel) into flutter_window.cpp's
// HandleDesktopMethodCall: a drag becomes the same WM_NCLBUTTONDOWN a real
// caption would have sent, and close goes through WM_CLOSE — never straight
// to DestroyWindow — so it still runs the willClose save handshake.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The Dart side of the three `prototype/desktop` calls this file's buttons
/// make, plus the drag and the maximized query. Kept beside
/// [DesktopShell]'s existing `willClose` handshake are two ends of the same
/// channel; this is the other direction, Dart calling native.
class WindowChrome {
  WindowChrome._();

  static const MethodChannel _ch = MethodChannel('prototype/desktop');

  static Future<void> minimize() => _ch.invokeMethod('minimizeWindow');
  static Future<void> toggleMaximize() =>
      _ch.invokeMethod('toggleMaximizeWindow');
  static Future<void> close() => _ch.invokeMethod('closeWindow');
  static Future<void> startDrag() => _ch.invokeMethod('startDrag');

  static Future<bool> isMaximized() async {
    final r = await _ch.invokeMethod<bool>('isMaximized');
    return r ?? false;
  }
}

/// True where this bar belongs: Windows only. iOS has its own status bar,
/// macOS its traffic lights, Linux its window manager's decoration — none of
/// those were part of the report and none of them are touched.
bool get windowChromeIsCustom => !kIsWeb && Platform.isWindows;

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

  /// The strip's height. 32 is Windows 11's own caption height at 100%
  /// scaling — tall enough to grab, short enough that it does not read as a
  /// bar.
  static const double height = 32;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar>
    with WidgetsBindingObserver {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A maximize/restore can arrive from Aero Snap, Win+Up/Down, or a
  // double-click on the strip below — every one of those resizes the
  // window, so didChangeMetrics is the one hook that catches all of them
  // without a push channel back from native.
  @override
  void didChangeMetrics() => _refresh();

  Future<void> _refresh() async {
    final m = await WindowChrome.isMaximized();
    if (mounted && m != _maximized) setState(() => _maximized = m);
  }

  Future<void> _toggleMaximize() async {
    await WindowChrome.toggleMaximize();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WindowTitleBar.height,
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => WindowChrome.startDrag(),
            onDoubleTap: _toggleMaximize,
            child: const SizedBox.expand(),
          ),
        ),
        _CaptionButton(
          onTap: WindowChrome.minimize,
          glyph: _paintMinimize,
        ),
        _CaptionButton(
          onTap: _toggleMaximize,
          glyph: _maximized ? _paintRestore : _paintMaximize,
        ),
        _CaptionButton(
          onTap: WindowChrome.close,
          glyph: _paintClose,
          danger: true,
        ),
      ]),
    );
  }
}

void _paintMinimize(Canvas c, Size s, Paint p) {
  final y = s.height / 2;
  c.drawLine(Offset(s.width / 2 - 5, y), Offset(s.width / 2 + 5, y), p);
}

void _paintMaximize(Canvas c, Size s, Paint p) {
  final r = Rect.fromCenter(
      center: s.center(Offset.zero), width: 10, height: 10);
  c.drawRect(r, p);
}

void _paintRestore(Canvas c, Size s, Paint p) {
  // Two offset outlined squares — not a true overlap-and-erase (Windows 11's
  // own glyph clips the back square's corner), just two clearly separate
  // rectangles reading as "restore" at 10x10 px. Close enough at this size
  // to be unmistakable, and it costs no blend-mode layer.
  final centre = s.center(Offset.zero);
  final back = Rect.fromCenter(
      center: centre + const Offset(1.5, -1.5), width: 7, height: 7);
  final front = Rect.fromCenter(
      center: centre + const Offset(-1.5, 1.5), width: 7, height: 7);
  c.drawRect(back, p);
  c.drawRect(front, p);
}

void _paintClose(Canvas c, Size s, Paint p) {
  final centre = s.center(Offset.zero);
  for (final flip in [1.0, -1.0]) {
    c.drawLine(
      centre + Offset(-5, -5 * flip),
      centre + Offset(5, 5 * flip),
      p,
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final Future<void> Function() onTap;
  final void Function(Canvas, Size, Paint) glyph;
  final bool danger;
  const _CaptionButton(
      {required this.onTap, required this.glyph, this.danger = false});

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.danger ? T.err : T.flyHov)
        : Colors.transparent;
    final stroke = _hover && widget.danger ? Colors.white : T.text;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: WindowTitleBar.height,
          color: bg,
          child: CustomPaint(
            painter: _GlyphPainter(widget.glyph, stroke),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final void Function(Canvas, Size, Paint) glyph;
  final Color color;
  const _GlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    glyph(canvas, size, p);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || old.glyph != glyph;
}
