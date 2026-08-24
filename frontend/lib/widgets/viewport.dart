// Prototype — viewport (#viewport / #sketchsvg), 1:1 port + real drawing.
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
import '../gesture_trace.dart';
import '../log.dart';
import '../menus.dart';
import '../constraints.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../perf.dart';
import '../part_model.dart' show kSectionHatch;
import '../pick_math.dart';
import 'package:native_menu/native_menu.dart';

import '../snap.dart';
import '../tools.dart';
import '../theme.dart';
import 'scrub_field.dart';
import 'ribbon_chrome.dart';
import '../touch.dart';
import 'bottom_tabbar.dart';
import 'dialog_dock.dart';
import 'pattern_dialog.dart';
import 'quick_tools.dart';
import 'viewport_window.dart';
import 'parameters_dialog.dart';
import 'freehand_dialog.dart';
import 'gear_dialog.dart';
import 'text_editor_window.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../inserts.dart';
import '../l10n/fmt.dart';
import '../l10n/l.dart';
import '../text_geometry.dart' show textLayoutOf;
import '../vector_font.dart' show measureText;

/// M45 — measures a rendered string into world-mm (width,height) for a text's
/// font and size. Single source of truth for the bounding rect and its snap
/// points.
///
/// M220 — measured from the OUTLINE font, not from a TextPainter. The box has
/// to bound the curves that are drawn, exported and extruded, and those come
/// from vector_font.dart; a screen font's metrics would have described a
/// different shape than the one in the file.
Size measureSketchText(SketchText t, String rendered) =>
    measureText(rendered.isEmpty ? ' ' : rendered, t.font, t.height);

class Viewport2D extends StatefulWidget {
  final AppState app;
  const Viewport2D({super.key, required this.app});
  @override
  State<Viewport2D> createState() => _Viewport2DState();
}

class _Viewport2DState extends State<Viewport2D> with WidgetsBindingObserver {
  bool _projCpSelected = false; // mock: click toggles yellow <-> blue
  double _panZoomStartZoom = 1;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // M206: see didChangeAppLifecycleState
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
    WidgetsBinding.instance.removeObserver(this);
    _lpTimer?.cancel();
    _liveWatchdog?.cancel();
    _closeQuickMenu();
    // A viewport torn down with the dimension box still open must not leave
    // the journal switched off for the rest of the session (M179).
    _endInlineEdit();
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

  /// M205 — every contact that is down, and the eviction rule for the ones
  /// that never came back up (see [LivePointers]). This replaced a bare
  /// counter: a single lost pointer-up used to leave the tally at 1 forever,
  /// which made every later tap look like a second finger and turned the whole
  /// viewport into a pan/zoom surface that could not draw, pick or drag.
  final LivePointers _live = LivePointers();

  /// Watchdog for [_live]: without it a lost contact is only noticed when the
  /// NEXT one goes down — i.e. the user's next gesture is the one it eats.
  Timer? _liveWatchdog;
  Offset? _clickDown;

  /// M51 — device kind of the pointer that armed [_clickDown]; picks and
  /// snaps widen for fingers (see touch.dart) and stay precise for the
  /// Pencil and the mouse.
  PointerDeviceKind _downKind = PointerDeviceKind.mouse;

  /// Touch pointers rejected as palm contact (arrived while the Pencil was
  /// down). They never count as clicks, taps or gesture fingers.
  final Set<int> _rejectedTouches = {};
  bool get _stylusDown => _live.stylusDown;

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

  /// True while the press that is in flight started on a floating window.
  bool _downOnWindow = false;

