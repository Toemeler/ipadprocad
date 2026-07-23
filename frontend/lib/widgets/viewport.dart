// iPadProCAD — viewport (#viewport / #sketchsvg), 1:1 port + real drawing.
//
// - Renders entities REAL from the QCAD document (geometry query via FFI).
// - Edit mode overlay exactly like the mock: grey X/Y axes + grey center
//   point (NON-interactive raw geometry) with the YELLOW projected center
//   point on top (interactive; click toggles select-blue, like the mock).
// - Input: keyboard + mouse + trackpad (two-finger pan, pinch zoom, wheel —
//   PointerPanZoom/Scroll events, untouched since M5) AND, since M51, full
//   Apple-Pencil + touch: the Pencil behaves exactly like the mouse (draw,
//   pick, drag, hover-snap on M2/Pro Pencils), fingers navigate (1-finger
//   pan on empty canvas, 2-finger pan/pinch) and operate with fat-finger
//   tolerances (grips/snap/picks at ~1.8x), two-finger tap = UNDO and
//   three-finger tap = REDO (Procreate), long-press = the right-click role
//   (cycle Split/Trim/Extend; OK/Cancel menu inside a tool), and touches are
//   ignored while the Pencil is down (palm rejection).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../gear.dart';
import '../diag.dart';
import '../log.dart';
import '../constraints.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../part_model.dart' show ChildSketch, sketchFrameOf;
import '../part_render.dart' show paintPartUnderlay;
import 'package:native_menu/native_menu.dart';

import '../snap.dart';
import '../tools.dart';
import '../theme.dart';
import '../touch.dart';
import 'pattern_dialog.dart';
import 'parameters_dialog.dart';
import 'gear_dialog.dart';
import 'text_editor_window.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../inserts.dart';

