// Prototype — 3D part viewport (M56), a 1:1 Flutter port of the HTML
// dummy's Part3D module: orthographic turntable camera about the origin,
// the three 20x20mm orange work planes + axes + centre point with green
// hover highlights, a ViewCube (face/edge/corner snap + Home + face-view
// nav arrows), the coordinate triad, zoom-to-cursor, plane-pick mode for
// "Start 2D Sketch", profile-region picking for Extrude, and the shaded
// solids of the part's features (depth-sorted triangles + B-Rep edges from
// the OCCT tessellation — no GPU dependency, plain CustomPainter).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:reality_view/reality_view.dart';

import '../app_state.dart';
import '../log.dart';
import 'cycles_layer.dart';
import '../part_pick.dart';
import '../pick_math.dart';
import '../perf.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../part_model.dart';
import '../part_render.dart';
import '../quat.dart';
import '../view_cube.dart';
import '../reality_scene.dart';
import '../text_geometry.dart' show textContours, textLayerOf;
import '../menus.dart';
import '../mouse_nav.dart';
import '../work_features.dart';
import '../svg_icons.dart' show homeTabIcon;
import '../icon_preview.dart';
import '../theme.dart';
import 'package:native_menu/native_menu.dart'
    show GlassBrowser, NativeMenu, NativeMenuItem;
import 'bottom_tabbar.dart';
import 'native_browser_host.dart';
import '../l10n/l.dart';
import 'ribbon_chrome.dart';

// M83: the origin planes/axes are no longer a fixed 20 mm square — they frame
// the part (originPlaneRect / originAxisSpan in part_model.dart). This constant
// survives only as the empty-part default, which lives there as
// kOriginExtentDefault; nothing in this file should size geometry with it.
// M236 — palette reads, for the reason spelled out in part_render.dart: the
// live extrude preview and the committed-boolean tint follow the scheme too.
Color get _orange => T.previewFill;
Color get _orangeEdge => T.previewEdge;
Color get _green => T.okSolid;
Color get _greenBright => T.okSolidBright;
// Cam3 (orthographic turntable camera) and paintPartSolids live in
// ../part_render.dart now — shared verbatim with off-screen thumbnail
// rendering (AppState._writePartPreview). kSolidBase/kSolidEdge moved with
// them.

/// M218 — the context menu behind a LONG PRESS on a sketch in the 3D
/// viewport ("long press a sketch in 3d and export as dxf only this sketch").
///
/// Edit and Hide are the model browser's own sketch commands, under the same
/// ids; Export and Share are the reason this menu exists. A sketch inside a
/// part is a DRAWING, and a drawing is something you hand to a machine — the
/// part exports as STEP, and until now the profile that would actually be cut
/// could only leave the app by way of the whole solid.
///
/// Visibility is one-way here, unlike the browser's Hide/Show toggle: only a
/// VISIBLE sketch can be under the finger ([_pickSketchCurve] skips the rest),
/// so a "Show" that could never be reached would be a dead control.
///
/// Top-level, and it TAKES the strings rather than reading a global, so a
/// host test can pin the contract — ids, order, labels — in either language
/// without a device: UIKit never sees these strings, this list is
/// their only source (exactly like `sketchMenuGroups` for the gallery card).
List<NativeMenuItem> sketch3dMenuItems(AppL10n t) => [
      NativeMenuItem(id: 'skEdit', title: t.ctxEditSketch, symbol: 'pencil.tip'),
      NativeMenuItem(id: 'skVisible', title: t.hide, symbol: 'eye.slash'),
      NativeMenuItem(
          id: 'skExportDxf',
          title: t.ctxExportDxf,
          symbol: 'square.and.arrow.down'),
      NativeMenuItem(
          id: 'skShareDxf',
          title: t.ctxShareDxf,
          symbol: 'square.and.arrow.up'),
      // M345 — a sketch caught by a long press in 3D is the sketch the user is
      // pointing at, so the two commands that take it somewhere else belong
      // here as much as they do on its browser row. Cut does not: it can be
      // refused (a consumed sketch) and this list is built without the part to
      // ask, and a menu entry that toasts a refusal is the thing M157 spent a
      // commit removing.
      NativeMenuItem(id: 'skCopy', title: t.btnCopy, symbol: 'doc.on.doc'),
      NativeMenuItem(
          id: 'skToDocument',
          title: t.ctxSketchToDocument,
          symbol: 'square.and.arrow.down.on.square'),
    ];

class Viewport3D extends StatefulWidget {
  final AppState app;
  const Viewport3D({super.key, required this.app});
  @override
  State<Viewport3D> createState() => _Viewport3DState();
}