  /// M209 — does [local] (viewport coords) land on a floating window?
  ///
  /// Asked at pointer DOWN as well as at the click, because a press that
  /// becomes a drag on a window's slider must not also start drawing.
  bool _onWindow(Offset local) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return ViewportWindow.hits(box.localToGlobal(local));
  }

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
    // M209 — every modeless window floats INSIDE the same Stack this Listener
    // wraps, so the Listener sees pointer-ups over them too. A tap on the
    // Freehand window's Finish button committed the curve AND placed the first
    // point of the next one; before that, M61 met the same thing on the Gear
    // dialog and guarded that ONE rectangle by hand. The windows say where
    // they are now — see [ViewportWindow].
    if (_onWindow(local)) return;
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

  /// Screen position of the last drag update — the release point, in the same
  /// space as [_toolDownLocal]. The world pair is not interchangeable with it:
  /// the threshold below is a THUMB-and-tip distance and has to be measured in
  /// pixels, or it would mean different things at different zooms.
  Offset? _toolDragLocal;
  bool _toolDragPlaced = false;

  /// M206 — how far a press must travel before it becomes a DRAWING DRAG.
  ///
  /// It was a flat 8 px, and that is inside the wobble of an ordinary Pencil
  /// tap. In `bug20260805T142912` eleven taps crossed it, and every one of
  /// them placed TWO points at the same spot: the update that crossed the
  /// threshold placed the anchor, and the release — which the recognizer
  /// dispatches from the SAME pointer event, 0.07 ms later — placed the drag
  /// point on top of it.
  ///
  ///     14:26:59.050361  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=0
  ///     14:26:59.050432  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=1
  ///     14:26:59.712185  toolClick tool=Tool.arcThreePoint w=( 1.48,20.00) picks=2
  ///     layer: tool Tool.arcThreePoint built no geometry from 3 point(s)
  ///
  /// Two of the three points are the same point, so the arc is degenerate and
  /// nothing is ever committed — "i can't finish drawing the arc properly".
  /// A circle gets a rim on its own centre and comes out with no radius.
  ///
  /// Measured against the traces in that bundle: taps wobble up to ~8 px,
  /// deliberate strokes run 25 to 70. 18 px separates them with room on both
  /// sides, and a finger gets the usual 1.8x.
  double get _toolDragPx =>
      touchSlop(_gestureFinger ? PointerDeviceKind.touch : _downKind, 18);
  int?
      _clickPtr; // the pointer that armed _clickDown (a palm up must not fire it)
  Offset? _lastStylusLocal; // fallback anchor for the Pencil-squeeze menu

  // M47: whole-entity body drag (grab the line/curve itself, not a grip point).
  int? _bodyEnt; // entity picked for a body drag
  Offset? _bodyAnchorW; // world point the finger grabbed
  bool _bodyStarted = false; // deferred begin: true once the drag actually ran

  /// Applies object snapping to a world point and publishes the marker.
  ///
  /// On the drag path this runs per pointer-move event, i.e. at the touch
  /// sampling rate (up to 120 Hz on ProMotion), and it walks the whole visible
  /// geometry list twice — once to filter, once inside [computeSnap]. That
  /// makes it a per-frame cost that does not appear in `2d.paint` at all,
  /// which is exactly the kind of blind spot M75 was about.
  Offset _snapped(Offset w, {Offset? exclude, double px = _snapPx}) =>
      snapViewportForBenchmark(widget.app, w, exclude: exclude, px: px);

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
    // M209 — the press began on a floating window; it is that window's drag
    // (a slider, a title bar), not a gesture on the canvas.
    if (_downOnWindow) {
      _gesture = 'none';
      return;
    }
    _scaleStartZoom = app.zoom;
    // M51: the kind of the SINGLE pointer driving this gesture. Fingers get
    // wider grab radii and, on empty canvas, pan instead of box-selecting.
    final soleKind = _live.soleKind;
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
        _toolDragLocal = lp;
        if (!_toolDragPlaced &&
            _toolDownLocal != null &&
            (lp - _toolDownLocal!).distance > _toolDragPx) {
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
          title: Text(L.of(context).hudOverConstrained,
              style: TextStyle(
                  fontSize: 14,
                  color: T.text,
                  fontWeight: FontWeight.w600)),
          content: Text(L.of(ctx).msgWouldOverConstrain,
              style: TextStyle(fontSize: 13, color: T.text)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(L.of(context).cancel,
                    style: TextStyle(fontSize: 12.5, color: T.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(L.of(context).hudDriven,
                    style: TextStyle(fontSize: 12.5, color: T.accent))),
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

  // M179 — ONE dimension edit is ONE undo step, however the number got there.
  //
  // The box drives the sketch live now: every detent of a scrub really solves,
  // so the geometry follows the finger instead of jumping on Enter. That would
  // otherwise cost a journal entry per detent, and Esc would have nothing to go
  // back to — so the whole time the box is open, AppState's live-edit bracket
  // holds checkpoints and messages back (the drag's own bracket nests inside
  // it, which is why that counter counts). Committing lifts the bracket and
  // applies once; Esc lifts it and restores the entry the journal never moved
  // off, which is the sketch exactly as the box found it.
  bool _inlineBracket = false;

  /// True once something in this editing session actually reached the sketch —
  /// the only case where Esc has anything to put back.
  bool _inlineLive = false;

  void _beginInlineEdit() {
    if (_inlineBracket) return;
    _inlineBracket = true;
    widget.app.beginLiveEdit();
  }

  void _endInlineEdit() {
    if (!_inlineBracket) return;
    _inlineBracket = false;
    widget.app.endLiveEdit();
  }

  /// M42: the dimension label under the mouse — highlighted whenever it is
  /// actionable: while the expression box is open (click inserts the
  /// parameter name, Inventor-style) and in plain layer-edit mode (tap opens
  /// the value editor).
  Constraint? _hoverDimLabel;

  // M206 — the movable windows park on the RIGHT, beside the quick-tool bar,
  // the way the Extrude panel and the Pattern dialog already do. They used to
  // open at a hard-coded Offset(60, 60) / (90, 90), which is the top-left
  // corner — i.e. underneath the model browser: "the gear dialog should spawn
  // at the right like the extrude panel and all other dialogs. now it spawns
  // under the Modell browser."
  //
  // Null means "not moved yet": the spot depends on the viewport size, which
  // is only known in build, and a window the user HAS dragged must stay where
  // they put it. See [DialogDock].
  static const Size _paramsSize = Size(420, 460);
  static const Size _gearSize = Size(300, 560);
  static const Size _textWinSize = Size(360, 320);
  Offset? _paramsPos;
  Offset? _gearPos;
  // M87 — where the freehand fit window sits (set to the end of the stroke).
  Offset _freehandPos = const Offset(120, 120);
  final GlobalKey _gearDialogKey = GlobalKey();

  /// M45: position of the movable text editor window.
  Offset? _textWinPos;

  /// Where a movable window sits: where the user dragged it, or its parking
  /// spot if they never have. Clamped so it can never be dragged (or docked)
  /// so far that its own title bar leaves the viewport.
  Offset _windowPos(Offset? moved, Size viewport, Size dialog) {
    final p = moved ?? DialogDock.spot(viewport, dialog);
    return Offset(
      p.dx.clamp(0.0, (viewport.width - 120).clamp(0.0, double.infinity)),
      p.dy.clamp(0.0, (viewport.height - 60).clamp(0.0, double.infinity)),
    );
  }
  // M44: insert-content interaction state
  final Map<String, ui.Image?> _imgCache = {}; // null = loading/broken
  SketchImage? _selImage; // selected image (shows resize/delete grips)
  SketchImage? _dragImage;
  SketchText? _dragText;
  Offset _dragOff = Offset.zero;
  final TextEditingController _dimCtrl = TextEditingController();
  final FocusNode _dimFocus = FocusNode();

  void _openInlineEditor(Constraint d, {required bool isNew}) {
    _beginInlineEdit();
    setState(() {
      _inlineDim = d;
      _inlineIsNew = isNew;
      _inlineLive = false;
      // M41: the box shows the RAW expression when the dimension is driven
      // by one (Inventor: value collapses on screen, equation reappears on
      // edit); a plain-value dimension shows its number.
      // M234 — the field is seeded in the UI's convention (decimal comma in
      // German), which is safe because every reader of it goes through
      // parseValueExpr / Fmt.num, and both accept ',' and '.' whatever the
      // language. An expression (d.expr) is user text and is shown verbatim.
      _dimCtrl.text = d.expr ??
          (_isAngleKind(d)
              ? Fmt.fixed(d.value ?? 0, 1)
              : Fmt.fixed(d.value ?? 0, 2));
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
    // Journalling and messages back on BEFORE the commit: this is the call
    // that has to land in history as the one step for the whole edit, and the
    // one allowed to say why a value was refused.
    _endInlineEdit();
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
    final live = _inlineLive;
    setState(() {
      _inlineDim = null;
      _inlineLive = false;
    });
    _endInlineEdit();
    if (live) {
      // M179 — a scrub already drove the sketch, and for a dimension being
      // placed it had to CREATE it first. Nothing since the box opened was
      // journalled, so the entry the journal is still sitting on is the sketch
      // as it was: restoring it takes the value, the geometry and the
      // dimension itself back in one move.
      widget.app.revertToLastCheckpoint();
    } else if (_inlineIsNew) {
      widget.app.cancelDimension();
    }
    _focus.requestFocus();
  }

  /// M179 — a detent of a scrub, applied to the SKETCH rather than only to the
  /// number in the box. This is the whole point of dragging a dimension: the
  /// geometry moves under the finger, so the value is chosen by looking at the
  /// drawing instead of at the box.
  void _scrubDim(String text) {
    final app = widget.app;
    final d = _inlineDim;
    setState(() {}); // the box repaints with the new number either way
    if (d == null || !app.dimTextValid(d, text)) return;
    if (_inlineIsNew) {
      // Placing a dimension and dragging it to size is ONE gesture, so the
      // dimension has to become real for the sketch to have anything to drive.
      // confirmDimensionText creates it with its MEASURED value first — which
      // moves nothing — and applies the dragged value on top. Esc still takes
      // the whole gesture back, dimension included; see _cancelInline.
      app.confirmDimensionText(text);
      _inlineIsNew = false;
      _inlineLive = true;
      return;
    }
    app.setDimensionText(d, text);
    _inlineLive = true;
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
            border: Border.all(color: T.accent, width: 1),
            boxShadow: [
              BoxShadow(color: T.shadow, blurRadius: 6),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          // M172 — drag the box left or right to scrub the dimension in
          // detents sized by the current zoom. Tap still opens the pad.
          child: ScrubField(
            app: widget.app,
            controller: _dimCtrl,
            onCommit: _scrubDim,
            // M206 — with no software keyboard there is no Return key on
            // touch, so the pad's OK has to be the same exit onSubmitted is
            // below. Without this the only way to close the box with a finger
            // would be to tap the canvas, which also places whatever the
            // armed tool places.
            onDone: _submitInline,
            child: TextField(
            controller: _dimCtrl,
            focusNode: _dimFocus,
            autofocus: true,
            // M41 accepts full expressions, but a dimension is a NUMBER
            // almost every time it is typed, and on touch or Pencil a full
            // QWERTY buries the geometry being dimensioned. M171 — the numeric
            // pad. An expression still goes in from a hardware keyboard, or
            // through the Parameters window, which keeps its text keyboard for
            // exactly that reason.
            keyboardType: kValueKeyboard,
            // M179 — no Scribble here. Dragging the Pencil across a dimension
            // is how it is sized; handwriting would take that stroke.
            stylusHandwritingEnabled: kValueHandwriting,
            autocorrect: false,
            enableSuggestions: false,
            // Inventor colours invalid syntax red while you type
            style: TextStyle(
                fontSize: 13, color: valid ? T.text : T.err),
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            // outside taps are handled by _handleClick (reference-insert or
            // commit) — the default unfocus-on-tap-outside must not race it
            onTapOutside: (_) {},
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              prefixText: name != null ? '$name = ' : null,
              prefixStyle: TextStyle(fontSize: 11, color: T.dim),
              suffixText: _isAngleKind(d) ? '\u00b0' : 'mm',
              suffixStyle: TextStyle(fontSize: 11, color: T.dim),
            ),
            onSubmitted: (_) => _submitInline(),
            ),
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
  /// since M192 is no longer the only way to Enter (OK) and Esc (Cancel): the
  /// quick-tool bar on the right edge carries both permanently.
  ///
  /// M193 — with no tool running, a long press on an entity SELECTS it first,
  /// so the menu's Delete acts on the thing under the finger. Long-pressing a
  /// line and being offered a delete for whatever happened to be selected
  /// somewhere else would be worse than offering nothing.
  void _fireLongPress(Offset local, Size size, PointerDeviceKind kind) {
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
    _toolDragLocal = null;
    _toolDragPlaced = false;
    _mft.nonTouchActivity();
    HapticFeedback.selectionClick();
    if (app.cycleModifyTool()) return;
    // M193 — with no tool armed, the press picks what is under it so the
    // menu's Delete has something to act on. An EXISTING selection is left
    // alone: a long press inside a box-selected group must not collapse it to
    // the one entity under the finger.
    if (app.tool == Tool.none && app.inEditMode && app.selection.isEmpty) {
      app.selectAt(_toWorld(local, size), touchSlop(kind, 10) / app.zoom);
    }
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

  /// M206 — leaving and coming back is a hard reset for input, and until now
  /// it was the ONLY one.
  ///
  /// `bug20260805T142912` is 91 seconds of a viewport that answered nothing:
  /// Pencil taps, two-finger taps, not one `toolClick` in the log. What ended
  /// it is in the log too, and it is not something the user did to the sketch:
  ///
  ///     14:29:17  lifecycle: paused
  ///     14:29:53  lifecycle: resumed
  ///     14:29:54  click: toolClick tool=Tool.arcThreePoint ... picks=0
  ///
  /// One second after coming back, drawing worked again. Backgrounding cancels
  /// every pointer, which is what cleared the contact the app still believed
  /// was down. M205's watchdog now cuts that from 91 seconds to about two, but
  /// a resume is the one moment where staleness is CERTAIN rather than
  /// inferred — nothing that was touching the glass before the app went away
  /// is touching it now — so it clears the set outright instead of waiting for
  /// the timer to work it out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      if (_live.isEmpty) return;
      _live.clear();
      _rejectedTouches.clear();
      _clickDown = null;
      _clickPtr = null;
      _cancelLp();
      _disarmLiveWatchdogIfIdle();
      GestureTrace.note('lifecycle $state: contacts cleared');
      Log.i('viewport', 'M206: lifecycle $state — live contacts cleared');
    }
  }

  // ---- M205: lost contacts ----

  /// Clears everything keyed by a pointer id for contacts [LivePointers] just
  /// dropped as lost. A stale id left in [_rejectedTouches] would reject a
  /// finger that is not there, and one left in [_mft] would poison every
  /// two-finger undo tap for the rest of the session.
  void _forgetLost(List<int> lost) {
    if (lost.isEmpty) return;
    for (final p in lost) {
      _rejectedTouches.remove(p);
      _mft.cancel(p);
      if (p == _clickPtr) {
        _clickPtr = null;
        _clickDown = null;
      }
    }
    GestureTrace.note('lost ${lost.length} contact(s): $lost');
    Log.i('viewport', 'M205: dropped lost contacts $lost');
  }

  /// Runs only while something is down, so an idle app keeps no timer.
  void _armLiveWatchdog() {
    _liveWatchdog ??= Timer.periodic(
        const Duration(milliseconds: 500), (_) => _sweepLostContacts());
  }

  void _disarmLiveWatchdogIfIdle() {
    if (_live.isEmpty) {
      _liveWatchdog?.cancel();
      _liveWatchdog = null;
    }
  }

  void _sweepLostContacts() {
    _forgetLost(_live.pruneStale());
    _disarmLiveWatchdogIfIdle();
  }

  void _closeQuickMenu() {
    OpenMenus.unregister(_closeQuickMenu);
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
        _qmItem(L.of(context).hudCancelEsc, () {
          app.cancelTool();
        }),
      // M193 — delete what is selected. On a touch-only device this and the
      // bar's trash button are the only ways to remove one entity; before
      // them the smallest thing a sketch could lose was a whole layer.
      if (app.canDeleteSelection)
        _qmItem(
            app.selection.length > 1
                ? L.of(context).hudDeleteN(app.selection.length)
                : L.of(context).delete,
            () => app.deleteSelection(),
            destructive: true),
      if (app.inEditMode) ...[
        _qmItem(L.of(context).hudLineKey, () => app.selectTool(Tool.line)),
        _qmItem(L.of(context).hudCircleKey, () => app.selectTool(Tool.circleCenter)),
        _qmItem(L.of(context).hudRectKey, () => app.selectTool(Tool.rectTwoPoint)),
        _qmItem(L.of(context).hudDimensionKey, () => app.selectTool(Tool.dimension)),
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
                color: T.fly,
                border: Border.all(color: T.sep),
                boxShadow: [
                  BoxShadow(
                      color: T.shadow,
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
    OpenMenus.register(_closeQuickMenu);
  }

  Widget _qmItem(String label, VoidCallback onTap, {bool destructive = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _closeQuickMenu();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // UIKit draws destructive rows red and we never colour anything else
        // ourselves — same tone the native menus get from the system.
        child: Text(label,
            style: ts(12.5, destructive ? T.err : T.mbText)),
      ),
    );
  }

  void _scaleEnd() {
    final app = widget.app;
    switch (_gesture) {
      case 'tooldrag': // M53: release places the second point
        // M206 — and only if the drag actually WENT somewhere. The update that
        // arms this gesture can be the one carried by the pointer-up itself,
        // in which case the anchor and the release are the same point, and
        // placing both is how a three-point arc ended up with two identical
        // points and built nothing at all. Releasing on the anchor leaves the
        // tool holding its first point, which is the click-click flow the user
        // gets from a plain tap anyway — nothing is lost, and the next tap
        // places the second point where they meant it.
        final travelled = _toolDownLocal != null &&
            _toolDragLocal != null &&
            (_toolDragLocal! - _toolDownLocal!).distance > _toolDragPx;
        if (_toolDragPlaced && _toolDragW != null && travelled) {
          app.toolClick(_snapped(_toolDragW!,
              px: _gestureFinger
                  ? touchSlop(PointerDeviceKind.touch, _snapPx)
                  : _snapPx));
          if (app.pendingDim != null) _showDimDialog(app.pendingDim!);
        }
        _toolDownLocal = null;
        _toolDragW = null;
        _toolDragLocal = null;
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
          // M87 — the freehand fit window owns Enter and Esc while it is up,
          // BEFORE the generic tool handlers below: Enter must finish the
          // curve rather than the variable-point tool, and Esc must throw the
          // ink away while leaving the tool armed for the next stroke.
          if (event is KeyDownEvent && app.freehand != null) {
            final k = event.logicalKey;
            if (k == LogicalKeyboardKey.enter ||
                k == LogicalKeyboardKey.numpadEnter) {
              app.freehandCommit();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.escape) {
              app.freehandCancel();
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            app.cancelTool();
            return KeyEventResult.handled;
          }
          // M193 — Delete / Backspace remove the selection. Below the HUD and
          // freehand blocks on purpose: while a value is being typed,
          // Backspace edits the number and never touches geometry.
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace)) {
            if (app.canDeleteSelection) {
              app.deleteSelection();
              return KeyEventResult.handled;
            }
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
              // M177 — saveCurrentDocument, not saveSketch: this fired in
              // parts too, where saveSketch could only ever fail. It also
              // writes an externally-opened document back to the file it came
              // from, and says which it was.
              app.saveCurrentDocument();
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
            // M207 — THE PENCIL THAT LEFT THE GLASS.
            //
            // "When i hover and the hover is interrupted because the distance
            // from pencil to screen is too far, the preview should stay
            // exactly like it was for this moment until the hover with pencil
            // is back. Right now the preview goes somewhere in the top left
            // corner for a moment, which results in a weird long line over the
            // screen."
            //
            // The corner is the tell. A hover reported at the window ORIGIN is
            // not a place the Pencil was — it is what arrives as the pointer
            // is torn down, the same synthetic (0,0) that the cancel storm in
            // M205 carried. Fed to _toWorld it is the viewport's top-left
            // corner, and the rubber band snaps a line the whole width of the
            // screen for one frame.
            //
            // Global, not local: the viewport's own local (0,0) could in
            // principle be hovered, but the window's is under the ribbon and
            // never can be. Dropping the event entirely is exactly what was
            // asked for — the preview simply keeps the last real position
            // until the tip comes back.
            if (e.position == Offset.zero) {
              GestureTrace.note('hover at the origin dropped (pointer gone)');
              return;
            }
            app.lastPointerWorld = _toWorld(e.localPosition, size); // M45
            // M207 — a FINISHED freehand stroke is not a rubber band. Once the
            // fit window is up the curve is decided; only its sliders may
            // change it. Hover kept feeding hoverWorld, and the preview draws
            // toolPoints PLUS the hover point, so the spline "still goes on"
            // under the Pencil after it was finished.
            if (app.tool != Tool.none && app.freehand == null) {
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
            // Register FIRST, and register every pointer: the up/cancel paths
            // remove unconditionally, so an early return here would leave the
            // set one short and make the next real finger look like the first
            // — i.e. a pan/zoom that starts drawing instead.
            //
            // M205: registering also EVICTS contacts that iOS lost (a down
            // with no up, see [LivePointers]). Anything evicted has to be
            // forgotten by the bookkeeping that hangs off a pointer id too,
            // or a stale palm id would keep rejecting a finger that has long
            // since lifted.
            _forgetLost(_live.down(e.pointer, e.device, e.kind));
            _armLiveWatchdog();
            // M209 — a press that lands on a floating window belongs to that
            // window. Recorded here rather than tested again at up, because a
            // window that MOVES under the finger (its own title-bar drag) must
            // not turn the release into a canvas click.
            _downOnWindow = _onWindow(e.localPosition);
            if (_downOnWindow) {
              _clickDown = null;
              _cancelLp();
              return;
            }
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
              // tip touches, not only after the first move. M207: not while a
              // finished freehand stroke is waiting on its fit window.
              if (app.tool != Tool.none && app.freehand == null) {
                app.setHover(_snapped(_toWorld(e.localPosition, size)));
              }
            }
            if (_live.count > 1) {
              _clickDown = null; // second finger: pan/zoom, never a click
              _cancelLp();
              // M87: a second finger means pan/zoom, so the freehand stroke
              // that the first finger started is abandoned rather than left
              // half-drawn while the view moves under it.
              if (app.freehand?.drawing == true) app.freehandCancel();
              return;
            }
            // M87 — FREEHAND: the stroke owns the pointer from here. It must
            // start before the click/long-press machinery so that drawing is
            // never mistaken for a tap, and it only runs with a single pointer
            // (checked above) so palm + pencil still behave.
            if (app.tool == Tool.splineFree &&
                app.freehand == null &&
                app.inEditMode &&
                (e.kind == PointerDeviceKind.touch ||
                    e.kind == PointerDeviceKind.stylus ||
                    e.kind == PointerDeviceKind.mouse)) {
              app.freehandBegin(_toWorld(e.localPosition, size));
              _cancelLp(); // drawing is not a long-press
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
                  () => _fireLongPress(e.localPosition, size, e.kind));
            }
          },
          onPointerMove: (e) {
            // M205 — a moving contact is by definition alive: this refreshes
            // it, and RE-ADOPTS it if the watchdog evicted it in error. That
            // is what makes the silence rule safe to be wrong about.
            _live.touch(e.pointer, e.device, e.kind);
            final rejected = _rejectedTouches.contains(e.pointer);
            // M87 — freehand ink. A rejected touch (palm) must never draw.
            if (!rejected && app.freehand?.drawing == true) {
              app.freehandExtend(_toWorld(e.localPosition, size));
              return;
            }
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
              if (app.tool != Tool.none &&
                  _toolCtx == null &&
                  app.freehand == null) {
                app.setHover(_snapped(_toWorld(e.localPosition, size)));
              }
            }
            final d = _clickDown;
            if (d != null && (e.localPosition - d).distance > 14) {
              _clickDown = null; // it's a drag
            }
          },
          onPointerCancel: (e) {
            _live.remove(e.pointer);
            _disarmLiveWatchdogIfIdle();
            _downOnWindow = false;
            _rejectedTouches.remove(e.pointer);
            if (e.kind == PointerDeviceKind.touch) _mft.cancel(e.pointer);
            _cancelLp();
            _clickDown = null;
          },
          onPointerUp: (e) {
            _live.remove(e.pointer);
            _disarmLiveWatchdogIfIdle();
            if (_downOnWindow) {
              _downOnWindow = false;
              return; // M209: the window had it
            }
            final wasRejected = _rejectedTouches.remove(e.pointer);
            _cancelLp();
            // M86 — THE PHANTOM SPLINE POINT. A finger and a no-hover Pencil
            // have no cursor once they lift, but setHover was only ever
            // called on down/move and never cleared. hoverWorld therefore kept
            // the last contact point, and every in-progress preview kept
            // treating it as a real pick: on a spline that is an extra fit
            // point, drawn as a stray tail running past the last placed grip —
            // "it looks like there is a point but there isn't", and it
            // disappears on finish because the committed geometry never had
            // it. Lifting now clears the hover. Hover-CAPABLE devices (mouse,
            // Pencil Pro/M2) re-report on their very next hover event, so they
            // are unaffected.
            if (e.kind == PointerDeviceKind.touch ||
                e.kind == PointerDeviceKind.stylus ||
                e.kind == PointerDeviceKind.invertedStylus) {
              app.setHover(null);
            }
            // M87: lifting ends the freehand stroke and opens the fit dialog.
            if (app.freehand?.drawing == true) {
              _freehandPos = e.localPosition + const Offset(18, 18);
              app.freehandEnd();
              return;
            }
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
                  //
                  // M192 — clear of the quick-tool bar, which owns the right
                  // edge now. A tall dialog reached down into it.
                  if (app.pattern != null)
                    Positioned(
                        right: 12 + QuickToolsBar.occupiedWidth,
                        top: 12 + RibbonMetrics.contentTop,
                        child: ViewportWindow(child: PatternDialog(app: app))),
                  // M43: movable Parameters (fx) window
                  if (app.showParams)
                    Positioned(
                      left: _windowPos(_paramsPos, size, _paramsSize).dx,
                      top: _windowPos(_paramsPos, size, _paramsSize).dy,
                      child: ViewportWindow(
                        child: ParametersDialog(
                            app: app,
                            onDrag: (d) => setState(() => _paramsPos =
                                _windowPos(_paramsPos, size, _paramsSize) + d)),
                      ),
                    ),
                  // M61: movable Gear window
                  if (app.gear != null)
                    Positioned(
                      left: _windowPos(_gearPos, size, _gearSize).dx,
                      top: _windowPos(_gearPos, size, _gearSize).dy,
                      child: ViewportWindow(
                        child: GearDialog(
                            key: _gearDialogKey,
                            app: app,
                            onDrag: (d) => setState(() => _gearPos =
                                _windowPos(_gearPos, size, _gearSize) + d)),
                      ),
                    ),
                  // M87: movable Freehand fit window — opens where the stroke
                  // ended, so the curve is not hidden behind its own dialog.
                  if (app.freehand != null && app.freehand!.drawing == false)
                    Positioned(
                      // M206 — it opens where the STROKE ended (M87), which
                      // is the point of it, but the right edge belongs to the
                      // quick-tool bar: clamped in, never under.
                      left: _freehandPos.dx.clamp(
                          0.0, DialogDock.left(size, 268)),
                      top: _freehandPos.dy.clamp(0.0, size.height - 60),
                      child: ViewportWindow(
                        child: FreehandDialog(
                            app: app,
                            onDrag: (d) => setState(() => _freehandPos += d)),
                      ),
                    ),
                  // M45: movable parametric-text editor window
                  if (app.editingText != null)
                    Positioned(
                      left: _windowPos(_textWinPos, size, _textWinSize).dx,
                      top: _windowPos(_textWinPos, size, _textWinSize).dy,
                      child: ViewportWindow(
                        child: TextEditorWindow(
                            app: app,
                            onDrag: (d) => setState(() => _textWinPos =
                                _windowPos(_textWinPos, size, _textWinSize) + d)),
                      ),
                    ),
                  // 2D Fillet / Chamfer value window (M36), same parking spot
                  if (app.filletSess != null &&
                      (app.tool == Tool.fillet || app.tool == Tool.chamfer))
                    Positioned(
                        right: 12 + QuickToolsBar.occupiedWidth,
                        top: 12 + RibbonMetrics.contentTop,
                        child: ViewportWindow(child: FilletChamferDialog(app: app))),
                  // M207 — the Polygon side count, in the same idiom and the
                  // same spot. It used to be a modal AlertDialog answered
                  // before the tool armed; now the tool is live and the number
                  // applies to the next polygon, exactly like the fillet
                  // radius applies to the next corner.
                  if (app.tool == Tool.polygon)
                    Positioned(
                        right: 12 + QuickToolsBar.occupiedWidth,
                        top: 12 + RibbonMetrics.contentTop,
                        child: ViewportWindow(child: PolygonDialog(app: app))),
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
                              ? L.of(context).hudFullyConstrained
                              : '${app.analysis!.dof} dimensions needed',
                          style: TextStyle(
                            fontSize: 11,
                            color: app.analysis!.dof <= 0
                                ? T.text
                                : T.dim,
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

  /// Per-phase timing for [_paint]. ONE instance for the whole app, on
  /// purpose: a painter is rebuilt on every frame, so a per-instance field
  /// would allocate a Stopwatch and a name cache 120 times a second, and the
  /// measuring apparatus would become part of what is being measured.
  ///
  /// Safe as shared state because `_paint` is not re-entrant and Flutter runs
  /// it on the UI thread only. [PerfPhases.mark] ignores a call outside a
  /// begin/end pair, so even a stray path cannot corrupt another frame.
  static final PerfPhases _ph = PerfPhases('2d.paint');

  @override
  void paint(Canvas canvas, Size size) => Perf.span('2d.paint', () {
        _ph.begin();
        try {
          _paint(canvas, size);
        } finally {
          // `2d.paint.z` catches everything after the last mark. If it ever
          // grows, a phase was added to _paint without a mark to close it.
          _ph.end();
        }
      });

  void _paint(Canvas canvas, Size size) {
    // M80 — when a sketch is open inside a part, the LIVE RealityKit scene is
    // rendered behind this canvas (main.dart) with its camera aimed down the
    // sketch plane. So this painter must stay TRANSPARENT and only veil the
    // model, instead of drawing its own opaque background over it.
    //
    // This replaces the CPU underlay (paintPartUnderlay), which rebuilt one
    // SceneTri per triangle on every paint — 34 236 for a single gear — and
    // was the real cause of the sketch-mode stutter (HANDOFF M75). The GPU now
    // draws the model, so pan and zoom only move a camera and cost nothing.
    final inPartSketch =
        app.currentPart != null && app.activeChild != null;
    if (inPartSketch) {
      // Dim the model so the sketch reads as the crisp foreground, exactly
      // what the old veil did — but over real 3D, with real occlusion.
      canvas.drawRect(Offset.zero & size,
          Paint()..color = T.viewport.withOpacity(0.55));
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    }
    final s = app.current;
    Offset map(double x, double y) => Offset(
        size.width / 2 + (x - app.pan.dx) * app.zoom,
        size.height / 2 - (y - app.pan.dy) * app.zoom);

    _ph.mark('bg');
    // ---- M168 Slice Graphics: hatch the section faces ----------------------
    // The cut is made AT this sketch plane, so the exposed faces are exactly
    // coplanar with the sketch — which is why the hatch belongs here, in 2D,
    // and not as a material on a 3D surface. Inventor draws it the same way:
    // the section reads as flat on the sketch.
    if (inPartSketch && app.sliceGraphics) {
      // M222 — one path per BODY, built from the section's boundary loops.
      // It used to be one path per mesh TRIANGLE, and the stroke below then
      // drew every tessellation edge: that is the reported "there are
      // triangles visible". A cut has an outline; a mesh has an arbitrary
      // number of internal edges, and none of them is a feature of the part.
      for (final slice in app.sectionSlices()) {
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final loop in slice.loops) {
          if (loop.length < 3) continue;
          final start = map(loop.first.dx, loop.first.dy);
          path.moveTo(start.dx, start.dy);
          for (var i = 1; i < loop.length; i++) {
            final q = map(loop[i].dx, loop[i].dy);
            path.lineTo(q.dx, q.dy);
          }
          path.close();
        }
        canvas.save();
        canvas.clipPath(path);
        // A light wash so the cut material reads as solid, then the section
        // lines over it. Spacing is in SCREEN space on purpose: a hatch is an
        // annotation, so it stays legible at any zoom instead of collapsing
        // into a smear when you zoom out.
        canvas.drawRect(
            Offset.zero & size, Paint()..color = T.rawGrey.withAlpha(77));
        final pen = Paint()
          ..color = T.rawGrey.withAlpha(217)
          ..strokeWidth = 1.0;
        final (deg, step) = kSectionHatch[slice.style % kSectionHatch.length];
        _hatch(canvas, size, deg, step, pen);
        canvas.restore();
        // The section OUTLINE, drawn crisply on top — the boundary is what
        // makes a section read as a cut rather than as shading.
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = T.rawGrey);
      }
    }

    _ph.mark('slice');
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

    _ph.mark('editRef');
    // ---- real entities from the QCAD document ----
    if (s != null) {
      final p = Paint()
        ..color = T.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final sel = Paint()
        ..color = T.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      // Inventor colours each entity by its constraint state: white when fully
      // defined, violet-blue while still under-constrained, blue when selected.
      final whitePaint = Paint()
        ..color = T.dofFull
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      // projected geometry (M32) is YELLOW like Inventor's projected loops
      final projPaint = Paint()
        ..color = T.projRef
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final underPaint = Paint()
        ..color = T.dofUnder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      // Geometry on a layer you are NOT editing (or a locked layer) is drawn as
      // dim reference while a layer is in edit mode, so the active layer's DOF
      // colours read clearly. Outside edit mode everything keeps its own state.
      final refPaint = Paint()
        ..color = T.refDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      // S4 — the FIRST of this paint's displayGeometry calls, and the only one
      // that solves. During a grip drag this is a live 25-iteration constraint
      // solve; the tool preview and the constraints phase further down ask the
      // same question about the same cursor position and are answered from the
      // memo in displayGeometry. Do not "optimise" this into a field or hoist
      // it out of the phase: the memo is keyed on the drag position, so the
      // sharing already happens, and this call is what pins the geometry every
      // entity, grip and halo in this phase is drawn from.
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

      _ph.mark('ent.dofColour');
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
          ..color = T.accent.withOpacity(.8)
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

      _ph.mark('ent.halo');
      // ---- Project tool: the 3D model edges you can pick (M76) ----------
      // Drawn only while the tool is active, so the sketch stays clean
      // otherwise. Inventor shows projectable edges the same way: faint until
      // you hover one, highlighted when a tap would take it.
      if (app.tool == Tool.project) {
        final hovered = app.hoverSolidEdge;
        final faint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = T.projRefEdge.withOpacity(0.45);
        final hot = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = T.hover;
        for (final e in app.projectableEdges()) {
          final ep = e.displayPts;
          if (ep.length < 2) continue;
          final p0 = map(ep[0].dx, ep[0].dy);
          final path = Path()..moveTo(p0.dx, p0.dy);
          for (var i = 1; i < ep.length; i++) {
            final q = map(ep[i].dx, ep[i].dy);
            path.lineTo(q.dx, q.dy);
          }
          canvas.drawPath(path, e.index == hovered ? hot : faint);
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

      _ph.mark('ent.projectEdges');
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
            // Stays white on purpose: this is an ALPHA MULTIPLIER for
            // drawImageRect, not a theme colour. Tinting it would tint the
            // user's underlay image.
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
                ..color = T.dim
                ..style = PaintingStyle.stroke);
        }
        if (identical(img, selImage) && onLayer) {
          canvas.drawRect(
              dst,
              Paint()
                ..color = T.accent
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4);
          // resize grip (visual bottom-right) + delete X (visual top-right).
          // The HIT TEST in _scaleStart/_handleClick must match these exact
          // screen corners (dst.bottomRight / dst.topRight), not the world
          // rect's corners — screen-down is -world-y, so they differ.
          canvas.drawRect(
              Rect.fromCenter(center: dst.bottomRight, width: 12, height: 12),
              Paint()..color = T.accent);
          final xC = dst.topRight;
          canvas.drawCircle(xC, 9, Paint()..color = T.err);
          final xp = Paint()
            ..color = T.onAccent
            ..strokeWidth = 1.6;
          canvas.drawLine(
              xC + const Offset(-3.5, -3.5), xC + const Offset(3.5, 3.5), xp);
          canvas.drawLine(
              xC + const Offset(-3.5, 3.5), xC + const Offset(3.5, -3.5), xp);
        }
      }

      _ph.mark('ent.images');
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
          // curve and get grips like any vertex. A Bézier chain (what Trim and
          // Split leave behind) has off-curve handles for exactly the same
          // reason, so it gets the same treatment.
          final g = gs[i];
          if ((g.spline == Geo.splineCv || g.spline == Geo.splineBez) &&
              (app.selection.contains(i) || app.hoverEnt == i)) {
            final poly = Paint()
              ..color = T.ctrl.withValues(alpha: 0.53)
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
            final dot = Paint()..color = T.ctrl;
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
      // M196 — the CENTRE POINT of a centre-start rectangle.
      //
      // "A midpoint rect should have a point in the middle." M92 gave those
      // rectangles their two construction diagonals so the centre would be
      // visible and snappable — and it is snappable, on either diagonal's
      // midpoint snap — but there was nothing DRAWN there, so the one place
      // the whole tool is named after was the one place with no marker.
      //
      // DERIVED, not stored. A real entity would be a circle, a circle's
      // radius is a free parameter, and every centre rectangle would then be
      // permanently one degree of freedom short of fully constrained —
      // trading a missing dot for a sketch that can never go green. The
      // crossing is the centre by construction, so drawing it costs nothing
      // and cannot drift: a drag moves it because the diagonals moved.
      //
      // Two construction lines that share a midpoint AND actually cross are a
      // rectangle's diagonals (in any parallelogram both diagonals bisect each
      // other). That is cheap to test and needs no tag, so it also works for
      // every sketch already saved.
      // geoEditable already implies inEditMode, which is the same gate the
      // diagonals themselves are drawn under: no diagonals, no centre dot.
      for (final c in centreMarks(gs,
          visible: (i) => app.geoVisible(gs[i]) && app.geoEditable(gs[i]))) {
        final p = map(c.dx, c.dy);
        canvas.drawCircle(p, 2.5, Paint()..color = T.dim);
      }
      // Degrees-of-freedom glyphs: arrows on every point that can still move
      // (they vanish one by one as constraints are added).
      final an = app.analysis;
      if (app.showDof &&
          app.inEditMode &&
          app.tool == Tool.none &&
          an != null) {
        final dp = Paint()
          ..color = T.dofArrow
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
            ..color = T.err
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
            ..color = T.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4;
          paintGeo(canvas, sp.pieces[sp.hovered], map, app.zoom, hi);
          final mark = Paint()..color = T.err;
          final ring = Paint()
            ..color = T.err
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
        final gp = Paint()..color = T.snapOk;
        for (final g in gripsOf(gs)) {
          if (g.entity < gs.length && !app.geoEditable(gs[g.entity])) continue;
          final o = map(g.pos.dx, g.pos.dy);
          canvas.drawRect(Rect.fromCenter(center: o, width: 4, height: 4), gp);
        }
        if (app.dragGrip != null && app.dragPos != null) {
          final o = map(app.dragPos!.dx, app.dragPos!.dy);
          canvas.drawRect(Rect.fromCenter(center: o, width: 7, height: 7),
              Paint()..color = T.err);
        }
      }
    }

    _ph.mark('entities');
    // ---- gear tool ghost: the whole gear (or planetary set) at the cursor,
    // exactly what a tap would commit ----
    if (app.tool == Tool.gear &&
        app.gear != null &&
        app.hoverWorld != null) {
      final g = app.gear!;
      final c = app.hoverWorld!;
      final ang = g.angleRad;
      final ghost = Paint()
        ..color = T.accent.withOpacity(0.85)
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
      canvas.drawCircle(map(c.dx, c.dy), 3, Paint()..color = T.accent);
    }

    _ph.mark('gearGhost');
    // ---- M87: raw freehand ink, while the pointer is still down ----
    // Thin and dimmer than committed geometry: this is ink, not yet a spline.
    // Once the pointer lifts, `freehand.drawing` goes false and the ordinary
    // preview below takes over — drawing the FITTED curve out of toolPoints,
    // which is literally the geometry that Finish will commit.
    final fh = app.freehand;
    if (fh != null && fh.drawing && fh.raw.length > 1) {
      final ink = Paint()
        ..color = T.hover
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(map(fh.raw.first.dx, fh.raw.first.dy).dx,
          map(fh.raw.first.dx, fh.raw.first.dy).dy);
      for (var i = 1; i < fh.raw.length; i++) {
        final o = map(fh.raw[i].dx, fh.raw[i].dy);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, ink);
    }

    _ph.mark('freehand');
    // ---- in-progress tool preview (blue, like the accent) ----
    if (app.tool != Tool.none &&
        (app.toolPoints.isNotEmpty || app.hoverWorld != null)) {
      final prev = Paint()
        ..color = T.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final pts = app.toolPoints;
      // M207 — a finished freehand stroke has no rubber band. The fit window
      // owns the curve from here; hover must not append a point to it. Belt
      // and braces with the guard in onPointerHover, because this is the line
      // that actually DRAWS the tail that "still goes on".
      final rawHov = app.freehand != null ? null : app.hoverWorld;
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
            Paint()..color = T.accent);
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

    _ph.mark('toolPreview');
    // ---- constraint glyphs + dimensions (M7) ----
    // Guarded: a painter exception aborts the whole frame, which would look
    // exactly like "the app draws nothing".
    try {
      // ---- M44/M45: parametric texts (real content: visible outside edit
      // mode). The anchor (t.x, t.y) is the LOWER-LEFT of the text; the text
      // grows up and to the right so the construction bounding rect matches the
      // measurer used for snapping. The rect renders in the CONSTRUCTION
      // linetype (thin dashed) and ONLY on the layer being edited.
      //
      // M220 — the letters are CURVES, drawn from the very contours that go
      // into the DXF and into the kernel (text_geometry.dart), not a
      // TextPainter's pixels. What is on screen is now what is in the file:
      // stroked like every other sketch curve, with a faint fill so a small
      // text is still legible.
      app.textRects.clear();
      if (s != null) {
        for (final t in s.texts) {
          final layout = textLayoutOf(s, t);
          final dim = !app.inEditMode || t.layer == app.editingLayer;
          final ink = dim ? T.text : T.inkDim;
          // NON-ZERO, the rule TrueType outlines are drawn with: a counter
          // runs opposite to its outer contour and so punches a hole, while
          // two letters that overlap stay solid where they meet (even-odd
          // would cut a gap out of them).
          final path = ui.Path();
          for (final c in layout.contours) {
            for (var i = 0; i < c.length; i++) {
              final p = map(c[i].dx, c[i].dy);
              i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
            }
            path.close();
          }
          canvas.drawPath(path, Paint()..color = ink.withOpacity(0.28));
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0
                ..color = ink);
          // the hit rect for tap/drag: the text's own box, in screen space
          final screenRect = Rect.fromPoints(
              map(t.x, t.y + layout.size.height),
              map(t.x + layout.size.width, t.y));
          app.textRects.add((t, screenRect));

          // construction bounding rect (edit-mode + own layer only)
          if (app.inEditMode && t.layer == app.editingLayer) {
            final wr = app.textBoundsWorld(s, t, measure: measureSketchText);
            final a = map(wr.left, wr.top); // world-top -> screen-top
            final b = map(wr.right, wr.bottom);
            final rr = Rect.fromPoints(a, b);
            final cp = Paint()
              ..color = T.constr // construction blue-grey
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
                  Paint()..color = T.constr);
            }
          }
        }
      }

      // M42: dimensions and constraint glyphs are SKETCH-EDIT artefacts — they
      // are invisible (and untappable: rects cleared) outside layer-edit mode,
      // like Inventor hides them when the sketch is not being edited.
      if (!app.inEditMode) app.dimLabelRects.clear();
      if (s != null && app.inEditMode) {
        // S4 — the SAME list the entities above were drawn from, not a second
        // solve. It used to be one: displayGeometry warm-starts from the frame
        // it last returned, so this call ran 25 more iterations on that result
        // and every glyph below was placed against geometry one refinement
        // ahead of the entity drawn under it. Measured at 60 painted frames /
        // 120 solves (PERFORMANCE_PROFILE.md §5.2); now 60 / 60.
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
                    style: TextStyle(
                        fontSize: 10, color: T.dofArrow)),
                textDirection: TextDirection.ltr)
              ..layout();
            canvas.drawRect(
                Rect.fromLTWH(o.dx - 2, o.dy - 1, tp.width + 4, tp.height + 2),
                Paint()..color = T.hudBg);
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

    _ph.mark('constraints');
    // ---- modify-tool ghost preview (dashed look via lighter blue) ----
    if (app.hoverWorld != null && s != null) {
      final ghost = app.modifyGhost(s, app.hoverWorld!);
      if (ghost.isNotEmpty) {
        final gp = Paint()
          ..color = T.accent.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final g in ghost) {
          paintGeo(canvas, g, map, app.zoom, gp);
        }
      }
    }

    _ph.mark('modifyGhost');
    // ---- pattern preview (M35): the pending copies, light blue ----
    if (app.pattern != null && s != null) {
      final ghost = app.patternPreview();
      if (ghost.isNotEmpty) {
        final gp = Paint()
          ..color = T.accent.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final g in ghost) {
          if (!geoFinite(g)) continue;
          paintGeo(canvas, g, map, app.zoom, gp);
        }
      }
    }

    _ph.mark('pattern');
    // ---- snap marker + alignment guides (Inventor green) ----
    final sn = app.snap;
    if (sn != null && (app.tool != Tool.none || app.dragGrip != null)) {
      final green = T.snapOk;
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

    _ph.mark('snap');
    // ---- box select rectangle (window = solid blue, crossing = dashed
    // green — exactly Inventor's two modes) ----
    if (app.boxStart != null && app.boxEnd != null) {
      final r = Rect.fromPoints(map(app.boxStart!.dx, app.boxStart!.dy),
          map(app.boxEnd!.dx, app.boxEnd!.dy));
      if (app.boxCrossing) {
        canvas.drawRect(r, Paint()..color = T.snapOk.withValues(alpha: 0.18));
        _dashedRect(
            canvas,
            r,
            Paint()
              ..color = T.snapOk
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      } else {
        canvas.drawRect(r, Paint()..color = T.accent.withValues(alpha: 0.18));
        canvas.drawRect(
            r,
            Paint()
              ..color = T.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }

    _ph.mark('boxSelect');
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
                      TextStyle(fontSize: 10, color: T.dofArrow)),
              textDirection: TextDirection.ltr)
            ..layout();
          final at = o + Offset(i * 16.0, 0);
          canvas.drawRect(
              Rect.fromLTWH(at.dx - 2, at.dy - 1, tp.width + 4, tp.height + 2),
              Paint()..color = T.hudBg);
          tp.paint(canvas, at);
        }
      }
    }

    // The bottom-LEFT "N degrees of freedom" readout is gone: it said the same
    // thing as the bottom-right "N dimensions needed" / "Fully Constrained"
    // overlay, in the number the user cannot act on. One status line is
    // enough, and it is the one phrased as an instruction.

    _ph.mark('cursorHints');
    // ---- transient notice (over-constrained warnings) ----
    if (app.message != null) {
      final tp = TextPainter(
          text: TextSpan(
              text: app.message!,
              style: TextStyle(fontSize: 12, color: T.toastText)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 60);
      // M203 — clear of the floating tab bar. At a flat 44 the notice sat
      // UNDER it: "the error was under the bottom bar and I couldn't see and
      // read it". The bar's height is not a constant here — it is zero off
      // iOS, where nothing floats — so it is asked for rather than guessed.
      final box = Rect.fromLTWH(
          (size.width - tp.width) / 2 - 12,
          size.height - tp.height - 44 - BottomTabBar.floatingHeight,
          tp.width + 24,
          tp.height + 12);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = T.toastBg);
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()
            ..color = T.toastBorder
            ..style = PaintingStyle.stroke);
      tp.paint(canvas, box.topLeft + const Offset(12, 6));
    }

    _ph.mark('notice');
    // ---- projected center point (YELLOW, on top, interactive) ----
    if (app.inEditMode) {
      final o = map(0, 0);
      canvas.drawCircle(
          o, 3.2, Paint()..color = projCpSelected ? T.accent : T.projRef);
      canvas.drawCircle(
          o,
          3.2,
          Paint()
            ..color = T.projRefEdge
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
    ..color = T.dimLine
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
      label = Fmt.mm(v);
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
      label = (c.dimKind == 'rad' ? 'R' : '⌀') + Fmt.mm(v);
      if (c.driven) label = '($label)';
      break;
    case 'gap':
      // M124 — radial gap between two concentric-ish circles. Drawn along the
      // ray from the shared centre towards the label, from the inner circle to
      // the outer one, so it reads as the annulus width it is.
      if (c.ents.length < 2 || c.ents[0] >= gs.length || c.ents[1] >= gs.length) {
        return;
      }
      final ga = gs[c.ents[0]], gb = gs[c.ents[1]];
      final cen = map(ga.data[0], ga.data[1]);
      var dir = t - cen;
      if (dir.distance < 1e-6) dir = const Offset(1, 0);
      dir = dir / dir.distance;
      final rIn = (map(ga.data[0] + math.min(ga.data[2], gb.data[2]),
                  ga.data[1]) -
              cen)
          .distance;
      final rOut = (map(ga.data[0] + math.max(ga.data[2], gb.data[2]),
                  ga.data[1]) -
              cen)
          .distance;
      final pa = cen + dir * rIn, pb = cen + dir * rOut;
      canvas.drawLine(pa, pb, p);
      _arrow(canvas, pa, dir, p);
      _arrow(canvas, pb, -dir, p);
      label = Fmt.mm(v);
      if (c.driven) label = '($label)';
      t = (pa + pb) / 2 + Offset(-dir.dy, dir.dx) * 10;
      break;
    case 'pline':
    case 'plinetan':
      // pts = [point, line A, line B]: perpendicular distance to the line.
      // Render as a linear dimension between the point and its foot on the
      // (extended) line; witness the extension with a dashed overshoot when
      // the foot falls outside the picked segment (Inventor does the same).
      if (c.pts.length < 3 || c.pts.any((q) => q.ent >= gs.length)) {
        return;
      }
      // M202 — the TANGENT variant measures from the rim, so it must be drawn
      // from the rim: the arrow lands on the nearest point of the circle, not
      // in the middle of it. Everything after this is shared with 'pline',
      // because from here on it IS the same dimension.
      var pw = refPt(gs, c.pts[0]);
      if (c.dimKind == 'plinetan' &&
          c.ents.isNotEmpty &&
          c.ents[0] >= 0 &&
          c.ents[0] < gs.length) {
        final cg = gs[c.ents[0]];
        final rr = cg.data[2];
        final la0 = refPt(gs, c.pts[1]);
        final lb0 = refPt(gs, c.pts[2]);
        final dd = lb0 - la0;
        final l2 = dd.dx * dd.dx + dd.dy * dd.dy;
        if (l2 > 1e-18 && rr > 1e-9) {
          final t0 = ((pw - la0).dx * dd.dx + (pw - la0).dy * dd.dy) / l2;
          final foot0 = la0 + dd * t0;
          final toLine = foot0 - pw;
          if (toLine.distance > 1e-9) {
            pw = pw + toLine / toLine.distance * rr; // the tangent point
          }
        }
      }
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
      label = Fmt.mm(v);
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
        // The legs are the lines' FAR ends from the crossing — the halves that
        // actually exist. angleArcSpan tries both directions of each anyway,
        // so a leg pointing the wrong way costs nothing.
        final la = (l1a - ix).distance >= (l1b - ix).distance ? l1a : l1b;
        final lb = (l2a - ix).distance >= (l2b - ix).distance ? l2a : l2b;
        t = _angleArc(canvas, map, ix, la, lb, t, v, p);
      }
      label = Fmt.deg(v);
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
        // M209 — arrowheads, tangent to the arc. This one always swept
        // between the real rays; it was only ever missing its arrows.
        final dir3 = sweep >= 0 ? 1.0 : -1.0;
        for (final (bearing, sign) in [(a0, dir3), (a0 + sweep, -dir3)]) {
          final u = Offset(math.cos(bearing), math.sin(bearing));
          _arrow(canvas, sv + u * rr, -Offset(-u.dy, u.dx) * sign, p);
        }
        t = sv +
            Offset(math.cos(a0 + sweep / 2), math.sin(a0 + sweep / 2)) * rr;
      }
      label = Fmt.deg(v);
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
        final la4 = (qa1 - ix4).distance >= (qa2 - ix4).distance ? qa1 : qa2;
        final lb4 = (qb1 - ix4).distance >= (qb2 - ix4).distance ? qb1 : qb2;
        t = _angleArc(canvas, map, ix4, la4, lb4, t, v, p);
      }
      label = Fmt.deg(v);
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
          style: TextStyle(fontSize: 11, color: T.dimText)),
      textDirection: TextDirection.ltr)
    ..layout();
  final bg =
      Rect.fromCenter(center: t, width: tp.width + 6, height: tp.height + 3);
  canvas.drawRect(
      bg,
      Paint()
        ..color =
            highlight ? T.dimPlateHot : T.dimPlate);
  if (highlight) {
    // M42: hover feedback — this label is clickable (inserts its parameter
    // name while the expression box is open, opens the editor otherwise)
    canvas.drawRect(
        bg.inflate(1),
        Paint()
          ..color = T.accent
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

/// M209 — an angle dimension, drawn the way Inventor draws one.
///
/// Centred on the vertex [vtxWorld], swept BETWEEN THE TWO LEGS (see
/// [angleArcSpan]) rather than about the label, with an arrowhead at each end
/// and a dashed extension out to the arc wherever a leg stops short of it.
/// The label only sets the radius and picks which of the four angles at the
/// crossing is meant.
///
/// [legA]/[legB] are any second point on each leg, in world coordinates; only
/// their direction from the vertex is used. Returns the point ON the arc where
/// the label belongs, so the number sits on its own arc instead of wherever it
/// was last dropped.
Offset _angleArc(Canvas canvas, Offset Function(double, double) map,
    Offset vtxWorld, Offset legA, Offset legB, Offset t, double deg, Paint p) {
  final sv = map(vtxWorld.dx, vtxWorld.dy);
  final rr = (t - sv).distance;
  if (rr < 1e-6) return t;
  final sa = map(legA.dx, legA.dy), sb = map(legB.dx, legB.dy);
  final da = sa - sv, db = sb - sv;
  if (da.distance < 1e-6 || db.distance < 1e-6) return t;

  final (start, sweep) = angleArcSpan(
      math.atan2(da.dy, da.dx),
      math.atan2(db.dy, db.dx),
      math.atan2((t - sv).dy, (t - sv).dx),
      deg);
  canvas.drawArc(
      Rect.fromCircle(center: sv, radius: rr), start, sweep, false, p);

  // Extension lines: a leg that ends before the arc gets a dashed run out to
  // it, which is what ties the arc to the geometry it measures.
  for (final (bearing, legLen) in [
    (start, da.distance),
    (start + sweep, db.distance),
  ]) {
    if (legLen >= rr - 0.5) continue;
    final u = Offset(math.cos(bearing), math.sin(bearing));
    _dashedLine(canvas, sv + u * legLen, sv + u * rr, p);
  }

  // Arrowheads, tangent to the arc and pointing along the sweep — the "no
  // arrows" half of the report.
  final dir = sweep >= 0 ? 1.0 : -1.0;
  for (final (bearing, sign) in [(start, dir), (start + sweep, -dir)]) {
    final u = Offset(math.cos(bearing), math.sin(bearing));
    final tangent = Offset(-u.dy, u.dx) * sign;
    _arrow(canvas, sv + u * rr, -tangent, p);
  }

  final midB = start + sweep / 2;
  return sv + Offset(math.cos(midB), math.sin(midB)) * rr;
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

/// M196 — centres of the centre-start rectangles, in world coordinates.
///
/// A rectangle's two diagonals bisect each other, so a pair of CONSTRUCTION
/// lines that share a midpoint and are not parallel is exactly that pair. The
/// test is geometric rather than tagged, so it holds for sketches saved before
/// this existed, and it keeps holding while the shape is dragged.
///
/// Public for the test: this is the whole rule, and "a dot appeared in the
/// middle of the wrong thing" is the failure worth pinning.
List<Offset> centreMarks(List<Geo> gs, {required bool Function(int) visible}) {
  final lines = <int>[
    for (var i = 0; i < gs.length; i++)
      if (gs[i].type == Geo.line &&
          gs[i].isConstruction &&
          geoFinite(gs[i]) &&
          visible(i))
        i
  ];
  final out = <Offset>[];
  for (var a = 0; a < lines.length; a++) {
    final ga = gs[lines[a]];
    final ma = Offset((ga.data[0] + ga.data[2]) / 2,
        (ga.data[1] + ga.data[3]) / 2);
    final da = Offset(ga.data[2] - ga.data[0], ga.data[3] - ga.data[1]);
    if (da.distance < 1e-9) continue;
    for (var b = a + 1; b < lines.length; b++) {
      final gb = gs[lines[b]];
      final mb = Offset((gb.data[0] + gb.data[2]) / 2,
          (gb.data[1] + gb.data[3]) / 2);
      if ((ma - mb).distance > 1e-6) continue;
      final db = Offset(gb.data[2] - gb.data[0], gb.data[3] - gb.data[1]);
      if (db.distance < 1e-9) continue;
      // Parallel lines through the same midpoint lie on top of each other —
      // that is one line drawn twice, not a pair of diagonals.
      final cross = (da.dx * db.dy - da.dy * db.dx).abs();
      if (cross < 1e-9 * da.distance * db.distance) continue;
      out.add(ma);
    }
  }
  return out;
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
            style: ts(11.5, locked ? T.accent : T.text,
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
              focused ? T.hudBgHot : T.hudBg);
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
          T.accent);
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

/// Paints the 2D viewport into [canvas] without a widget tree.
///
/// The perf suite needs the real painter, not an approximation of it: the
/// device session showed `2d.paint.ent.dofColour` alone at 85% of all painting,
/// and a reimplementation would measure the reimplementation. This is the same
/// [CustomPainter] the app uses, driven directly, so every `2d.paint.*` phase
/// records exactly as it does on screen.
///
/// Deliberately the ONLY seam into the private painter. Callers hand in a
/// `PictureRecorder`-backed canvas; nothing here touches the widget layer, so
/// it runs from a unit test and from a device button alike.
void paintViewportForBenchmark(Canvas canvas, Size size, AppState app) {
  _ViewportPainter(app: app, projCpSelected: false).paint(canvas, size);
}

/// Snaps [w] against [app]'s visible geometry and publishes the marker — the
/// whole pointer-move snap path, with no widget state involved.
///
/// This IS the implementation: `_snapped` delegates here rather than the other
/// way round, and there is no second copy for benchmarking. That direction is
/// the point. The body used to live inside `_Viewport2DState`, which made
/// snapping unreachable from anything but a live gesture: the M211 suite's
/// `ui.snapHover` scenario drove `setHover` and therefore recorded
/// `2d.pickEntity` and nothing else, so `2d.snap` never appeared in a single
/// report and the phase read as free. Writing a benchmark-only copy would have
/// produced a number for the copy; moving the body out produces a number for
/// the app.
///
/// It runs per pointer-move event — up to 120 Hz on ProMotion — and walks the
/// visible geometry list twice, once to filter and once inside [computeSnap],
/// so it is a per-frame cost that never shows up anywhere in `2d.paint`.
Offset snapViewportForBenchmark(AppState app, Offset w,
        {Offset? exclude, double px = _Viewport2DState._snapPx}) =>
    Perf.span('2d.snap', () => _snapAt(app, w, exclude: exclude, px: px));

Offset _snapAt(AppState app, Offset w, {Offset? exclude, required double px}) {
  final s = app.current;
  if (s == null) return w;
  // Hidden layers must not attract the cursor either. Snap carries no entity
  // indices, so filtering the list here is safe (grips are NOT filtered —
  // those carry indices and must stay aligned with the geometry list).
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

/// M222 — parallel hatch lines at [deg] across the whole canvas, [step] px
/// apart, measured perpendicular to their own direction so 45 and 135 come out
/// equally dense (stepping in x would make the diagonals differ by sqrt(2)).
///
/// Anchored at the canvas origin rather than at the model, deliberately and for
/// the same reason the spacing is in pixels: the hatch is an annotation about
/// WHAT the material is, not about where it sits.
void _hatch(Canvas canvas, Size size, double deg, double step, Paint pen) {
  final rad = deg * math.pi / 180;
  final dx = math.cos(rad), dy = math.sin(rad);
  final nx = -dy, ny = dx;
  final span = size.width + size.height; // covers the diagonal either way
  for (var t = -span; t <= span; t += step) {
    final cx = nx * t, cy = ny * t;
    canvas.drawLine(Offset(cx - dx * span, cy - dy * span),
        Offset(cx + dx * span, cy + dy * span), pen);
  }
}
