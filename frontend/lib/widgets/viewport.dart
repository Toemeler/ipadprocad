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
import '../diag.dart';
import '../log.dart';
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
    _dimCtrl.dispose();
    _dimFocus.dispose();
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
  int _pointers = 0;
  Offset? _clickDown;
  DateTime _clickTime = DateTime.now();

  /// The dimension whose PAINTED label contains [local] (screen coords) —
  /// generous +8px for fingers, topmost (last drawn) wins.
  Constraint? _dimAtScreen(Offset local) {
    final rects = widget.app.dimLabelRects;
    for (final (c, r) in rects.reversed) {
      if (r.inflate(8).contains(local)) return c;
    }
    return null;
  }

  void _handleClick(Offset local, Size size) {
    final app = widget.app;
    if (_inlineDim != null) {
      // Tapping the SAME label again (the second tap of a double tap lands
      // here) keeps the editor open instead of committing it shut — that
      // made "double tap to edit" close the field it had just opened.
      if (_dimAtScreen(local) == _inlineDim) {
        _dimCtrl.selection = TextSelection(
            baseOffset: 0, extentOffset: _dimCtrl.text.length);
        _dimFocus.requestFocus();
        return;
      }
      // clicking anywhere else while the value field is open COMMITS —
      // Inventor keeps the dimension when you click away
      _submitInline();
      return;
    }
    _focus.requestFocus();
    if (app.tool != Tool.none) {
      // Inventor: with the Dimension tool active, clicking an EXISTING
      // dimension's text opens its edit box instead of starting a new pick.
      if (app.tool == Tool.dimension) {
        final dim = _dimAtScreen(local);
        if (dim != null) {
          _editDimValue(dim);
          return;
        }
      }
      app.toolClick(_snapped(_toWorld(local, size)));
      if (app.pendingDim != null) _showDimDialog(app.pendingDim!);
      return;
    }
    if (app.inEditMode) {
      final cpScreen = _worldToScreen(Offset.zero, size);
      if ((local - cpScreen).distance <= 6) {
        setState(() => _projCpSelected = !_projCpSelected);
        return;
      }
    }
    _tapNoTool(local, _toWorld(local, size));
  }

  String _gesture = 'none'; // none|panzoom|grip|box
  double _scaleStartZoom = 1;
  Offset? _boxStartW;

  /// Applies object snapping to a world point and publishes the marker.
  Offset _snapped(Offset w, {Offset? exclude}) {
    final app = widget.app;
    final s = app.current;
    if (s == null) return w;
    // Hidden layers must not attract the cursor either. Snap carries no entity
    // indices, so filtering the list here is safe (grips below are NOT filtered
    // — those carry indices and must stay aligned with the geometry list).
    final visible = [
      for (final g in app.displayGeometry(s)) if (app.geoVisible(g)) g
    ];
    final sn = computeSnap(visible, w, _snapPx / app.zoom,
        ref: app.toolPoints.isNotEmpty ? app.toolPoints.last : null,
        exclude: exclude,
        // Let the cursor snap to the points already placed by the active tool —
        // above all the start point, so a spline/polyline can close on itself.
        extraPoints: app.toolPoints);
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
      // Inventor: fully constrained geometry cannot be dragged by hand. Skip
      // those grips entirely instead of starting a drag that the solver undoes
      // on release (which looked like "the point moves, then snaps back") —
      // the gesture then falls through to box-select and the point stays put.
      // freePoints == null means the analysis has not run yet: allow the drag.
      final free = app.analysis?.freePoints;
      for (final g in gripsOf(s.geometry)) {
        if (g.entity < s.geometry.length &&
            !app.geoEditable(s.geometry[g.entity])) {
          continue; // only the layer being edited has grips
        }
        // Only grips that ARE point refs may be tested against freePoints: a
        // circle's radius grips carry idx 1..4 while the circle owns a single
        // point (the centre), so filtering them here would make circles
        // unresizable. ptCount is the exact boundary.
        final isPoint = g.idx < ptCount(s.geometry[g.entity]);
        if (isPoint && free != null && !free.contains((g.entity, g.idx))) {
          continue;
        }
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
      Log.d('gesture', 'no grip under finger at '
          '(${w.dx.toStringAsFixed(2)},${w.dy.toStringAsFixed(2)}) '
          '-> box select; grips=${gripsOf(s.geometry).length}');
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

  void _tapNoTool(Offset local, Offset w) {
    final app = widget.app;
    // where the label is REALLY painted (dist labels are not at textPos)...
    final dim = _dimAtScreen(local) ??
        // ...with the old anchor test as fallback (e.g. before first paint)
        app.dimensionAt(w, 14 / app.zoom);
    if (dim != null) {
      _editDimValue(dim);
      return;
    }
    app.selectAt(w, 10 / app.zoom);
  }

  Future<void> _showDimDialog(Constraint d) async {
    final app = widget.app;
    if (app.pendingDimRedundant) {
      final driven = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: T.fly,
          title: const Text('Over-constrained',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
          content: const Text(
              'Adding this dimension will over-constrain the sketch. '
              'Keep it as a driven (reference) dimension?',
              style: TextStyle(fontSize: 13, color: T.text)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(fontSize: 12.5, color: T.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Driven',
                    style: TextStyle(fontSize: 12.5, color: T.blue))),
          ],
        ),
      );
      if (!mounted) return;
      if (driven == true) {
        app.confirmDimension(null, driven: true);
      } else {
        app.cancelDimension();
      }
      return;
    }
    _openInlineEditor(d, isNew: true);
  }

  static bool _isAngleKind(Constraint d) =>
      d.dimKind == 'ang' || d.dimKind == 'ang3' || d.dimKind == 'ang4';

  void _editDimValue(Constraint d) => _openInlineEditor(d, isNew: false);

  // ---- inline dimension value editor (Inventor-style) ----
  // A small text field ON the dimension itself: opens right after placing a
  // new dimension and on tapping an existing one; Enter commits, Esc cancels,
  // clicking elsewhere commits (Inventor keeps the dimension either way).
  Constraint? _inlineDim;
  bool _inlineIsNew = false;
  final TextEditingController _dimCtrl = TextEditingController();
  final FocusNode _dimFocus = FocusNode();

  void _openInlineEditor(Constraint d, {required bool isNew}) {
    setState(() {
      _inlineDim = d;
      _inlineIsNew = isNew;
      _dimCtrl.text = _isAngleKind(d)
          ? (d.value ?? 0).toStringAsFixed(1)
          : (d.value ?? 0).toStringAsFixed(2);
      _dimCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _dimCtrl.text.length);
    });
    _dimFocus.requestFocus();
  }

  void _submitInline() {
    final d = _inlineDim;
    if (d == null) return;
    final v = _isAngleKind(d)
        ? double.tryParse(_dimCtrl.text.replaceAll(',', '.'))
        : _parseLengthMm(_dimCtrl.text);
    setState(() => _inlineDim = null);
    if (_inlineIsNew) {
      // an unparseable entry keeps the measured value — the dimension is
      // still created, exactly like clicking away in Inventor
      widget.app.confirmDimension(v ?? d.value);
    } else if (v != null) {
      widget.app.setDimensionValue(d, v);
    }
    _focus.requestFocus();
  }

  void _cancelInline() {
    final d = _inlineDim;
    if (d == null) return;
    setState(() => _inlineDim = null);
    if (_inlineIsNew) widget.app.cancelDimension();
    _focus.requestFocus();
  }

  Widget _inlineEditor(Size size) {
    final d = _inlineDim!;
    final t = d.textPos ?? Offset.zero;
    final sp = _worldToScreen(t, size);
    const w = 96.0, h = 34.0;
    final left = (sp.dx - w / 2).clamp(4.0, size.width - w - 4.0);
    final top = (sp.dy - h / 2).clamp(4.0, size.height - h - 4.0);
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancelInline();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          decoration: BoxDecoration(
            color: T.fly,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: T.blue, width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 6),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          child: TextField(
            controller: _dimCtrl,
            focusNode: _dimFocus,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13, color: T.text),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              suffixText: _isAngleKind(d) ? '\u00b0' : 'mm',
              suffixStyle: const TextStyle(fontSize: 11, color: T.dim),
            ),
            onSubmitted: (_) => _submitInline(),
          ),
        ),
      ),
    );
  }

  /// Value entry dialog. When [length] is true the field accepts a unit
  /// suffix (mm — the default — or cm / m) and the returned value is always
  /// in millimetres, the sketch's base unit.
  /// Parses a length entry into millimetres. Accepts an optional unit suffix:
  /// `mm` (default), `cm` (×10) or `m` (×1000). Returns null if unparseable.
  double? _parseLengthMm(String s) {
    var t = s.trim().toLowerCase().replaceAll(',', '.');
    var factor = 1.0;
    if (t.endsWith('mm')) {
      t = t.substring(0, t.length - 2);
    } else if (t.endsWith('cm')) {
      t = t.substring(0, t.length - 2);
      factor = 10.0;
    } else if (t.endsWith('m')) {
      t = t.substring(0, t.length - 1);
      factor = 1000.0;
    }
    final v = double.tryParse(t.trim());
    return v == null ? null : v * factor;
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
          // ---- shortcuts (M30). Never while the inline dimension editor is
          // typing (its key events bubble up through this ancestor Focus).
          if (event is KeyDownEvent && _inlineDim == null) {
            final k = event.logicalKey;
            final ctrl = HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            if (ctrl && k == LogicalKeyboardKey.keyS) {
              final tab = app.curTab;
              if (tab != null) {
                app.saveSketch(tab).then((ok) =>
                    app.toast(ok ? 'Saved "$tab"' : 'Save failed'));
              }
              return KeyEventResult.handled;
            }
            if (!ctrl && !HardwareKeyboard.instance.isAltPressed) {
              final t = k == LogicalKeyboardKey.keyD
                  ? Tool.dimension
                  : k == LogicalKeyboardKey.keyL
                      ? Tool.line
                      : k == LogicalKeyboardKey.keyC
                          ? Tool.circleCenter
                          : k == LogicalKeyboardKey.keyR
                              ? Tool.rectTwoPoint
                              : null;
              if (t != null) {
                app.selectTool(t); // toasts a hint when not editing a layer
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.keyS) {
                // S: finish editing the current layer — or, outside a layer,
                // start (and enter) a new one
                if (app.inEditMode) {
                  app.finishEdit(save: true);
                } else {
                  app.startNewLayer();
                }
                return KeyEventResult.handled;
              }
            }
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
          // Tool clicks are handled on RAW pointer events, not via
          // GestureDetector.onTap: the ScaleGestureRecognizer (pan/zoom,
          // grips, box select) wins the gesture arena as soon as the finger
          // slides a few pixels, which silently swallowed every tap and made
          // drawing impossible. The Listener sees pointers regardless of the
          // arena.
          onPointerDown: (e) {
            _pointers++;
            if (_pointers > 1) {
              _clickDown = null; // second finger: pan/zoom, never a click
              return;
            }
            _clickDown = e.localPosition;
            _clickTime = DateTime.now();
          },
          onPointerMove: (e) {
            final d = _clickDown;
            if (d != null && (e.localPosition - d).distance > 14) {
              _clickDown = null; // it's a drag
            }
          },
          onPointerCancel: (e) {
            _pointers = (_pointers - 1).clamp(0, 10);
            _clickDown = null;
          },
          onPointerUp: (e) {
            _pointers = (_pointers - 1).clamp(0, 10);
            final d = _clickDown;
            _clickDown = null;
            if (d == null) return;
            if (DateTime.now().difference(_clickTime).inMilliseconds > 700) {
              return;
            }
            if ((e.localPosition - d).distance > 14) return;
            _handleClick(e.localPosition, size);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // one finger: grip drag / box select; two fingers: pan + zoom
            onScaleStart: (d) => _scaleStart(d, size),
            onScaleUpdate: (d) => _scaleUpdate(d, size),
            onScaleEnd: (d) => _scaleEnd(),
            child: MouseRegion(
              cursor: app.tool == Tool.none
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.precise,
              // Clip the painter to the viewport's own box. Without this a
              // panned/zoomed sketch draws past the top and left edges and,
              // because the viewport is painted AFTER the ribbon and model
              // browser in the Column/Row, the stray geometry lands ON TOP of
              // them. Clipping keeps every drawn line inside the canvas.
              child: ClipRect(
                child: Stack(children: [
                  CustomPaint(
                    size: size,
                    painter: _ViewportPainter(
                      app: app,
                      projCpSelected: _projCpSelected,
                    ),
                  ),
                  if (_inlineDim != null) _inlineEditor(size),
                  // Inventor's status readout, bottom right of the graphics
                  // window: "N dimensions needed" while under-constrained,
                  // "Fully Constrained" at DOF 0.
                  if (app.analysis != null &&
                      (app.current?.geometry.isNotEmpty ?? false))
                    Positioned(
                      right: 10,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Text(
                          app.analysis!.dof <= 0
                              ? 'Fully Constrained'
                              : '${app.analysis!.dof} dimensions needed',
                          style: TextStyle(
                            fontSize: 11,
                            color: app.analysis!.dof <= 0
                                ? const Color(0xFFDDE0E3)
                                : const Color(0xFF9EA4AA),
                          ),
                        ),
                      ),
                    ),
                ]),
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

bool _overlayErrorLogged = false;

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
      // Inventor colours each entity by its constraint state: white when fully
      // defined, violet-blue while still under-constrained, blue when selected.
      final whitePaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      // projected geometry (M32) is YELLOW like Inventor's projected loops
      final projPaint = Paint()
        ..color = const Color(0xFFE8C84A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final underPaint = Paint()
        ..color = const Color(0xFF9A8CF5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      // Geometry on a layer you are NOT editing (or a locked layer) is drawn as
      // dim reference while a layer is in edit mode, so the active layer's DOF
      // colours read clearly. Outside edit mode everything keeps its own state.
      final refPaint = Paint()
        ..color = const Color(0xFF5C6066)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final gs = app.displayGeometry(s);
      final hasAnalysis = app.analysis != null;
      // Inventor colours each entity by ITS OWN carrier (confirmed Inventor
      // behaviour): a line goes white as soon as direction + position are
      // fixed, even while its length is still free — the movable endpoint is
      // a separate entity (grips / DOF arrows). Plain polylines are coloured
      // per EDGE, so a rectangle whites up edge by edge like Inventor's four
      // lines instead of all at once when the last vertex locks.
      bool segFull(int i, int seg) =>
          hasAnalysis && app.analysis!.carrierFixed(i, seg);

      // ---- pre-select / pick halo, painted UNDER the geometry so the DOF
      // colour above it stays readable. Inventor highlights whatever the next
      // click would grab, and keeps a tool's picks lit until it finishes.
      final halo = Paint()
        ..color = T.hover
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;
      void haloEdge(int e, int i0) {
        if (e < 0 || e >= gs.length) return;
        final g = gs[e];
        if (g.type != Geo.polyline) return;
        final n = g.data[1].toInt();
        if (n < 2) return;
        final a = getPt(g, i0), b = getPt(g, (i0 + 1) % n);
        canvas.drawLine(map(a.dx, a.dy), map(b.dx, b.dy), halo);
      }

      for (final e in app.conEnts) {
        if (e >= 0 && e < gs.length) {
          paintGeo(canvas, gs[e], map, app.zoom, halo);
        }
      }
      final pickedEdge = app.pickedEdge;
      if (pickedEdge != null) haloEdge(pickedEdge.$1, pickedEdge.$2);
      // edges picked as LINE-like dimension participants (pt+edge, line+edge,
      // edge+edge — M28)
      for (final (ea, _) in app.conEdges) {
        haloEdge(ea.ent, ea.pt);
      }
      // picked POINTS of the constrain/dimension tools (a polyline edge shows
      // as an edge halo above instead of two lone dots)
      if (pickedEdge == null) {
        for (final r in app.conPts) {
          if (r.ent >= gs.length) continue;
          final q = refPt(gs, r); // ent < 0 -> projected CP at the origin
          canvas.drawCircle(map(q.dx, q.dy), 5, halo);
        }
      }

      final he = app.hoverEnt;
      if (he != null && he < gs.length && app.dragGrip == null) {
        if (gs[he].type == Geo.polyline && !gs[he].isSpline) {
          // plain polyline: highlight just the edge under the cursor
          final hv = app.hoverEdge;
          if (hv != null) haloEdge(hv.$1, hv.$2);
        } else {
          // lines, circles, arcs — and spline/ellipse-tagged polylines, whose
          // paintGeo draws the CURVE. Highlighting one control-polygon edge
          // here showed a stray slanted line instead of the ellipse/spline.
          paintGeo(canvas, gs[he], map, app.zoom, halo);
        }
      }

      for (var i = 0; i < gs.length; i++) {
        final reference = app.inEditMode && !app.geoEditable(gs[i]);
        final paint = app.selection.contains(i)
            ? sel
            : reference
                ? refPaint
                : gs[i].isProjection
                    ? projPaint
                    : (segFull(i, 0) ? whitePaint : underPaint);
        // ONE bad entity must not take the whole sketch down with it. A throw
        // in here aborts CustomPainter.paint, so every entity AFTER it stays
        // unpainted — which reads as "all my geometry disappeared". Same for
        // NaN/Inf: Skia drops those paths without a word. Contain both, and say
        // exactly which entity and which numbers did it.
        if (!app.geoVisible(gs[i])) continue; // layer eye is off
        if (!geoFinite(gs[i])) {
          if (Log.every('paint-nonfinite', 500)) {
            Log.e('paint', 'SKIPPING non-finite ${geoStr(i, gs[i])} '
                '(dragging=${app.dragGrip != null})');
          }
          continue;
        }
        try {
          final g0 = gs[i];
          final perEdge = !app.selection.contains(i) &&
              !reference &&
              g0.type == Geo.polyline &&
              !g0.isSpline &&
              g0.data[1].toInt() >= 2;
          if (perEdge) {
            // plain polyline: every edge carries its own constraint state
            final n = g0.data[1].toInt();
            final edges = g0.data[0] != 0 ? n : n - 1;
            for (var seg = 0; seg < edges; seg++) {
              final a = map(g0.data[2 + 2 * seg], g0.data[3 + 2 * seg]);
              final k = (seg + 1) % n;
              final b = map(g0.data[2 + 2 * k], g0.data[3 + 2 * k]);
              canvas.drawLine(a, b, segFull(i, seg) ? whitePaint : underPaint);
            }
          } else {
            paintGeo(canvas, gs[i], map, app.zoom, paint);
          }
          // Inventor shows the CONTROL POLYGON of a CV spline (dashed, with
          // vertex dots) whenever it is selected or hovered — without it the
          // off-curve control points are invisible and the spline feels
          // uneditable. Fit splines don't need it: their points sit ON the
          // curve and get grips like any vertex.
          final g = gs[i];
          if (g.spline == Geo.splineCv &&
              (app.selection.contains(i) || app.hoverEnt == i)) {
            final poly = Paint()
              ..color = const Color(0x88E8C060)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1;
            final n = g.data[1].toInt();
            final closedS = g.data[0] != 0;
            for (var v = 0; v + 1 < n; v++) {
              final a = map(g.data[2 + 2 * v], g.data[3 + 2 * v]);
              final b = map(g.data[4 + 2 * v], g.data[5 + 2 * v]);
              _dashedLine(canvas, a, b, poly);
            }
            if (closedS && n > 2) {
              _dashedLine(
                  canvas,
                  map(g.data[2 + 2 * (n - 1)], g.data[3 + 2 * (n - 1)]),
                  map(g.data[2], g.data[3]),
                  poly);
            }
            final dot = Paint()..color = const Color(0xFFE8C060);
            for (var v = 0; v < n; v++) {
              canvas.drawCircle(
                  map(g.data[2 + 2 * v], g.data[3 + 2 * v]), 3, dot);
            }
          }
        } catch (err, st) {
          if (Log.every('paint-throw', 500)) {
            Log.e('paint', 'paintGeo THREW for ${geoStr(i, gs[i])}', err, st);
          }
        }
      }
      // Degrees-of-freedom glyphs: arrows on every point that can still move
      // (they vanish one by one as constraints are added).
      final an = app.analysis;
      if (app.showDof && app.tool == Tool.none && an != null) {
        final dp = Paint()
          ..color = const Color(0xFFEFD37A)
          ..strokeWidth = 1.2;
        for (final (e, pt) in an.freePoints) {
          if (e >= gs.length || pt >= ptCount(gs[e])) continue;
          final o = map(getPt(gs[e], pt).dx, getPt(gs[e], pt).dy);
          for (final d in const [
            Offset(1, 0),
            Offset(-1, 0),
            Offset(0, 1),
            Offset(0, -1)
          ]) {
            final tip = o + d * 9;
            canvas.drawLine(o + d * 3, tip, dp);
            final n = Offset(-d.dy, d.dx);
            canvas.drawLine(tip, tip - d * 3 + n * 2, dp);
            canvas.drawLine(tip, tip - d * 3 - n * 2, dp);
          }
        }
      }
      // Trim preview: draw the picked entity red, then repaint what survives
      // in the normal colour — the red remainder is exactly what gets cut.
      if (app.tool == Tool.trim && app.hoverWorld != null) {
        final tp = app.trimPreview(app.hoverWorld!);
        if (tp != null) {
          final red = Paint()
            ..color = const Color(0xFFE0554F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4;
          paintGeo(canvas, tp.$1, map, app.zoom, red);
          for (final k in tp.$2) {
            paintGeo(canvas, k, map, app.zoom, p);
          }
        }
      }
      // sketch point grips (Inventor shows them whenever no tool is active)
      if (app.tool == Tool.none) {
        final gp = Paint()..color = const Color(0xFF7BC96A);
        for (final g in gripsOf(gs)) {
          if (g.entity < gs.length && !app.geoEditable(gs[g.entity])) continue;
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
    // Guarded: a painter exception aborts the whole frame, which would look
    // exactly like "the app draws nothing".
    try {
    if (s != null) {
      final gs2 = app.displayGeometry(s);
      if (app.showConstraints) {
        final seen = <String, int>{};
        final shown = [
          for (final c in s.constraints)
            if (app.constraintVisible(s, c)) c
        ];
        for (final (pos, raw) in constraintGlyphs(gs2, shown)) {
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
      app.dimLabelRects.clear();
      for (final c in s.constraints) {
        if (c.type == CType.dimension &&
            c.textPos != null &&
            app.constraintVisible(s, c)) {
          _paintDimension(canvas, gs2, c, map,
              labelSink: app.dimLabelRects);
        }
      }
      // dimension being placed follows the cursor
      final pd = app.pendingDim;
      if (pd != null && pd.textPos != null) {
        _paintDimension(canvas, gs2, pd, map);
      }
      // live preview: once the pick set is chosen, the dimension tracks the
      // cursor until the click that places it (Inventor behaviour).
      if (pd == null && app.hoverWorld != null) {
        final preview = app.dimensionPreview(app.hoverWorld!);
        if (preview != null) _paintDimension(canvas, gs2, preview, map);
      }
    }

    } catch (err, st) {
      if (!_overlayErrorLogged) {
        _overlayErrorLogged = true;
        Log.e('paint', 'constraint/dimension overlay failed', err, st);
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

    // ---- cursor constraint hints (Inventor shows the symbol on the cursor
    // for every constraint it is about to apply automatically) ----
    if (s != null && app.hoverWorld != null) {
      final hints = app.inferredHints(s, app.hoverWorld!);
      if (hints.isNotEmpty) {
        final o = map(app.hoverWorld!.dx, app.hoverWorld!.dy) +
            const Offset(14, 10);
        for (var i = 0; i < hints.length; i++) {
          final tp = TextPainter(
              text: TextSpan(
                  text: constraintLabel(hints[i]),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFFEFD37A))),
              textDirection: TextDirection.ltr)
            ..layout();
          final at = o + Offset(i * 16.0, 0);
          canvas.drawRect(
              Rect.fromLTWH(at.dx - 2, at.dy - 1, tp.width + 4, tp.height + 2),
              Paint()..color = const Color(0xCC333333));
          tp.paint(canvas, at);
        }
      }
    }

    // ---- sketch status: DOF count / Fully Constrained (Inventor status bar)
    if (s != null && app.analysis != null) {
      final an = app.analysis!;
      final txt = an.fullyConstrained
          ? 'Fully Constrained'
          : '${an.dof} degree${an.dof == 1 ? '' : 's'} of freedom';
      final tp = TextPainter(
          text: TextSpan(
              text: txt,
              style: TextStyle(
                  fontSize: 11,
                  color: an.fullyConstrained
                      ? const Color(0xFF66B2A0)
                      : T.dim)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(10, size.height - tp.height - 8));
    }

    // ---- transient notice (over-constrained warnings) ----
    if (app.message != null) {
      final tp = TextPainter(
          text: TextSpan(
              text: app.message!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFF2D6A2))),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 60);
      final box = Rect.fromLTWH((size.width - tp.width) / 2 - 12,
          size.height - tp.height - 44, tp.width + 24, tp.height + 12);
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = const Color(0xE6402F1F));
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()
            ..color = const Color(0xFF8A6A3A)
            ..style = PaintingStyle.stroke);
      tp.paint(canvas, box.topLeft + const Offset(12, 6));
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
    Offset Function(double, double) map,
    {List<(Constraint, Rect)>? labelSink}) {
  final p = Paint()
    ..color = const Color(0xFFB8C4A8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  String label;
  final v = c.value ?? measureDim(gs, c);
  Offset t = map(c.textPos!.dx, c.textPos!.dy);
  switch (c.dimKind) {
    case 'dist':
    case 'distx':
    case 'disty':
      // q.ent < 0 is the projected center point (origin) — a legal ref
      if (c.pts.length < 2 || c.pts.any((q) => q.ent >= gs.length)) return;
      final a = refPt(gs, c.pts[0]);
      final b = refPt(gs, c.pts[1]);
      final sa = map(a.dx, a.dy), sb = map(b.dx, b.dy);
      // measuring direction: along the geometry (aligned), or along the
      // screen axes for the horizontal/vertical distance variants
      final Offset dir = c.dimKind == 'distx'
          ? const Offset(1, 0)
          : c.dimKind == 'disty'
              ? const Offset(0, 1)
              : (sb - sa);
      if (dir.distance < 1e-6) return;
      final n = Offset(-dir.dy, dir.dx) / dir.distance;
      // offset of the dim line = projection of textPos on the normal
      // project both points onto the dimension line through the text pos
      final u = dir / dir.distance;
      Offset onLine(Offset q) {
        final rel = q - t;
        return t + u * (rel.dx * u.dx + rel.dy * u.dy);
      }

      final da = onLine(sa), db = onLine(sb);
      final off = ((t - sa).dx * n.dx + (t - sa).dy * n.dy);
      canvas.drawLine(sa, da, p); // extension lines
      canvas.drawLine(sb, db, p);
      canvas.drawLine(da, db, p); // dimension line
      _arrow(canvas, da, u, p);
      _arrow(canvas, db, -u, p);
      label = '${v.toStringAsFixed(2)} mm';
      if (c.driven) label = '($label)';
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
      label = (c.dimKind == 'rad' ? 'R' : '⌀') +
          '${v.toStringAsFixed(2)} mm';
      if (c.driven) label = '($label)';
      break;
    case 'pline':
      // pts = [point, line A, line B]: perpendicular distance to the line.
      // Render as a linear dimension between the point and its foot on the
      // (extended) line; witness the extension with a dashed overshoot when
      // the foot falls outside the picked segment (Inventor does the same).
      if (c.pts.length < 3 || c.pts.any((q) => q.ent >= gs.length)) {
        return;
      }
      final pw = refPt(gs, c.pts[0]);
      final aw = refPt(gs, c.pts[1]);
      final bw = refPt(gs, c.pts[2]);
      final dl = bw - aw;
      final len2 = dl.dx * dl.dx + dl.dy * dl.dy;
      if (len2 < 1e-18) return;
      final tt = ((pw - aw).dx * dl.dx + (pw - aw).dy * dl.dy) / len2;
      final fw = aw + dl * tt; // foot of the perpendicular (world)
      final sp = map(pw.dx, pw.dy), sf = map(fw.dx, fw.dy);
      if (tt < 0 || tt > 1) {
        // dashed extension from the nearer segment end to the foot
        final endW = tt < 0 ? aw : bw;
        final se = map(endW.dx, endW.dy);
        _dashedLine(canvas, se, sf, p);
      }
      final dirP = sp - sf;
      if (dirP.distance < 1e-6) return;
      final uP = dirP / dirP.distance;
      final nP = Offset(-uP.dy, uP.dx);
      Offset onLineP(Offset q) {
        final rel = q - t;
        return t + uP * (rel.dx * uP.dx + rel.dy * uP.dy);
      }

      final dp = onLineP(sp), df = onLineP(sf);
      final offP = ((t - sp).dx * nP.dx + (t - sp).dy * nP.dy);
      canvas.drawLine(sp, dp, p); // extension lines
      canvas.drawLine(sf, df, p);
      canvas.drawLine(dp, df, p); // dimension line
      _arrow(canvas, dp, uP, p);
      _arrow(canvas, df, -uP, p);
      label = '${v.toStringAsFixed(2)} mm';
      if (c.driven) label = '($label)';
      t = (dp + df) / 2 + nP * (offP >= 0 ? 10 : -10);
      break;
    case 'ang':
      if (c.ents.length < 2 ||
          c.ents.any((e) => e >= gs.length || gs[e].type != Geo.line)) {
        return;
      }
      // arc between the two lines, centered on their intersection, through
      // the text position (Inventor's look); skip the arc when parallel
      final l1a = getPt(gs[c.ents[0]], 0), l1b = getPt(gs[c.ents[0]], 1);
      final l2a = getPt(gs[c.ents[1]], 0), l2b = getPt(gs[c.ents[1]], 1);
      final ix = _lineIntersect(l1a, l1b, l2a, l2b);
      if (ix != null) {
        _angleArc(canvas, map, ix, t, v, p);
      }
      label = '${v.toStringAsFixed(1)}\u00b0';
      if (c.driven) label = '($label)';
      break;
    case 'ang3':
      // pts = [ray end, VERTEX, ray end]
      if (c.pts.length < 3 || c.pts.any((q) => q.ent >= gs.length)) {
        return;
      }
      final vtx = refPt(gs, c.pts[1]);
      final ra = refPt(gs, c.pts[0]);
      final rb = refPt(gs, c.pts[2]);
      final sv = map(vtx.dx, vtx.dy);
      final sa2 = map(ra.dx, ra.dy), sb2 = map(rb.dx, rb.dy);
      final rr = (t - sv).distance;
      if (rr > 1e-6) {
        final a0 = math.atan2((sa2 - sv).dy, (sa2 - sv).dx);
        final a1 = math.atan2((sb2 - sv).dy, (sb2 - sv).dx);
        var sweep = a1 - a0;
        while (sweep <= -math.pi) sweep += 2 * math.pi;
        while (sweep > math.pi) sweep -= 2 * math.pi;
        canvas.drawArc(Rect.fromCircle(center: sv, radius: rr), a0, sweep,
            false, p);
        // dashed ray extensions out to the arc radius
        _dashedLine(canvas, sv, sv + (sa2 - sv) / (sa2 - sv).distance * rr, p);
        _dashedLine(canvas, sv, sv + (sb2 - sv) / (sb2 - sv).distance * rr, p);
      }
      label = '${v.toStringAsFixed(1)}\u00b0';
      if (c.driven) label = '($label)';
      break;
    case 'ang4':
      // pts = [a1, a2, b1, b2] — angle between two edges/lines over points;
      // arc centered on the INTERSECTION of the infinite carriers, Inventor's
      // look for a line-line angle, drawn through the text position.
      if (c.pts.length < 4 || c.pts.any((q) => q.ent >= gs.length)) {
        return;
      }
      final qa1 = refPt(gs, c.pts[0]), qa2 = refPt(gs, c.pts[1]);
      final qb1 = refPt(gs, c.pts[2]), qb2 = refPt(gs, c.pts[3]);
      final ix4 = _lineIntersect(qa1, qa2, qb1, qb2);
      if (ix4 != null) {
        _angleArc(canvas, map, ix4, t, v, p);
      }
      label = '${v.toStringAsFixed(1)}\u00b0';
      if (c.driven) label = '($label)';
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
  // The SCREEN rect the label really occupies — for 'dist' kinds t is
  // recomputed above and does NOT sit at textPos, so tap hit-testing must use
  // this, not the anchor (that mismatch made dimensions nearly untappable).
  labelSink?.add((c, bg));
}

/// Intersection of the infinite lines a1-a2 and b1-b2 (world coords), or
/// null when (near-)parallel.
Offset? _lineIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
  final d1 = a2 - a1, d2 = b2 - b1;
  final den = d1.dx * d2.dy - d1.dy * d2.dx;
  if (den.abs() < 1e-12) return null;
  final t = ((b1 - a1).dx * d2.dy - (b1 - a1).dy * d2.dx) / den;
  return a1 + d1 * t;
}

/// Angle-dimension arc: centered on the vertex [vtxWorld], radius chosen so
/// the arc passes near the label position [t] (screen), sweeping [deg].
void _angleArc(Canvas canvas, Offset Function(double, double) map,
    Offset vtxWorld, Offset t, double deg, Paint p) {
  final sv = map(vtxWorld.dx, vtxWorld.dy);
  final rr = (t - sv).distance;
  if (rr < 1e-6) return;
  final mid = math.atan2((t - sv).dy, (t - sv).dx);
  final half = deg * math.pi / 360; // deg/2 in radians
  canvas.drawArc(
      Rect.fromCircle(center: sv, radius: rr), mid - half, 2 * half, false, p);
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
