// M209 — a click on a floating window is not a click on the canvas.
//
// "On the freehand spline, when i click finish it sets a last spline point.
// This shouldn't happen."
//
// The modeless windows — Freehand, Gear, Parameters, Text, Pattern, Fillet,
// Polygon — float INSIDE the same Stack that the viewport's raw pointer
// Listener wraps. Flutter delivers a pointer to every target on its hit path,
// so the Listener sees the up over the Finish button as well as the button
// does, and with a tool armed that up is a tool click. Pressing Finish
// therefore committed the curve AND placed one more point of the next one.
//
// M61 already met this, with the Gear window, and fixed it the way one fixes a
// thing once: a hard-coded rectangle test for that one dialog, rebuilt from
// its Positioned offset and a fallback size. Six windows later it is the only
// one guarded, which is how the freehand report happened.
//
// So the windows say where they are, instead of the viewport guessing. Each
// one wraps itself in a [ViewportWindow]; the viewport asks whether a point
// lands on any of them. Nothing to keep in step, and a window added tomorrow
// is covered by wrapping it.
import 'package:flutter/widgets.dart';

/// Wraps a modeless window that floats over the viewport.
class ViewportWindow extends StatefulWidget {
  final Widget child;
  const ViewportWindow({super.key, required this.child});

  static final Set<_ViewportWindowState> _live = <_ViewportWindowState>{};

  /// True when [global] lands on one of the windows currently on screen.
  ///
  /// Global coordinates on purpose: the windows and the viewport share a Stack
  /// today, and a guard that quietly depended on that would be wrong the first
  /// time one of them moved into an Overlay.
  static bool hits(Offset global) {
    for (final w in _live) {
      if (w.containsGlobal(global)) return true;
    }
    return false;
  }

  /// Number of windows on screen. Tests read this; nothing else should.
  static int get count => _live.length;

  @override
  State<ViewportWindow> createState() => _ViewportWindowState();
}

class _ViewportWindowState extends State<ViewportWindow> {
  @override
  void initState() {
    super.initState();
    ViewportWindow._live.add(this);
  }

  @override
  void dispose() {
    ViewportWindow._live.remove(this);
    super.dispose();
  }

  bool containsGlobal(Offset global) {
    if (!mounted) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