class _Viewport3DState extends State<Viewport3D>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _camAnim = AnimationController(vsync: this, duration: _camSwing)
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
        // Overlay stays hidden until the swing has essentially arrived; a
        // fixed-transform 2D canvas over a moving camera reads as the sketch
        // sliding off the model.
        final v = _camAnim!.value;
        widget.app.setSketchOverlayFade(v < 0.85 ? 0 : (v - 0.85) / 0.15);
      })
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) {
          widget.app.setSketchOverlayFade(1);
        }
      });
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _wheelStop();
    _camAnim?.dispose();
    _refineTimer?.cancel();
    _cancelLongPress();
    // The controller itself is owned (and disposed) by the RealityView widget's
    // own State; just drop our reference so late pushes are no-ops.
    _reality = null;
    RealityPush.nativeDrain = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    // M182 — part-level Undo/Redo: Ctrl+Z / Cmd+Z steps back through the
    // destructive-operation journal (delete feature/body/sketch/below EOP),
    // Ctrl+Shift+Z / Cmd+Shift+Z (or Ctrl+Y) steps forward again.
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.app.redoPart();
      } else {
        widget.app.undoPart();
      }
      return true;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      widget.app.redoPart();
      return true;
    }
    // M345 — the clipboard, in 3D. What Copy takes follows the document: the
    // selected body of a part, the selected component of an assembly. Paste
    // is the one command in app_state, which decides what the payload means
    // where it lands.
    if (ctrl && k == LogicalKeyboardKey.keyC) {
      widget.app.copyCurrent();
      return true;
    }
    if (ctrl && k == LogicalKeyboardKey.keyX) {
      widget.app.copyCurrent(cut: true);
      return true;
    }
    if (ctrl && k == LogicalKeyboardKey.keyV) {
      unawaited(widget.app.paste());
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (widget.app.pickPlane ||
          // M260 — ...and an armed work-feature command, which Esc could not
          // reach either. escape3D knows what to do with it.
          widget.app.pickWorkGeometry ||
          widget.app.extrudeSession != null ||
          widget.app.edgeSession != null ||
          // M212 — Esc must reach the pattern panel too: it is a 3D command
          // like the others, and escape3D already knows the order (a pick
          // backs out of the pick, not out of the panel that owns it).
          widget.app.patternSession != null) {
        widget.app.escape3D();
        return true;
      }
    }
    return false;
  }

  String? _hover; // 'yz'|'xz'|'xy'|'x'|'y'|'z'|'cp'|'wp:N'

  /// M169 — the work plane under an active drag, where it was grabbed, and
  /// whether the finger has travelled far enough to be a drag rather than a
  /// tap. The threshold is what lets one gesture be both.
  WorkPlane? _wpDrag;

  /// M174 — the plane or face a NEW work plane is being dragged off.
  PlaneFrame? _wpNewBase;
  Offset _wpDown = Offset.zero;
  bool _wpMoved = false;

  /// How far a pointer must travel before it is a DRAG and not a tap, per
  /// input kind. Touch needs the most room (a resting finger wobbles), a
  /// stylus the least (it is precise, and waiting reads as lag).
  double get _dragSlop => switch (_dragKind) {
        PointerDeviceKind.touch => 9.0,
        PointerDeviceKind.stylus ||
        PointerDeviceKind.invertedStylus =>
          2.0,
        _ => 3.0,
      };
  int? _hoverRegion; // outer-loop id of the hovered profile region
  // M59 Phase 2: face prehighlight while picking a sketch plane —
  // (solid, v4 face id) of the planar face under the cursor.
  (KernelSolid, int)? _hoverFace;
  // M283 — what the mouse drag in flight is doing to the view: the middle
  // button pans, shift with it orbits.
  MouseDrag _mouseNav = MouseDrag.none;
  // Its own last position, deliberately NOT the _mmbLast the scale recognizer
  // writes. THE STEP BACK ON RELEASE: a middle-button drag drives the raw
  // Listener AND the GestureDetector's ScaleGestureRecognizer, which accepts
  // any button — and both wrote _mmbLast. onScaleStart reports the focal point
  // the gesture STARTED at, so the moment the recognizer won the arena it
  // rewound the anchor to the press position and the next Listener move
  // re-applied travel the view had already made; every later onScaleUpdate
  // then overwrote the anchor again mid-drag. The drag jittered and the last
  // contested delta landed as a jump at the end. One field per owner is the
  // whole fix.
  Offset _navLast = Offset.zero;
  Offset _mmbLast = Offset.zero;
  // M283 — the wheel zoom still owed, and the ticker paying it out. See
  // mouse_nav.dart: a notch arrives over a few frames instead of in one jump,
  // which is what makes a discrete wheel feel continuous.
  final WheelZoom _wheel = WheelZoom();
  Ticker? _wheelTick;
  Duration? _wheelLast;
  Size _viewSize = Size.zero;
  double _scaleStartH = 27;

  // Adaptive tessellation: re-mesh solids to the current screen resolution so
  // curved edges stay smooth at any zoom. Debounced so a continuous pinch
  // coalesces into a single kernel re-mesh once the gesture settles.
  Timer? _refineTimer;

  // ==== M218 — long press on a sketch = its context menu ==================
  //
  // A timer in the raw Listener, not GestureDetector.onLongPressStart, and
  // ARMED ONLY when the press starts on a sketch curve. The reason is the
  // one-finger orbit: a long-press recognizer that joins the arena wins it by
  // holding still for half a second, and everything else in the gesture — the
  // orbit the user was about to start — is rejected with it. Arming on the
  // pick means a press anywhere else never enters the question, and a press
  // ON a curve is a press on the one thing that has a menu.
  Timer? _lpTimer;
  Offset _lpDown = Offset.zero;

  /// True from the moment the press fires until the next pointer goes down:
  /// the tap that ends the SAME contact must not also run the general pick,
  /// and the camera must not orbit out from under an open menu.
  bool _lpFired = false;

  // M60: the RealityKit output surface. Null until the platform view is
  // created, and always null off-iOS — where the CPU painter (_ScenePainter)
  // still draws, so host/widget tests and the headless thumbnail path are
  // unaffected. When present, all world-space geometry is rendered by
  // RealityKit (GPU depth buffer), and this widget only pushes scene/camera/
  // overlay payloads; the Flutter layer keeps gestures, ViewCube and triad.
  /// Hovered / selected sketch curve, addressed by [sketchKey]. Selection has
  /// no consumer yet — it exists so curves are already pickable in 3D.
  /// Trackpad two-finger gesture in progress (PointerPanZoom), and the kind of
  /// device that started the current drag. Touch keeps its old behaviour; the
  /// trackpad gets Inventor-style navigation instead.
  bool _tpActive = false;
  Offset _tpLastPan = Offset.zero;
  PointerDeviceKind _dragKind = PointerDeviceKind.touch;

  String? _hoverSketch;
  final Set<String> _selSketch = <String>{};

  RealityViewController? _reality;
  String? _lastSceneSig;
  /// Mesh revisions the native side currently holds. Reset together with
  /// [_lastSceneSig] whenever a fresh platform view appears.
  Map<String, int> _sentRevs = const {};

  PartModel? get part => widget.app.currentPart;

  /// Nearest VISIBLE sketch curve under the cursor, or null. Mirrors exactly
  /// the curves reality_scene draws, so what highlights is what you see.
  /// M133 — sketch curve under the pointer.
  ///
  /// Shares [segDistSq] and [PickBest] with the B-Rep edge picker in
  /// part_pick.dart. It used to carry a private distance function and a
  /// pixel-only tie-break, which meant a curve on the FAR side of the model
  /// could win over the one you were pointing at; PickBest resolves by depth
  /// first, exactly as face and edge picking do.
  /// M231 — the same pick, with the hit KEPT.
  ///
  /// The walk below already computes the world point where the ray met the
  /// curve (it needs it for the depth test) and the direction of the segment
  /// it met — which, on the adaptively sampled curve M219 gives us, is the
  /// TANGENT to within the sampling tolerance. Both were being thrown away.
  /// Everything that only wants the key calls [_pickSketchCurve], unchanged.
  ({String key, Vec3 at, Vec3 dir})? _pickSketchCurveHit(Cam3 cam, Offset px) {
    final p = part;
    if (p == null) return null;
    final sess = widget.app.extrudeSession;
    const tolPx = 9.0;
    const tol2 = tolPx * tolPx;
    final best = PickBest<({String key, Vec3 at, Vec3 dir})>();
    for (final cs in p.childSketches) {
      final showForSession = sess?.sketchName == cs.model.name ||
          (sess != null && sess.sketchName == null);
      if (!cs.visible && !showForSession) continue;
      if (cs.rolledBack) continue; // M113 — below End of Part
      final frame = sketchFrameOf(cs);
      for (var gi = 0; gi < cs.model.geometry.length; gi++) {
        final g = cs.model.geometry[gi];
        if (cs.model.hiddenLayers.contains(g.layer)) continue;
        final li = cs.model.layers.indexOf(g.layer);
        if (li >= 0 && li >= cs.model.eosAfter) continue;
        final pts = sketchCurve(g);
        if (pts.length < 2) continue;
        var prevW = frame.toWorld(pts.first);
        var prev = cam.project(prevW);
        for (var i = 1; i < pts.length; i++) {
          final w = frame.toWorld(pts[i]);
          final cur = cam.project(w);
          final (d2, t) = segDistSq(px, prev, cur);
          if (d2 <= tol2) {
            final hit = prevW + (w - prevW) * t;
            best.offer(
                (
                  key: sketchKey(cs.model.name, gi),
                  at: hit,
                  dir: w - prevW,
                ),
                cam.depth(hit),
                math.sqrt(d2));
          }
          prevW = w;
          prev = cur;
        }
      }
    }
    return best.value;
  }

  /// The sketch curve under [px], as the key every caller but M231 wants.
  String? _pickSketchCurve(Cam3 cam, Offset px) =>
      _pickSketchCurveHit(cam, px)?.key;

  // ---- M218: long press a sketch -> Edit / Hide / Export DXF / Share ------

  /// The sketch a long press at [px] would act on, or null.
  ///
  /// Both the ARMING test and the ACTING test, so what starts the timer and
  /// what the menu is built for can never disagree — the finger may have
  /// wandered a few pixels in between, and the answer must still be the same
  /// sketch or no menu at all.
  ChildSketch? _sketchAt(Cam3 cam, Offset px) {
    final p = part;
    if (p == null || widget.app.picking3D || widget.app.activeChild != null) {
      return null;
    }
    final key = _pickSketchCurve(cam, px);
    if (key == null) return null;
    final i = key.lastIndexOf('#');
    return i < 0 ? null : p.sketchByName(key.substring(0, i));
  }

  void _cancelLongPress() {
    _lpTimer?.cancel();
    _lpTimer = null;
  }

  /// The press has been held long enough: select the whole sketch (so what is
  /// about to be exported is lit up while the menu is over it) and open the
  /// menu at the finger.
  Future<void> _fireSketchLongPress(
      Cam3 cam, Offset local, Offset global) async {
    _lpTimer = null;
    if (!mounted) return;
    final cs = _sketchAt(cam, local);
    if (cs == null) return;
    _lpFired = true;
    HapticFeedback.selectionClick();
    // M205 — anything else that is open is cancelled by a press elsewhere,
    // and this press is elsewhere.
    OpenMenus.closeAll();
    setState(() {
      _selSketch
        ..clear()
        ..addAll([
          for (var gi = 0; gi < cs.model.geometry.length; gi++)
            sketchKey(cs.model.name, gi)
        ]);
    });
    // iPad refuses to present a popover without a source rectangle, and the
    // finger is the source: an action sheet at the press point, and the share
    // sheet that may follow it hangs off the same spot.
    final anchor = Rect.fromCenter(center: global, width: 1, height: 1);
    final choice = await _showSketchMenu(anchor, cs.model.name);
    if (choice == null || !mounted) return;
    await _onSketchMenu(choice, cs, anchor);
  }

  /// The native action sheet on iOS, an identical Flutter popup everywhere
  /// else — same ids, so both paths funnel into one handler.
  Future<String?> _showSketchMenu(Rect anchor, String title) async {
    final items = sketch3dMenuItems(L.of(context));
    if (NativeMenu.isSupported) {
      // The sketch's NAME as the sheet title: a curve in 3D is a thin line
      // among several, and the menu has to say which sketch it caught.
      return NativeMenu.menu(items: items, anchor: anchor, title: title);
    }
    return showMenu<String>(
      context: context,
      color: T.fly,
      position: RelativeRect.fromLTRB(
          anchor.left, anchor.top, anchor.left, anchor.top),
      items: [
        for (final i in items)
          PopupMenuItem<String>(
              value: i.id,
              height: 40,
              child: Text(i.title, style: ts(12.5, T.text))),
      ],
    );
  }

  Future<void> _onSketchMenu(String id, ChildSketch cs, Rect anchor) async {
    final app = widget.app;
    switch (id) {
      case 'skEdit':
        app.openChildSketch(cs.model.name);
        break;
      case 'skVisible':
        app.toggleSketchVisible(cs);
        break;
      case 'skExportDxf':
        await _sendSketchDxf(cs, anchor, share: false);
        break;
      case 'skShareDxf':
        await _sendSketchDxf(cs, anchor, share: true);
        break;
      // M345
      case 'skCopy':
        app.copyChildSketch(cs.model.name);
        break;
      case 'skToDocument':
        await app.sketchDocumentFromChild(cs.model.name);
        break;
    }
  }

  /// Writes the sketch's DXF and hands it to the Files exporter (Save to
  /// Files) or the share sheet. A refusal has already said why on screen
  /// ([AppState.childSketchExportPath]), so a null path is silent here.
  Future<void> _sendSketchDxf(ChildSketch cs, Rect anchor,
      {required bool share}) async {
    final p = part;
    if (p == null) return;
    final path = await widget.app.childSketchExportPath(p.name, cs.model.name);
    if (path == null || !mounted) return;
    if (share) {
      await NativeMenu.shareFile(path, anchor: anchor);
    } else {
      await NativeMenu.exportFile(path, anchor: anchor);
    }
  }

  /// Push the current camera (always), the scene (only when its signature
  /// changed — meshes are large) and the light overlay state to RealityKit.
  void _pushReality(AppState app, PartModel p, Size size) =>
      Perf.span('3d.push', () => _pushRealityInner(app, p, size));

  void _pushRealityInner(AppState app, PartModel p, Size size) {
    final c = _reality;
    if (c == null) return;
    // M80 — while a child sketch is open the 2D editor OWNS navigation, so the
    // 3D camera is derived from its pan/zoom rather than kept independently.
    // One source of truth is the whole reason the cursor cannot drift away
    // from the model: PartCamera.forSketch reproduces exactly the projection
    // Viewport2D.map() uses (pinned by a test in m79_perf_test.dart).
    final cam = _effectiveCamera(app, p, size);
    c.setCamera(cameraPayload(cam, size));
    RealityPush.recordCamera('${cam.runtimeType} on ${size.width.toInt()}x'
        '${size.height.toInt()}');
    final sig = sceneSignature(app, p);
    if (sig != _lastSceneSig) {
      _lastSceneSig = sig;
      final pushed = <String>[];
      for (final (id, s) in visibleSolids(app, p)) {
        logMeshConvention(id, s.mesh);
        pushed.add('$id: tris=${s.mesh.indices.length ~/ 3} '
            'verts=${s.mesh.positions.length ~/ 3} '
            'rev=${identityHashCode(s.mesh)}');
      }
      RealityPush.recordScene(sig, pushed);
      c.setScene(Perf.span('3d.payload', () => buildScenePayload(app, p,
          hover: _hover,
          hoverFace: _hoverFace,
          hoverSketch: _hoverSketch,
          selSketch: _selSketch,
          knownRevs: _sentRevs)));
      _sentRevs = sceneRevs(app, p);
    }
    c.setOverlays(buildOverlaysPayload(app, p,
        hover: _hover,
        hoverFace: _hoverFace,
        hoverSketch: _hoverSketch,
        selSketch: _selSketch));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final p = part;
    if (p == null) return ColoredBox(color: T.viewport);
    return LayoutBuilder(builder: (context, bc) {
      final size = Size(bc.maxWidth, bc.maxHeight);
      _viewSize = size; // the wheel glide runs outside build and needs it
      final cam = Cam3(_effectiveCamera(app, p, size), size);
      // Keep solids at screen resolution: refine on the first frame, on resize,
      // and whenever a new (coarse) preview appears. Cheap no-op once smooth.
      _armRefine(size);
      // Drive the RealityKit surface (iOS). Off-iOS this is a no-op and the
      // CustomPaint fallback below renders instead.
      if (RealityView.isSupported) _pushReality(app, p, size);
      return Stack(children: [
        // The render surfaces sit at the BOTTOM and are never hit-tested; the
        // gesture layer is stacked on top of them (see below).
        Positioned.fill(
          child: ClipRect(
            child: Stack(children: [
              Positioned.fill(
                child: RealityView.isSupported
                    // IgnorePointer: the ARView is a pure output surface. A
                    // platform view must never be the topmost hit target — on
                    // iOS its touch interception swallowed taps before the
                    // Flutter gesture arena saw them (hover worked, taps did
                    // not: device build 0f04ca2).
                    ? IgnorePointer(
                        child: RealityView(
                          placeholder: ColoredBox(color: T.viewport),
                          onCreated: (c) {
                            _reality = c;
                            // Let the bug bundle reach the NATIVE timing table
                            // without reaching into this State. Cleared in
                            // dispose, so a drain after the view goes away is
                            // an empty map rather than a push into a dead
                            // channel.
                            RealityPush.nativeDrain = c.drainNativePerf;
                            // A FRESH platform view starts empty. Without
                            // clearing these, the signature would still match
                            // the old view's contents, setScene would never
                            // fire and the viewport would stay blank forever
                            // (app resume, tab switch, part switch).
                            _lastSceneSig = null;
                            _sentRevs = const {};
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() {});
                            });
                          },
                        ),
                      )
                    : CustomPaint(
                        painter: _ScenePainter(
                            app, p, _hover, _hoverRegion, _hoverFace),
                        size: Size.infinite,
                      ),
              ),
              // M304 — the path-traced image, when rendered mode has one.
              // Over the shaded render and UNDER the decorations: a hover ring
              // or a plane label is a thing you are doing right now, and a
              // photograph of the model is not a reason to stop seeing it.
              Positioned.fill(
                  child: CyclesLayer(
                      app: app,
                      cam: cam,
                      size: size,
                      // M347 — while the path-traced image covers the
                      // viewport, the RealityKit surface below it is rendering
                      // full-resolution frames nobody sees, on the GPU the path
                      // tracer is already saturating. Reported by the layer, so
                      // the surface goes down only once there is a texture over
                      // it and comes back on the frame that texture goes.
                      onCover: (covering) => _reality?.setPaused(covering))),
              // Screen-space decorations (iOS only — the CPU painter draws its
              // own): profile regions, hover rings, plane label.
              if (RealityView.isSupported)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _OverlayPainter(app, p, _hover, _hoverRegion),
                      size: Size.infinite,
                    ),
                  ),
                ),
            ]),
          ),
        ),
        Positioned.fill(
          child: Listener(
            onPointerDown: (e) {
              _dragKind = e.kind;
              // M283 — with a mouse the middle button drags the view and
              // shift with it turns the model. Tested FIRST: navigation is not
              // a pick, and a middle button that happens to land on a work
              // plane must move the view, not the plane.
              final nav = mouseDrag(e.kind, e.buttons,
                  shift: HardwareKeyboard.instance.isShiftPressed);
              if (nav != MouseDrag.none) {
                _mouseNav = nav;
                _navLast = e.localPosition;
                _wheel.cancel(); // a drag owns the camera now
                _cancelLongPress();
                _lpFired = false;
                return;
              }
              // M174 — the Plane command is armed: pointer down on a plane or
              // a face starts DRAGGING a new one off it. Nothing is created
              // until you let go, so a mis-grab costs nothing, and the offset
              // is set by the gesture instead of defaulting to 10 mm.
              //
              // M260 — and the GENERIC Plane command keeps that gesture. It
              // is the half of the command that a drag means; a tap falls
              // through to _tap, where it becomes a pick for the inference
              // (see AppState.commitWorkPlaneCreate, which no longer cancels
              // on a press that never moved).
              if (app.workPlaneArm == WorkPlaneKind.offset ||
                  app.workPlaneAutoArmed) {
                final (base, label) = _planeOrFaceAt(cam, e.localPosition, p);
                if (base != null) {
                  _wpNewBase = base;
                  _wpDown = e.localPosition;
                  _wpMoved = false;
                  app.beginWorkPlaneCreate(base, label);
                  return;
                }
              }
              // M169 — grab a WORK PLANE and drag it along its own normal,
              // the way Inventor lets you slide one off its base. Only when
              // nothing else is armed: a plane pick, an extrude profile pick
              // or an edge pick all mean the tap belongs to that command.
              if (!app.pickPlane &&
                  app.extrudeSession == null &&
                  app.edgeSession == null &&
                  !app.pickingEdges &&
                  // M212 — ...and a pattern selector waiting for a plane or a
                  // direction means the tap belongs to THAT, not to a drag.
                  app.patternSession == null) {
                final w = _workPlaneAt(cam, e.localPosition, p);
                if (w != null) {
                  // Tapping a plane still SELECTS it — that is only a
                  // highlight, and it is how the browser row lights up too.
                  app.selectWorkPlane(w);
                  // M252 — but only the plane currently being EDITED can be
                  // grabbed. Every plane used to be draggable forever, so a
                  // plane stayed movable long after its OK, and a one-finger
                  // orbit that happened to start on one moved the plane
                  // instead of the view (`_wpDrag != null` also suppresses
                  // orbit and the general pick, further down this file).
                  // Arming is now explicit: "Edit Offset" on the row's
                  // long-press menu in the model browser, or the drag that
                  // created the plane, and it ends when the value is
                  // committed. See AppState.workPlaneDraggable.
                  if (app.workPlaneDraggable(w)) {
                    _wpDrag = w;
                    _wpDown = e.localPosition;
                    _wpMoved = false;
                  }
                }
              }
              // M218 — long-press a SKETCH for its context menu (the
              // right-click role, 600 ms, exactly as in 2D — M53). Armed only
              // when the press starts ON a curve and nothing else has claimed
              // the pointer, so navigation is untouched everywhere else.
              _cancelLongPress();
              _lpFired = false;
              if (_wpDrag == null &&
                  _wpNewBase == null &&
                  _mouseNav == MouseDrag.none &&
                  _sketchAt(cam, e.localPosition) != null) {
                _lpDown = e.localPosition;
                _lpTimer = Timer(const Duration(milliseconds: 600),
                    () => _fireSketchLongPress(cam, _lpDown, e.position));
              }
            },
            onPointerMove: (e) {
              // Moving is orbiting or dragging, not a long press (8 px, the
              // 2D viewport's threshold).
              if (_lpTimer != null &&
                  (e.localPosition - _lpDown).distance > 8) {
                _cancelLongPress();
              }
              // M174 — a new plane being dragged off its base. Same projection
              // as M169: pointer travel onto the base normal, scaled by the
              // normal's screen length per world mm.
              final nb = _wpNewBase;
              if (nb != null) {
                final o = cam.project(nb.origin);
                final n2 = cam.project(nb.origin + nb.n) - o;
                final len2 = n2.dx * n2.dx + n2.dy * n2.dy;
                if (len2 > 4.0) {
                  final d = e.localPosition - _wpDown;
                  if (!_wpMoved && d.distance > _dragSlop) _wpMoved = true;
                  if (_wpMoved) {
                    app.updateWorkPlaneCreate(
                        (d.dx * n2.dx + d.dy * n2.dy) / len2);
                  }
                }
                return;
              }
              final wd = _wpDrag;
              if (wd != null) {
                // Screen travel projected onto the plane's own normal. The
                // normal's SCREEN length per world mm is the scale, so the
                // plane tracks the finger exactly however the view is turned;
                // an ortho camera makes that a constant, not an approximation.
                final o = cam.project(wd.frame.origin);
                final n2 = cam.project(wd.frame.origin + wd.frame.n) - o;
                final len2 = n2.dx * n2.dx + n2.dy * n2.dy;
                // Edge-on: the normal has no screen direction to drag along,
                // so a drag cannot express a distance. Do nothing rather than
                // send the plane flying on a rounding error.
                if (len2 > 4.0) {
                  final d = e.localPosition - _wpDown;
                  // M170 — the tap/drag threshold belongs to the INPUT, not to
                  // the widget. A finger wobbles several pixels just resting
                  // on the glass, so 3 px turned taps into drags; a Pencil is
                  // steady enough that 3 px felt like lag before it moved.
                  if (!_wpMoved && d.distance > _dragSlop) {
                    _wpMoved = true;
                    app.beginWorkPlaneDrag(wd);
                  }
                  if (_wpMoved) {
                    app.updateWorkPlaneDrag((d.dx * n2.dx + d.dy * n2.dy) / len2);
                  }
                }
                return; // the drag owns this pointer
              }
              if (_mouseNav != MouseDrag.none) {
                final d = e.localPosition - _navLast;
                _navLast = e.localPosition;
                setState(() {
                  if (_mouseNav == MouseDrag.pan) {
                    _pan(p, d, size);
                  } else {
                    _orbit(p, d);
                  }
                });
              }
            },
            onPointerUp: (_) {
              _mouseNav = MouseDrag.none;
              // The press ended before the menu was earned. (_lpFired is NOT
              // cleared here: the tap that follows this up must still know
              // the press was consumed, and the next pointer down clears it.)
              _cancelLongPress();
              if (_wpNewBase != null) {
                _wpNewBase = null;
                _wpMoved = false;
                app.commitWorkPlaneCreate();
                return;
              }
              if (_wpDrag != null) {
                // A tap that never moved needs nothing: the pointer only got
                // here because this plane is already the one being edited, so
                // its field is already open. (It used to OPEN the field on a
                // tap, which is what made every plane editable by touching
                // it — M252.)
                if (_wpMoved) app.endWorkPlaneDrag();
                _wpDrag = null;
                _wpMoved = false;
              }
            },
            onPointerCancel: (_) {
              _mouseNav = MouseDrag.none;
              _cancelLongPress();
              if (_wpNewBase != null) {
                _wpNewBase = null;
                _wpMoved = false;
                app.cancelWorkPlaneCreate();
                return;
              }
              if (_wpMoved) app.cancelWorkPlaneOffset();
              _wpDrag = null;
              _wpMoved = false;
            },
            // Trackpad gestures arrive as PointerPanZoom, never as extra
            // pointers, so they are handled here rather than through the scale
            // recognizer: two fingers orbit, two fingers + shift pan, pinch
            // still zooms. One finger (a click-drag, reported as a mouse
            // pointer) deliberately does nothing.
            onPointerPanZoomStart: (e) {
              _wheel.cancel(); // the trackpad takes over from a wheel glide
              _tpActive = true;
              _tpLastPan = Offset.zero;
              _scaleStartH = p.camera.halfH;
            },
            onPointerPanZoomUpdate: (e) {
              if (!_tpActive) return;
              setState(() {
                if (e.scale > 0 && (e.scale - 1).abs() > 1e-4) {
                  final f = (_scaleStartH / e.scale) / p.camera.halfH;
                  _zoomAt(p, Cam3(p.camera, size), e.localPosition, f);
                }
                final d = e.pan - _tpLastPan;
                _tpLastPan = e.pan;
                if (d == Offset.zero) return;
                if (HardwareKeyboard.instance.isShiftPressed) {
                  _pan(p, d, size);
                } else {
                  _orbit(p, d);
                }
              });
            },
            onPointerPanZoomEnd: (_) => _tpActive = false,
            onPointerSignal: (e) {
              // M283 — the wheel no longer zooms a fixed step per event
              // however far it turned. It adds to a pending zoom that a ticker
              // pays out over the next few frames; see mouse_nav.dart.
              if (e is PointerScrollEvent) {
                _wheel.add(
                    wheelDoublings(e.scrollDelta.dy), e.localPosition);
                _wheelStart();
              }
            },
            child: MouseRegion(
              // M170 — trackpad and mouse users get told what a thing DOES
              // before they commit to it. A work plane is draggable along one
              // axis, so it takes the resize cursor rather than the pointing
              // hand every other pickable thing gets; on a Magic Keyboard that
              // is the only affordance there is, since there is no hover
              // pressure or haptic to feel.
              cursor: _hover != null && _hover!.startsWith('wp:')
                  ? SystemMouseCursors.resizeUpDown
                  : (_hover != null || _hoverRegion != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer),
              onHover: (e) => _updateHover(cam, e.localPosition),
              onExit: (_) => setState(() {
                _hover = null;
                _hoverRegion = null;
                _hoverFace = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // M170 — a tap consumed by a work-plane DRAG is handled in
                // the Listener; running the general pick as well would fight
                // it. M252 — that is now only ever the plane being edited, so
                // a tap on any other plane falls through to the pick, which is
                // what makes orbiting off a plane work again.
                onTapUp: (d) {
                  if (_wpDrag != null) return;
                  // M218 — the long press already consumed this contact: it
                  // opened the sketch menu, and the finger coming off it is
                  // not a pick.
                  if (_lpFired) return;
                  _tap(cam, d.localPosition);
                },
                onScaleStart: (d) {
                  _wheel.cancel(); // M283 — a touch gesture outranks the glide
                  _scaleStartH = p.camera.halfH;
                  _mmbLast = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  // the trackpad path above already handled this gesture
                  if (_tpActive) return;
                  // M283 — and a mouse navigation drag owns the camera outright.
                  // Returning BEFORE the _mmbLast write at the end of this
                  // callback is the point: that write is what used to rewind
                  // the drag's anchor mid-gesture.
                  if (_mouseNav != MouseDrag.none) return;
                  if (d.pointerCount >= 2) {
                    if (d.scale > 0) {
                      final f = (_scaleStartH / d.scale) / p.camera.halfH;
                      _zoomAt(p, Cam3(p.camera, size), d.localFocalPoint, f);
                    }
                    _pan(p, d.localFocalPoint - _mmbLast, size);
                  } else if (_wpDrag == null &&
                      // M218 — and NOT under an open sketch menu. Same trap
                      // as the work-plane drag: the press that opened it
                      // lives in the raw Listener, so the finger still on the
                      // glass would otherwise orbit the model away behind the
                      // sheet.
                      !_lpFired &&
                      _dragKind == PointerDeviceKind.touch) {
                    // One finger orbits ON TOUCH only. A single trackpad or
                    // mouse drag is reserved for picking and must not move the
                    // view; orbiting there is the two-finger gesture.
                    //
                    // M170 — and NOT while a work plane is being dragged. The
                    // drag lives in the raw Listener above, which never enters
                    // the gesture arena, so without this a finger dragging a
                    // plane orbited the camera at the same time. Pencil and
                    // trackpad were unaffected (neither one-finger orbits),
                    // which is exactly the kind of touch-only fault that only
                    // shows up on the device.
                    _orbit(p, d.localFocalPoint - _mmbLast);
                  }
                  _mmbLast = d.localFocalPoint;
                }),
                // Transparent hit surface: the render layers sit BELOW
                // this in the outer Stack, so the topmost hit target is
                // always a plain Flutter widget, never the platform view.
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        // M357 — THE VIEWPORT'S OWN FLOATING CHROME, inside the band's edge.
        //
        // The cube, the triad and the toast are not the model: they float over
        // it, exactly as the browser and the tab bar do, and everything that
        // floats is supposed to clear the band (M290). They did — until M350
        // ran the document edge to edge under the glass, which took this
        // Stack's corners out to the screen's corners and put the triad behind
        // the ribbon.
        //
        // One Padding around all three rather than four numbers adjusted in
        // four places: whatever floats in this viewport tomorrow is inside it
        // by default, which is the property M290 was defending. The inset is
        // zero unless the band actually floats, so off iOS this is exactly the
        // Stack M290 left. See [RibbonBleed].
        Positioned.fill(
          child: ValueListenableBuilder<EdgeInsets>(
            valueListenable: RibbonBleed.inset,
            builder: (_, bleed, __) => Padding(
              padding: bleed,
              child: Stack(children: [
        // ViewCube + Home, top-right.
        //
        // M290 — plain numbers again. M146 put the ribbon into this coordinate
        // space and the cube had to be told where the glass ended; the band is
        // a row of the layout now, so this Stack's top-right corner IS the
        // corner of the content area, on every dock.
        Positioned(
            top: 8,
            right: 10,
            child: ViewCube(
              camera: p.camera,
              onChanged: () => setState(() {}),
              // M275 — the part's own front, and the command that redefines it.
              orient: p.cubeOrient,
              onOrient: app.setCubeOrient,
              // M283 — every view the cube sends the camera to is framed on
              // the part's own solids. _liveSolids, so the extrude preview
              // counts: it is on screen and it is what the user is looking at.
              fit: (c) => fitPartView(c, _liveSolids().toList(), size),
            )),
        // Coordinate triad. M146 — moved to the RIGHT of the model browser
        // instead of under it: the browser card reaches down into the
        // bottom-left corner the triad used to have to itself. Off iOS there
        // is no floating card, so it keeps the corner.
        //
        // M207 — and it FOLLOWS the panel now. It used to be pinned to the
        // expanded width whatever the panel was doing; retracting the browser
        // is a deliberate act to get that corner back, and the triad stayed
        // out in the open where the card no longer was.
        if (GlassBrowser.isSupported)
          ValueListenableBuilder<double>(
            valueListenable: NativeModelBrowser.occupied,
            builder: (_, w, child) => Positioned(
              // The triad follows the model browser inward. Retracted,
              // [NativeModelBrowser.triadInset] returns it to the border.
              left: NativeModelBrowser.triadInset(w),
              // M150 — the tab bar floats over the viewport now, so bottom: 0
              // would put the triad behind it.
              bottom: BottomTabBar.floatingHeight,
              child: child!,
            ),
            child: IgnorePointer(
                child: CustomPaint(
                    painter: TriadPainter(p.camera),
                    size: const Size(118, 118))),
          )
        else
          Positioned(
              left: 0,
              bottom: BottomTabBar.floatingHeight,
              child: IgnorePointer(
                  child: CustomPaint(
                      painter: TriadPainter(p.camera),
                      size: const Size(118, 118)))),
        if (app.message != null)
          Positioned(
            left: 0,
            right: 0,
            // M203 — above the floating tab bar, not behind it.
            bottom: 44 + BottomTabBar.floatingHeight,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: T.toastBg,
                  border: Border.all(color: T.toastBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child:
                    Text(app.message!, style: ts(12, T.toastText)),
              ),
            ),
          ),
              ]),
            ),
          ),
        ),
      ]);
    });
  }

  void _orbit(PartModel p, Offset d) {
    // TRACKBALL (M90). Was: az -= dx; pol = (pol - dy).clamp(0.02, pi - 0.02).
    // That is a turntable, and the clamp meant you could never look straight
    // down — let alone keep going. Rotating the basis about the SCREEN axes
    // instead is Inventor's Free Orbit and Blender's trackball: no preferred
    // up, no degenerate case, 360 degrees in every direction.
    // Counted, not timed: the orbit itself is a basis rotation and cannot be
    // slow. What matters is HOW MANY arrive — one orbit event per frame is a
    // camera move, ten per frame is an input-coalescing problem, and only the
    // count can tell those apart.
    Perf.count('3d.orbit.events');
    widget.app.engageView();
    p.camera.orbitScreen(-d.dx * 0.01, -d.dy * 0.01);
  }

  /// M260 — PAN, once. The same four lines stood inline at the middle-button
  /// drag, the shift-trackpad drag and the two-finger drag; folding them here
  /// gives the engagement latch a single place to sit, which is the whole
  /// reason it was worth doing.
  void _pan(PartModel p, Offset d, Size size) {
    widget.app.engageView();
    final wpp = (2 * p.camera.halfH) / size.height;
    p.camera.ox -= d.dx * wpp;
    p.camera.oy += d.dy * wpp;
  }

  void _zoomAt(PartModel p, Cam3 cam, Offset px, double factor) {
    widget.app.engageView();
    final a = cam.aspect;
    final nx = (px.dx / cam.size.width) * 2 - 1;
    final ny = -((px.dy / cam.size.height) * 2 - 1);
    final old = p.camera.halfH;
    p.camera.halfH = PartCamera.clampHalfH(old * factor);
    final dH = old - p.camera.halfH;
    if (dH.isFinite) {
      p.camera.ox += nx * a * dH;
      p.camera.oy += ny * dH;
    }
    _armRefine(cam.size); // re-tessellate to the new screen resolution
  }

  // ---- M283: the wheel glide -------------------------------------------
  //
  // A scroll event does not move the camera itself. It adds to [_wheel], and
  // this ticker takes a slice of what is owed every frame until it is spent.
  // One notch therefore arrives as a short movement rather than a jump, and a
  // fast scroll melts into one continuous zoom instead of a staircase.
  void _wheelStart() {
    if (_wheelTick != null) return;
    _wheelLast = null;
    _wheelTick = createTicker(_wheelFrame)..start();
  }

  void _wheelStop() {
    _wheelTick?.dispose();
    _wheelTick = null;
    _wheelLast = null;
  }

  void _wheelFrame(Duration elapsed) {
    final p = part;
    final last = _wheelLast;
    _wheelLast = elapsed;
    if (p == null || _viewSize.isEmpty || !mounted) {
      _wheel.cancel();
      _wheelStop();
      return;
    }
    // The first frame has nothing to measure against; one frame at 60 Hz is
    // the honest guess, and being a millisecond out is invisible.
    final dt =
        last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1000000.0;
    final f = _wheel.takeHalfHeightFactor(dt);
    if (f != 1) {
      setState(() => _zoomAt(p, Cam3(p.camera, _viewSize), _wheel.focus, f));
    }
    if (!_wheel.active) _wheelStop();
  }

  /// All drawable solids currently in the part (features + live preview).
  Iterable<KernelSolid> _liveSolids() sync* {
    final p = part;
    if (p == null) return;
    final sess = widget.app.extrudeSession;
    for (final f in p.features) {
      if (f.visible &&
          f.solid != null &&
          !f.consumedByJoin &&
          !f.rolledBack && // M91

          f.bodyName != sess?.previewReplacesBody) {
        yield f.solid!;
      }
    }
    final prev = sess?.preview;
    if (prev != null) yield prev;
  }

  /// The solids worth spending kernel time on — [_liveSolids] WITHOUT the
  /// extrude/revolve/coil preview.
  ///
  /// M161 — a preview is transient by construction: it exists while a dialog
  /// is open and is discarded the moment OK is pressed, when the committed
  /// feature is meshed from scratch. Refining it therefore buys a picture that
  /// is about to be thrown away, and then pays for the same tessellation
  /// again. The device log shows exactly that, and what it costs on a coil:
  ///
  ///   23:57:39  remesh n=1 lin=1.80e-2 tris=1002412 in 9952ms   <- preview
  ///   23:57:40  coil created Coil1; mesh Coil1: tris=7536       <- discarded
  ///   23:57:50  remesh n=1 lin=1.80e-2 tris=1002412 in 9959ms   <- again
  ///
  /// Twenty seconds for one coil, half of it for a mesh nobody kept. The
  /// preview still shows at its own (coarse) mesh and still COUNTS towards the
  /// triangle budget through [_liveSolids] — it is on screen and its cost is
  /// real — it is simply never the thing we refine.
  Iterable<KernelSolid> _refinableSolids() sync* {
    final prev = widget.app.extrudeSession?.preview;
    for (final s in _liveSolids()) {
      if (!identical(s, prev)) yield s;
    }
  }

  /// True when any live solid is coarser than this viewport's screen-space
  /// target — i.e. a re-mesh would make a curve visibly smoother.
  // ---- sketch-entry camera animation (M88) --------------------------------
  //
  // Snapping straight to the sketch plane is disorienting: the model appears
  // to jump to an unrelated orientation and you lose track of which face you
  // picked. Inventor swings the view across, which keeps that connection.
  AnimationController? _camAnim;
  PartCamera? _camFrom; // where the swing started
  bool _wasSketching = false;

  static const _camSwing = Duration(milliseconds: 420);

  /// Target camera with no animation applied.
  PartCamera _targetCamera(AppState app, PartModel p, Size size) {
    final child = app.activeChild;
    if (child == null) return p.camera;
    for (final cs in p.childSketches) {
      if (identical(cs.model, child) || cs.model.name == child.name) {
        return PartCamera.forSketch(
            sketchFrameOf(cs), size, app.pan, app.zoom);
      }
    }
    return p.camera;
  }

  /// The camera actually shown: the part's own while orbiting, one aimed down
  /// the open sketch's plane while sketching, and a blend of the two while
  /// entering or leaving a sketch.
  PartCamera _effectiveCamera(AppState app, PartModel p, Size size) {
    final target = _targetCamera(app, p, size);
    final sketching = app.activeChild != null;
    if (sketching != _wasSketching) {
      // Start the swing FROM whatever is on screen right now, so entering and
      // leaving mid-animation does not jump.
      _camFrom = _camAnim?.isAnimating == true && _camFrom != null
          ? PartCamera.lerp(_camFrom!, target, _camAnim!.value)
          : (sketching ? p.camera : _lastShown ?? p.camera);
      _wasSketching = sketching;
      app.setSketchOverlayFade(0);
      _camAnim
        ?..reset()
        ..forward();
    }
    final a = _camAnim;
    final from = _camFrom;
    final shown = (a != null && a.isAnimating && from != null)
        ? PartCamera.lerp(from, target, Curves.easeInOutCubic.transform(a.value))
        : target;
    _lastShown = shown;
    return shown;
  }

  PartCamera? _lastShown;

  int _sceneTriangles() {
    var n = 0;
    for (final s in _liveSolids()) {
      n += s.mesh.indices.length ~/ 3;
    }
    return n;
  }

  /// M172 — publish the viewport height so a DIALOG can convert screen pixels
  /// to model units without owning a BuildContext. Every scrubbable field has
  /// to agree on that scale or the same gesture means two different things.
  void _publishViewportHeight(double h) {
    if (h > 0 && widget.app.viewportHeightPx != h) {
      widget.app.viewportHeightPx = h;
    }
  }

  bool _anyCoarse(Size size) {
    final p = part;
    if (p == null) return false;
    final target = budgetedLinDeflection(
        viewLinearDeflection(p.camera.halfH, size.height), _sceneTriangles());
    for (final s in _refinableSolids()) {
      // M159 — ask the same bounded question _refineNow will act on, or the
      // debounce arms for a pass that then does nothing.
      if (meshNeedsRefine(s.meshLin, steppedLinDeflection(s.meshLin, target))) {
        return true;
      }
    }
    return false;
  }

  /// (Re)arm the debounce so a burst of zoom steps triggers exactly one
  /// kernel re-mesh after the gesture settles.
  void _armRefine(Size size) {
    // Never re-tessellate while a sketch is being edited. Even at v10's
    // parallel speed one pass still blocks the UI thread for ~400-590 ms, and
    // the device log shows those landing WHILE the user is drawing on a solid
    // face — which is exactly the stutter. The 3D view is not what is being
    // looked at during sketching and its camera is not moving, so there is
    // nothing to gain; refinement resumes on the next camera change after the
    // sketch is finished.
    _publishViewportHeight(size.height);
    if (widget.app.activeChild != null) return;
    if (!_anyCoarse(size)) return;
    _refineTimer?.cancel();
    _refineTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) _refineNow(size);
    });
  }

  void _refineNow(Size size) {
    final p = part;
    if (p == null) return;
    // Refinement only ever makes meshes FINER, so without a budget every zoom
    // step ratchets the scene up and nothing gives it back.
    final target = budgetedLinDeflection(
        viewLinearDeflection(p.camera.halfH, size.height), _sceneTriangles());
    var changed = false;
    var remeshed = 0;
    final sw = Stopwatch()..start();
    for (final s in _refinableSolids()) {
      // M159 — bound how much finer ONE pass may go. Without this a single
      // solid can leap from 7 536 to 1 002 412 triangles in one call and the
      // budget only learns about it afterwards, having paid ~10-56 s for it.
      final step = steppedLinDeflection(s.meshLin, target);
      final angStep = viewAngularDeflection(step);
      if (meshNeedsRefine(s.meshLin, step) && s.refine(step, angStep)) {
        changed = true;
        remeshed++;
      }
    }
    sw.stop();
    if (changed) {
      // Why this is logged: the 39555ac device log showed one gear being
      // re-tessellated FOUR times on the way in (41640 -> 46180 -> 49040 ->
      // 50548) and then thrown back to 4304 and redone when a second extrude
      // started. Without a timing here that is invisible.
      final tris = _sceneTriangles();
      Perf.record('kernel.remesh', sw.elapsedMicroseconds / 1000.0);
      Perf.gauge('sceneTris', tris);
      Perf.gauge('remeshCount', remeshed);
      Log.i(
          'perf',
          'remesh n=$remeshed lin=${target.toStringAsExponential(2)} '
          'tris=$tris in ${sw.elapsedMilliseconds}ms');
    }
    if (changed && mounted) setState(() {});
  }

  void _updateHover(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
    String? hit;
    int? region;
    // profile-region hover while the extrude dialog is picking profiles
    final sess = app.extrudeSession;
    if (sess != null && sess.sketchName != null) {
      final cs = p.sketchByName(sess.sketchName!);
      if (cs != null) {
        final frame = sketchFrameOf(cs);
        final w = cam.rayOnPlane(px, frame.n, frame.origin);
        if (w != null) {
          final sp = frame.toSketch(w); // M175 — origin-aware, like the sketch
          final r = regionAt(app.sessionRegions(cs), sp);
          region = r?.outer.id;
        }
      }
    }
    if (region == null) {
      hit = _hitOrigin(cam, px, p, planesOnly: app.pickPlane);
    }
    // Inventor prehighlight (M59): while picking a sketch plane, hovering a
    // planar solid face tints it blue. The face wins over an origin plane
    // BEHIND it — compare view depth, since the huge origin planes otherwise
    // capture every pixel and the face would never highlight.
    // M97 — while picking a target body, the body under the cursor is what
    // matters. Publishing it on AppState is what makes the model browser row
    // light up at the same time: both read app.hoverBody.
    if (app.pickingBody) {
      // _pickSolidFace runs per pointer move, but only while a pick is armed
      // — outside that mode this branch is a single bool test. setHoverBody
      // early-returns when the name is unchanged, so a move across one body
      // repaints once, not once per frame.
      // M102 — STICKY. _pickSolidFace returns the frontmost face, and where
      // two bodies meet or overlap that flips between them on sub-pixel
      // movement — the highlight "jumped around". The body under the cursor
      // only changes when the cursor is genuinely over a DIFFERENT body and
      // stays there; a momentary miss (a gap between facets, an edge) keeps
      // the current one rather than dropping it.
      final pick = _pickSolidAny(cam, px); // M105 — any face, not just planar
      final name = pick == null ? null : _bodyNameOf(p, pick);
      // M103 — hysteresis in BOTH directions. M102 only damped the drop to
      // null, so a sweep across the seam between two bodies still switched on
      // the first sample of the neighbour — and every switch recomputes the
      // boolean preview, which is what flickered while the mouse moved. A new
      // body now has to win twice in a row before the preview is rebuilt.
      // M104 — with the preview/body loop closed there is nothing left to
      // damp: a sample either lands on a body (including the preview standing
      // in for one) or on nothing. The two-sample confirmation added in M103
      // is REMOVED — it made a genuine switch need a second sample that a slow
      // hand might never deliver, which is why the highlight got worse rather
      // than better. Only the miss counter stays, so a hairline crack between
      // facets does not blink the highlight off.
      if (name == app.hoverBody) {
        _hoverBodyMiss = 0;
      } else if (name == null) {
        if (++_hoverBodyMiss >= 3) app.setHoverBody(null);
      } else {
        _hoverBodyMiss = 0;
        app.setHoverBody(name);
      }
    }
    // M135 — prehighlight the edge under the pointer while an edge pick is
    // armed. Same shape as the body hover above: gated on the mode, and
    // setHoverEdge early-returns when nothing changed, so holding still costs
    // one comparison rather than a ribbon rebuild per frame.
    if (app.pickingEdges) {
      final hit = _pickEdgeAt(cam, px);
      app.setHoverEdge3d(
          hit?.$1, (hit != null && hit.$2.usable) ? hit.$2.displayEdge : -1);
    }
    (KernelSolid, int)? hf;
    // M260 — while a WORK-FEATURE command is collecting as well, not just the
    // Offset/Midplane flow. The generic Plane button used to arm Offset, which
    // set [AppState.pickPlane] and lit the face under the pointer; now it arms
    // the inferring command, and a pick command that does not show you what
    // you are about to pick is the same tool with the lights off.
    //
    // Planar faces only, which is what _pickSolidFace answers by default: it
    // is the right set for a plane, and the one pick it misses (a torus) is
    // still perfectly pickable, just not pre-lit.
    if ((app.pickPlane || app.pickWorkGeometry) && region == null) {
      final pick = _pickSolidFace(cam, px);
      if (pick != null && pick.$2 >= 0) {
        final planeD = hit == null
            ? double.infinity
            : _planeDepthAt(cam, px, hit) ?? double.infinity;
        if (pick.$4 <= planeD + 1e-6) {
          hf = (pick.$1, pick.$2);
          hit = null; // the face is in front: it prehighlights, not the plane
        }
      }
    }
    // Sketch curves prehighlight in plain 3D (nothing consumes the selection
    // yet — this makes them addressable for later). Origin geometry, profile
    // regions and solid faces all outrank them.
    final sk = (hit == null && region == null && hf == null)
        ? _pickSketchCurve(cam, px)
        : null;
    if (hit != _hover ||
        region != _hoverRegion ||
        sk != _hoverSketch ||
        hf?.$1 != _hoverFace?.$1 ||
        hf?.$2 != _hoverFace?.$2) {
      setState(() {
        _hover = hit;
        _hoverRegion = region;
        _hoverFace = hf;
        _hoverSketch = sk;
      });
    } else {
      setState(() {}); // cursor moved (plane-pick marker etc.)
    }
  }

  /// Points/edges win over planes, exactly like the mock's raycast order.
  /// 3D pick against origin geometry, work planes and solid faces.
  ///
  /// Runs on the tap path and — via [_hitOrigin] callers on hover — can run
  /// per pointer-move. It projects candidate geometry through the camera in
  /// Dart, so its cost grows with the scene, not with the screen.
  String? _hitOrigin(Cam3 cam, Offset px, PartModel p,
          {bool planesOnly = false}) =>
      Perf.span('3d.hitTest',
          () => _hitOriginInner(cam, px, p, planesOnly: planesOnly));

  String? _hitOriginInner(Cam3 cam, Offset px, PartModel p,
      {bool planesOnly = false}) {
    const pickPx = 8.0;
    if (!planesOnly) {
      if (p.vis['cp'] == true &&
          (cam.project(Vec3.zero) - px).distance < pickPx) {
        return 'cp';
      }
      for (final e in [
        ('x', const Vec3(1, 0, 0)),
        ('y', const Vec3(0, 1, 0)),
        ('z', const Vec3(0, 0, 1))
      ]) {
        if (p.vis[e.$1] != true) continue;
        // M83: exactly the span the painter draws (originAxisSpan), so an
        // axis is never pickable past its visible end.
        final (al, ah) = originAxisSpan(p, e.$2);
        final a = cam.project(e.$2 * al), b = cam.project(e.$2 * ah);
        if (segDistSq(px, a, b).$1 < pickPx * pickPx) return e.$1;
      }
    }
    // planes, nearest first
    String? best;
    var bestD = double.infinity;
    for (final key in kPlaneKeys) {
      // Origin planes are auto-pickable only while the part is still empty
      // (first extrusion); afterwards only if explicitly switched on.
      if (!(p.vis[key] == true ||
          (planesOnly && widget.app.pickPlane && !p.hasSolid))) {
        continue;
      }
      final f = planeFrame(key);
      final w = cam.rayOnPlane(px, f.n, f.origin);
      if (w == null) continue;
      final sp0 = f.toSketch(w);
      final uu = sp0.dx, vv = sp0.dy;
      // M83: the picked rectangle is the DRAWN rectangle. Both come from
      // originPlaneRect, so a plane is never clickable off its own edge.
      final (uMin, uMax, vMin, vMax) = originPlaneRect(p, key);
      if (uu >= uMin && uu <= uMax && vv >= vMin && vv <= vMax) {
        final d = cam.depth(w);
        if (d < bestD) {
          bestD = d;
          best = key;
        }
      }
    }
    // M151 — work planes, same test with their own frame and rectangle. They
    // are always pickable: unlike the origin planes they exist because the
    // user asked for them, so hiding them behind a visibility rule would be
    // surprising.
    for (final w in p.workPlanes) {
      if (!w.visible) continue;
      final f = w.frame;
      final wp = cam.rayOnPlane(px, f.n, f.origin);
      if (wp == null) continue;
      final sp0 = f.toSketch(wp);
      final uu = sp0.dx, vv = sp0.dy;
      final (uMin, uMax, vMin, vMax) = planeRectFor(p, f);
      if (uu >= uMin && uu <= uMax && vv >= vMin && vv <= vMax) {
        final d = cam.depth(wp);
        if (d < bestD) {
          bestD = d;
          best = w.id;
        }
      }
    }
    return best;
  }

  /// M174 — the plane or FACE under [px] to build a new work plane from, with
  /// a label for its definition line. A face wins over a plane behind it, the
  /// same rule the sketch-plane pick uses, so what you grab is what you see.
  (PlaneFrame?, String) _planeOrFaceAt(Cam3 cam, Offset px, PartModel p) {
    final key = _hitOrigin(cam, px, p, planesOnly: true);
    final face = _pickSolidFace(cam, px);
    final planeD =
        key != null ? (_planeDepthAt(cam, px, key) ?? double.infinity) : double.infinity;
    final faceD = face?.$4 ?? double.infinity;
    if (face != null && faceD <= planeD + 1e-6) return (face.$3, 'face');
    if (key != null) {
      final f = frameForPlaneKey(p, key);
      if (f != null) {
        return (f, kPlaneKeys.contains(key) ? key.toUpperCase() : key);
      }
    }
    if (face != null) return (face.$3, 'face');
    return (null, '');
  }

  /// M169 — the work plane under [px], or null. Reuses the same hit test the
  /// hover and the picker use, so what lights up is what you grab.
  WorkPlane? _workPlaneAt(Cam3 cam, Offset px, PartModel p) {
    final hit = _hitOrigin(cam, px, p);
    return hit == null ? null : _workPlaneById(p, hit);
  }

  /// The work plane a pick key names, or null when it names something else.
  static WorkPlane? _workPlaneById(PartModel p, String key) {
    for (final w in p.workPlanes) {
      if (w.id == key) return w;
    }
    return null;
  }

  /// View depth of origin plane [key] directly under the pointer, or null if
  /// the ray misses the plane's bounded extent. Lets hover/tap compare a
  /// plane against a solid face sitting in front of it.
  double? _planeDepthAt(Cam3 cam, Offset px, String key) {
    final p = widget.app.currentPart;
    final f = p == null ? null : frameForPlaneKey(p, key);
    if (f == null) return null;
    final w = cam.rayOnPlane(px, f.n, f.origin);
    if (w == null) return null;
    return cam.depth(w);
  }

  /// Nearest front-facing solid triangle under the pointer -> the frame of
  /// the planar face it belongs to (Inventor's sketch-on-face, M58). The
  /// orthographic projection is affine, so barycentric coordinates of the
  /// screen hit reproduce the world point exactly.
  /// The nearest PLANAR solid face under [px]: (solid, v4 face id or -1,
  /// sketch frame, view depth). Planarity comes from the B-Rep face record
  /// when the mesh carries v4 metadata, else from the vertex-normal test.
  /// M97 — which body a picked solid belongs to. The pick returns the mesh of
  /// one FEATURE; the body is the name that feature builds into.
  /// Consecutive hover samples that hit no body (M102 — see the hover code).
  int _hoverBodyMiss = 0;


  /// M105 — frontmost solid under [px], ANY face, planar or not.
  ///
  /// Body hovering used `_pickSolidFace`, which exists for sketch-on-face and
  /// therefore skips every non-planar face (`kFacePlane`). On a cylinder the
  /// round face is exactly that, so hovering the curved side of a body found
  /// nothing at all — the reported dead spots. Picking a BODY does not care
  /// what kind of surface you touched, so this drops the planarity test and
  /// keeps only the facing and depth logic.
  KernelSolid? _pickSolidAny(Cam3 cam, Offset px) {
    KernelSolid? best;
    var bestDepth = double.infinity;
    for (final s in _liveSolids()) {
      final m = s.mesh;
      for (var t = 0; t < m.indices.length; t += 3) {
        final i0 = m.indices[t] * 3,
            i1 = m.indices[t + 1] * 3,
            i2 = m.indices[t + 2] * 3;
        final w0 =
            Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
        final w1 =
            Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
        final w2 =
            Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
        final n = (w1 - w0).cross(w2 - w0);
        // Camera-facing only, same convention as _pickSolidFace (n·dir > 0).
        if (n.length < 1e-12 || !cam.facesCamera(n)) continue;
        // Barycentric test in SCREEN space: cheap and independent of the
        // surface type, which is the whole point here.
        final a = cam.project(w0), b = cam.project(w1), c = cam.project(w2);
        final d = (b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy);
        if (d.abs() < 1e-9) continue;
        final u = ((px.dx - a.dx) * (c.dy - a.dy) -
                (c.dx - a.dx) * (px.dy - a.dy)) /
            d;
        final v = ((b.dx - a.dx) * (px.dy - a.dy) -
                (px.dx - a.dx) * (b.dy - a.dy)) /
            d;
        if (u < -1e-6 || v < -1e-6 || u + v > 1 + 1e-6) continue;
        final depth = cam.depth(w0) * (1 - u - v) +
            cam.depth(w1) * u +
            cam.depth(w2) * v;
        if (depth < bestDepth) {
          bestDepth = depth;
          best = s;
        }
      }
    }
    return best;
  }

  String? _bodyNameOf(PartModel p, KernelSolid solid) {
    // M104 — THE FLICKER, and why holding still did not help either.
    //
    // Hovering a body builds the boolean preview and sets
    // previewReplacesBody, and visibleSolids then HIDES that body and draws
    // the combined preview in its place. The very next hover sample therefore
    // hit the PREVIEW mesh, which belongs to the throwaway session feature and
    // is in no p.features — so this returned null, the miss counter ran up,
    // the hover cleared, the preview reverted, the real body reappeared and
    // was hit again. A loop that repaints forever, entirely of my own making
    // in M100.
    //
    // The preview STANDS IN for that body, so hovering it is hovering the
    // body. Saying so breaks the loop at the root; the hysteresis added in
    // M102/M103 was treating the symptom.
    final sess = widget.app.extrudeSession;
    if (sess != null &&
        sess.preview != null &&
        identical(sess.preview, solid) &&
        sess.previewReplacesBody != null) {
      return sess.previewReplacesBody;
    }
    for (final f in p.features) {
      if (identical(f.solid, solid)) return f.bodyName;
    }
    return null;
  }

  /// M133 — the B-Rep edge under the pointer, or null.
  ///
  /// The decision itself lives in part_pick.dart so it can be tested without
  /// a device; all this does is hand it the live meshes and the camera's two
  /// projections, then map the mesh index back to its solid.
  /// M215 — the tap under a Work Axis / Work Point command, reduced to what
  /// it CONTRIBUTES (see WorkRef). Null when nothing usable is under [px].
  ///
  /// Priority, and why each step is where it is:
  ///   1. existing work features and origin entities. They are drawn thin and
  ///      are the easiest things on screen to miss, so a tap within tolerance
  ///      of both an axis and the face behind it means the axis — the same
  ///      rule the revolve-axis pick already follows for origin axes.
  ///   2. edges. An edge sits ON a face, so a face test would always win at
  ///      the boundary and "pick an edge" would be unreachable.
  ///   3. faces, any type. Planar gives a plane; a cylinder or cone gives its
  ///      axis of revolution; a sphere or torus gives its centre.
  WorkRef? _pickWorkRef(Cam3 cam, Offset px, PartModel p) {
    // -- 1. work features and origin entities ------------------------------
    final wf = _hitWorkFeature(cam, px, p);
    if (wf != null) return wf;
    final origin = _hitOrigin(cam, px, p);
    if (origin != null) {
      if (origin == 'cp') {
        return WorkRef.point('Center Point', Vec3.zero);
      }
      if (origin == 'x' || origin == 'y' || origin == 'z') {
        final d = origin == 'x'
            ? const Vec3(1, 0, 0)
            : origin == 'y'
                ? const Vec3(0, 1, 0)
                : const Vec3(0, 0, 1);
        // An origin axis is INFINITE, so it offers no midpoint — the middle
        // of an infinite line is not a point the user pointed at.
        return WorkRef.axis('${origin.toUpperCase()} Axis', Vec3.zero, d);
      }
      final f = frameForPlaneKey(p, origin);
      if (f != null) {
        final label = origin.startsWith('wp:')
            ? _workPlaneById(p, origin)?.name ?? 'Work Plane'
            : planeLabel(origin);
        return WorkRef.plane(label, f.origin, f.n);
      }
    }

    // -- 2. edges ----------------------------------------------------------
    final e = _pickEdgeAt(cam, px);
    if (e != null) {
      final ep = e.$2;
      final m = e.$1.mesh;
      // The ANALYTIC curve record, not the tessellation: a circle picked off
      // its polyline would give a centre that wobbles with the deflection.
      final ci = ep.displayEdge * 16;
      if (ci >= 0 && ci + 16 <= m.edgeCurves.length) {
        final c = m.edgeCurves;
        final type = c[ci].round();
        if (type == 1) {
          final a = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
          final b = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
          if ((b - a).length > 1e-9) return WorkRef.line('Edge', a, b);
        } else if (type == 2 || type == 3) {
          final centre = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
          final xd = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
          final yd = Vec3(c[ci + 7], c[ci + 8], c[ci + 9]);
          final axis = xd.cross(yd);
          if (axis.length > 1e-9) {
            return WorkRef.circle(
                type == 2 ? 'Circular Edge' : 'Elliptical Edge', centre, axis);
          }
        }
      }
      // No analytic record (a spline, or a legacy mesh): the tessellation
      // still gives an honest MIDPOINT, which is a real Inventor input.
      return WorkRef.point('Edge Midpoint', ep.mid);
    }

    // -- 3. faces ----------------------------------------------------------
    final fr = _pickFaceRecord(cam, px);
    // M231 — nothing solid under the finger: a sketch curve is the last thing
    // it can have meant, and it is the input "Normal to Curve at Point" wants.
    if (fr == null) return _pickWorkCurve(cam, px);
    final (info, _, hit) = fr;
    final type = info[0].round();
    final at = Vec3(info[1], info[2], info[3]);
    final dir = Vec3(info[4], info[5], info[6]);
    if (dir.length < 1e-9 && type != kFacePlane) return null;
    switch (type) {
      case kFacePlane:
        return WorkRef.plane('Face', at, dir);
      case kFaceCylinder:
        // M224 — radius (slot 10) and the tapped point: everything a tangent
        // plane needs beyond the axis.
        return WorkRef.cylinder('Cylindrical Face', at, dir,
            radius: info[10], hitAt: hit);
      case kFaceCone:
        return WorkRef.revolvedFace('Conical Face', at, dir);
      case kFaceSphere:
        return WorkRef.sphere('Spherical Face', at);
      case kFaceTorus:
        return WorkRef.torus('Toroidal Face', at, dir);
      default:
        return null; // a surface with no axis and no centre offers nothing
    }
  }

  /// M231 — a sketch CURVE, as a last resort.
  ///
  /// Last on purpose: every solid pick above wins over it, so nothing that
  /// worked before M231 picks differently now. A curve only answers when
  /// nothing solid was under the finger, which is also when the user can only
  /// have meant the curve.
  WorkRef? _pickWorkCurve(Cam3 cam, Offset px) {
    final hit = _pickSketchCurveHit(cam, px);
    if (hit == null || hit.dir.length < 1e-9) return null;
    return WorkRef.curveAt('Curve', hit.at, hit.dir);
  }

  /// The frontmost face's 15-double surface record under [px], with its depth
  /// and the world point the ray HIT.
  /// Unlike [_pickSolidFace] this accepts EVERY surface type — a work feature
  /// wants the cylinder that a sketch cannot be drawn on.
  ///
  /// M224 — the hit point comes back because a tangent work plane needs the
  /// SIDE of the cylinder that was tapped: there are two tangent planes
  /// through a point outside it, and nothing in the cylinder's own geometry
  /// says which one the user meant. It was already being computed here for the
  /// depth test.
  (List<double>, double, Vec3)? _pickFaceRecord(Cam3 cam, Offset px) {
    (List<double>, double, Vec3)? best;
    var bestDepth = double.infinity;
    for (final s in _liveSolids()) {
      final m = s.mesh;
      if (m.triFaces.length * 3 != m.indices.length || m.faceInfos.isEmpty) {
        continue; // no face identity on this mesh: nothing to report
      }
      for (var t = 0; t < m.indices.length; t += 3) {
        final i0 = m.indices[t] * 3,
            i1 = m.indices[t + 1] * 3,
            i2 = m.indices[t + 2] * 3;
        final w0 =
            Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
        final w1 =
            Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
        final w2 =
            Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
        final n = (w1 - w0).cross(w2 - w0);
        // Front faces only — see _pickSolidFace for why n·dir > 0 is the
        // visible side.
        if (n.length < 1e-12 || !cam.facesCamera(n)) continue;
        final a = cam.project(w0), b = cam.project(w1), c = cam.project(w2);
        final den =
            (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
        if (den.abs() < 1e-9) continue;
        final l0 =
            ((b.dy - c.dy) * (px.dx - c.dx) + (c.dx - b.dx) * (px.dy - c.dy)) /
                den;
        final l1 =
            ((c.dy - a.dy) * (px.dx - c.dx) + (a.dx - c.dx) * (px.dy - c.dy)) /
                den;
        final l2 = 1 - l0 - l1;
        const e = -1e-6;
        if (l0 < e || l1 < e || l2 < e) continue;
        final hit = w0 * l0 + w1 * l1 + w2 * l2;
        final d = cam.depth(hit);
        if (d >= bestDepth) continue;
        final fid = m.triFaces[t ~/ 3];
        if (15 * fid + 15 > m.faceInfos.length) continue;
        bestDepth = d;
        best = (m.faceInfos.sublist(15 * fid, 15 * fid + 15), d, hit);
      }
    }
    return best;
  }

  /// M217 — the face under [px] for a Delete Face / Direct Edit pick, as
  /// (mesh index, fingerprint). Null when the tap missed every solid.
  ///
  /// Any surface type, unlike [_pickSolidFace]: deleting the cylindrical face
  /// of a hole is the single commonest thing Delete Face is reached for, and a
  /// planar-only pick would make it unreachable.
  (int, FacePick)? _pickFaceForEdit(Cam3 cam, Offset px) {
    for (final sol in _liveSolids()) {
      final m = sol.mesh;
      final hit = _frontFaceIndex(cam, px, sol);
      if (hit == null) continue;
      for (final fr in facesOf(m)) {
        if (fr.meshIndex != hit) continue;
        return (
          hit,
          FacePick(fr.centre.x, fr.centre.y, fr.centre.z, fr.normal.x,
              fr.normal.y, fr.normal.z, fr.area, fr.kind)
        );
      }
    }
    return null;
  }

  /// Index of the frontmost face of [sol] under [px], or null.
  ///
  /// Takes the SOLID rather than its mesh because this file deliberately does
  /// not import the FFI layer (see the imports) and so cannot name
  /// OcctMeshData — which it never needs to.
  int? _frontFaceIndex(Cam3 cam, Offset px, KernelSolid sol) {
    final m = sol.mesh;
    if (m.triFaces.length * 3 != m.indices.length || m.faceInfos.isEmpty) {
      return null;
    }
    int? best;
    var bestDepth = double.infinity;
    for (var t = 0; t < m.indices.length; t += 3) {
      final i0 = m.indices[t] * 3,
          i1 = m.indices[t + 1] * 3,
          i2 = m.indices[t + 2] * 3;
      final w0 =
          Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
      final w1 =
          Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
      final w2 =
          Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
      final n = (w1 - w0).cross(w2 - w0);
      if (n.length < 1e-12 || !cam.facesCamera(n)) continue;
      final a = cam.project(w0), b = cam.project(w1), c = cam.project(w2);
      final den = (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
      if (den.abs() < 1e-9) continue;
      final l0 =
          ((b.dy - c.dy) * (px.dx - c.dx) + (c.dx - b.dx) * (px.dy - c.dy)) /
              den;
      final l1 =
          ((c.dy - a.dy) * (px.dx - c.dx) + (a.dx - c.dx) * (px.dy - c.dy)) /
              den;
      final l2 = 1 - l0 - l1;
      const e = -1e-6;
      if (l0 < e || l1 < e || l2 < e) continue;
      final d = cam.depth(w0 * l0 + w1 * l1 + w2 * l2);
      if (d >= bestDepth) continue;
      bestDepth = d;
      best = m.triFaces[t ~/ 3];
    }
    return best;
  }

  /// An existing work axis or work point under [px], as a [WorkRef] — so a
  /// work feature can be built ON another one, exactly as Inventor allows
  /// ("any combination of two lines including ... work axes").
  WorkRef? _hitWorkFeature(Cam3 cam, Offset px, PartModel p) {
    const pickPx = 9.0;
    for (final pt in p.workPoints) {
      if (!pt.visible) continue;
      if ((cam.project(pt.at) - px).distance < pickPx) {
        return WorkRef.point(pt.name, pt.at, source: WorkRefSource.vertex);
      }
    }
    for (final a in p.workAxes) {
      if (!a.visible) continue;
      final (s0, s1) = _workAxisEnds(p, a);
      if (segDistSq(px, cam.project(s0), cam.project(s1)).$1 <
          pickPx * pickPx) {
        return WorkRef.axis(a.name, a.at, a.dir);
      }
    }
    return null;
  }

  /// The drawn ends of [a], so picking and painting can never disagree about
  /// where the axis stops — the rule M83 established for the origin axes.
  (Vec3, Vec3) _workAxisEnds(PartModel p, WorkAxis a) {
    // Null bounds means an empty part — workAxisSpan's own minimum then
    // supplies a stub long enough to see and tap, which is what an axis on a
    // part with no geometry needs.
    final b = partContentBounds(p);
    return workAxisSpan(
        a.at, a.dir, b?.$1 ?? a.at, b?.$2 ?? a.at);
  }

  (KernelSolid, EdgePick)? _pickEdgeAt(Cam3 cam, Offset px) {
    final solids = _liveSolids().toList();
    if (solids.isEmpty) return null;
    final hit = pickEdge(
      [for (final s in solids) s.mesh],
      cam.project,
      cam.depth,
      px,
    );
    if (hit == null) return null;
    return (solids[hit.meshIndex], hit);
  }

  /// [planarOnly] is what sketch-on-face needs (Inventor only sketches on a
  /// plane). M213 picks ANY face, because the feature that made a cylinder is
  /// as selectable as the one that made a wall.
  (KernelSolid, int, PlaneFrame, double)? _pickSolidFace(Cam3 cam, Offset px,
      {bool planarOnly = true}) {
    (KernelSolid, int, PlaneFrame, double)? best;
    var bestDepth = double.infinity;
    for (final s in _liveSolids()) {
      final m = s.mesh;
      final v4 =
          m.triFaces.length * 3 == m.indices.length && m.faceInfos.isNotEmpty;
      for (var t = 0; t < m.indices.length; t += 3) {
        final i0 = m.indices[t] * 3,
            i1 = m.indices[t + 1] * 3,
            i2 = m.indices[t + 2] * 3;
        final w0 =
            Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
        final w1 =
            Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
        final w2 =
            Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
        final n = (w1 - w0).cross(w2 - w0);
        // Keep the triangles FACING THE CAMERA. Measured on device
        // (mesh3d convention log, build 2648d2e): the winding normal
        // cross(p1-p0, p2-p0) agrees with the per-vertex normal for 100% of
        // triangles, and those normals point outward for 100% of vertices —
        // so this normal IS the outward one, and the camera sits at +dir
        // ("camera at dir*D", Cam3). A visible face therefore has n·dir > 0.
        // The old test kept n·dir < 0, i.e. the BACK faces, which is why:
        // sketches landed on the far side of the body (making an extrusion
        // read as a recess), the blue prehighlight was built on a face hidden
        // behind the solid, and picking missed entirely near the silhouette
        // where no back face lies under the cursor. The ViewCube uses the
        // n·dir > 0 form and has always worked.
        if (n.length < 1e-12 || !cam.facesCamera(n)) continue;
        final nn = n.normalized();
        var faceId = -1;
        if (v4) {
          faceId = m.triFaces[t ~/ 3];
          // Only PLANAR faces accept sketches (Inventor) — authoritative
          // answer straight from the B-Rep surface record.
          if (planarOnly && m.faceInfos[15 * faceId].round() != kFacePlane) {
            continue;
          }
        } else if (planarOnly) {
          // fallback: planar iff the tessellation vertex normals all equal
          // the geometric normal (curved faces fan out)
          var planar = true;
          for (final vi in [i0, i1, i2]) {
            final vn =
                Vec3(m.normals[vi], m.normals[vi + 1], m.normals[vi + 2]);
            if (vn.dot(nn).abs() < 0.9999) {
              planar = false;
              break;
            }
          }
          if (!planar) continue;
        }
        final a = cam.project(w0), b = cam.project(w1), c = cam.project(w2);
        final den =
            (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
        if (den.abs() < 1e-9) continue;
        final l0 =
            ((b.dy - c.dy) * (px.dx - c.dx) + (c.dx - b.dx) * (px.dy - c.dy)) /
                den;
        final l1 =
            ((c.dy - a.dy) * (px.dx - c.dx) + (a.dx - c.dx) * (px.dy - c.dy)) /
                den;
        final l2 = 1 - l0 - l1;
        const e = -1e-6;
        if (l0 < e || l1 < e || l2 < e) continue;
        final w = w0 * l0 + w1 * l1 + w2 * l2;
        final d = cam.depth(w);
        if (d < bestDepth) {
          bestDepth = d;
          // outward normal from the face record when present (exact),
          // else the geometric triangle normal
          var fn = nn;
          if (v4) {
            fn = Vec3(m.faceInfos[15 * faceId + 4],
                    m.faceInfos[15 * faceId + 5], m.faceInfos[15 * faceId + 6])
                .normalized();
          }
          best = (s, faceId, faceFrame(w, fn), d);
        }
      }
    }
    return best;
  }

  /// M153 — fingerprint of the face just picked, so the sketch placed on it
  /// can find that face again after the model rebuilds. Null when the mesh
  /// carries no v4 metadata (fakes, legacy meshes), which leaves the sketch
  /// with the old frozen frame rather than a wrong one.
  SketchFaceSel? _faceRefOf(KernelSolid s, int faceId) {
    if (faceId < 0) return null;
    for (final f in planarFaceRecs(s.mesh)) {
      if (f.id == faceId) return SketchFaceSel.of(f);
    }
    return null;
  }

  /// M212 — one tap, routed to whichever pattern selector is armed.
  ///
  /// Every branch either fills its field or says what it wanted; a miss never
  /// silently disarms the selector, because a pattern is usually defined by
  /// picking twice in the same corner of the model and losing the arming on
  /// the first near-miss is what makes a pick field feel unreliable.
  void _patternTap(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
    final s = app.patternSession!;
    switch (s.active) {
      case PatternField.dirA:
      case PatternField.dirB:
      case PatternField.axis:
        // An ORIGIN AXIS outranks an edge: it is drawn thinner and is easier
        // to miss, so within tolerance of both it is what was meant (the same
        // rule the revolve axis pick follows).
        final origin = _hitOrigin(cam, px, p);
        if (origin == 'x' || origin == 'y' || origin == 'z') {
          final d = switch (origin) {
            'x' => const Vec3(1, 0, 0),
            'y' => const Vec3(0, 1, 0),
            _ => const Vec3(0, 0, 1),
          };
          app.patternAxisPicked(
              Vec3.zero, d, '${origin!.toUpperCase()} Axis');
          return;
        }
        final hit = _pickEdgeAt(cam, px);
        if (hit != null) {
          final ax = edgeAxis(hit.$1.mesh, hit.$2.displayEdge);
          if (ax != null) {
            app.patternAxisPicked(ax.$1, ax.$2, ax.$3);
            return;
          }
          app.toast(L.current.msgEdgeIsSpline);
          return;
        }
        // A sketch LINE is a direction too, and on a part whose origin axes
        // are switched off it is often the only one to hand. Anything else —
        // an arc, a spline, a trimmed ellipse — is a PATH the row runs along,
        // which is exactly the range Inventor accepts for a row or column.
        final key = _pickSketchCurve(cam, px);
        if (key != null) {
          final line = _sketchLineOf(p, key);
          if (line != null) {
            app.patternAxisPicked(line.$1, line.$2, 'Sketch line');
            return;
          }
          final path = _sketchPathOf(p, key);
          if (path != null) {
            if (s.active == PatternField.axis) {
              app.toast(L.current.msgRotationAxisStraight);
              return;
            }
            app.patternPathPicked(path, first: s.active == PatternField.dirA);
            return;
          }
        }
        app.toast(L.current.msgPickEdgeOrCurve);
      case PatternField.startA:
      case PatternField.startB:
        final first = s.active == PatternField.startA;
        final sel = first ? s.pathA : s.pathB;
        if (sel == null) {
          app.toast(L.current.msgPickCurveFirst);
          return;
        }
        final cs = p.sketchByName(sel.sketchName);
        if (cs == null) {
          app.toast(L.current.msgCurveGone);
          return;
        }
        // The tap is turned into a point ON THE CURVE'S PLANE, which is where
        // the curve is; the arc length nearest that point is the start.
        final frame = sketchFrameOf(cs);
        final w = cam.rayOnPlane(px, frame.n, frame.origin);
        if (w == null) {
          app.toast(L.current.msgTapOnTheCurve);
          return;
        }
        app.patternStartPicked(w, first: first);
      case PatternField.orientFace:
        final face = _pickSolidFace(cam, px, planarOnly: false);
        if (face == null) {
          app.toast(L.current.msgTapFaceToFollow);
          return;
        }
        app.patternOrientFacePicked(face.$3);
      case PatternField.plane:
        final face = _pickSolidFace(cam, px);
        final key = _hitOrigin(cam, px, p, planesOnly: true);
        final planeD = key != null
            ? (_planeDepthAt(cam, px, key) ?? double.infinity)
            : double.infinity;
        final faceD = face?.$4 ?? double.infinity;
        if (face != null && faceD <= planeD) {
          app.patternPlanePicked(face.$3.origin, face.$3.n, 'Face');
          return;
        }
        final fr = key == null ? null : frameForPlaneKey(p, key);
        if (fr != null) {
          app.patternPlanePicked(fr.origin, fr.n,
              kPlaneKeys.contains(key) ? '${key!.toUpperCase()} Plane'
                  : (_workPlaneById(p, key!)?.name ?? 'Work Plane'));
          return;
        }
        app.toast(L.current.msgPickPlanarFace);
      case PatternField.pointSketch:
      case PatternField.basePoint:
        final hit = _sketchPointAt(cam, px, p);
        if (hit == null) {
          app.toast(L.current.msgPickSketchPointOccurrences);
          return;
        }
        if (s.active == PatternField.pointSketch) {
          app.patternPointSketchPicked(hit.$1);
        } else {
          app.patternBasePointPicked(hit.$1, hit.$2);
        }
      case PatternField.solid:
        final solid = _pickSolidAny(cam, px);
        final name = solid == null ? null : _bodyNameOf(p, solid);
        if (name == null) {
          app.toast(L.current.msgPickSolidBodyToPattern);
          return;
        }
        app.patternBodyPicked(name);
      case PatternField.features:
        // M213 — a face names the feature that made it. The provenance is
        // recovered geometrically (see attributeFaces), so it can honestly
        // fail to know; when it does, say which face and point at the
        // browser rather than selecting something at random.
        final face = _pickSolidFace(cam, px, planarOnly: false);
        if (face == null) {
          app.toast(L.current.msgTapFaceOfFeature);
          return;
        }
        final owner = app.featureOfFace(face.$1, face.$2);
        if (owner == null) {
          app.toast(L.current.msgFaceNoSingleFeature);
          return;
        }
        if (!app.patternToggleFeature(owner)) return;
        app.toast(app.patternHasFeature(owner.name)
            ? L.current.msgAddedNamed(owner.name)
            : L.current.msgRemovedNamed(owner.name));
      case PatternField.none:
        break;
    }
  }

  /// The sketch LINE behind a `sketchName#index` pick key, as (point,
  /// direction) in world coordinates. Null when the key names anything else.
  (Vec3, Vec3)? _sketchLineOf(PartModel p, String key) {
    final i = key.lastIndexOf('#');
    if (i < 0) return null;
    final cs = p.sketchByName(key.substring(0, i));
    final gi = int.tryParse(key.substring(i + 1)) ?? -1;
    if (cs == null || gi < 0 || gi >= cs.model.geometry.length) return null;
    final g = cs.model.geometry[gi];
    if (g.type != Geo.line || g.data.length < 4) return null;
    final frame = sketchFrameOf(cs);
    final a = frame.toWorld(Offset(g.data[0], g.data[1]));
    final b = frame.toWorld(Offset(g.data[2], g.data[3]));
    final d = b - a;
    return d.length < 1e-9 ? null : (a, d.normalized());
  }

  /// The sketch CURVE behind a `sketchName#index` pick key, as the
  /// re-findable [CurveSel] a pattern path is stored as. Null for a straight
  /// line, which is a direction rather than a path.
  CurveSel? _sketchPathOf(PartModel p, String key) {
    final i = key.lastIndexOf('#');
    if (i < 0) return null;
    final name = key.substring(0, i);
    final cs = p.sketchByName(name);
    final gi = int.tryParse(key.substring(i + 1)) ?? -1;
    if (cs == null || gi < 0 || gi >= cs.model.geometry.length) return null;
    final g = cs.model.geometry[gi];
    if (g.type == Geo.line) return null;
    final pts = sketchCurve(g);
    if (pts.length < 2) return null;
    var len = 0.0;
    for (var k = 1; k < pts.length; k++) {
      len += (pts[k] - pts[k - 1]).distance;
    }
    return CurveSel(name, gi, pts.first.dx, pts.first.dy, pts.last.dx,
        pts.last.dy, len);
  }

  /// The sketch POINT under [px]: its sketch name and its position in that
  /// sketch's coordinates. Points are what a sketch-driven pattern is made
  /// of, and they are markers rather than curves, so they get their own hit
  /// test rather than going through the curve picker.
  (String, Offset)? _sketchPointAt(Cam3 cam, Offset px, PartModel p) {
    const tolPx = 14.0;
    (String, Offset)? best;
    var bestD = tolPx * tolPx;
    for (final cs in p.childSketches) {
      // Only what is DRAWN can be tapped: a point in a hidden sketch is not
      // on screen, and picking one would be picking something invisible.
      if (cs.rolledBack || !cs.visible) continue;
      final frame = sketchFrameOf(cs);
      for (final pt in sketchPatternPoints(cs.model)) {
        final sp = cam.project(frame.toWorld(pt));
        final dx = sp.dx - px.dx, dy = sp.dy - px.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 <= bestD) {
          bestD = d2;
          best = (cs.model.name, pt);
        }
      }
    }
    return best;
  }

  void _tap(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
    // M212 — the PATTERN panel's selectors come FIRST, before even the plain
    // sketch-curve selection: while the panel is waiting for a direction, an
    // axis, a plane or a point, that is what the tap is for. Anything below
    // would otherwise consume it and the pick field would look dead.
    if (app.patternPicking3D) {
      _patternTap(cam, px);
      return;
    }
    // M225 — the hole panel wants sketch POINTS, and nothing else may consume
    // the tap while it is open: a pick field that looks dead is the failure
    // this file has fixed twice (M210's profile pick, M212's selectors).
    // M227 — the combine panel wants BODIES, and owns the tap while it is up.
    if (app.combinePicking3D) {
      final solid = _pickSolidAny(cam, px);
      final name = solid == null ? null : _bodyNameOf(p, solid);
      if (name == null) {
        app.toast(L.current.msgTapSolidBody);
        return;
      }
      app.combineBodyPicked(name);
      return;
    }
    if (app.holePicking3D) {
      final hit = _sketchPointAt(cam, px, p);
      if (hit == null) {
        app.toast(L.current.msgTapSketchPointForHole);
        return;
      }
      app.holePointPicked(hit.$1, hit.$2);
      return;
    }
    // M291 — a section command is waiting for a plane, and owns the tap while
    // it is. The SAME hit test the work-plane drag uses, which is what makes
    // an origin plane, a work plane and a planar face all valid targets
    // without three code paths — and what makes "pick any plane or planar
    // face" true here in the sense Inventor means it.
    if (app.sectionPicking) {
      final (frame, label) = _planeOrFaceAt(cam, px, p);
      if (frame == null) {
        app.toast(app.sectionDraft == null
            ? L.current.msgPickSectionPlane
            : L.current.msgPickSectionPlane2);
        return;
      }
      app.sectionPlanePicked(frame, label);
      // Still asking: the two-plane commands prompt for the second one rather
      // than leaving the viewport silent with a command half given.
      if (app.sectionPicking) app.toast(L.current.msgPickSectionPlane2);
      return;
    }
    // M254 — a tap that is NOT on a work plane clears the work-plane
    // selection, the other half of "die work plane im Modell browser [ist]
    // immer gehighlighted". Pointer-down selects the plane you touch; nothing
    // ever un-selected it, so the row stayed lit for the rest of the session.
    // Here and not on pointer-down, because a DRAG that happens to start on
    // empty space is an orbit and must not change the selection.
    if (!app.pickPlane &&
        app.extrudeSession == null &&
        app.selectedWorkPlane != null &&
        _workPlaneAt(cam, px, p) == null) {
      app.selectWorkPlane(null);
    }
    // A hovered sketch curve is selectable in plain 3D. Shift/ctrl extends the
    // set, a plain tap replaces it, a tap on empty space clears it.
    //
    // M260 — but NOT while a work-feature command is collecting. This branch
    // returns when it takes a curve, so it was swallowing the tap before the
    // work-feature pick below could see it, and a sketch LINE is a perfectly
    // good axis for a plane to be normal to (it is exactly what
    // [WorkRef.line] is for). The guard reads `pickPlane` because the Offset
    // and Midplane flows set that; the legacy Axis, Point and Plane commands
    // set [AppState.pickWorkGeometry] instead and were never covered.
    if (!app.pickPlane &&
        !app.pickWorkGeometry &&
        app.extrudeSession == null) {
      final sk = _pickSketchCurve(cam, px);
      if (sk != null) {
        setState(() {
          final add = HardwareKeyboard.instance.isShiftPressed ||
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (!add) {
            final had = _selSketch.contains(sk);
            _selSketch.clear();
            if (!had) _selSketch.add(sk);
          } else if (!_selSketch.remove(sk)) {
            _selSketch.add(sk);
          }
        });
        return;
      }
      if (_selSketch.isNotEmpty) setState(_selSketch.clear);
    }
    // M131b — 0. picking the sweep PATH. Same sketch-curve picker as the
    // revolve axis; a path IS a sketch curve.
    if (app.pickingSweepPath) {
      final key = _pickSketchCurve(cam, px);
      if (key != null) {
        final i = key.lastIndexOf('#');
        app.sweepPathPicked(i < 0 ? key : key.substring(0, i),
            i < 0 ? -1 : (int.tryParse(key.substring(i + 1)) ?? -1));
      } else {
        app.cancelPickSweepPath();
      }
      return;
    }
    // M131b — 0. picking LOFT sections. Stays armed: a loft needs several,
    // and a miss must not discard the ones already chosen.
    if (app.pickingLoftSections) {
      // Any sketch, unlike extrude which locks to one: a loft's whole point is
      // running between profiles on DIFFERENT sketches.
      for (final cs in p.childSketches) {
        final frame = sketchFrameOf(cs);
        final w = cam.rayOnPlane(px, frame.n, frame.origin);
        if (w == null) continue;
        final sp = frame.toSketch(w); // M175 — origin-aware, like the sketch
        final r = regionAt(app.sessionRegions(cs), sp);
        if (r != null) {
          final ip = regionAnchor(r); // M221 — the region's, not its loop's
          app.toggleLoftSection(
              cs.model.name, ProfileSel(ip.dx, ip.dy, r.outer.area));
          return;
        }
      }
      return;
    }
    // M217 — 0. a Delete Face / Direct Edit command is armed. Like the edge
    // pick it STAYS armed: a face set is built up over several taps and a miss
    // must not throw away what is already selected.
    if (app.pickingFaces) {
      final hit = _pickFaceForEdit(cam, px);
      if (hit != null) app.toggleFacePick(hit.$2, hit.$1);
      return;
    }
    // M215 — 0. a Work Axis / Work Point command is armed. Runs before every
    // other pick mode because it is the ONLY one that wants edges, faces,
    // vertices and existing work features all at once: letting the plane pick
    // below see the tap first would swallow every face before this could ask
    // whether the user meant its axis.
    //
    // A miss does NOT cancel. These commands can need two or three picks, and
    // throwing away a half-built selection because one tap landed on empty
    // space would be the most expensive possible response to the cheapest
    // possible mistake. Esc and the ribbon toggle cancel; nothing else does.
    if (app.pickWorkGeometry) {
      final ref = _pickWorkRef(cam, px, p);
      if (ref != null) {
        app.workFeaturePick(ref);
      } else {
        app.toast(app.workFeaturePrompt);
      }
      return;
    }
    // M137 — 0. picking the AXIS of revolution. Reuses the sketch-curve
    // picker: an axis IS a sketch line, and _pickSketchCurve already returns
    // the sketchName#index key that identifies one.
    if (app.pickingRevolveAxis) {
      // An ORIGIN AXIS outranks a sketch line: it is drawn thinner and is
      // easier to miss, so if the tap is within tolerance of both, the axis
      // is what was meant.
      final origin = _hitOrigin(cam, px, p);
      if (origin == 'x' || origin == 'y' || origin == 'z') {
        app.revolveAxisPickedOrigin(origin!);
        return;
      }
      final key = _pickSketchCurve(cam, px);
      if (key != null) {
        final i = key.lastIndexOf('#');
        final name = i < 0 ? key : key.substring(0, i);
        final gi = i < 0 ? -1 : (int.tryParse(key.substring(i + 1)) ?? -1);
        app.revolveAxisPicked(name, gi);
      } else {
        app.cancelPickRevolveAxis();
      }
      return;
    }
    // M133 — 0a. picking the termination FACE for the "To" extent. Reuses
    // the planar face pick: a planar face is exactly the case
    // resolveExtrudeSpan can solve analytically.
    if (app.pickingExtentFace) {
      final face = _pickSolidFace(cam, px);
      if (face != null) {
        app.extentFacePicked(face.$3);
      } else {
        app.cancelPickExtentFace(); // tapping empty space backs out, like Esc
      }
      return;
    }
    // M133 — 0b. picking EDGES for fillet/chamfer. Unlike the single-shot
    // picks above this one STAYS armed: an edge set is built up over several
    // taps, and a miss must not throw away what is already selected.
    if (app.pickingEdges) {
      final hit = _pickEdgeAt(cam, px);
      if (hit != null && hit.$2.usable) {
        // toSel() fingerprints the edge's arc-length MIDPOINT, not the tap
        // location — that is the anchor occt_shape_edge_info reports and the
        // only one a rebuild can be matched against.
        app.toggleEdgePick(hit.$2.topoEdge, hit.$2.toSel(),
            solid: hit.$1, display: hit.$2.displayEdge);
      }
      return;
    }
    // M97 — 0. picking a TARGET BODY for the extrude dialog. Runs before
    // everything else: while the dialog is waiting, a tap on a solid means
    // "this one", not "sketch on this face".
    if (app.pickingBody) {
      // M103 — take the body that is CURRENTLY highlighted, not a fresh
      // frontmost pick. Re-picking at the instant of the tap could land on the
      // neighbour at a seam, so you clicked the highlighted solid and got the
      // other one — "selecting doesn't work". What you see is what you get.
      final shown = app.hoverBody;
      if (shown != null) {
        app.pickBody(shown);
        return;
      }
      final face = _pickSolidAny(cam, px); // M105
      final name = face == null ? null : _bodyNameOf(p, face);
      if (name != null) {
        app.pickBody(name);
        return;
      }
      app.cancelPickBody(); // tapping empty space backs out, like Esc
      return;
    }
    // 1. plane pick (Start 2D Sketch): origin planes first, then any planar
    //    face of a solid (Inventor's sketch-on-face)
    if (app.pickPlane) {
      final key = _hitOrigin(cam, px, p, planesOnly: true);
      final face = _pickSolidFace(cam, px);
      // whichever surface is NEARER under the pointer wins — a solid face in
      // front of an origin plane must be the one you sketch on (Inventor).
      // Depth is w·(-dir) and the camera sits at +dir, so NEARER is SMALLER.
      final planeD = key != null
          ? (_planeDepthAt(cam, px, key) ?? double.infinity)
          : double.infinity;
      final faceD = face?.$4 ?? double.infinity;
      // M181 — a plane the USER placed does not lose a tie with a face. The
      // renderer already lifts every plane a hair toward the camera so that a
      // coplanar face "can never win the depth test against it" — its words —
      // and a pick that then hands the tap to the face behind is exactly the
      // what-you-see-is-not-what-you-get this has been reported as. The bias
      // is the same sub-pixel idea, expressed in model units: the face has to
      // be VISIBLY in front, not in front by a rounding error.
      final planeBias = key != null && !kPlaneKeys.contains(key)
          ? -3 * app.viewUnitsPerPixel
          : 1e-6;
      if (face != null && faceD <= planeD + planeBias) {
        app.facePicked(face.$3, _faceRefOf(face.$1, face.$2));
        return;
      }
      // M173 — say which surface won and why. "I still cannot sketch on a
      // work plane" has now survived two fixes that both looked right by
      // inspection (M151 built the path, M167 taught planePicked the key), so
      // the next report should arrive with the decision already in the log
      // rather than costing another round of reading code.
      Log.i(
          'pick',
          'sketch plane: hit=${key ?? "none"} planeD='
              '${planeD.isFinite ? planeD.toStringAsFixed(3) : "inf"} '
              'faceD=${faceD.isFinite ? faceD.toStringAsFixed(3) : "inf"} '
              '-> ${face != null && faceD <= planeD + planeBias ? "FACE" : (key == null ? "nothing" : (kPlaneKeys.contains(key) ? "origin plane" : "work plane"))}');
      if (key != null && kPlaneKeys.contains(key)) {
        app.planePicked(key);
        return;
      }
      // M181 — one command, given the plane by name. It used to go down the
      // sketch-on-FACE path with a bare frame, which stored the result as a
      // face sketch: a second encoding of the same thing, and the reason the
      // two routes could not be reasoned about together.
      if (key != null) {
        final wp = _workPlaneById(p, key);
        if (wp != null) {
          Log.i('pick', 'starting a sketch on work plane $key');
          app.startSketchOnWorkPlane(wp, alreadyArmed: true);
          return;
        }
        Log.w('pick', 'hit "$key" but no work plane matched it — falling '
            'through to the face behind it');
      }
      if (face != null) app.facePicked(face.$3, _faceRefOf(face.$1, face.$2));
      return;
    }
    // 2. profile pick for the extrude dialog
    final sess = app.extrudeSession;
    if (sess != null) {
      // the pick may LOCK the session to a sketch: try the session sketch
      // first, then every child sketch (nearest plane wins)
      final order = <ChildSketch>[
        if (sess.sketchName != null && p.sketchByName(sess.sketchName!) != null)
          p.sketchByName(sess.sketchName!)!,
        ...p.childSketches.where((c) => c.model.name != sess.sketchName),
      ];
      for (final cs in order) {
        final frame = sketchFrameOf(cs);
        final w = cam.rayOnPlane(px, frame.n, frame.origin);
        if (w == null) continue;
        final sp = frame.toSketch(w); // M175 — origin-aware, like the sketch
        final r = regionAt(app.sessionRegions(cs), sp);
        if (r != null) {
          app.toggleSessionProfile(cs.model.name, r,
              remove: HardwareKeyboard.instance.isShiftPressed);
          return;
        }
        // M155 — only a session the user has actually committed to one sketch
        // is locked. `sess.sketchName` is ALWAYS set when the dialog opens
        // (openExtrude defaults it to the newest sketch), and that sketch is
        // first in `order`, so this used to break on the very first pass and
        // no second sketch was ever reachable — tapping a profile in the other
        // sketch did nothing. That is what blocked extruding from either of
        // two sketches, and loft/sweep need at least two.
        // `toggleSessionProfile` already enforces the real rule: an
        // auto-picked profile yields to the user's pick, and only an explicit
        // multi-profile selection refuses to cross sketches.
        if (sess.sketchName == cs.model.name &&
            !sess.autoPicked &&
            sess.profiles.isNotEmpty) {
          break; // genuinely locked to this sketch
        }
      }
      return;
    }
  }

}

// ---------------------------------------------------------------------------
// scene painter
// ---------------------------------------------------------------------------
/// M215 — a dashed segment in SCREEN space.
///
/// Screen space and not model space on purpose: the dash is a legend ("the
/// user made this"), so it must read the same at every zoom. A model-space
/// dash would turn into a solid line when you zoom out and into one long dash
/// when you zoom in, which is the opposite of what a legend does.
void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
    {double dash = 6, double gap = 4}) {
  final total = (b - a).distance;
  if (total < 1e-6) return;
  final step = dash + gap;
  final dir = (b - a) / total;
  for (var t = 0.0; t < total; t += step) {
    final end = math.min(t + dash, total);
    canvas.drawLine(a + dir * t, a + dir * end, paint);
  }
}

