// iPadProCAD — viewport (#viewport / #sketchsvg), 1:1 port + real drawing.
//
// - Renders entities REAL from the QCAD document (geometry query via FFI).
// - Edit mode overlay exactly like the mock: grey X/Y axes + grey center
//   point (NON-interactive raw geometry) with the YELLOW projected center
//   point on top (interactive; click toggles select-blue, like the mock).
// - Input (M5 scope): keyboard + mouse. Touch gestures come later, EXCEPT
//   two-finger trackpad pan and trackpad pinch zoom, which are in this
//   version (PointerPanZoom events).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ffi/qcad_engine.dart';
import '../theme.dart';

class Viewport2D extends StatefulWidget {
  final AppState app;
  const Viewport2D({super.key, required this.app});
  @override
  State<Viewport2D> createState() => _Viewport2DState();
}

class _Viewport2DState extends State<Viewport2D> {
  bool _projCpSelected = false; // mock: click toggles yellow <-> blue
  double _panZoomStartZoom = 1;
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Offset _toWorld(Offset local, Size size) {
    final app = widget.app;
    final c = Offset(size.width / 2, size.height / 2);
    final d = local - c;
    return Offset(app.pan.dx + d.dx / app.zoom, app.pan.dy - d.dy / app.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return LayoutBuilder(builder: (context, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            app.cancelTool();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          // trackpad two-finger pan + pinch zoom (FIRST version requirement)
          onPointerPanZoomStart: (e) => _panZoomStartZoom = app.zoom,
          onPointerPanZoomUpdate: (e) {
            if (e.scale != 1.0) {
              final w = _toWorld(e.localPosition, size);
              app.zoomBy((_panZoomStartZoom * e.scale) / app.zoom,
                  aroundWorld: w);
            }
            if (e.panDelta != Offset.zero) {
              app.panBy(e.panDelta);
            }
          },
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              // mouse wheel / two-finger scroll -> zoom around cursor
              final w = _toWorld(e.localPosition, size);
              app.zoomBy(e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1, aroundWorld: w);
            }
          },
          onPointerHover: (e) {
            if (app.tool != Tool.none) {
              app.setHover(_toWorld(e.localPosition, size));
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              _focus.requestFocus();
              if (app.tool != Tool.none) {
                app.toolClick(_toWorld(d.localPosition, size));
              } else if (app.inEditMode) {
                // only projected (yellow) stuff is interactive
                final cpScreen = _worldToScreen(Offset.zero, size);
                if ((d.localPosition - cpScreen).distance <= 6) {
                  setState(() => _projCpSelected = !_projCpSelected);
                }
              }
            },
            child: MouseRegion(
              cursor: app.tool == Tool.none
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.precise,
              child: CustomPaint(
                size: size,
                painter: _ViewportPainter(
                  app: app,
                  projCpSelected: _projCpSelected,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Offset _worldToScreen(Offset w, Size size) {
    final app = widget.app;
    return Offset(
        size.width / 2 + (w.dx - app.pan.dx) * app.zoom,
        size.height / 2 - (w.dy - app.pan.dy) * app.zoom);
  }
}

class _ViewportPainter extends CustomPainter {
  final AppState app;
  final bool projCpSelected;
  _ViewportPainter({required this.app, required this.projCpSelected});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    final s = app.current;
    Offset map(double x, double y) => Offset(
        size.width / 2 + (x - app.pan.dx) * app.zoom,
        size.height / 2 - (y - app.pan.dy) * app.zoom);

    // ---- edit-mode reference overlay (grey axes + grey CP, pure display) ----
    if (app.inEditMode) {
      final grey = Paint()
        ..color = T.rawGrey
        ..strokeWidth = 1;
      final o = map(0, 0);
      canvas.drawLine(Offset(0, o.dy), Offset(size.width, o.dy), grey);
      canvas.drawLine(Offset(o.dx, 0), Offset(o.dx, size.height), grey);
      canvas.drawCircle(o, 3.2, Paint()..color = T.rawGrey);
    }

    // ---- real entities from the QCAD document ----
    if (s != null) {
      final p = Paint()
        ..color = const Color(0xFFC4C9CE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (final g in s.geometry) {
        paintGeo(canvas, g, map, app.zoom, p);
      }
    }

    // ---- in-progress tool preview (blue, like the accent) ----
    if (app.tool != Tool.none && app.toolPoints.isNotEmpty) {
      final prev = Paint()
        ..color = T.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final pts = app.toolPoints;
      final hov = app.hoverWorld;
      switch (app.tool) {
        case Tool.line:
          if (hov != null) {
            canvas.drawLine(map(pts.last.dx, pts.last.dy),
                map(hov.dx, hov.dy), prev);
          }
          break;
        case Tool.circleCenter:
          if (hov != null) {
            final c = map(pts[0].dx, pts[0].dy);
            canvas.drawCircle(c, (hov - pts[0]).distance * app.zoom, prev);
          }
          break;
        case Tool.rectTwoPoint:
          if (hov != null) {
            final a = map(pts[0].dx, pts[0].dy);
            final b = map(hov.dx, hov.dy);
            canvas.drawRect(Rect.fromPoints(a, b), prev);
          }
          break;
        case Tool.arcThreePoint:
          if (pts.length == 1 && hov != null) {
            canvas.drawLine(
                map(pts[0].dx, pts[0].dy), map(hov.dx, hov.dy), prev);
          } else if (pts.length == 2 && hov != null) {
            final arc = arcFrom3Points(pts[0], pts[1], hov);
            if (arc != null) {
              paintGeo(
                  canvas,
                  Geo(Geo.arc, [
                    arc.$1.dx,
                    arc.$1.dy,
                    arc.$2,
                    arc.$3,
                    arc.$4,
                    arc.$5 ? 1.0 : 0.0
                  ]),
                  map,
                  app.zoom,
                  prev);
            }
          }
          break;
        case Tool.none:
          break;
      }
      // committed picks as blue grips
      for (final pt in pts) {
        final o = map(pt.dx, pt.dy);
        canvas.drawRect(
            Rect.fromCenter(center: o, width: 5, height: 5),
            Paint()..color = T.blue);
      }
    }

    // ---- projected center point (YELLOW, on top, interactive) ----
    if (app.inEditMode) {
      final o = map(0, 0);
      canvas.drawCircle(
          o,
          3.2,
          Paint()
            ..color = projCpSelected ? T.blue : T.projYellow);
      canvas.drawCircle(
          o,
          3.2,
          Paint()
            ..color = T.projYellowEdge
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter old) => true;
}