/// M45 — measures a rendered string into world-mm (width,height) for a text's
/// font and cap height. Single source of truth for the bounding rect and its
/// snap points; used by both the widget (snapping) and the painter (drawing).
/// Cap height maps to font size 1:1 (mm == logical px in world space).
Size measureSketchText(SketchText t, String rendered) {
  final tp = TextPainter(
      text: TextSpan(
          text: rendered.isEmpty ? ' ' : rendered,
          style: TextStyle(fontFamily: t.font, fontSize: t.height)),
      textDirection: TextDirection.ltr)
    ..layout();
  return Size(tp.width, tp.height);
}

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
  void initState() {
    super.initState();
    // M53 — Apple Pencil hardware gestures (UIPencilInteraction, forwarded
    // by the native_menu plugin). Both respect the user's system setting:
    // the plugin only reports a double-tap when iOS says the app may act.
    NativeMenu.setPencilHandler((event, x, y) {
      if (!mounted) return;
      if (event == 'squeeze') {
        _pencilSqueeze(x, y);
      } else if (event == 'tap') {
        _pencilDoubleTap();
      }
    });
  }

  @override
  void dispose() {
    _lpTimer?.cancel();
    _toolCtx?.remove();
    NativeMenu.setPencilHandler(null);
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

  /// M51 — device kind of the pointer that armed [_clickDown]; picks and
  /// snaps widen for fingers (see touch.dart) and stay precise for the
  /// Pencil and the mouse.
  PointerDeviceKind _downKind = PointerDeviceKind.mouse;

  /// M51 — every live pointer's kind. Feeds palm rejection (touches are
  /// rejected while a stylus is down) and lets _scaleStart know whether the
  /// single dragging pointer is a finger.
  final Map<int, PointerDeviceKind> _kinds = {};

  /// Touch pointers rejected as palm contact (arrived while the Pencil was
  /// down). They never count as clicks, taps or gesture fingers.
  final Set<int> _rejectedTouches = {};
  bool get _stylusDown => _kinds.values.any((k) =>
      k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus);

  /// M51 — Procreate taps: two fingers = undo, three = redo.
  final MultiFingerTap _mft = MultiFingerTap();

  /// M51 — long-press = the right-click role for Pencil and finger. Armed on
  /// down, cancelled by movement (>10 px), lift, or a second pointer.
  Timer? _lpTimer;
  Offset? _lpDown;
  bool _lpFired = false;
  OverlayEntry? _toolCtx; // long-press OK/Cancel menu inside an active tool
  /// M42-Fix: the dimension label under the pointer AT DOWN time. Tapping
  /// outside the inline editor unfocuses the TextField on pointer DOWN,
  /// which (with the keyboard dismiss) could relayout the canvas before
  /// pointer UP — hit-testing at up-time then missed the label the user
  /// visibly tapped. The down-time hit is authoritative for the click.
  Constraint? _downDimHit;
  DateTime _clickTime = DateTime.now();

  /// The dimension whose PAINTED label contains [local] (screen coords) —
  /// +8px for the mouse/Pencil, +16px for fingers, topmost (last drawn) wins.
  Constraint? _dimAtScreen(Offset local, {double inflate = 8}) {
    final rects = widget.app.dimLabelRects;
    for (final (c, r) in rects.reversed) {
      if (r.inflate(inflate).contains(local)) return c;
    }
    return null;
  }

  void _handleClick(Offset local, Size size,
      {Constraint? downDim, PointerDeviceKind kind = PointerDeviceKind.mouse}) {
    final app = widget.app;
    // The Gear dialog floats INSIDE the same Stack that this Listener wraps, so
    // the Listener sees pointer-ups over it too. Without this guard, tapping a
    // dialog field would fall through to the Gear tool and place a gear. Ignore
    // any click whose position is inside the dialog's rectangle. (`local` and
    // the dialog's Positioned left/top share this Stack's coordinate space.)
    if (app.gear != null) {
      final gl = _gearPos.dx.clamp(0.0, size.width - 120);
      final gt = _gearPos.dy.clamp(0.0, size.height - 60);
      final box = _gearDialogKey.currentContext?.findRenderObject();
      final dsize = box is RenderBox ? box.size : const Size(300, 560);
      if (Rect.fromLTWH(gl, gt, dsize.width, dsize.height).contains(local)) {
        return;
      }
    }
    // M43/M45: while a Parameters equation cell OR the text editor's template
    // field is focused, tapping a dimension label inserts its parameter name
    // there (the text window wraps it in quotes) instead of doing anything
    // else in the sketch.
    if ((app.paramRefSink != null || app.textRefSink != null) &&
        _inlineDim == null) {
      final hit = downDim ?? _dimAtScreen(local, inflate: touchSlop(kind, 8));
      if (hit != null) {
        final s = app.current;
        if (s != null) {
          final name = app.ensureParamName(s, hit);
          (app.paramRefSink ?? app.textRefSink)!(name);
        }
        return;
      }
    }
    if (_inlineDim != null) {
      // Tapping the SAME label again (the second tap of a double tap lands
      // here) keeps the editor open instead of committing it shut — that
      // made "double tap to edit" close the field it had just opened.
      // Prefer the DOWN-time hit (see _downDimHit) over re-testing at up.
      final hit = downDim ?? _dimAtScreen(local, inflate: touchSlop(kind, 8));
      if (hit == _inlineDim) {
        _dimCtrl.selection =
            TextSelection(baseOffset: 0, extentOffset: _dimCtrl.text.length);
        _dimFocus.requestFocus();
        return;
      }
      // M41: tapping ANOTHER dimension inserts its parameter name at the
      // cursor (Inventor's click-to-reference) — the editor stays open.
      if (hit != null) {
        _insertParamRef(hit);
        return;
      }
      // clicking anywhere else while the value field is open COMMITS —
      // Inventor keeps the dimension when you click away
      _submitInline(clickAway: true);
      return;
    }
    _focus.requestFocus();
    // M44: the Text tool places parametric text where you tap.
    if (app.tool == Tool.text) {
      final w = _toWorld(local, size);
      _openTextEditor(pos: w);
      return;
    }
    if (app.tool != Tool.none) {
      // Inventor: with the Dimension tool active, clicking an EXISTING
      // dimension's text opens its edit box instead of starting a new pick.
      if (app.tool == Tool.dimension) {
        final dim = downDim ?? _dimAtScreen(local, inflate: touchSlop(kind, 8));
        if (dim != null) {
          _editDimValue(dim);
          return;
        }
      }
      app.toolClick(
          _snapped(_toWorld(local, size), px: touchSlop(kind, _snapPx)));
      if (app.pendingDim != null) _showDimDialog(app.pendingDim!);
      return;
    }
    if (app.inEditMode) {
      // M44: tap a text -> edit dialog; tap an image -> select (the selected
      // image shows a resize grip bottom-right and a delete X top-right).
      final tHit = _textAtScreen(local);
      if (tHit != null) {
        _openTextEditor(existing: tHit);
        return;
      }
      final w0 = _toWorld(local, size);
      final sel = _selImage;
      if (sel != null &&
          app.current?.images.contains(sel) == true &&
          (!app.inEditMode || sel.layer == app.editingLayer)) {
        final tr =
            _worldToScreen(Offset(sel.x + sel.w / 2, sel.y + sel.h / 2), size);
        if ((local - tr).distance < touchSlop(kind, 14)) {
          app.deleteImage(sel);
          setState(() => _selImage = null);
          return;
        }
      }
      final iHit = _imageAtWorld(w0);
      if (!identical(iHit, _selImage)) {
        setState(() => _selImage = iHit);
        if (iHit != null) return; // selecting consumes the tap
      }
      final cpScreen = _worldToScreen(Offset.zero, size);
      if ((local - cpScreen).distance <= touchSlop(kind, 6)) {
        setState(() => _projCpSelected = !_projCpSelected);
        return;
      }
    }
    _tapNoTool(local, _toWorld(local, size), kind: kind);
  }

  String _gesture = 'none';
  // none|panzoom|fingerpan|tooldrag|grip|box|body|text|imgmove|imgresize
  double _scaleStartZoom = 1;
  Offset? _boxStartW;
  // M53: true while the single gesture pointer is a FINGER (wide slops).
  bool _gestureFinger = false;
  // M53: press-drag-release drawing with the Pencil — down = first point,
  // drag = live rubber band with snapping, release = second point. A plain
  // tap (no movement past the slop) stays a classic click-click pick.
  Offset? _toolDownLocal;
  Offset? _toolDragW;
  bool _toolDragPlaced = false;
  int?
      _clickPtr; // the pointer that armed _clickDown (a palm up must not fire it)
  Offset? _lastStylusLocal; // fallback anchor for the Pencil-squeeze menu

  // M47: whole-entity body drag (grab the line/curve itself, not a grip point).
  int? _bodyEnt; // entity picked for a body drag
  Offset? _bodyAnchorW; // world point the finger grabbed
  bool _bodyStarted = false; // deferred begin: true once the drag actually ran

  /// Applies object snapping to a world point and publishes the marker.
  Offset _snapped(Offset w, {Offset? exclude, double px = _snapPx}) {
    final app = widget.app;
    final s = app.current;
    if (s == null) return w;
    // Hidden layers must not attract the cursor either. Snap carries no entity
    // indices, so filtering the list here is safe (grips below are NOT filtered
    // — those carry indices and must stay aligned with the geometry list).
    final visible = [
      for (final g in app.displayGeometry(s))
        if (app.geoVisible(g)) g
    ];
    final sn = computeSnap(visible, w, px / app.zoom,
        ref: app.toolPoints.isNotEmpty ? app.toolPoints.last : null,
        exclude: exclude,
        // Let the cursor snap to the points already placed by the active tool —
        // above all the start point, so a spline/polyline can close on itself.
        // M45: text bounding-box corners/midpoints are also snap targets, so
        // dimensions and new geometry can measure to a text box.
        extraPoints: [
          ...app.toolPoints,
          ...app.textSnapPoints(s, measure: measureSketchText),
        ]);
    app.setSnap(sn);
    return sn?.pos ?? w;
  }

  // ---- M44 helpers ----
  void _ensureImages() {
    final app = widget.app;
    final s = app.current;
    if (s == null) return;
    for (final i in s.images) {
      if (_imgCache.containsKey(i.file)) continue;
      _imgCache[i.file] = null;
      final f = File(app.imagePath(i));
      f.readAsBytes().then((b) => ui.instantiateImageCodec(b)).then((c) async {
        final fr = await c.getNextFrame();
        if (mounted) setState(() => _imgCache[i.file] = fr.image);
      }, onError: (e) => Log.w('insert', 'image decode failed: $e'));
    }
  }

  Rect _imageWorldRect(SketchImage i) =>
      Rect.fromCenter(center: Offset(i.x, i.y), width: i.w, height: i.h);

  SketchImage? _imageAtWorld(Offset w) {
    final s = widget.app.current;
    if (s == null) return null;
    for (final i in s.images.reversed) {
      if (_imageWorldRect(i).contains(w)) return i;
    }
    return null;
  }

  SketchText? _textAtScreen(Offset local) {
    for (final (t, r) in widget.app.textRects.reversed) {
      if (r.inflate(8).contains(local)) return t;
    }
    return null;
  }

  /// Text create/edit dialog: multiline template with <Param> placeholders
  /// and a height field. [existing] == null creates at [pos].
  /// M45 — opens the movable text editor window (create at [pos] or edit
  /// [existing]). Replaces the old modal AlertDialog.
  void _openTextEditor({SketchText? existing, Offset? pos}) {
    final app = widget.app;
    if (existing != null) {
      app.beginTextEdit(existing, isNew: false);
    } else if (pos != null) {
      final t =
          app.addText(pos, '', placeholder: true); // kept only if committed
      app.beginTextEdit(t, isNew: true);
    }
  }

  /// M46 — true when a text input currently holds focus anywhere in the app
  /// (the inline dimension box, a Parameters cell, the text window, or any
  /// future TextField). While one does, the viewport suppresses ALL of its
  /// key handling so raw letters and Enter/Escape go to the field. Detected
  /// by scanning the primary-focus element's subtree for an EditableText —
  /// stays correct even if new text-bearing windows are added later.
  bool _editableHasFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || identical(primary, _focus)) return false;
    final ctx = primary.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var editable = false;
    void scan(Element el) {
      if (editable) return;
      if (el.widget is EditableText) {
        editable = true;
        return;
      }
      el.visitChildren(scan);
    }

    (ctx as Element).visitChildren(scan);
    return editable;
  }

  void _scaleStart(ScaleStartDetails d, Size size) {
    final app = widget.app;
    _scaleStartZoom = app.zoom;
    // M51: the kind of the SINGLE pointer driving this gesture. Fingers get
    // wider grab radii and, on empty canvas, pan instead of box-selecting.
    final soleKind = _kinds.length == 1 ? _kinds.values.first : null;
    final finger = soleKind == PointerDeviceKind.touch;
    _gestureFinger = finger;
    if (d.pointerCount >= 2) {
      _gesture = 'panzoom';
      return;
    }
    if (app.tool != Tool.none) {
      // PENCIL AND FINGER press-drag-draw: non-hover Pencils (gen 1/2) see
      // no rubber band between taps, so down anchors the first point, the
      // drag previews live WITH snapping, release places — while a plain
      // tap keeps the classic click-click flow. One finger draws exactly
      // the same way (two fingers still pan/zoom, Procreate-style).
      // Geometry tools only (toolMeta): dimensioning/modify stay pure
      // picks, and there a FINGER falls back to panning.
      if (finger && toolMeta[app.tool] == null) {
        _gesture = 'fingerpan';
        return;
      }
      if ((finger ||
              soleKind == PointerDeviceKind.stylus ||
              soleKind == PointerDeviceKind.invertedStylus) &&
          toolMeta[app.tool] != null) {
        _gesture = 'tooldrag';
        _toolDownLocal = d.localFocalPoint;
        _toolDragW = null;
        _toolDragPlaced = false;
        return;
      }
      _gesture = 'none'; // mouse: click-driven, exactly as before
      return;
    }
    final grabPx =
        finger ? touchSlop(PointerDeviceKind.touch, _gripPx) : _gripPx;
    final w = _toWorld(d.localFocalPoint, size);
    // grip under the finger?
    final s = app.current;
    if (s != null) {
      Grip? hit;
      var bd = grabPx / app.zoom;
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
      Log.d(
          'gesture',
          'no grip under finger at '
              '(${w.dx.toStringAsFixed(2)},${w.dy.toStringAsFixed(2)}) '
              '-> box select; grips=${gripsOf(s.geometry).length}');
      // M44: text drag, then SELECTED-image resize grip / body drag — all
      // lower priority than geometry grips, higher than box select.
      final tHit = _textAtScreen(d.localFocalPoint);
      if (tHit != null) {
        _gesture = 'text';
        _dragText = tHit;
        _dragOff = Offset(tHit.x, tHit.y) - w;
        return;
      }
      final sel = _selImage;
      if (sel != null &&
          s.images.contains(sel) &&
          (!app.inEditMode || sel.layer == app.editingLayer)) {
        // grips are drawn at SCREEN corners; hit-test there (world-y is
        // flipped, so the world rect's corners are the wrong ones)
        final tl =
            _worldToScreen(Offset(sel.x - sel.w / 2, sel.y + sel.h / 2), size);
        final br =
            _worldToScreen(Offset(sel.x + sel.w / 2, sel.y - sel.h / 2), size);
        final dst = Rect.fromPoints(tl, br);
        if ((d.localFocalPoint - dst.bottomRight).distance <
            (finger ? touchSlop(PointerDeviceKind.touch, 16) : 16)) {
          _gesture = 'imgresize';
          _dragImage = sel;
          return;
        }
        if (dst.contains(d.localFocalPoint)) {
          _gesture = 'imgmove';
          _dragImage = sel;
          _dragOff = Offset(sel.x, sel.y) - w;
          return;
        }
      }
      // M47: DIRECT BODY DRAG — grab a line/circle/arc/polyline/spline/ellipse
      // by its BODY (not a grip point) and translate the whole entity. Only
      // editable, visible, non-projected geometry with at least one still-free
      // defining point qualifies (fully-constrained geometry is locked, like
      // Inventor); everything else falls through to box select. The actual drag
      // begins LAZILY on the first move (see _scaleUpdate) so a plain tap on a
      // line still selects it without a no-op rebuild. Reuses the `free` set
      // resolved above (freePoints of the current analysis, null = not run yet).
      var bodyI = -1;
      var bodyD = grabPx / app.zoom;
      for (var i = 0; i < s.geometry.length; i++) {
        final g = s.geometry[i];
        if (!app.geoEditable(g) || !app.geoVisible(g)) continue;
        if (g.isProjection) continue; // projections are pinned reference geo
        var anyFree = free == null;
        if (free != null) {
          for (var p = 0; p < ptCount(g); p++) {
            if (free.contains((i, p))) {
              anyFree = true;
              break;
            }
          }
        }
        if (!anyFree) continue;
        final dd = distToEntity(g, w);
        if (dd < bodyD) {
          bodyD = dd;
          bodyI = i;
        }
      }
      if (bodyI >= 0) {
        _gesture = 'body';
        _bodyEnt = bodyI;
        _bodyAnchorW = w;
        _bodyStarted = false;
        Log.d('gesture',
            'body-drag candidate e$bodyI (d=${bodyD.toStringAsFixed(2)})');
        return;
      }
    }
    // Empty canvas: a FINGER pans (touch-first navigation, one finger is
    // enough to move around); the Pencil and the mouse keep Inventor's
    // drag-a-window box select — the Pencil is the precision instrument.
    if (finger) {
      _gesture = 'fingerpan';
      return;
    }
    _gesture = 'box';
    _boxStartW = w;
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
    final app = widget.app;
    if (d.pointerCount >= 2 && _gesture != 'panzoom') {
      // second finger arrived: abort grip/body/box, switch to pan/zoom
      if (_gesture == 'grip') app.endGripDrag();
      if (_gesture == 'body' && _bodyStarted) {
        app.endGripDrag();
        _bodyStarted = false;
      }
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
      case 'fingerpan': // M53: one finger on empty canvas moves the view
        app.panBy(d.focalPointDelta);
        break;
      case 'tooldrag': // M53: Pencil press-drag-release drawing
        final lp = d.localFocalPoint;
        if (!_toolDragPlaced &&
            _toolDownLocal != null &&
            (lp - _toolDownLocal!).distance > 8) {
          // the FIRST point lands where the tip touched DOWN, snapped —
          // dragging away must not smear the anchor
          app.toolClick(_snapped(_toWorld(_toolDownLocal!, size),
              px: _gestureFinger
                  ? touchSlop(PointerDeviceKind.touch, _snapPx)
                  : _snapPx));
          _toolDragPlaced = true;
          _clickDown = null; // the release is a placement, never a tap
        }
        if (_toolDragPlaced) {
          final wNow = _toWorld(lp, size);
          _toolDragW = wNow;
          // live rubber band, HUD applies; fingers snap with fat radii
          app.setHover(_snapped(wNow,
              px: _gestureFinger
                  ? touchSlop(PointerDeviceKind.touch, _snapPx)
                  : _snapPx));
        }
        break;
      case 'text':
        final t = _dragText;
        if (t != null) {
          app.moveText(t, _toWorld(d.localFocalPoint, size) + _dragOff);
        }
        break;
      case 'imgmove':
        final im = _dragImage;
        if (im != null) {
          app.moveImage(im, _toWorld(d.localFocalPoint, size) + _dragOff);
        }
        break;
      case 'imgresize':
        final ir = _dragImage;
        if (ir != null) {
          final w = _toWorld(d.localFocalPoint, size);
          app.resizeImage(ir, (w.dx - ir.x).abs() * 2);
        }
        break;
      case 'grip':
        final w = _toWorld(d.localFocalPoint, size);
        app.updateGripDrag(_snapped(w,
            exclude: app.dragGrip?.pos,
            px: _gestureFinger
                ? touchSlop(PointerDeviceKind.touch, _snapPx)
                : _snapPx));
        break;
      case 'body':
        // Defer the actual begin to the first move: a stationary press becomes
        // a tap (→ select via the Listener) and must not start a rebuild. No
        // snapping — a body drag is a pure translation that follows the finger
        // exactly (snapping the arbitrary grab point to a vertex would make the
        // whole entity lurch).
        final cursor = _toWorld(d.localFocalPoint, size);
        if (!_bodyStarted && _bodyEnt != null && _bodyAnchorW != null) {
          app.beginBodyDrag(_bodyEnt!, _bodyAnchorW!);
          _bodyStarted = true;
        }
        if (_bodyStarted) app.updateGripDrag(cursor);
        break;
      case 'box':
        app.boxSelectUpdate(_boxStartW!, _toWorld(d.localFocalPoint, size));
        break;
    }
  }

  void _tapNoTool(Offset local, Offset w,
      {PointerDeviceKind kind = PointerDeviceKind.mouse}) {
    final app = widget.app;
    // where the label is REALLY painted (dist labels are not at textPos)...
    final dim = _dimAtScreen(local, inflate: touchSlop(kind, 8)) ??
        // ...with the old anchor test as fallback (e.g. before first paint)
        app.dimensionAt(w, touchSlop(kind, 14) / app.zoom);
    if (dim != null) {
      _editDimValue(dim);
      return;
    }
    app.selectAt(w, touchSlop(kind, 10) / app.zoom);
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

  /// M42: the dimension label under the mouse — highlighted whenever it is
  /// actionable: while the expression box is open (click inserts the
  /// parameter name, Inventor-style) and in plain layer-edit mode (tap opens
  /// the value editor).
  Constraint? _hoverDimLabel;

  /// M43: position of the movable Parameters window (viewport coords).
  Offset _paramsPos = const Offset(60, 60);
  Offset _gearPos = const Offset(60, 60);
  final GlobalKey _gearDialogKey = GlobalKey();

  /// M45: position of the movable text editor window.
  Offset _textWinPos = const Offset(90, 90);
  // M44: insert-content interaction state
  final Map<String, ui.Image?> _imgCache = {}; // null = loading/broken
  SketchImage? _selImage; // selected image (shows resize/delete grips)
  SketchImage? _dragImage;
  SketchText? _dragText;
  Offset _dragOff = Offset.zero;
  final TextEditingController _dimCtrl = TextEditingController();
  final FocusNode _dimFocus = FocusNode();

  void _openInlineEditor(Constraint d, {required bool isNew}) {
    setState(() {
      _inlineDim = d;
      _inlineIsNew = isNew;
      // M41: the box shows the RAW expression when the dimension is driven
      // by one (Inventor: value collapses on screen, equation reappears on
      // edit); a plain-value dimension shows its number.
      _dimCtrl.text = d.expr ??
          (_isAngleKind(d)
              ? (d.value ?? 0).toStringAsFixed(1)
              : (d.value ?? 0).toStringAsFixed(2));
      _dimCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _dimCtrl.text.length);
    });
    _dimFocus.requestFocus();
  }

  /// Enter pressed. An INVALID entry keeps the editor open (Inventor blocks
  /// the green check while the expression is red); [clickAway] commits
  /// whatever is committable and otherwise keeps the measured value — the
  /// dimension is kept either way, exactly like clicking away in Inventor.
  void _submitInline({bool clickAway = false}) {
    final d = _inlineDim;
    if (d == null) return;
    final app = widget.app;
    final raw = _dimCtrl.text;
    final valid = app.dimTextValid(d, raw);
    if (!valid && !clickAway) {
      setState(() {}); // stays open, shown red
      return;
    }
    setState(() => _inlineDim = null);
    if (_inlineIsNew) {
      if (valid) {
        app.confirmDimensionText(raw);
      } else {
        app.confirmDimension(null); // keep the measured value
      }
    } else if (valid) {
      app.setDimensionText(d, raw);
    }
    _focus.requestFocus();
  }

  /// M41: while the edit box is open, tapping ANOTHER dimension's label
  /// inserts its parameter name at the cursor instead of committing —
  /// Inventor: "if the value is displayed in the graphics window, you can
  /// click it to enter its name automatically".
  void _insertParamRef(Constraint other) {
    final app = widget.app;
    final s = app.current;
    if (s == null) return;
    final name = app.ensureParamName(s, other);
    final sel = _dimCtrl.selection;
    final t = _dimCtrl.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _dimCtrl.text = t.replaceRange(start, end, name);
    _dimCtrl.selection = TextSelection.collapsed(offset: start + name.length);
    setState(() {});
    _dimFocus.requestFocus();
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
    // M41: wider box — it holds full expressions now, and shows the
    // parameter name as a prefix (Inventor: "Edit Dimension : d3").
    const w = 170.0, h = 34.0;
    final valid = widget.app.dimTextValid(d, _dimCtrl.text);
    final name = d.paramName;
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
            // M41: full expressions — letters, operators, parens, units
            keyboardType: TextInputType.text,
            autocorrect: false,
            enableSuggestions: false,
            // Inventor colours invalid syntax red while you type
            style: TextStyle(
                fontSize: 13, color: valid ? T.text : const Color(0xFFE05A5A)),
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            // outside taps are handled by _handleClick (reference-insert or
            // commit) — the default unfocus-on-tap-outside must not race it
            onTapOutside: (_) {},
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              prefixText: name != null ? '$name = ' : null,
              prefixStyle: const TextStyle(fontSize: 11, color: T.dim),
              suffixText: _isAngleKind(d) ? '\u00b0' : 'mm',
              suffixStyle: const TextStyle(fontSize: 11, color: T.dim),
            ),
            onSubmitted: (_) => _submitInline(),
          ),
        ),
      ),
    );
  }

  // ==== M53 — long-press / Pencil-squeeze quick menu =====================

  void _cancelLp() {
    _lpTimer?.cancel();
    _lpTimer = null;
    _lpDown = null;
  }

  /// The right-click role for Pencil and finger (600 ms, still). Inside the
  /// Split/Trim/Extend family it hops to the next member exactly like
  /// Inventor's right-click (M49); otherwise it opens the quick menu — which
  /// is also the ONLY way a touch-only user reaches Enter (OK) and Esc
  /// (Cancel) inside a running tool.
  void _fireLongPress(Offset local, Size size) {
    if (!mounted) return;
    _lpTimer = null;
    _lpDown = null;
    final app = widget.app;
    _lpFired = true;
    _clickDown = null;
    // whatever gesture was brewing, the long-press consumes it
    _gesture = 'none';
    _boxStartW = null;
    _toolDownLocal = null;
    _toolDragPlaced = false;
    _mft.nonTouchActivity();
    HapticFeedback.selectionClick();
    if (app.cycleModifyTool()) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    _showQuickMenu(box.localToGlobal(local));
  }

  /// Pencil Pro squeeze: Apple's own apps open a tool palette at the tip —
  /// so do we. [x],[y] are window coords of the hover pose when iOS provides
  /// one, else the last known Pencil position, else the viewport centre.
  void _pencilSqueeze(double? x, double? y) {
    HapticFeedback.selectionClick();
    Offset global;
    final box = context.findRenderObject();
    if (x != null && y != null && x >= 0) {
      global = Offset(x, y);
    } else if (box is RenderBox && _lastStylusLocal != null) {
      global = box.localToGlobal(_lastStylusLocal!);
    } else if (box is RenderBox) {
      global = box.localToGlobal(box.size.center(Offset.zero));
    } else {
      return;
    }
    _showQuickMenu(global);
  }

  /// Pencil double-tap. Inventor users live on Esc + re-pick; the closest
  /// analog: inside the modify family it cycles (right-click role), with a
  /// tool armed it is Esc, and with no tool it re-arms the last drawing
  /// tool — draw, double-tap out, inspect, double-tap back in.
  void _pencilDoubleTap() {
    final app = widget.app;
    HapticFeedback.selectionClick();
    if (app.cycleModifyTool()) return;
    if (app.tool != Tool.none) {
      app.cancelTool();
      return;
    }
    if (app.inEditMode && app.lastDrawTool != Tool.none) {
      app.selectTool(app.lastDrawTool);
    }
  }

  void _closeQuickMenu() {
    _toolCtx?.remove();
    _toolCtx = null;
  }

  void _showQuickMenu(Offset globalPos) {
    _closeQuickMenu();
    final app = widget.app;
    final meta = toolMeta[app.tool];
    final canOk = meta != null &&
        meta.fixed == null &&
        app.toolPoints.length >= meta.minVar;
    final items = <Widget>[
      if (canOk)
        _qmItem('OK', () {
          app.finishVariableTool();
        }),
      if (app.tool != Tool.none)
        _qmItem('Cancel (Esc)', () {
          app.cancelTool();
        }),
      if (app.inEditMode) ...[
        _qmItem('Line (L)', () => app.selectTool(Tool.line)),
        _qmItem('Circle (C)', () => app.selectTool(Tool.circleCenter)),
        _qmItem('Rectangle (R)', () => app.selectTool(Tool.rectTwoPoint)),
        _qmItem('Dimension (D)', () => app.selectTool(Tool.dimension)),
      ],
    ];
    if (items.isEmpty) return; // outside edit mode with no tool: nothing to do
    _toolCtx = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _closeQuickMenu(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: globalPos.dx,
          top: globalPos.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              // the ceiling is NOT optional — see the model browser's menu
              constraints: const BoxConstraints(minWidth: 168, maxWidth: 240),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF212429),
                border: Border.all(color: T.sep),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x8C000000),
                      blurRadius: 22,
                      offset: Offset(0, 8))
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: items),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_toolCtx!);
  }

  Widget _qmItem(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _closeQuickMenu();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(label, style: ts(12.5, T.mbText)),
      ),
    );
  }

  void _scaleEnd() {
    final app = widget.app;
    switch (_gesture) {
      case 'tooldrag': // M53: release places the second point
        if (_toolDragPlaced && _toolDragW != null) {
          app.toolClick(_snapped(_toolDragW!,
              px: _gestureFinger
                  ? touchSlop(PointerDeviceKind.touch, _snapPx)
                  : _snapPx));
          if (app.pendingDim != null) _showDimDialog(app.pendingDim!);
        }
        _toolDownLocal = null;
        _toolDragW = null;
        _toolDragPlaced = false;
        break;
      case 'grip':
        app.endGripDrag();
        break;
      case 'body':
        // Commit only if the drag actually ran (a plain tap never began one —
        // see the 'body' case in _scaleUpdate); endGripDrag is a no-op anyway
        // when dragGrip is null, but this also avoids a stray settle.
        if (_bodyStarted) app.endGripDrag();
        _bodyEnt = null;
        _bodyAnchorW = null;
        _bodyStarted = false;
        break;
      case 'box':
        app.boxSelectFinish();
        break;
      case 'text': // M44: commit the move as one journal step
        final t = _dragText;
        if (t != null) app.moveText(t, Offset(t.x, t.y), commit: true);
        _dragText = null;
        break;
      case 'imgmove':
        final im = _dragImage;
        if (im != null) app.moveImage(im, Offset(im.x, im.y), commit: true);
        _dragImage = null;
        break;
      case 'imgresize':
        final ir = _dragImage;
        if (ir != null) app.resizeImage(ir, ir.w, commit: true);
        _dragImage = null;
        break;
    }
    _gesture = 'none';
    _boxStartW = null;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    _ensureImages(); // M44: decode any newly inserted images
    return LayoutBuilder(builder: (context, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      widget.app.viewportSize = size; // M45: for cursor-anchored inserts
      // Entering the sketcher: open at the SAME world scale as the 3D view.
      // Deferred to after this frame — it mutates app state and notifies.
      if (widget.app.sketchZoomNeedsFit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.app.fitSketchZoom(size.height);
        });
      }
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          // M46: when a text field is being typed into (inline dimension
          // editor, Parameters window, or the parametric-text window), NO
          // viewport key handling runs — not the letter shortcuts, and not
          // Escape/Enter either. Escape should cancel the field's edit and
          // Enter should commit it; both are the TextField's job, so we let
          // the events pass through (KeyEventResult.ignored) instead of
          // stealing them for cancelTool()/finishVariableTool().
          final typing = _inlineDim != null ||
              app.editingText != null ||
              app.showParams ||
              _editableHasFocus();
          if (typing) return KeyEventResult.ignored;
          // HUD / Dynamic Input: while a create tool with value boxes is live,
          // keystrokes drive the boxes — digits/'.'/'-' type into the focused
          // box, Tab locks it and advances, Enter places the point, Backspace
          // edits. Letters still fall through to the tool shortcuts. Escape
          // clears a pending value first, then (empty) cancels the tool.
          if (app.hudActive && event is KeyDownEvent) {
            final hk = event.logicalKey;
            if (hk == LogicalKeyboardKey.tab ||
                hk == LogicalKeyboardKey.arrowRight ||
                hk == LogicalKeyboardKey.arrowDown) {
              app.hudTab();
              return KeyEventResult.handled;
            }
            // arrows also walk the boxes BACKWARDS — on a rectangle that is
            // simply "switch between w and h" in either direction
            if (hk == LogicalKeyboardKey.arrowLeft ||
                hk == LogicalKeyboardKey.arrowUp) {
              app.hudTabBack();
              return KeyEventResult.handled;
            }
            if (hk == LogicalKeyboardKey.enter ||
                hk == LogicalKeyboardKey.numpadEnter) {
              app.hudEnter();
              return KeyEventResult.handled;
            }
            if (hk == LogicalKeyboardKey.backspace) {
              app.hudBackspace();
              return KeyEventResult.handled;
            }
            if (hk == LogicalKeyboardKey.escape) {
              if (app.hudClearInput()) return KeyEventResult.handled;
              // empty buffer: fall through to cancelTool below
            } else {
              final ch = event.character;
              if (ch != null && ch.length == 1 && '0123456789.-'.contains(ch)) {
                app.hudType(ch);
                return KeyEventResult.handled;
              }
            }
          }
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
          // ---- shortcuts (M30) ----
          if (event is KeyDownEvent) {
            final k = event.logicalKey;
            final ctrl = HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            if (ctrl && k == LogicalKeyboardKey.keyS) {
              final tab = app.curTab;
              if (tab != null) {
                app.saveSketch(tab).then(
                    (ok) => app.toast(ok ? 'Saved "$tab"' : 'Save failed'));
              }
              return KeyEventResult.handled;
            }
            // Undo / Redo (M39): Ctrl+Z steps back, Ctrl+Shift+Z (or Ctrl+Y)
            // steps forward — always only in the CURRENT sketch.
            if (ctrl && k == LogicalKeyboardKey.keyZ) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                app.redo();
              } else {
                app.undo();
              }
              return KeyEventResult.handled;
            }
            if (ctrl && k == LogicalKeyboardKey.keyY) {
              app.redo();
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
            app.lastPointerWorld = _toWorld(e.localPosition, size); // M45
            if (app.tool != Tool.none) {
              final w = _toWorld(e.localPosition, size);
              app.setHover(_snapped(w));
            }
            // M42: highlight the dimension label under the cursor when
            // interacting with it would do something — insert its parameter
            // name (expression box open) or open its editor (edit mode, no
            // tool / dimension tool).
            final actionable = _inlineDim != null ||
                app.paramRefSink != null ||
                app.textRefSink != null ||
                (app.inEditMode &&
                    (app.tool == Tool.none || app.tool == Tool.dimension));
            var hd = actionable ? _dimAtScreen(e.localPosition) : null;
            if (identical(hd, _inlineDim)) hd = null; // own label: no hint
            if (!identical(hd, _hoverDimLabel)) {
              setState(() => _hoverDimLabel = hd);
            }
          },
          // Tool clicks are handled on RAW pointer events, not via
          // GestureDetector.onTap: the ScaleGestureRecognizer (pan/zoom,
          // grips, box select) wins the gesture arena as soon as the finger
          // slides a few pixels, which silently swallowed every tap and made
          // drawing impossible. The Listener sees pointers regardless of the
          // arena.
          onPointerDown: (e) {
            // Count FIRST, and count every pointer: onPointerUp decrements
            // unconditionally, so an early return here would leave the tally
            // one short and make the next real finger look like the first —
            // i.e. a pan/zoom that starts drawing instead. (The clamp in
            // onPointerUp hides the sign but not the drift.)
            _pointers++;
            _kinds[e.pointer] = e.kind;
            // M53 palm rejection: a touch arriving while the Pencil is DOWN
            // is the heel of the hand, not input. It is counted (the M52
            // contract above) but never clicks, never taps, and the scale
            // recognizer refuses it (_PalmAwareScale) — so resting the palm
            // mid-stroke neither pans nor draws nor undoes.
            if (e.kind == PointerDeviceKind.touch && _stylusDown) {
              _rejectedTouches.add(e.pointer);
              return;
            }
            // M49: a right-click inside the Split/Trim/Extend session hops to
            // the next member of the family, exactly like Inventor. It never
            // counts as a tool click.
            if (e.kind == PointerDeviceKind.mouse &&
                e.buttons == kSecondaryButton &&
                app.cycleModifyTool()) {
              _clickDown = null;
              return;
            }
            // M53: feed the Procreate tap classifier (2 fingers = undo,
            // 3 = redo). Any non-touch activity poisons the session.
            if (e.kind == PointerDeviceKind.touch) {
              _mft.down(e.pointer, e.localPosition);
            } else {
              _mft.nonTouchActivity();
            }
            if (e.kind == PointerDeviceKind.stylus ||
                e.kind == PointerDeviceKind.invertedStylus) {
              _lastStylusLocal = e.localPosition;
              // no-hover Pencils: the snap marker appears the instant the
              // tip touches, not only after the first move
              if (app.tool != Tool.none) {
                app.setHover(_snapped(_toWorld(e.localPosition, size)));
              }
            }
            if (_pointers > 1) {
              _clickDown = null; // second finger: pan/zoom, never a click
              _cancelLp();
              return;
            }
            _clickDown = e.localPosition;
            _clickPtr = e.pointer;
            _downKind = e.kind;
            _clickTime = DateTime.now();
            _downDimHit =
                _dimAtScreen(e.localPosition, inflate: touchSlop(e.kind, 8));
            app.lastPointerWorld = _toWorld(e.localPosition, size); // M45
            // M53: long-press = the right-click role, for Pencil and finger
            if (e.kind == PointerDeviceKind.touch ||
                e.kind == PointerDeviceKind.stylus ||
                e.kind == PointerDeviceKind.invertedStylus) {
              _lpDown = e.localPosition;
              _lpFired = false;
              _lpTimer?.cancel();
              _lpTimer = Timer(const Duration(milliseconds: 600),
                  () => _fireLongPress(e.localPosition, size));
            }
          },
          onPointerMove: (e) {
            final rejected = _rejectedTouches.contains(e.pointer);
            if (!rejected && e.kind == PointerDeviceKind.touch) {
              _mft.move(e.pointer, e.localPosition);
            }
            if (_lpDown != null && (e.localPosition - _lpDown!).distance > 8) {
              _cancelLp(); // moving is drawing/dragging, not a long-press
            }
            if (!rejected &&
                (e.kind == PointerDeviceKind.stylus ||
                    e.kind == PointerDeviceKind.invertedStylus)) {
              _lastStylusLocal = e.localPosition;
              // M53: the CONTACT preview for no-hover Pencils — while the
              // tip is down with a tool armed, the rubber band + snap marker
              // track it live (hover-capable Pencils get this via
              // onPointerHover already, exactly like the mouse).
              app.lastPointerWorld = _toWorld(e.localPosition, size);
              if (app.tool != Tool.none && _toolCtx == null) {
                app.setHover(_snapped(_toWorld(e.localPosition, size)));
              }
            }
            final d = _clickDown;
            if (d != null && (e.localPosition - d).distance > 14) {
              _clickDown = null; // it's a drag
            }
          },
          onPointerCancel: (e) {
            _pointers = (_pointers - 1).clamp(0, 10);
            _kinds.remove(e.pointer);
            _rejectedTouches.remove(e.pointer);
            if (e.kind == PointerDeviceKind.touch) _mft.cancel(e.pointer);
            _cancelLp();
            _clickDown = null;
          },
          onPointerUp: (e) {
            _pointers = (_pointers - 1).clamp(0, 10);
            _kinds.remove(e.pointer);
            final wasRejected = _rejectedTouches.remove(e.pointer);
            _cancelLp();
            // M53: Procreate taps — a clean two-finger tap is UNDO, three
            // fingers REDO. The classifier separates them from pan/pinch
            // (which always moves) and from a resting palm (poisoned).
            if (e.kind == PointerDeviceKind.touch && !wasRejected) {
              final n = _mft.up(e.pointer, e.localPosition);
              if (n == 2 || n == 3) {
                final typing = _inlineDim != null ||
                    app.editingText != null ||
                    app.showParams ||
                    app.gear != null ||
                    app.hudActive ||
                    _editableHasFocus();
                if (!typing && app.dragGrip == null) {
                  HapticFeedback.mediumImpact();
                  if (n == 2) {
                    app.undo();
                  } else {
                    app.redo();
                  }
                }
                _clickDown = null;
                return;
              }
            }
            if (wasRejected) return; // palm contact never clicks
            if (_lpFired) {
              // the long-press consumed this contact (menu / tool cycle)
              _lpFired = false;
              _clickDown = null;
              return;
            }
            if (e.pointer != _clickPtr) return; // not the pointer that armed
            final d = _clickDown;
            _clickDown = null;
            _clickPtr = null;
            if (d == null) return;
            if (DateTime.now().difference(_clickTime).inMilliseconds > 700) {
              return;
            }
            if ((e.localPosition - d).distance > 14) return;
            _handleClick(e.localPosition, size,
                downDim: _downDimHit, kind: _downKind);
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            // One finger: grip drag / body drag / box select (Pencil, mouse)
            // or pan (finger); two fingers: pan + zoom. A custom recognizer
            // instead of GestureDetector.onScale for M53's palm rejection:
            // touches are refused ENTRY into the gesture while the Pencil is
            // down, so a resting palm can never hijack a stroke into a pan.
            gestures: <Type, GestureRecognizerFactory>{
              _PalmAwareScale:
                  GestureRecognizerFactoryWithHandlers<_PalmAwareScale>(
                () => _PalmAwareScale(rejectTouch: () => _stylusDown),
                (r) {
                  r.onStart = (d) => _scaleStart(d, size);
                  r.onUpdate = (d) => _scaleUpdate(d, size);
                  r.onEnd = (_) => _scaleEnd();
                },
              ),
            },
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
                      hoverDim: _hoverDimLabel,
                      imgCache: _imgCache,
                      selImage: _selImage,
                    ),
                  ),
                  if (_inlineDim != null) _inlineEditor(size),
                  // Pattern dialogs (M35) float MODELESS over the viewport,
                  // top-right like Inventor parks them — picks keep landing
                  // in the canvas while the dialog is open.
                  if (app.pattern != null)
                    Positioned(
                        right: 12, top: 12, child: PatternDialog(app: app)),
                  // M43: movable Parameters (fx) window
                  if (app.showParams)
                    Positioned(
                      left: _paramsPos.dx.clamp(0.0, size.width - 120),
                      top: _paramsPos.dy.clamp(0.0, size.height - 60),
                      child: ParametersDialog(
                          app: app,
                          onDrag: (d) => setState(() => _paramsPos += d)),
                    ),
                  // M61: movable Gear window
                  if (app.gear != null)
                    Positioned(
                      left: _gearPos.dx.clamp(0.0, size.width - 120),
                      top: _gearPos.dy.clamp(0.0, size.height - 60),
                      child: GearDialog(
                          key: _gearDialogKey,
                          app: app,
                          onDrag: (d) => setState(() => _gearPos += d)),
                    ),
                  // M45: movable parametric-text editor window
                  if (app.editingText != null)
                    Positioned(
                      left: _textWinPos.dx.clamp(0.0, size.width - 120),
                      top: _textWinPos.dy.clamp(0.0, size.height - 60),
                      child: TextEditorWindow(
                          app: app,
                          onDrag: (d) => setState(() => _textWinPos += d)),
                    ),
                  // 2D Fillet / Chamfer value window (M36), same parking spot
                  if (app.filletSess != null &&
                      (app.tool == Tool.fillet || app.tool == Tool.chamfer))
                    Positioned(
                        right: 12,
                        top: 12,
                        child: FilletChamferDialog(app: app)),
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
    return Offset(size.width / 2 + (w.dx - app.pan.dx) * app.zoom,
        size.height / 2 - (w.dy - app.pan.dy) * app.zoom);
  }
}