/// M215 — user work axes and work points, in SCREEN space.
///
/// Called from BOTH painters, and that is the whole point. On iOS the scene is
/// RealityKit and `_ScenePainter` never runs — only `_OverlayPainter` does. A
/// work feature drawn in the scene painter alone would have been perfectly
/// visible on the host and invisible on the device it was built for.
///
/// Screen space also means no Swift: an axis is two projected points joined by
/// a dashed line and a point is a small cross, neither of which needs an
/// entity in the RealityKit graph to look right. (A work PLANE does — it is a
/// filled quad that has to be depth-tested against the solid — which is why
/// that one goes through the scene payload and these two do not.)
void paintWorkFeatures(
        Canvas canvas, Cam3 cam, PartModel part, AppState app) =>
    paintWorkAxesAndPoints(canvas, cam,
        axes: part.workAxes,
        points: part.workPoints,
        bounds: partContentBounds(part),
        app: app);

/// M247 — the same two glyphs, for whichever document owns them.
///
/// Split out with the lists and the content box as parameters so the ASSEMBLY
/// viewport draws its own work axes and points with this code and not a copy
/// of it: the dash pattern, the selection colour and the end caps are what
/// tell a user "this is a work axis", and two implementations would be two
/// answers to that.
///
/// [bounds] is the document's content box, which is what the axis is spanned
/// over — a part's for a part, the placed components' for an assembly.
void paintWorkAxesAndPoints(
  Canvas canvas,
  Cam3 cam, {
  required Iterable<WorkAxis> axes,
  required Iterable<WorkPoint> points,
  required (Vec3, Vec3)? bounds,
  required AppState app,
}) {
  for (final a in axes) {
    if (!a.visible) continue;
    final sel = identical(app.selectedWorkAxis, a);
    final b = bounds;
    final (e0, e1) = workAxisSpan(a.at, a.dir, b?.$1 ?? a.at, b?.$2 ?? a.at);
    final p0 = cam.project(e0), p1 = cam.project(e1);
    // Dashed, because unlike an origin axis this is something the user made
    // and can delete — the same cue that already separates a work plane from
    // an origin plane.
    _dashedLine(
        canvas,
        p0,
        p1,
        Paint()
          ..strokeWidth = sel ? 2 : 1.2
          ..color = sel ? _greenBright : _orangeEdge);
    if (sel) {
      for (final e in [p0, p1]) {
        canvas.drawCircle(
            e,
            5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _greenBright);
      }
    }
  }
  for (final pt in points) {
    if (!pt.visible) continue;
    final sel = identical(app.selectedWorkPoint, pt);
    final c = cam.project(pt.at);
    // A cross in a box, not a filled dot: it has to stay tellable apart from
    // the origin centre point and from a sketch point at the same place.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sel ? 2 : 1.3
      ..color = sel ? _greenBright : _orangeEdge;
    const r = 4.5;
    canvas.drawLine(c + const Offset(-r, 0), c + const Offset(r, 0), paint);
    canvas.drawLine(c + const Offset(0, -r), c + const Offset(0, r), paint);
    canvas.drawRect(
        Rect.fromCenter(center: c, width: r * 2, height: r * 2), paint);
  }
}

