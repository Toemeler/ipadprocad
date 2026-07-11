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
import '../constraints.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../snap.dart';
import '../tools.dart';
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

  // ---- snapping + gestures (M6) ----
  static const _snapPx = 12.0, _gripPx = 12.0;
  String _gesture = 'none'; // none|panzoom|grip|box
  double _scaleStartZoom = 1;
  Offset? _boxStartW;

  /// Applies object snapping to a world point and publishes the marker.
  Offset _snapped(Offset w, {Offset? exclude}) {
    final app = widget.app;
    final s = app.current;
    if (s == null) return w;
    final sn = computeSnap(app.displayGeometry(s), w, _snapPx / app.zoom,
        ref: app.toolPoints.isNotEmpty ? app.toolPoints.last : null,
        exclude: exclude);
    app.setSnap(sn);
    return sn?.pos ?? w;
  }

  void _scaleStart(ScaleStartDetails d, Size size) {
    final app = widget.app;
    _scaleStartZoom = app.zoom;
    if (d.pointerCount >= 2) {
      _gesture = 'panzoom';
      return;
    }
    if (app.tool != Tool.none) {
      _gesture = 'none'; // tools are click-driven
      return;
    }
    final w = _toWorld(d.localFocalPoint, size);
    // grip under the finger?
    final s = app.current;
    if (s != null) {
      Grip? hit;
      var bd = _gripPx / app.zoom;
      for (final g in gripsOf(s.geometry)) {
        final dd = (g.pos - w).distance;
        if (dd < bd) {
          bd = dd;
          hit = g;
        }
      }
      if (hit != null) {
        _gesture = 'grip';
        app.beginGripDrag(hit);
        return;
      }
    }
    _gesture = 'box';
    _boxStartW = w;
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
    final app = widget.app;
    if (d.pointerCount >= 2 && _gesture != 'panzoom') {
      // second finger arrived: abort grip/box, switch to pan/zoom
      if (_gesture == 'grip') app.endGripDrag();
      if (_gesture == 'box') app.boxSelectFinish();
      _gesture = 'panzoom';
    }
    switch (_gesture) {
      case 'panzoom':
        if (d.scale != 1.0) {
          final w = _toWorld(d.localFocalPoint, size);
          app.zoomBy((_scaleStartZoom * d.scale) / app.zoom, aroundWorld: w);
        }
        app.panBy(d.focalPointDelta);
        break;
      case 'grip':
        final w = _toWorld(d.localFocalPoint, size);
        app.updateGripDrag(
            _snapped(w, exclude: app.dragGrip?.pos));
        break;
      case 'box':
        app.boxSelectUpdate(_boxStartW!, _toWorld(d.localFocalPoint, size));
        break;
    }
  }

  void _tapNoTool(Offset w) {
    final app = widget.app;
    final dim = app.dimensionAt(w, 14 / app.zoom);
    if (dim != null) {
      _editDimValue(dim);
      return;
    }
    app.selectAt(w, 10 / app.zoom);
  }

  Future<void> _showDimDialog(Constraint d) async {
    final v = await _askValue(
        d.dimKind == 'ang' ? 'Angle (deg)' : 'Dimension',
        d.value ?? 0);
    if (!mounted) return;
    if (v == null) {
      widget.app.cancelDimension();
    } else {
      widget.app.confirmDimension(v);
    }
  }

  Future<void> _editDimValue(Constraint d) async {
    final v = await _askValue(
        d.dimKind == 'ang' ? 'Angle (deg)' : 'Dimension', d.value ?? 0);
    if (v != null && mounted) widget.app.setDimensionValue(d, v);
  }

  Future<double?> _askValue(String title, double current) async {
    final c = TextEditingController(text: current.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.fly,
        title: Text(title,
            style: const TextStyle(
                fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13, color: T.text),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 12.5, color: T.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK',
                  style: TextStyle(fontSize: 12.5, color: T.blue))),
        ],
      ),
    );
    if (ok != true) return null;
    return double.tryParse(c.text.replaceAll(',', '.'));
  }

  void _scaleEnd() {
    final app = widget.app;
    switch (_gesture) {
      case 'grip':
        app.endGripDrag();
        break;
      case 'box':
        app.boxSelectFinish();
        break;
    }
    _gesture = 'none';
    _boxStartW = null;
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
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
            app.finishVariableTool();
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
              final w = _toWorld(e.localPosition, size);
              app.setHover(_snapped(w));
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // one finger: grip drag / box select; two fingers: pan + zoom
            onScaleStart: (d) => _scaleStart(d, size),
            onScaleUpdate: (d) => _scaleUpdate(d, size),
            onScaleEnd: (d) => _scaleEnd(),
            onTapUp: (d) {
              _focus.requestFocus();
              if (app.tool != Tool.none) {
                app.toolClick(_snapped(_toWorld(d.localPosition, size)));
                if (app.pendingDim != null) _showDimDialog(app.pendingDim!);
              } else if (app.inEditMode) {
                // only projected (yellow) stuff is interactive
                final cpScreen = _worldToScreen(Offset.zero, size);
                if ((d.localPosition - cpScreen).distance <= 6) {
                  setState(() => _projCpSelected = !_projCpSelected);
                } else {
                  _tapNoTool(_toWorld(d.localPosition, size));
                }
              } else {
                _tapNoTool(_toWorld(d.localPosition, size));
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
      final sel = Paint()
        ..color = T.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      final gs = app.displayGeometry(s);
      for (var i = 0; i < gs.length; i++) {
        paintGeo(canvas, gs[i], map, app.zoom,
            app.selection.contains(i) ? sel : p);
      }
      // sketch point grips (Inventor shows them whenever no tool is active)
      if (app.tool == Tool.none) {
        final gp = Paint()..color = const Color(0xFF7BC96A);
        for (final g in gripsOf(gs)) {
          final o = map(g.pos.dx, g.pos.dy);
          canvas.drawRect(
              Rect.fromCenter(center: o, width: 4, height: 4), gp);
        }
        if (app.dragGrip != null && app.dragPos != null) {
          final o = map(app.dragPos!.dx, app.dragPos!.dy);
          canvas.drawRect(Rect.fromCenter(center: o, width: 7, height: 7),
              Paint()..color = const Color(0xFFE05555));
        }
      }
    }

    // ---- in-progress tool preview (blue, like the accent) ----
    if (app.tool != Tool.none &&
        (app.toolPoints.isNotEmpty || app.hoverWorld != null)) {
      final prev = Paint()
        ..color = T.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final pts = app.toolPoints;
      final hov = app.hoverWorld;
      // ONE source of truth: preview = the exact geometry the commit would
      // produce with the hover point appended.
      final probe = [...pts, if (hov != null) hov];
      final s2 = app.current;
      final geos = s2 == null
          ? null
          : buildToolGeometry(app.tool, probe,
              existing: app.displayGeometry(s2),
              params: app.toolParams,
              expr: app.toolExpr);
      if (geos != null) {
        for (final g in geos) {
          paintGeo(canvas, g, map, app.zoom, prev);
        }
      } else if (hov != null && pts.isNotEmpty) {
        // not enough points yet: rubber line from the last pick
        canvas.drawLine(
            map(pts.last.dx, pts.last.dy), map(hov.dx, hov.dy), prev);
      }
      // committed picks as blue grips
      for (final pt in pts) {
        final o = map(pt.dx, pt.dy);
        canvas.drawRect(
            Rect.fromCenter(center: o, width: 5, height: 5),
            Paint()..color = T.blue);
      }
    }

    // ---- constraint glyphs + dimensions (M7) ----
    if (s != null) {
      final gs2 = app.displayGeometry(s);
      if (app.showConstraints) {
        final seen = <String, int>{};
        for (final (pos, raw) in constraintGlyphs(gs2, s.constraints)) {
          final label = raw.split('#').first;
          final key = '${pos.dx.toStringAsFixed(2)},${pos.dy.toStringAsFixed(2)}';
          final slot = seen[key] = (seen[key] ?? 0) + 1;
          final o = map(pos.dx, pos.dy) + Offset(8.0 + 15.0 * (slot - 1), -12);
          final tp = TextPainter(
              text: TextSpan(
                  text: label,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFFEFD37A))),
              textDirection: TextDirection.ltr)
            ..layout();
          canvas.drawRect(
              Rect.fromLTWH(o.dx - 2, o.dy - 1, tp.width + 4, tp.height + 2),
              Paint()..color = const Color(0xB2333333));
          tp.paint(canvas, o);
        }
      }
      for (final c in s.constraints) {
        if (c.type == CType.dimension && c.textPos != null) {
          _paintDimension(canvas, gs2, c, map);
        }
      }
      // dimension being placed follows the cursor
      final pd = app.pendingDim;
      if (pd != null && pd.textPos != null) {
        _paintDimension(canvas, gs2, pd, map);
      }
    }

    // ---- modify-tool ghost preview (dashed look via lighter blue) ----
    if (app.hoverWorld != null && s != null) {
      final ghost = app.modifyGhost(s, app.hoverWorld!);
      if (ghost.isNotEmpty) {
        final gp = Paint()
          ..color = T.blue.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final g in ghost) {
          paintGeo(canvas, g, map, app.zoom, gp);
        }
      }
    }

    // ---- snap marker + alignment guides (Inventor green) ----
    final sn = app.snap;
    if (sn != null && (app.tool != Tool.none || app.dragGrip != null)) {
      const green = Color(0xFF58C05C);
      final o = map(sn.pos.dx, sn.pos.dy);
      final mp = Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      switch (sn.kind) {
        case 'endpoint':
        case 'vertex':
          canvas.drawRect(
              Rect.fromCenter(center: o, width: 9, height: 9), mp);
          break;
        case 'midpoint':
          final path = Path()
            ..moveTo(o.dx, o.dy - 5)
            ..lineTo(o.dx - 5, o.dy + 4)
            ..lineTo(o.dx + 5, o.dy + 4)
            ..close();
          canvas.drawPath(path, mp);
          break;
        case 'center':
        case 'origin':
          canvas.drawCircle(o, 4.5, mp);
          break;
        case 'quadrant':
          final path = Path()
            ..moveTo(o.dx, o.dy - 5.5)
            ..lineTo(o.dx + 5.5, o.dy)
            ..lineTo(o.dx, o.dy + 5.5)
            ..lineTo(o.dx - 5.5, o.dy)
            ..close();
          canvas.drawPath(path, mp);
          break;
        case 'on':
          canvas.drawLine(o + const Offset(-4, -4), o + const Offset(4, 4), mp);
          canvas.drawLine(o + const Offset(-4, 4), o + const Offset(4, -4), mp);
          break;
        case 'align':
          canvas.drawCircle(o, 2.5, Paint()..color = green);
          break;
      }
      for (final a in sn.alignRefs) {
        _dashedLine(canvas, map(a.dx, a.dy), o,
            Paint()
              ..color = green.withOpacity(0.85)
              ..strokeWidth = 1);
      }
    }

    // ---- box select rectangle (window = solid blue, crossing = dashed
    // green — exactly Inventor's two modes) ----
    if (app.boxStart != null && app.boxEnd != null) {
      final r = Rect.fromPoints(map(app.boxStart!.dx, app.boxStart!.dy),
          map(app.boxEnd!.dx, app.boxEnd!.dy));
      if (app.boxCrossing) {
        canvas.drawRect(r, Paint()..color = const Color(0x2E58C05C));
        _dashedRect(canvas, r,
            Paint()
              ..color = const Color(0xFF58C05C)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      } else {
        canvas.drawRect(r, Paint()..color = const Color(0x2E3D9BE9));
        canvas.drawRect(
            r,
            Paint()
              ..color = T.blue
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
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

void _paintDimension(Canvas canvas, List<Geo> gs, Constraint c,
    Offset Function(double, double) map) {
  final p = Paint()
    ..color = const Color(0xFFB8C4A8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  String label;
  final v = c.value ?? measureDim(gs, c);
  Offset t = map(c.textPos!.dx, c.textPos!.dy);
  switch (c.dimKind) {
    case 'dist':
      if (c.pts.length < 2 ||
          c.pts.any((q) => q.ent >= gs.length)) return;
      final a = getPt(gs[c.pts[0].ent], c.pts[0].pt);
      final b = getPt(gs[c.pts[1].ent], c.pts[1].pt);
      final sa = map(a.dx, a.dy), sb = map(b.dx, b.dy);
      final dir = sb - sa;
      if (dir.distance < 1e-6) return;
      final n = Offset(-dir.dy, dir.dx) / dir.distance;
      // offset of the dim line = projection of textPos on the normal
      final off = ((t - sa).dx * n.dx + (t - sa).dy * n.dy);
      final da = sa + n * off, db = sb + n * off;
      canvas.drawLine(sa, da, p); // extension lines
      canvas.drawLine(sb, db, p);
      canvas.drawLine(da, db, p); // dimension line
      _arrow(canvas, da, dir / dir.distance, p);
      _arrow(canvas, db, -dir / dir.distance, p);
      label = v.toStringAsFixed(2);
      t = (da + db) / 2 + n * (off >= 0 ? 10 : -10);
      break;
    case 'rad':
    case 'dia':
      if (c.ents.isEmpty || c.ents[0] >= gs.length) return;
      final g = gs[c.ents[0]];
      final ce = map(g.data[0], g.data[1]);
      final d = t - ce;
      if (d.distance < 1e-6) return;
      canvas.drawLine(ce, t, p);
      label = (c.dimKind == 'rad' ? 'R' : '\u2300') + v.toStringAsFixed(2);
      break;
    case 'ang':
      if (c.ents.length < 2 ||
          c.ents.any((e) => e >= gs.length || gs[e].type != Geo.line)) {
        return;
      }
      label = '${v.toStringAsFixed(1)}\u00b0';
      break;
    default:
      return;
  }
  final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 11, color: Color(0xFFDDE6CF))),
      textDirection: TextDirection.ltr)
    ..layout();
  final bg = Rect.fromCenter(
      center: t, width: tp.width + 6, height: tp.height + 3);
  canvas.drawRect(bg, Paint()..color = const Color(0xCC212830));
  tp.paint(canvas, bg.topLeft + const Offset(3, 1.5));
}

void _arrow(Canvas c, Offset tip, Offset dir, Paint p) {
  final n = Offset(-dir.dy, dir.dx);
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + dir.dx * 8 + n.dx * 2.6, tip.dy + dir.dy * 8 + n.dy * 2.6)
    ..lineTo(tip.dx + dir.dx * 8 - n.dx * 2.6, tip.dy + dir.dy * 8 - n.dy * 2.6)
    ..close();
  c.drawPath(path, Paint()..color = p.color);
}

void _dashedLine(Canvas c, Offset a, Offset b, Paint p,
    {double dash = 5, double gap = 4}) {
  final d = b - a;
  final len = d.distance;
  if (len < 1e-6) return;
  final dir = d / len;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + dash, len);
    c.drawLine(a + dir * t, a + dir * e, p);
    t = e + gap;
  }
}

void _dashedRect(Canvas c, Rect r, Paint p) {
  _dashedLine(c, r.topLeft, r.topRight, p);
  _dashedLine(c, r.topRight, r.bottomRight, p);
  _dashedLine(c, r.bottomRight, r.bottomLeft, p);
  _dashedLine(c, r.bottomLeft, r.topLeft, p);
}