bool _overlayErrorLogged = false;

class _ViewportPainter extends CustomPainter {
  final AppState app;
  final bool projCpSelected;

  /// M42: dimension label to render highlighted (hover feedback).
  final Constraint? hoverDim;

  /// M44: decoded inserted images + the currently selected one (adornments).
  final Map<String, ui.Image?> imgCache;
  final SketchImage? selImage;
  _ViewportPainter(
      {required this.app,
      required this.projCpSelected,
      this.hoverDim,
      this.imgCache = const {},
      this.selImage});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    // ---- M59: while sketching inside a part, Inventor keeps the 3D model
    // visible — render the committed solids straight down the sketch frame
    // with THIS view's pan/zoom, then dim them behind a veil so the sketch
    // stays the crisp foreground.
    final part59 = app.currentPart;
    final child59 = app.activeChild;
    if (part59 != null && child59 != null) {
      ChildSketch? cs59;
      for (final c in part59.childSketches) {
        if (identical(c.model, child59) || c.model.name == child59.name) {
          cs59 = c;
          break;
        }
      }
      if (cs59 != null) {
        final solids = [
          for (final f in part59.features)
            if (f.visible && f.solid != null && !f.consumedByJoin) f.solid!
        ];
        if (solids.isNotEmpty) {
          paintPartUnderlay(
              canvas, size, solids, sketchFrameOf(cs59), app.pan, app.zoom);
          canvas.drawRect(Offset.zero & size,
              Paint()..color = T.viewport.withOpacity(0.55));
        }
      }
    }
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
      // Pattern dialog picks (M35): geometry set gets the pre-select halo,
      // the direction / axis / mirror-line picks get the selection blue —
      // Inventor lights all of a dialog's inputs until it closes.
      final pat = app.pattern;
      if (pat != null) {
        for (final e in pat.geo) {
          if (e >= 0 && e < gs.length) {
            paintGeo(canvas, gs[e], map, app.zoom, halo);
          }
        }
        final refHalo = Paint()
          ..color = T.blue.withOpacity(.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round;
        for (final e in [pat.dir1Ent, pat.dir2Ent, pat.mirrorEnt]) {
          if (e != null && e < gs.length) {
            paintGeo(canvas, gs[e], map, app.zoom, refHalo);
          }
        }
        final ax = pat.axisPt;
        if (ax != null && (ax.ent < 0 || ax.ent < gs.length)) {
          final q = refPt(gs, ax);
          canvas.drawCircle(map(q.dx, q.dy), 6, refHalo);
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

      // M44: inserted images are an underlay — painted BELOW all geometry.
      for (final img in s.images) {
        final u = imgCache[img.file];
        final tl = map(img.x - img.w / 2, img.y + img.h / 2);
        final br = map(img.x + img.w / 2, img.y - img.h / 2);
        final dst = Rect.fromPoints(tl, br);
        // M45: an image not on the layer being edited is dimmed and greyed
        // (Inventor greys other-sketch underlays) — full colour only on its
        // own layer, or when no layer is being edited at all.
        final onLayer = !app.inEditMode || img.layer == app.editingLayer;
        if (u != null) {
          final paint = Paint()..filterQuality = FilterQuality.medium;
          if (!onLayer) {
            paint.color = const Color(0x66FFFFFF); // ~40% opacity
            paint.colorFilter = const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 40, // desaturate toward grey
              0.2126, 0.7152, 0.0722, 0, 40,
              0.2126, 0.7152, 0.0722, 0, 40,
              0, 0, 0, 1, 0,
            ]);
          }
          canvas.drawImageRect(
              u,
              Rect.fromLTWH(0, 0, u.width.toDouble(), u.height.toDouble()),
              dst,
              paint);
        } else {
          canvas.drawRect(
              dst,
              Paint()
                ..color = const Color(0x33FFFFFF)
                ..style = PaintingStyle.stroke);
        }
        if (identical(img, selImage) && onLayer) {
          canvas.drawRect(
              dst,
              Paint()
                ..color = T.blue
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4);
          // resize grip (visual bottom-right) + delete X (visual top-right).
          // The HIT TEST in _scaleStart/_handleClick must match these exact
          // screen corners (dst.bottomRight / dst.topRight), not the world
          // rect's corners — screen-down is -world-y, so they differ.
          canvas.drawRect(
              Rect.fromCenter(center: dst.bottomRight, width: 12, height: 12),
              Paint()..color = T.blue);
          final xC = dst.topRight;
          canvas.drawCircle(xC, 9, Paint()..color = const Color(0xFFE05A5A));
          final xp = Paint()
            ..color = Colors.white
            ..strokeWidth = 1.6;
          canvas.drawLine(
              xC + const Offset(-3.5, -3.5), xC + const Offset(3.5, 3.5), xp);
          canvas.drawLine(
              xC + const Offset(-3.5, 3.5), xC + const Offset(3.5, -3.5), xp);
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
        // M42: construction geometry is scaffolding for constraining — it is
        // only shown while its sketch layer is being edited.
        if (!app.inEditMode && gs[i].isConstruction) continue;
        if (!geoFinite(gs[i])) {
          if (Log.every('paint-nonfinite', 500)) {
            Log.e(
                'paint',
                'SKIPPING non-finite ${geoStr(i, gs[i])} '
                    '(dragging=${app.dragGrip != null})');
          }
          continue;
        }
        try {
          final g0 = gs[i];
          final perEdge = !app.selection.contains(i) &&
              !reference &&
              !g0.isProjection && // projections are yellow as a whole (M34)
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
      if (app.showDof &&
          app.inEditMode &&
          app.tool == Tool.none &&
          an != null) {
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
      // M49 — Split preview: highlight the span the cursor is on and mark the
      // cut point(s) where the carrier meets the nearest intersecting curve.
      // Inventor shows this on hover, before the click commits anything.
      if (app.tool == Tool.split && app.hoverWorld != null) {
        final sp = app.splitPreview(app.hoverWorld!);
        if (sp != null) {
          final hi = Paint()
            ..color = T.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4;
          paintGeo(canvas, sp.pieces[sp.hovered], map, app.zoom, hi);
          final mark = Paint()..color = const Color(0xFFE0554F);
          final ring = Paint()
            ..color = const Color(0xFFE0554F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4;
          for (final c in sp.cuts) {
            final o = map(c.dx, c.dy);
            canvas.drawCircle(o, 2.5, mark);
            canvas.drawCircle(o, 5.5, ring);
          }
        }
      }
      // sketch point grips (Inventor shows them whenever no tool is active)
      if (app.tool == Tool.none) {
        final gp = Paint()..color = const Color(0xFF7BC96A);
        for (final g in gripsOf(gs)) {
          if (g.entity < gs.length && !app.geoEditable(gs[g.entity])) continue;
          final o = map(g.pos.dx, g.pos.dy);
          canvas.drawRect(Rect.fromCenter(center: o, width: 4, height: 4), gp);
        }
        if (app.dragGrip != null && app.dragPos != null) {
          final o = map(app.dragPos!.dx, app.dragPos!.dy);
          canvas.drawRect(Rect.fromCenter(center: o, width: 7, height: 7),
              Paint()..color = const Color(0xFFE05555));
        }
      }
    }

    // ---- gear tool ghost: the whole gear (or planetary set) at the cursor,
    // exactly what a tap would commit ----
    if (app.tool == Tool.gear &&
        app.gear != null &&
        app.hoverWorld != null) {
      final g = app.gear!;
      final c = app.hoverWorld!;
      final ang = g.angleRad;
      final ghost = Paint()
        ..color = T.blue.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round;
      void loop(List<Offset> pw) {
        if (pw.length < 2) return;
        final first = map(pw.first.dx, pw.first.dy);
        final p = Path()..moveTo(first.dx, first.dy);
        for (var i = 1; i < pw.length; i++) {
          final o = map(pw[i].dx, pw[i].dy);
          p.lineTo(o.dx, o.dy);
        }
        p.close();
        canvas.drawPath(p, ghost);
      }

      try {
        if (g.kind == GearKind.planetary) {
          if (g.sunTeeth >= 4 && g.planetTeeth >= 4 && g.planetCount >= 2) {
            final layout = buildPlanetaryLayout(
                base: g.params,
                sunTeeth: g.sunTeeth,
                planetTeeth: g.planetTeeth,
                planetCount: g.planetCount,
                systemAngle: ang);
            for (final m in layout.members) {
              loop(gearProfile(
                  center: c + m.center,
                  angle: m.angle,
                  params: m.params,
                  flankSamples: 14));
            }
          }
        } else {
          final p = g.params.copy()..internal = g.kind == GearKind.internal;
          if (p.valid) {
            loop(gearProfile(
                center: c, angle: ang, params: p, flankSamples: 16));
          }
        }
      } catch (_) {/* half-typed params: skip the ghost this frame */}
      // centre marker
      canvas.drawCircle(map(c.dx, c.dy), 3, Paint()..color = T.blue);
    }

    // ---- in-progress tool preview (blue, like the accent) ----
    if (app.tool != Tool.none &&
        (app.toolPoints.isNotEmpty || app.hoverWorld != null)) {
      final prev = Paint()
        ..color = T.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final pts = app.toolPoints;
      final rawHov = app.hoverWorld;
      // HUD / Dynamic Input: fold the locked/typed values into the hover point
      // so the preview shows EXACTLY what the commit will produce.
      final hov = rawHov == null ? null : app.hudApply(rawHov);
      // ONE source of truth: preview = the exact geometry the commit would
      // produce with the (locked) hover point appended.
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
        canvas.drawRect(Rect.fromCenter(center: o, width: 5, height: 5),
            Paint()..color = T.blue);
      }
      // HUD value boxes NEXT TO the live geometry, never on it: the block
      // continues the stroke direction past the tip — beyond a line's
      // endpoint, radially outside a circle's rim, outside a rectangle's
      // dragged corner. With no direction yet (first click) it trails
      // lower-right of the cursor like before.
      if (app.hudActive && rawHov != null && hov != null) {
        final a = map(hov.dx, hov.dy);
        var dir = const Offset(0.8, 0.6);
        if (pts.isNotEmpty) {
          final p = map(pts.last.dx, pts.last.dy);
          final v = a - p;
          if (v.distance > 1) dir = v / v.distance;
        }
        _paintHud(canvas, app.hudDisplays(rawHov), a, dir);
      }
    }

    // ---- constraint glyphs + dimensions (M7) ----
    // Guarded: a painter exception aborts the whole frame, which would look
    // exactly like "the app draws nothing".
    try {
      // ---- M44/M45: parametric texts (real content: visible outside edit
      // mode). The anchor (t.x, t.y) is the LOWER-LEFT of the text; the text
      // grows up and to the right so the construction bounding rect matches the
      // measurer used for snapping. The rect renders in the CONSTRUCTION
      // linetype (thin dashed) and ONLY on the layer being edited.
      app.textRects.clear();
      if (s != null) {
        final table = app.paramTable(s);
        for (final t in s.texts) {
          final rendered = renderTemplate(t.template, table);
          final fontPx = (t.height * app.zoom).clamp(3.0, 1200.0);
          final dim = !app.inEditMode || t.layer == app.editingLayer;
          final tp = TextPainter(
              text: TextSpan(
                  text: rendered,
                  style: TextStyle(
                      color: dim
                          ? const Color(0xFFDDE0E3)
                          : const Color(0x66DDE0E3),
                      fontFamily: t.font,
                      fontSize: fontPx)),
              textDirection: TextDirection.ltr)
            ..layout();
          // lower-left anchor -> the paint origin (top-left) is height up
          final o = map(t.x, t.y);
          final topLeft = o - Offset(0, tp.height);
          tp.paint(canvas, topLeft);
          final screenRect =
              Rect.fromLTWH(topLeft.dx, topLeft.dy, tp.width, tp.height);
          app.textRects.add((t, screenRect));

          // construction bounding rect (edit-mode + own layer only)
          if (app.inEditMode && t.layer == app.editingLayer) {
            final wr = app.textBoundsWorld(s, t, measure: measureSketchText);
            final a = map(wr.left, wr.top); // world-top -> screen-top
            final b = map(wr.right, wr.bottom);
            final rr = Rect.fromPoints(a, b);
            final cp = Paint()
              ..color = const Color(0xFF6FA8D8) // construction blue-grey
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            // dashed like the construction linetype
            const dash = 5.0, gap = 3.0;
            void dline(Offset p0, Offset p1) {
              final len = (p1 - p0).distance;
              if (len < 0.01) return;
              final dir = (p1 - p0) / len;
              var d = 0.0;
              while (d < len) {
                final e = (d + dash).clamp(0.0, len);
                canvas.drawLine(p0 + dir * d, p0 + dir * e, cp);
                d += dash + gap;
              }
            }

            dline(rr.topLeft, rr.topRight);
            dline(rr.topRight, rr.bottomRight);
            dline(rr.bottomRight, rr.bottomLeft);
            dline(rr.bottomLeft, rr.topLeft);
            // small square snap markers at the corners
            for (final c in [
              rr.topLeft,
              rr.topRight,
              rr.bottomLeft,
              rr.bottomRight
            ]) {
              canvas.drawRect(Rect.fromCenter(center: c, width: 4, height: 4),
                  Paint()..color = const Color(0xFF6FA8D8));
            }
          }
        }
      }

      // M42: dimensions and constraint glyphs are SKETCH-EDIT artefacts — they
      // are invisible (and untappable: rects cleared) outside layer-edit mode,
      // like Inventor hides them when the sketch is not being edited.
      if (!app.inEditMode) app.dimLabelRects.clear();
      if (s != null && app.inEditMode) {
        final gs2 = app.displayGeometry(s);
        if (app.showConstraints) {
          final seen = <String, int>{};
          final shown = [
            for (final c in s.constraints)
              if (app.constraintVisible(s, c)) c
          ];
          for (final (pos, raw) in constraintGlyphs(gs2, shown)) {
            final label = raw.split('#').first;
            final key =
                '${pos.dx.toStringAsFixed(2)},${pos.dy.toStringAsFixed(2)}';
            final slot = seen[key] = (seen[key] ?? 0) + 1;
            final o =
                map(pos.dx, pos.dy) + Offset(8.0 + 15.0 * (slot - 1), -12);
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
                labelSink: app.dimLabelRects,
                highlight: identical(c, hoverDim));
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

    // ---- pattern preview (M35): the pending copies, light blue ----
    if (app.pattern != null && s != null) {
      final ghost = app.patternPreview();
      if (ghost.isNotEmpty) {
        final gp = Paint()
          ..color = T.blue.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final g in ghost) {
          if (!geoFinite(g)) continue;
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
          canvas.drawRect(Rect.fromCenter(center: o, width: 9, height: 9), mp);
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
        _dashedLine(
            canvas,
            map(a.dx, a.dy),
            o,
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
        _dashedRect(
            canvas,
            r,
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
        final o =
            map(app.hoverWorld!.dx, app.hoverWorld!.dy) + const Offset(14, 10);
        for (var i = 0; i < hints.length; i++) {
          final tp = TextPainter(
              text: TextSpan(
                  text: constraintLabel(hints[i]),
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFFEFD37A))),
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

    // The bottom-LEFT "N degrees of freedom" readout is gone: it said the same
    // thing as the bottom-right "N dimensions needed" / "Fully Constrained"
    // overlay, in the number the user cannot act on. One status line is
    // enough, and it is the one phrased as an instruction.

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
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)),
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
          o, 3.2, Paint()..color = projCpSelected ? T.blue : T.projYellow);
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
    {List<(Constraint, Rect)>? labelSink, bool highlight = false}) {
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
      label = (c.dimKind == 'rad' ? 'R' : '⌀') + '${v.toStringAsFixed(2)} mm';
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
        canvas.drawArc(
            Rect.fromCircle(center: sv, radius: rr), a0, sweep, false, p);
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
  // M41: equation-driven dimensions carry Inventors fx: prefix — the screen
  // shows only the CALCULATED value, the raw expression reappears in the
  // edit box.
  if (c.expr != null && !c.driven) label = 'fx: $label';
  final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 11, color: Color(0xFFDDE6CF))),
      textDirection: TextDirection.ltr)
    ..layout();
  final bg =
      Rect.fromCenter(center: t, width: tp.width + 6, height: tp.height + 3);
  canvas.drawRect(
      bg,
      Paint()
        ..color =
            highlight ? const Color(0xCC2C3A4C) : const Color(0xCC212830));
  if (highlight) {
    // M42: hover feedback — this label is clickable (inserts its parameter
    // name while the expression box is open, opens the editor otherwise)
    canvas.drawRect(
        bg.inflate(1),
        Paint()
          ..color = T.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }
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

/// Inventor's heads-up value boxes: a small stack of "label value" chips to the
/// lower-right of the cursor. The focused box is outlined bright; locked boxes
/// show a padlock and the value in the accent colour.
void _paintHud(Canvas canvas, List<(String, String, bool, bool, bool)> rows,
    Offset anchor, Offset dir) {
  if (rows.isEmpty) return;
  const pad = 6.0, gap = 4.0, rowGap = 4.0, lockW = 10.0;
  final labelTps = <TextPainter>[], valueTps = <TextPainter>[];
  var maxLabel = 0.0, maxValue = 0.0, glyphH = 0.0;
  for (final r in rows) {
    final label = r.$1;
    final value = r.$2;
    final locked = r.$3;
    final focused = r.$4;
    final lt = TextPainter(
        text: TextSpan(text: label, style: ts(11, T.dim)),
        textDirection: TextDirection.ltr)
      ..layout();
    final vt = TextPainter(
        text: TextSpan(
            text: value,
            style: ts(11.5, locked ? T.blue : T.text,
                w: focused ? FontWeight.w600 : FontWeight.w500)),
        textDirection: TextDirection.ltr)
      ..layout();
    labelTps.add(lt);
    valueTps.add(vt);
    maxLabel = math.max(maxLabel, lt.width);
    maxValue = math.max(maxValue, vt.width);
    glyphH = math.max(glyphH, math.max(lt.height, vt.height));
  }
  final boxW = pad + maxLabel + gap + maxValue + lockW + pad;
  final rowH = glyphH + 5;
  // Slide the whole block 26 px past the anchor ALONG the stroke and let it
  // grow away from the geometry (leftwards when the stroke points left,
  // upwards when it points up) — so it can never lie on the rubber band.
  final blockH = rows.length * rowH + (rows.length - 1) * rowGap;
  final base = anchor + dir * 26;
  final left = dir.dx >= 0 ? base.dx + 4 : base.dx - boxW - 4;
  var top = dir.dy >= 0 ? base.dy + 4 : base.dy - blockH - 4;
  for (var i = 0; i < rows.length; i++) {
    final locked = rows[i].$3, focused = rows[i].$4;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, boxW, rowH), const Radius.circular(4));
    canvas.drawRRect(
        rect,
        Paint()
          ..color =
              focused ? const Color(0xF01E2A38) : const Color(0xE01B1E22));
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = focused ? 1.4 : 1.0
          ..color = focused ? T.hover : T.panelSep);
    labelTps[i].paint(
        canvas, Offset(left + pad, top + (rowH - labelTps[i].height) / 2));
    valueTps[i].paint(
        canvas,
        Offset(left + pad + maxLabel + gap,
            top + (rowH - valueTps[i].height) / 2));
    if (locked) {
      _paintLock(canvas, Offset(left + boxW - pad - lockW / 2, top + rowH / 2),
          T.blue);
    }
    top += rowH + rowGap;
  }
}

void _paintLock(Canvas canvas, Offset c, Color color) {
  final body =
      Rect.fromCenter(center: c + const Offset(0, 1.5), width: 6, height: 4.5);
  canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(1)),
      Paint()..color = color);
  canvas.drawPath(
      Path()
        ..addArc(Rect.fromCircle(center: c + const Offset(0, -1.2), radius: 2),
            math.pi, math.pi),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color);
}

void _dashedRect(Canvas c, Rect r, Paint p) {
  _dashedLine(c, r.topLeft, r.topRight, p);
  _dashedLine(c, r.topRight, r.bottomRight, p);
  _dashedLine(c, r.bottomRight, r.bottomLeft, p);
  _dashedLine(c, r.bottomLeft, r.topLeft, p);
}

/// M53 — a ScaleGestureRecognizer that refuses TOUCH pointers while the
/// Apple Pencil is down. Rejection happens at arena entry (isPointerAllowed),
/// so a resting palm never becomes the "second finger" that flips a running
/// Pencil stroke into pan/zoom.
class _PalmAwareScale extends ScaleGestureRecognizer {
  _PalmAwareScale({required this.rejectTouch});
  final bool Function() rejectTouch;
  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch && rejectTouch()) return false;
    return super.isPointerAllowed(event);
  }
}