class _ScenePainter extends CustomPainter {
  final AppState app;
  final PartModel part;
  final String? hover;
  final int? hoverRegion;
  final (KernelSolid, int)? hoverFace; // M59 face prehighlight
  _ScenePainter(
      this.app, this.part, this.hover, this.hoverRegion, this.hoverFace);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    final cam = Cam3(part.camera, size);

    // The opaque solids form a depth occluder: origin planes and sketches are
    // infinitely thin, so their pixels are hidden wherever a nearer solid
    // front face covers them. This is what makes the 2D overlays read as
    // truly 3D (a sketch behind the model is hidden; one in front covers it).
    final occSolids = [
      for (final f in part.features)
        if (f.visible &&
            f.solid != null &&
            !f.consumedByJoin &&
            !f.rolledBack && // M91

            f != app.extrudeSession?.editing &&
            f.bodyName != app.extrudeSession?.previewReplacesBody)
          f.solid!
    ];
    // M250 — EDIT IN PLACE: the rest of the parent assembly, already in this
    // part's own frame. Empty for every ordinary part render. It goes into the
    // occluder as well as the painter, so a sketch or an origin plane behind a
    // surrounding component is hidden by it — see solidOccluder.
    final context = [
      for (final (_, at, sol) in app.inPlaceContextPieces) (at, sol)
    ];
    final occ = occSolids.isEmpty && context.isEmpty
        ? null
        : solidOccluder(occSolids, cam, context: context);

    // Draw the SOLIDS first, then origin planes, then sketches. This gives the
    // Inventor coplanar tie-break — a sketch or plane on the exact plane of a
    // face is not hidden by it (occlusion bias) and, being drawn later, layers
    // ON TOP: sketch > plane > geometry. Overlays genuinely BEHIND the model
    // are still removed per-pixel by [occ]. The edited feature is replaced by
    // its translucent live preview, drawn on top by paintPartSolids. For a
    // boolean preview the whole target body is hidden too, so the combined
    // result (sess.preview) stands in for it rather than z-fighting it.
    {
      final sess = app.extrudeSession;
      final solids = [
        for (final f in part.features)
          if (f.visible &&
              f.solid != null &&
              !f.consumedByJoin &&
              !f.rolledBack && // M91

              f != sess?.editing &&
              f.bodyName != sess?.previewReplacesBody)
            f.solid!
      ];
      // M144 — the accent set the RealityKit overlay draws, drawn here too so
      // the CPU painter (non-iOS, and gallery thumbnails) agrees with it.
      // Hover and selection merge into one set, as they do on device.
      final accentSolid = app.pickedEdgeSolid ?? app.hoverEdge3d?.$1;
      final accent = <int>{
        if (app.pickedEdgeSolid != null)
          for (final d in app.pickedEdgeDisplay)
            if (d >= 0) d,
        if (app.hoverEdge3d != null &&
            identical(app.hoverEdge3d!.$1, accentSolid) &&
            app.hoverEdge3d!.$2 >= 0)
          app.hoverEdge3d!.$2,
      };
      // The bodies selected and hovered in the model browser, drawn the way
      // RealityKit draws them (a tinted body) so the two viewports say the
      // same thing. `solids` is what is actually being DRAWN — a body hidden
      // behind a boolean preview or an open feature edit must not light up.
      List<KernelSolid> solidsOfBody(String? body) => body == null
          ? const []
          : [
              for (final f in part.features)
                if (f.bodyName == body &&
                    f.solid != null &&
                    solids.any((s) => identical(s, f.solid)))
                  f.solid!
            ];
      paintPartSolids(canvas, cam, solids,
          previewSolid: sess?.preview,
          highlightSolid: hoverFace?.$1,
          highlightFace: hoverFace?.$2 ?? -1,
          accentSolid: accentSolid,
          accentEdges: accent,
          selectedSolids: solidsOfBody(app.selectedBody),
          hoveredSolids: solidsOfBody(app.browserHoverBody),
          // M272 — and the appearance each body was given, so the CPU painter
          // and RealityKit show the same part. Keyed through the feature that
          // built the solid, because a material belongs to the BODY.
          materialOf: (s) => materialColorOfSolid(part, s),
          // M250 — the assembly around an in-place edit, in the same depth
          // pass as the part so the two occlude each other properly.
          context: context);
    }

    // ---- work planes (M151) ----
    // Drawn with the origin planes and by the same helpers: an occluded fill
    // so the plane passes THROUGH the model rather than floating on it, and
    // the same green-on-hover the origin planes use, so a work plane
    // highlights identically to the thing it was defined from.
    for (final w in part.workPlanes) {
      if (!w.visible) continue;
      final f = w.frame;
      final (uMin, uMax, vMin, vMax) = planeRectFor(part, f);
      final c0 = f.toWorld(Offset(uMin, vMin));
      final c1 = f.toWorld(Offset(uMax, vMin));
      final c2 = f.toWorld(Offset(uMax, vMax));
      final c3 = f.toWorld(Offset(uMin, vMax));
      final hot = hover == w.id;
      drawOccludedQuadFill(canvas, cam, c0, c1, c2, c3,
          (hot ? _green : _orange).withValues(alpha: hot ? 0.42 : 0.22),
          occ: occ);
      drawOccludedPolyline(
          canvas,
          cam,
          [c0, c1, c2, c3, c0],
          Paint()
            ..color =
                (hot ? _green : _orange).withValues(alpha: hot ? 0.95 : 0.65)
            ..strokeWidth = hot ? 2.0 : 1.2
            ..style = PaintingStyle.stroke,
          occ: occ);
    }

    // ---- origin planes (fills first: everything else draws over them) ----
    for (final key in kPlaneKeys) {
      // M291 — and while a section command is asking for a plane, the three
      // origin planes are shown whatever the part's own visibility says. They
      // are the commonest thing to section at and you cannot tap what is not
      // drawn; ending the command puts them back as they were, because this
      // reads the flag rather than writing `vis`.
      final visible = part.vis[key] == true ||
          (app.pickPlane && !part.hasSolid) ||
          app.sectionPicking;
      if (!visible) continue;
      final f = planeFrame(key);
      // M83: the plane's own padded rectangle around the part, NOT a fixed
      // square. Same function the RealityKit payload and the hit-test use.
      final (uMin, uMax, vMin, vMax) = originPlaneRect(part, key);
      final corners = [
        f.toWorld(Offset(uMin, vMin)),
        f.toWorld(Offset(uMax, vMin)),
        f.toWorld(Offset(uMax, vMax)),
        f.toWorld(Offset(uMin, vMax)),
      ];
      final hot = hover == key;
      // The construction plane fill is a real 3D surface: it is occluded by
      // the solids so it passes THROUGH the model instead of floating on top.
      drawOccludedQuadFill(canvas, cam, corners[0], corners[1], corners[2],
          corners[3], (hot ? _green : _orange).withOpacity(hot ? 0.42 : 0.28),
          occ: occ);
      drawOccludedPolyline(
          canvas,
          cam,
          corners,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = hot ? _greenBright : _orangeEdge,
          occ: occ,
          close: true,
          extra: occ?.edgeMargin ?? 0);
      if (hot) {
        // M254 — corner DOTS (not rings), centre dot, name label lying on the
        // plane. Same marker as the iOS overlay painter draws, and it has to
        // stay the same marker: the two viewports draw the same chrome.
        for (final c in corners) {
          canvas.drawCircle(cam.project(c), 4, Paint()..color = _greenBright);
        }
        canvas.drawCircle(cam.project(Vec3.zero), 4,
            Paint()..color = T.dofArrow);
        final p0 = cam.project(f.toWorld(Offset(uMin + 0.6, vMin + 1.4)));
        final p1 = cam.project(f.toWorld(Offset(uMin + 4.6, vMin + 1.4)));
        final ang = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
        canvas.save();
        canvas.translate(p0.dx, p0.dy);
        canvas.rotate(ang);
        final tp = TextPainter(
            text: TextSpan(
                text: planeLabel(key),
                style: ts(12, _greenBright, w: FontWeight.w700)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(0, -tp.height));
        canvas.restore();
      }
    }

    // ---- axes + centre point ----
    for (final e in [
      ('x', const Vec3(1, 0, 0)),
      ('y', const Vec3(0, 1, 0)),
      ('z', const Vec3(0, 0, 1))
    ]) {
      if (part.vis[e.$1] != true) continue;
      final hot = hover == e.$1;
      final (al, ah) = originAxisSpan(part, e.$2);
      final a = cam.project(e.$2 * al), b = cam.project(e.$2 * ah);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = 1
            ..color = hot ? _green : _orange);
      if (hot) {
        for (final p in [a, b]) {
          canvas.drawCircle(p, 4, Paint()..color = _greenBright);
        }
      }
    }
    if (part.vis['cp'] == true) {
      final c = cam.project(Vec3.zero);
      final hot = hover == 'cp';
      canvas.drawCircle(
          c, hot ? 5 : 3.5, Paint()..color = hot ? _green : _orange);
      if (hot) {
        canvas.drawCircle(
            c,
            9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _greenBright);
      }
    }

    paintWorkFeatures(canvas, cam, part, app);

    // ---- child sketches as curves on their planes: Inventor visibility —
    // a sketch renders while cs.visible (consumption turns it off, the
    // browser eye turns it back on), and always while a session shows it ----
    final sess = app.extrudeSession;
    for (final cs in part.childSketches) {
      final showForSession = sess?.sketchName == cs.model.name ||
          (sess != null && sess.sketchName == null);
      if (!cs.visible && !showForSession) continue;
      // M93 — same rule as the RealityKit payload: the sketch currently being
      // edited is drawn LIVE by Viewport2D and must not be drawn a second time
      // here, or a stale ghost trails the one under your finger.
      if (app.inEditMode &&
          app.activeChild != null &&
          (identical(app.activeChild, cs.model) ||
              app.activeChild!.name == cs.model.name)) {
        continue;
      }
      _paintSketch(canvas, cam, cs, occ: occ);
      if (sess != null && showForSession) {
        _paintRegions(canvas, cam, cs, sess);
      }
    }
  }

  void _paintSketch(Canvas canvas, Cam3 cam, ChildSketch cs,
      {SceneOccluders? occ}) {
    final frame = sketchFrameOf(cs);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = T.ink;
    for (final g in cs.model.geometry) {
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      final li = cs.model.layers.indexOf(g.layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      // M93: construction geometry is 2D scaffolding — never part of the 3D
      // view. Only the sketch being edited ever showed it, and that sketch is
      // no longer painted here at all.
      if (g.isConstruction) continue;
      final pts = sketchCurve(g);
      if (pts.length < 2) continue;
      // Project to world on the sketch plane, then stroke only the parts not
      // hidden behind a nearer solid face — the sketch now sits in 3D.
      drawOccludedPolyline(
          canvas, cam, [for (final p in pts) frame.toWorld(p)], pen,
          occ: occ, extra: occ?.edgeMargin ?? 0);
    }
    // M220 — a text is geometry, so it is part of the sketch in 3D as well:
    // the same contours the extrude reads, closed (first point repeated).
    for (final t in cs.model.texts) {
      final layer = textLayerOf(t);
      if (cs.model.hiddenLayers.contains(layer)) continue;
      final li = cs.model.layers.indexOf(layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      for (final c in textContours(cs.model, t)) {
        if (c.length < 3) continue;
        drawOccludedPolyline(
            canvas,
            cam,
            [for (final p in [...c, c.first]) frame.toWorld(p)],
            pen,
            occ: occ,
            extra: occ?.edgeMargin ?? 0);
      }
    }
  }

  void _paintRegions(
      Canvas canvas, Cam3 cam, ChildSketch cs, ExtrudeSession sess) {
    final frame = sketchFrameOf(cs);
    for (final r in app.sessionRegions(cs)) {
      final selected = sess.sketchName == cs.model.name &&
          sess.hasProfileAt(regionAnchor(r));
      final hovered = hoverRegion == r.outer.id;
      if (!selected && !hovered) continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      void loopPath(List<Offset> pts) {
        for (var i = 0; i < pts.length; i++) {
          final s = cam.project(frame.toWorld(pts[i]));
          i == 0 ? path.moveTo(s.dx, s.dy) : path.lineTo(s.dx, s.dy);
        }
        path.close();
      }

      loopPath(r.outer.pts);
      for (final h in r.holes) {
        loopPath(h.pts);
      }
      canvas.drawPath(
          path, Paint()..color = T.accent.withOpacity(selected ? 0.38 : 0.16));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 1.6 : 1
            ..color = selected ? T.hover : T.accent.withOpacity(0.7));
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}

// ---------------------------------------------------------------------------
// screen-space overlay painter (M60)
//
// The decorations the CPU painter drew WITHOUT any occluder — profile-region
// fills, plane hover rings/label, axis end rings, centre-point ring. They are
// pure screen-space HUD, so on iOS they stay in Flutter and are stacked ON TOP
// of the RealityKit surface, reproducing the previous behaviour exactly. Only
// the depth-tested world geometry moved to RealityKit.
// ---------------------------------------------------------------------------
class _OverlayPainter extends CustomPainter {
  final AppState app;
  final PartModel part;
  final String? hover;
  final int? hoverRegion;
  _OverlayPainter(this.app, this.part, this.hover, this.hoverRegion);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = Cam3(part.camera, size);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _greenBright;
    // M254 — the corner and end markers are DOTS. Reported: "die punkte an den
    // ecken der plane sollten punkte sein nicht kreise". They were stroked
    // rings, and a ring reads as a thing with a hole in it, where what these
    // mark is a point. [ring] stays for the centre-point hover, which really
    // is a ring drawn AROUND a dot that already exists.
    final dot = Paint()..color = _greenBright;

    // ---- hovered origin plane: corner rings + centre dot + name label ----
    if (hover != null && kPlaneKeys.contains(hover)) {
      final f = planeFrame(hover!);
      // M83: the plane's own padded rectangle around the part, NOT a fixed
      // square. Same function the RealityKit payload and the hit-test use.
      final (uMin, uMax, vMin, vMax) = originPlaneRect(part, hover!);
      final corners = [
        f.toWorld(Offset(uMin, vMin)),
        f.toWorld(Offset(uMax, vMin)),
        f.toWorld(Offset(uMax, vMax)),
        f.toWorld(Offset(uMin, vMax)),
      ];
      for (final c in corners) {
        canvas.drawCircle(cam.project(c), 4, dot);
      }
      canvas.drawCircle(
          cam.project(Vec3.zero), 4, Paint()..color = T.dofArrow);
      final p0 = cam.project(f.toWorld(Offset(uMin + 0.6, vMin + 1.4)));
      final p1 = cam.project(f.toWorld(Offset(uMin + 4.6, vMin + 1.4)));
      final ang = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
      canvas.save();
      canvas.translate(p0.dx, p0.dy);
      canvas.rotate(ang);
      final tp = TextPainter(
          text: TextSpan(
              text: planeLabel(hover!),
              style: ts(12, _greenBright, w: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(0, -tp.height));
      canvas.restore();
    }

    // ---- hovered axis: rings at both ends ----
    for (final e in [
      ('x', const Vec3(1, 0, 0)),
      ('y', const Vec3(0, 1, 0)),
      ('z', const Vec3(0, 0, 1))
    ]) {
      if (part.vis[e.$1] != true || hover != e.$1) continue;
      final (al, ah) = originAxisSpan(part, e.$2);
      for (final p in [
        cam.project(e.$2 * al),
        cam.project(e.$2 * ah),
      ]) {
        canvas.drawCircle(p, 4, dot);
      }
    }

    // ---- hovered centre point: highlight ring (the dot itself is a
    // RealityKit entity, so it stays depth-tested) ----
    if (part.vis['cp'] == true && hover == 'cp') {
      canvas.drawCircle(cam.project(Vec3.zero), 9, ring);
    }

    paintWorkFeatures(canvas, cam, part, app);

    // ---- extrude profile regions (hovered / selected) ----
    final sess = app.extrudeSession;
    if (sess == null) return;
    for (final cs in part.childSketches) {
      final showForSession =
          sess.sketchName == cs.model.name || sess.sketchName == null;
      if (!showForSession) continue;
      final frame = sketchFrameOf(cs);
      for (final r in app.sessionRegions(cs)) {
        final selected = sess.sketchName == cs.model.name &&
            sess.hasProfileAt(regionAnchor(r));
        final hovered = hoverRegion == r.outer.id;
        if (!selected && !hovered) continue;
        final path = Path()..fillType = PathFillType.evenOdd;
        void loopPath(List<Offset> pts) {
          for (var i = 0; i < pts.length; i++) {
            final s = cam.project(frame.toWorld(pts[i]));
            i == 0 ? path.moveTo(s.dx, s.dy) : path.lineTo(s.dx, s.dy);
          }
          path.close();
        }

        loopPath(r.outer.pts);
        for (final h in r.holes) {
          loopPath(h.pts);
        }
        canvas.drawPath(
            path, Paint()..color = T.accent.withOpacity(selected ? 0.38 : 0.16));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected ? 1.6 : 1
              ..color = selected ? T.hover : T.accent.withOpacity(0.7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

// ---------------------------------------------------------------------------
// The ViewCube: the cube itself, Home, the face-view arrows, and the menu that
// redefines which way is front.
//
// M275 — the geometry moved to view_cube.dart, pure and shared, because the
// region under the pointer, the region that lights up and the direction a tap
// sends the camera are three answers to one question. See that file's header
// for the pan/roll mismatch that made the highlight so unreliable.
// ---------------------------------------------------------------------------

/// The ViewCube, the Home button, the face-view nav arrows and the roll pair.
///
/// PUBLIC since M240: the assembly viewport shows the same cube over the same
/// [PartCamera]. It knows nothing about a part — it turns a camera — so
/// sharing it is not a coupling, and a second copy would be a second place for
/// "snap to TOP" to drift.
///
/// M275 — [orient] and [onOrient] are how a document redefines its front. Both
/// optional: a caller that does not offer the command passes neither and gets
/// the cube it always had.
class ViewCube extends StatefulWidget {
  final PartCamera camera;
  final VoidCallback onChanged;

  /// Cube space -> world space. Identity until front is redefined.
  final Quat orient;

  /// Called with the new orientation when the user redefines front or top, or
  /// with [Quat.identity] to reset. Null hides those menu entries entirely
  /// rather than showing commands that would do nothing.
  final void Function(Quat)? onOrient;

  /// M283 — frames the model in a camera the cube is about to swing to.
  ///
  /// "when i click on a viewing direction the zoom should also animate so that
  /// the whole model is visible". The cube still knows nothing about a part or
  /// an assembly: it hands over a camera already turned to the chosen
  /// direction and the host sets the pan and zoom that fit ITS geometry into
  /// the viewport. Null keeps the old fixed framing, which is what an empty
  /// document gets.
  final void Function(PartCamera)? fit;

  const ViewCube({
    super.key,
    required this.camera,
    required this.onChanged,
    this.orient = Quat.identity,
    this.onOrient,
    this.fit,
  });
  @override
  State<ViewCube> createState() => _ViewCubeState();
}

/// The whole control's box. The cube is 84 inside it, with room above-left for
/// Home and a ring of arrows around the rest.
const double _kCubeBox = 132;
const double _kCubeSize = 84;
const double _kCubeInset = 24;

class _ViewCubeState extends State<ViewCube>
    with SingleTickerProviderStateMixin {
  CubeHit? _hit;

  // ---- M277: the view SWINGS to where you sent it ------------------------
  //
  // Snapping the camera in one frame is disorienting for the reason M88 gives
  // about entering a sketch: the model appears at an unrelated orientation and
  // you lose track of which side you were looking at. A quarter turn is the
  // case where that matters most — front and back of a symmetric part are the
  // same picture, and only the motion between them says which you are on.
  //
  // Every command here goes through it: the faces, the edges and corners, the
  // step arrows, the roll pair and Home. A control where two of six things
  // animate is worse than one where none of them do.
  AnimationController? _anim;
  PartCamera? _from, _to;

  static const _swing = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _swing)
      ..addListener(_tick)
      ..addStatusListener((st) {
        if (st != AnimationStatus.completed) return;
        // Land EXACTLY on the target rather than on the last interpolated
        // step: a face view is a face view to a thousandth of a radian, and
        // _faceView (which decides whether the arrows exist at all) tests for
        // one.
        final to = _to;
        if (to != null) widget.camera.setFrom(to);
        _from = null;
        _to = null;
        widget.onChanged();
      });
  }

  @override
  void dispose() {
    _anim?.dispose();
    super.dispose();
  }

  void _tick() {
    final a = _anim, from = _from, to = _to;
    if (a == null || from == null || to == null) return;
    widget.camera
        .setFrom(PartCamera.lerp(from, to, Curves.easeInOutCubic.transform(a.value)));
    widget.onChanged();
  }

  /// Runs [mutate] on a COPY and swings the live camera onto the result.
  ///
  /// The copy is what makes an interrupted swing behave: a second tap starts
  /// from whatever is on screen at that instant — which is the live camera,
  /// because the tick writes into it — rather than from where the first swing
  /// began.
  void _animateTo(void Function(PartCamera) mutate) {
    final target = widget.camera.copy();
    mutate(target);
    final a = _anim;
    if (a == null) {
      widget.camera.setFrom(target);
      widget.onChanged();
      return;
    }
    _from = widget.camera.copy();
    _to = target;
    a
      ..reset()
      ..forward();
  }

  bool get _faceView {
    final d = widget.camera.dir;
    return [d.x.abs(), d.y.abs(), d.z.abs()].reduce((a, b) => a > b ? a : b) >
        0.999;
  }

  Offset _local(Offset inBox) =>
      inBox - const Offset(_kCubeInset, _kCubeInset);

  void _pick(Offset inBox) {
    final r = cubePick(widget.camera, _local(inBox), _kCubeSize,
        orient: widget.orient);
    if (r == null && _hit == null) return;
    setState(() => _hit = r);
  }

  void _clear() {
    if (_hit == null) return;
    setState(() => _hit = null);
  }

  /// M283 — pan and zoom so the whole model is in frame, once the camera has
  /// been turned. The swing then animates the framing along with the
  /// orientation for free: [PartCamera.lerp] interpolates ox, oy and halfH
  /// too, the last one geometrically, so the zoom glides rather than steps.
  void _frame(PartCamera c) {
    final fit = widget.fit;
    if (fit != null) {
      fit(c);
      return;
    }
    // No geometry to frame (an empty document, or a host that offers no fit):
    // centred, at the same fixed height Home has always used.
    c.ox = 0;
    c.oy = 0;
    c.halfH = 27;
  }

  void _snapTo(Vec3 d) => _animateTo((c) {
        // M90 — snapping to top/bottom is exact now; the clamp that kept it a
        // thousandth of a radian short is gone with the trackball.
        if (d.y.abs() < 0.999) c.az = math.atan2(d.x, d.z);
        c.setBasis(d, PartCamera.rightFor(c.az));
        _frame(c);
      });

  /// A quarter turn about the VIEW DIRECTION — Inventor's curved arrows.
  ///
  /// Not orbitScreen: that turns the camera to look somewhere else, and this
  /// must keep looking at exactly the same thing and only change which way is
  /// up. Rolling the right vector about dir is the whole of it.
  void _roll(double sign) => _animateTo((c) =>
      c.setBasis(c.dir, rotateAboutAxis(c.right, c.dir, sign * math.pi / 2)));

  void _step(String key) {
    // M90 — these step arrows used to clamp pol away from the poles, which put
    // the limit straight back after the drag was freed. Going through the same
    // trackball rotation keeps them consistent with dragging, and a quarter
    // turn up from the top now carries on over instead of sticking.
    const q = math.pi / 2;
    _animateTo((c) {
      switch (key) {
        case 'up':
          c.orbitScreen(0, q);
          break;
        case 'down':
          c.orbitScreen(0, -q);
          break;
        case 'left':
          c.orbitScreen(-q, 0);
          break;
        default:
          c.orbitScreen(q, 0);
      }
      _frame(c);
    });
  }

  /// The long-press menu: Inventor puts "Set Current View as Front" on the
  /// ViewCube's own context menu, and so does this.
  Future<void> _menu(Offset globalPos) async {
    final on = widget.onOrient;
    if (on == null) return;
    final t = L.of(context);
    final anchor = Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1);
    final items = [
      NativeMenuItem(id: 'front', title: t.cubeSetFront, symbol: 'cube'),
      NativeMenuItem(id: 'top', title: t.cubeSetTop, symbol: 'cube'),
      if (!widget.orient.isIdentity)
        NativeMenuItem(
            id: 'reset', title: t.cubeResetFront, symbol: 'arrow.uturn.left'),
    ];
    String? pick;
    if (NativeMenu.isSupported) {
      pick = await NativeMenu.menu(
          items: items, anchor: anchor, cancelLabel: t.cancel);
    } else if (mounted) {
      pick = await showMenu<String>(
        context: context,
        color: T.fly,
        position: RelativeRect.fromLTRB(
            anchor.left, anchor.top, anchor.right, anchor.bottom),
        items: [
          for (final it in items)
            PopupMenuItem(
                value: it.id,
                height: 40,
                child: Text(it.title, style: ts(12.5, T.text))),
        ],
      );
    }
    if (pick == null) return;
    switch (pick) {
      case 'front':
        on(cubeOrientFront(widget.camera));
        break;
      case 'top':
        on(cubeOrientTop(widget.camera));
        break;
      case 'reset':
        on(Quat.identity);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.camera;
    final t = L.of(context);
    return SizedBox(
      width: _kCubeBox,
      height: _kCubeBox,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          top: 0,
          left: 0,
          child: GestureDetector(
            onTap: () => _animateTo((cam) {
              cam.home();
              // M283 — and Home frames the model too. A home view that leaves
              // the part off screen is the same complaint as a front view that
              // does.
              _frame(cam);
            }),
            child: Tooltip(
              message: t.menuHomeView,
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: iconWidget(homeTabIcon)),
            ),
          ),
        ),
        // The cube. MouseRegion for a trackpad or a hovering Pencil, and a
        // Listener for a FINGER — which never hovers, so without the pointer
        // events a touch user only ever saw the highlight they were already
        // committed to.
        Positioned.fill(
          child: MouseRegion(
            onHover: (e) => _pick(e.localPosition),
            onExit: (_) => _clear(),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _pick(e.localPosition),
              onPointerMove: (e) => _pick(e.localPosition),
              onPointerCancel: (_) => _clear(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (d) {
                  final r = cubePick(c, _local(d.localPosition), _kCubeSize,
                      orient: widget.orient);
                  _clear();
                  if (r != null) _snapTo(r.dir);
                },
                onTapCancel: _clear,
                onLongPressStart: (d) {
                  _clear();
                  _menu(d.globalPosition);
                },
                child: CustomPaint(
                  painter: _CubePainter(c, _hit, widget.orient),
                  size: const Size(_kCubeBox, _kCubeBox),
                ),
              ),
            ),
          ),
        ),
        // M275 — the face-view controls, and only in a face view: they express
        // "a quarter turn from here", which needs a here to turn from.
        if (_faceView) ..._navArrows(t),
      ]),
    );
  }

  List<Widget> _navArrows(AppL10n t) {
    const gap = 3.0;
    Widget step(String key, double left, double top, double turns) => Positioned(
          left: left,
          top: top,
          child: Semantics(
            button: true,
            label: t.cubeStep,
            child: GestureDetector(
              onTap: () => _step(key),
              behavior: HitTestBehavior.opaque,
              child: RotatedBox(
                quarterTurns: (turns * 4).round(),
                child: const _StepArrow(),
              ),
            ),
          ),
        );
    const a = _StepArrow.size;
    const mid = _kCubeInset + _kCubeSize / 2 - a / 2;
    const near = _kCubeInset - a - gap;
    const far = _kCubeInset + _kCubeSize + gap;
    return [
      step('up', mid, near, 0),
      step('down', mid, far, 0.5),
      step('left', near, mid, 0.75),
      step('right', far, mid, 0.25),
      // The roll pair, above the cube's top-right corner, where Inventor puts
      // it. Two arrows and not one: which way a single one would turn is a
      // guess the user has to make and then undo.
      Positioned(
        left: _kCubeInset + _kCubeSize - 6,
        top: 0,
        child: Row(children: [
          Semantics(
            button: true,
            label: t.cubeRollLeft,
            child: GestureDetector(
              onTap: () => _roll(1),
              behavior: HitTestBehavior.opaque,
              child: const _RollArrow(clockwise: false),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: t.cubeRollRight,
            child: GestureDetector(
              onTap: () => _roll(-1),
              behavior: HitTestBehavior.opaque,
              child: const _RollArrow(clockwise: true),
            ),
          ),
        ]),
      ),
    ];
  }
}

/// One of the four triangles that step a quarter turn to the next face.
class _StepArrow extends StatelessWidget {
  const _StepArrow();
  static const double size = 15;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(size, size), painter: _StepArrowPainter());
}

class _StepArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width / 2, 1)
      ..lineTo(s.width - 1.5, s.height - 2)
      ..lineTo(1.5, s.height - 2)
      ..close();
    canvas.drawPath(p, Paint()..color = T.cubeFace);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round
          ..color = T.cubeEdge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// One of the two curved arrows that roll the view a quarter turn.
class _RollArrow extends StatelessWidget {
  final bool clockwise;
  const _RollArrow({required this.clockwise});
  static const double size = 20;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(size, size),
      painter: _RollArrowPainter(clockwise: clockwise));
}

class _RollArrowPainter extends CustomPainter {
  final bool clockwise;
  _RollArrowPainter({required this.clockwise});

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width * 0.34;
    final c = Offset(s.width / 2, s.height * 0.58);
    // Three quarters of a circle, so the gap says which way it is open and the
    // head says which way it goes.
    final rect = Rect.fromCircle(center: c, radius: r);
    final start = clockwise ? -math.pi * 0.85 : -math.pi * 0.15;
    final sweep = (clockwise ? 1 : -1) * math.pi * 1.25;
    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = T.cubeEdge);
    // The head, at the far end of the sweep and tangent to it.
    final end = start + sweep;
    final tip = c + Offset(math.cos(end) * r, math.sin(end) * r);
    final tangent = clockwise
        ? Offset(-math.sin(end), math.cos(end))
        : Offset(math.sin(end), -math.cos(end));
    final n = Offset(-tangent.dy, tangent.dx);
    canvas.drawPath(
        Path()
          ..addPolygon([
            tip + tangent * 4.5,
            tip - tangent * 2 + n * 3.4,
            tip - tangent * 2 - n * 3.4,
          ], true),
        Paint()..color = T.cubeEdge);
  }

  @override
  bool shouldRepaint(covariant _RollArrowPainter old) =>
      old.clockwise != clockwise;
}

class _CubePainter extends CustomPainter {
  final PartCamera camera;
  final CubeHit? hit;
  final Quat orient;
  _CubePainter(this.camera, this.hit, this.orient);

  static const Map<String, int> _order = {
    'RIGHT': 0,
    'LEFT': 0,
    'TOP': 1,
    'BOTTOM': 2,
    'FRONT': 0,
    'BACK': 0,
  };

  @override
  void paint(Canvas canvas, Size size) {
    // The cube sits inset in a larger box that also holds Home and the arrows,
    // so everything below is drawn in the cube's own square.
    canvas.save();
    canvas.translate(_kCubeInset, _kCubeInset);
    final box = const Size(_kCubeSize, _kCubeSize);
    // ONE camera for the picture and the pick — see view_cube.dart.
    final cam = Cam3(cubeCamera(camera), box);
    final tint = [T.cubeFace, T.cubeFaceTop, T.cubeFaceDim];

    Offset pr(Vec3 v) => cam.project(orient.rotate(v));

    final faces = <(double, String, Vec3, List<Offset>)>[];
    for (final (label, n) in kCubeFaces) {
      // Back faces of the cube. The normal has to be rotated first: after
      // front is redefined, cube space and world space are different rooms.
      if (orient.rotate(n).dot(cam.dir) <= 0.02) continue;
      final (u, v) = faceBasis(n);
      final centre = n * 0.5;
      final quad = [
        pr(centre + u * -0.5 + v * -0.5),
        pr(centre + u * 0.5 + v * -0.5),
        pr(centre + u * 0.5 + v * 0.5),
        pr(centre + u * -0.5 + v * 0.5),
      ];
      faces.add((cam.depth(orient.rotate(centre)), label, n, quad));
    }
    faces.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, label, n, quad) in faces) {
      final path = Path()..addPolygon(quad, true);
      canvas.drawPath(path, Paint()..color = tint[_order[label]!]);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = T.cubeEdge);
      _paintHighlight(canvas, cam, n, pr);
      _paintLabel(canvas, cam, box, label, n, pr);
    }
    canvas.restore();
  }

  /// M275 — the highlight is the picked CELL, not the whole face.
  ///
  /// This is the visible half of the bug report. An edge pick used to light
  /// both of its faces end to end, so hovering anywhere near a boundary flooded
  /// half the cube and there was no way to tell an edge from the face beside
  /// it. A cell is a strip or a corner square, and it appears on each face the
  /// pick touches — which is exactly what makes an edge read as one strip
  /// folded over two faces.
  void _paintHighlight(
      Canvas canvas, Cam3 cam, Vec3 n, Offset Function(Vec3) pr) {
    final h = hit;
    if (h == null) return;
    final cell = cubeCell(h, n);
    if (cell == null) return;
    final (cu, cv) = cell;
    final (u0, u1, v0, v1) = cubeCellRect(cu, cv);
    final (u, v) = faceBasis(n);
    final centre = n * 0.5;
    final quad = [
      pr(centre + u * u0 + v * v0),
      pr(centre + u * u1 + v * v0),
      pr(centre + u * u1 + v * v1),
      pr(centre + u * u0 + v * v1),
    ];
    final path = Path()..addPolygon(quad, true);
    canvas.drawPath(path, Paint()..color = T.accent.withValues(alpha: 0.45));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = T.accent);
  }

  void _paintLabel(Canvas canvas, Cam3 cam, Size size, String label, Vec3 n,
      Offset Function(Vec3) pr) {
    // Label painted ON the face like a decal. Its basis is the face's FIXED
    // (u, v) axes, so the text turns, tilts and foreshortens exactly with the
    // face it belongs to. The old version rotated by the angle of ONE quad
    // edge; which edge that was changed as the cube turned, so the text
    // re-oriented on screen and could come out upside down (TOP read "dOT").
    final (fu, fv) = faceBasis(n);
    final fc = n * 0.5;
    final c0 = pr(fc);
    // Screen delta of a unit step along each face axis, normalised by the
    // head-on projected length: the glyphs keep their size when a face looks
    // straight at you and only compress as it turns away.
    final s0 = size.height / 2 / kCubeHalfH;
    final ex = (pr(fc + fu * 0.5) - pr(fc - fu * 0.5)) / s0;
    final ey = (pr(fc + fv * 0.5) - pr(fc - fv * 0.5)) / s0;
    final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: T.cubeText)),
        textDirection: TextDirection.ltr)
      ..layout();
    // Column-major affine: text +x follows u, text +y (down on screen)
    // follows -v. (u, v, n) is right-handed, so nothing ever mirrors.
    final m = Float64List(16);
    m[0] = ex.dx;
    m[1] = ex.dy;
    m[4] = -ey.dx;
    m[5] = -ey.dy;
    m[10] = 1;
    m[12] = c0.dx;
    m[13] = c0.dy;
    m[15] = 1;
    canvas.save();
    canvas.transform(m);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => true;
}

/// The bottom-left coordinate triad. Public for the same reason [ViewCube] is.
class TriadPainter extends CustomPainter {
  final PartCamera camera;
  TriadPainter(this.camera);

  @override
  void paint(Canvas canvas, Size size) {
    final cam =
        Cam3(PartCamera(az: camera.az, pol: camera.pol, halfH: 1.5), size);
    void arrow(Vec3 d, Color col, String label) {
      final a = cam.project(Vec3.zero), b = cam.project(d);
      final p = Paint()
        ..color = col
        ..strokeWidth = 2;
      canvas.drawLine(a, b, p);
      final dir = (b - a);
      if (dir.distance > 1e-6) {
        final u = dir / dir.distance;
        final n = Offset(-u.dy, u.dx);
        canvas.drawPath(
            Path()
              ..addPolygon([b, b - u * 9 + n * 4.5, b - u * 9 - n * 4.5], true),
            Paint()..color = col);
      }
      final lp = cam.project(d * 1.28);
      final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: col)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
    }

    arrow(const Vec3(1, 0, 0), T.err, 'X');
    arrow(const Vec3(0, 1, 0), T.axisY, 'Y');
    arrow(const Vec3(0, 0, 1), T.axisZ, 'Z');
  }

  @override
  bool shouldRepaint(covariant TriadPainter old) => true;
}
