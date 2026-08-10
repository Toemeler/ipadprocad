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
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:reality_view/reality_view.dart';

import '../app_state.dart';
import '../log.dart';
import '../part_pick.dart';
import '../pick_math.dart';
import '../perf.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../part_model.dart';
import '../part_render.dart';
import '../reality_scene.dart';
import '../svg_icons.dart' show homeTabIcon;
import '../theme.dart';
import 'package:native_menu/native_menu.dart' show GlassBrowser;
import 'bottom_tabbar.dart';
import 'native_browser_host.dart';
import 'ribbon_chrome.dart';

// M83: the origin planes/axes are no longer a fixed 20 mm square — they frame
// the part (originPlaneRect / originAxisSpan in part_model.dart). This constant
// survives only as the empty-part default, which lives there as
// kOriginExtentDefault; nothing in this file should size geometry with it.
const _orange = Color(0xFFEA9E5C);
const _orangeEdge = Color(0xE6F0A868);
const _green = Color(0xFF39D65B);
const _greenBright = Color(0xFF8DFFA0);
// Cam3 (orthographic turntable camera) and paintPartSolids live in
// ../part_render.dart now — shared verbatim with off-screen thumbnail
// rendering (AppState._writePartPreview). kSolidBase/kSolidEdge moved with
// them.

class Viewport3D extends StatefulWidget {
  final AppState app;
  const Viewport3D({super.key, required this.app});
  @override
  State<Viewport3D> createState() => _Viewport3DState();
}

class _Viewport3DState extends State<Viewport3D>
    with SingleTickerProviderStateMixin {
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
    _camAnim?.dispose();
    _refineTimer?.cancel();
    // The controller itself is owned (and disposed) by the RealityView widget's
    // own State; just drop our reference so late pushes are no-ops.
    _reality = null;
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
    if (k == LogicalKeyboardKey.escape) {
      if (widget.app.pickPlane ||
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
  // MMB drag (desktop): pan with shift, orbit without
  bool _mmb = false, _mmbPan = false;
  Offset _mmbLast = Offset.zero;
  double _scaleStartH = 27;

  // Adaptive tessellation: re-mesh solids to the current screen resolution so
  // curved edges stay smooth at any zoom. Debounced so a continuous pinch
  // coalesces into a single kernel re-mesh once the gesture settles.
  Timer? _refineTimer;

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
  String? _pickSketchCurve(Cam3 cam, Offset px) {
    final p = part;
    if (p == null) return null;
    final sess = widget.app.extrudeSession;
    const tolPx = 9.0;
    const tol2 = tolPx * tolPx;
    final best = PickBest<String>();
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
            best.offer(sketchKey(cs.model.name, gi), cam.depth(hit),
                math.sqrt(d2));
          }
          prevW = w;
          prev = cur;
        }
      }
    }
    return best.value;
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
    if (p == null) return const ColoredBox(color: T.viewport);
    return LayoutBuilder(builder: (context, bc) {
      final size = Size(bc.maxWidth, bc.maxHeight);
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
                          placeholder: const ColoredBox(color: T.viewport),
                          onCreated: (c) {
                            _reality = c;
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
              // M174 — the Plane command is armed: pointer down on a plane or
              // a face starts DRAGGING a new one off it. Nothing is created
              // until you let go, so a mis-grab costs nothing, and the offset
              // is set by the gesture instead of defaulting to 10 mm.
              if (app.workPlaneArm == WorkPlaneKind.offset) {
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
                  _wpDrag = w;
                  _wpDown = e.localPosition;
                  _wpMoved = false;
                  app.selectWorkPlane(w);
                }
              }
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons == kMiddleMouseButton) {
                _mmb = true;
                _mmbPan = HardwareKeyboard.instance.isShiftPressed;
                _mmbLast = e.localPosition;
              }
            },
            onPointerMove: (e) {
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
              if (_mmb) {
                final d = e.localPosition - _mmbLast;
                _mmbLast = e.localPosition;
                setState(() {
                  if (_mmbPan) {
                    final wpp = (2 * p.camera.halfH) / size.height;
                    p.camera.ox -= d.dx * wpp;
                    p.camera.oy += d.dy * wpp;
                  } else {
                    _orbit(p, d);
                  }
                });
              }
            },
            onPointerUp: (_) {
              _mmb = false;
              if (_wpNewBase != null) {
                _wpNewBase = null;
                _wpMoved = false;
                app.commitWorkPlaneCreate();
                return;
              }
              if (_wpDrag != null) {
                if (_wpMoved) {
                  app.endWorkPlaneDrag();
                } else {
                  // A TAP, not a drag: select and open the field, so the value
                  // is editable without hunting for a menu.
                  final w = _wpDrag!;
                  if (w.offsetEditable) app.workPlaneOffsetEditing = true;
                }
                _wpDrag = null;
                _wpMoved = false;
              }
            },
            onPointerCancel: (_) {
              _mmb = false;
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
                  final wpp = (2 * p.camera.halfH) / size.height;
                  p.camera.ox -= d.dx * wpp;
                  p.camera.oy += d.dy * wpp;
                } else {
                  _orbit(p, d);
                }
              });
            },
            onPointerPanZoomEnd: (_) => _tpActive = false,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() => _zoomAt(
                    p, cam, e.localPosition, e.scrollDelta.dy > 0 ? 1.1 : 0.9));
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
                // M170 — a tap consumed by a work plane is handled in the
                // Listener (select + open the field); running the general pick
                // as well would fight it.
                onTapUp: (d) {
                  if (_wpDrag != null) return;
                  _tap(cam, d.localPosition);
                },
                onScaleStart: (d) {
                  _scaleStartH = p.camera.halfH;
                  _mmbLast = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  // the trackpad path above already handled this gesture
                  if (_tpActive) return;
                  if (d.pointerCount >= 2) {
                    if (d.scale > 0) {
                      final f = (_scaleStartH / d.scale) / p.camera.halfH;
                      _zoomAt(p, Cam3(p.camera, size), d.localFocalPoint, f);
                    }
                    final mv = d.localFocalPoint - _mmbLast;
                    final wpp = (2 * p.camera.halfH) / size.height;
                    p.camera.ox -= mv.dx * wpp;
                    p.camera.oy += mv.dy * wpp;
                  } else if (!_mmb &&
                      _wpDrag == null &&
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
        // ViewCube + Home (top-right, BELOW the floating ribbon — M146: the
        // ribbon shares this coordinate space now, and at top: 8 the cube was
        // simply behind the glass).
        RibbonMetrics.build((_, top) => Positioned(
            top: top + 8,
            right: 10,
            child:
                _ViewCube(camera: p.camera, onChanged: () => setState(() {})))),
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
              left: w,
              // M150 — the tab bar floats over the viewport now, so bottom: 0
              // would put the triad behind it.
              bottom: BottomTabBar.floatingHeight,
              child: child!,
            ),
            child: IgnorePointer(
                child: CustomPaint(
                    painter: _TriadPainter(p.camera),
                    size: const Size(118, 118))),
          )
        else
          Positioned(
              left: 0,
              bottom: BottomTabBar.floatingHeight,
              child: IgnorePointer(
                  child: CustomPaint(
                      painter: _TriadPainter(p.camera),
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
                  color: const Color(0xE6402F1F),
                  border: Border.all(color: const Color(0xFF8A6A3A)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child:
                    Text(app.message!, style: ts(12, const Color(0xFFF2D6A2))),
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
    p.camera.orbitScreen(-d.dx * 0.01, -d.dy * 0.01);
  }

  void _zoomAt(PartModel p, Cam3 cam, Offset px, double factor) {
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
    if (app.pickPlane && region == null) {
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
  String? _hitOrigin(Cam3 cam, Offset px, PartModel p,
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
        if (n.length < 1e-12 || n.normalized().dot(cam.dir) <= 0) continue;
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
        if (n.length < 1e-12 || n.normalized().dot(cam.dir) <= 0) continue;
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
          app.toast('That edge is a spline — it defines no single direction.');
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
              app.toast('A rotation axis must be a straight line or an axis.');
              return;
            }
            app.patternPathPicked(path, first: s.active == PatternField.dirA);
            return;
          }
        }
        app.toast('Pick a straight or circular edge, a sketch curve, or an '
            'origin axis.');
      case PatternField.startA:
      case PatternField.startB:
        final first = s.active == PatternField.startA;
        final sel = first ? s.pathA : s.pathB;
        if (sel == null) {
          app.toast('Pick the curve for this direction first.');
          return;
        }
        final cs = p.sketchByName(sel.sketchName);
        if (cs == null) {
          app.toast('That curve is no longer available.');
          return;
        }
        // The tap is turned into a point ON THE CURVE'S PLANE, which is where
        // the curve is; the arc length nearest that point is the start.
        final frame = sketchFrameOf(cs);
        final w = cam.rayOnPlane(px, frame.n, frame.origin);
        if (w == null) {
          app.toast('Tap on the curve.');
          return;
        }
        app.patternStartPicked(w, first: first);
      case PatternField.orientFace:
        final face = _pickSolidFace(cam, px, planarOnly: false);
        if (face == null) {
          app.toast('Tap the face the occurrences should follow.');
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
        app.toast('Pick a planar face, a work plane, or an origin plane.');
      case PatternField.pointSketch:
      case PatternField.basePoint:
        final hit = _sketchPointAt(cam, px, p);
        if (hit == null) {
          app.toast('Pick a sketch POINT — the occurrences go where the '
              'points are.');
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
          app.toast('Pick the solid body to pattern.');
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
          app.toast('Tap a face of the feature to pattern, or pick it in the '
              'browser.');
          return;
        }
        final owner = app.featureOfFace(face.$1, face.$2);
        if (owner == null) {
          app.toast('That face cannot be traced back to one feature — pick '
              'the feature in the browser.');
          return;
        }
        if (!app.patternToggleFeature(owner)) return;
        app.toast(app.patternHasFeature(owner.name)
            ? 'Added ${owner.name}.'
            : 'Removed ${owner.name}.');
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
    // A hovered sketch curve is selectable in plain 3D. Shift/ctrl extends the
    // set, a plain tap replaces it, a tap on empty space clears it.
    if (!app.pickPlane && app.extrudeSession == null) {
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
          final ip = interiorPointOf(r.outer);
          app.toggleLoftSection(
              cs.model.name, ProfileSel(ip.dx, ip.dy, r.outer.area));
          return;
        }
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
    final occ = occSolids.isEmpty ? null : solidOccluder(occSolids, cam);

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
      paintPartSolids(canvas, cam, solids,
          previewSolid: sess?.preview,
          highlightSolid: hoverFace?.$1,
          highlightFace: hoverFace?.$2 ?? -1,
          accentSolid: accentSolid,
          accentEdges: accent);
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
      final visible =
          part.vis[key] == true || (app.pickPlane && !part.hasSolid);
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
        // corner rings + centre dot + name label lying on the plane
        for (final c in corners) {
          canvas.drawCircle(
              cam.project(c),
              6,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = _greenBright);
        }
        canvas.drawCircle(cam.project(Vec3.zero), 4,
            Paint()..color = const Color(0xFFFFE07A));
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
          canvas.drawCircle(
              p,
              6,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = _greenBright);
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
      ..color = const Color(0xFFC4C9CE);
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
  }

  void _paintRegions(
      Canvas canvas, Cam3 cam, ChildSketch cs, ExtrudeSession sess) {
    final frame = sketchFrameOf(cs);
    for (final r in app.sessionRegions(cs)) {
      final selected = sess.sketchName == cs.model.name &&
          sess.hasProfileAt(interiorPointOf(r.outer));
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
          path, Paint()..color = T.blue.withOpacity(selected ? 0.38 : 0.16));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 1.6 : 1
            ..color = selected ? T.hover : T.blue.withOpacity(0.7));
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
        canvas.drawCircle(cam.project(c), 6, ring);
      }
      canvas.drawCircle(
          cam.project(Vec3.zero), 4, Paint()..color = const Color(0xFFFFE07A));
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
        canvas.drawCircle(p, 6, ring);
      }
    }

    // ---- hovered centre point: highlight ring (the dot itself is a
    // RealityKit entity, so it stays depth-tested) ----
    if (part.vis['cp'] == true && hover == 'cp') {
      canvas.drawCircle(cam.project(Vec3.zero), 9, ring);
    }

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
            sess.hasProfileAt(interiorPointOf(r.outer));
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
            path, Paint()..color = T.blue.withOpacity(selected ? 0.38 : 0.16));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected ? 1.6 : 1
              ..color = selected ? T.hover : T.blue.withOpacity(0.7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

// ---------------------------------------------------------------------------
// ViewCube (84x84 with a Home icon above-left) + face-view nav arrows
// ---------------------------------------------------------------------------
const _cubeFaces = <(String, Vec3)>[
  ('RIGHT', Vec3(1, 0, 0)),
  ('LEFT', Vec3(-1, 0, 0)),
  ('TOP', Vec3(0, 1, 0)),
  ('BOTTOM', Vec3(0, -1, 0)),
  ('FRONT', Vec3(0, 0, 1)),
  ('BACK', Vec3(0, 0, -1)),
];

(Vec3, Vec3) faceBasis(Vec3 n) {
  final up = n.y.abs() > 0.9 ? const Vec3(0, 0, 1) : const Vec3(0, 1, 0);
  final u = up.cross(n).normalized();
  final v = n.cross(u).normalized();
  return (u, v);
}

/// Snap direction for a pointer on the cube: the face normal plus the
/// edge/corner components when the hit sits in the outer 22% band.
(Vec3, Set<String>)? cubePick(PartCamera c, Offset px, double sizePx) {
  final cam = Cam3(c, Size(sizePx, sizePx));
  // ray/unit-cube (slab method), camera-plane origin scaled to half 0.86
  final o0 = cam.unprojectOnCamPlane(px);
  final o = o0 * (0.86 / cam.halfH); // cube canvas uses its own half-height
  final rd = cam.dir * -1;
  var tmin = -1e9, tmax = 1e9;
  Vec3 nEnter = Vec3.zero;
  for (final ax in [
    (const Vec3(1, 0, 0), o.x, rd.x),
    (const Vec3(0, 1, 0), o.y, rd.y),
    (const Vec3(0, 0, 1), o.z, rd.z)
  ]) {
    final (n, oc, dc) = ax;
    if (dc.abs() < 1e-9) {
      if (oc.abs() > 0.5) return null;
      continue;
    }
    var t1 = (-0.5 - oc) / dc, t2 = (0.5 - oc) / dc;
    var nn = n * (dc > 0 ? -1.0 : 1.0);
    if (t1 > t2) {
      final t = t1;
      t1 = t2;
      t2 = t;
      nn = nn * -1;
    }
    if (t1 > tmin) {
      tmin = t1;
      nEnter = nn;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  final hit = o + rd * tmin;
  final (u, v) = faceBasis(nEnter);
  final du = hit.dot(u), dv = hit.dot(v);
  final cu = du < -0.28 ? -1.0 : (du > 0.28 ? 1.0 : 0.0);
  final cv = dv < -0.28 ? -1.0 : (dv > 0.28 ? 1.0 : 0.0);
  final lit = <String>{_nkey(nEnter)};
  if (cu != 0) lit.add(_nkey(u * cu));
  if (cv != 0) lit.add(_nkey(v * cv));
  final dir = (nEnter + u * cu + v * cv).normalized();
  return (dir, lit);
}

String _nkey(Vec3 v) => '${v.x.round()},${v.y.round()},${v.z.round()}';

class _ViewCube extends StatefulWidget {
  final PartCamera camera;
  final VoidCallback onChanged;
  const _ViewCube({required this.camera, required this.onChanged});
  @override
  State<_ViewCube> createState() => _ViewCubeState();
}

class _ViewCubeState extends State<_ViewCube> {
  Set<String> _lit = const {};

  bool get _faceView {
    final d = widget.camera.dir;
    return [d.x.abs(), d.y.abs(), d.z.abs()].reduce((a, b) => a > b ? a : b) >
        0.999;
  }

  void _snapTo(Vec3 d) {
    final c = widget.camera;
    // M90 — snapping to top/bottom is exact now; the clamp that kept it a
    // thousandth of a radian short is gone with the trackball.
    if (d.y.abs() < 0.999) c.az = math.atan2(d.x, d.z);
    c.setBasis(d, PartCamera.rightFor(c.az));
    c.ox = 0;
    c.oy = 0;
    c.halfH = 27;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.camera;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(children: [
        Positioned(
          top: 0,
          left: 14,
          child: GestureDetector(
            onTap: () {
              c.home();
              widget.onChanged();
            },
            child: Tooltip(
              message: 'Home view',
              child: SizedBox(
                  width: 22, height: 22, child: SvgPicture.string(homeTabIcon)),
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          child: MouseRegion(
            onHover: (e) {
              final r = cubePick(c, e.localPosition, 84);
              setState(() => _lit = r?.$2 ?? const {});
            },
            onExit: (_) => setState(() => _lit = const {}),
            child: GestureDetector(
              onTapUp: (d) {
                final r = cubePick(c, d.localPosition, 84);
                if (r != null) _snapTo(r.$1);
              },
              child: CustomPaint(
                  painter: _CubePainter(c, _lit), size: const Size(84, 84)),
            ),
          ),
        ),
        // face-view navigation arrows (rotate 90° to the neighbouring face)
        if (_faceView) ..._navArrows(c),
      ]),
    );
  }

  List<Widget> _navArrows(PartCamera c) {
    Widget arrow(String key, Alignment a, double turns) => Align(
          alignment: a,
          child: GestureDetector(
            onTap: () {
              // M90 — these step arrows used to clamp pol away from the
              // poles, which put the limit straight back after the drag was
              // freed. Going through the same trackball rotation keeps them
              // consistent with dragging, and a quarter turn up from the top
              // now carries on over instead of sticking.
              const q = math.pi / 2;
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
              c.ox = 0;
              c.oy = 0;
              c.halfH = 27;
              widget.onChanged();
            },
            child: RotatedBox(
              quarterTurns: (turns * 4).round(),
              child: const Icon(Icons.arrow_drop_up,
                  size: 22, color: Color(0xFFC5CACE)),
            ),
          ),
        );
    return [
      arrow('up', Alignment.topCenter, 0),
      arrow('down', Alignment.bottomCenter, 0.5),
      arrow('left', Alignment.centerLeft, 0.75),
      arrow('right', Alignment.centerRight, 0.25),
    ];
  }
}

class _CubePainter extends CustomPainter {
  final PartCamera camera;
  final Set<String> lit;
  _CubePainter(this.camera, this.lit);

  @override
  void paint(Canvas canvas, Size size) {
    final cam =
        Cam3(PartCamera(az: camera.az, pol: camera.pol, halfH: 0.86), size);
    const tint = {
      'RIGHT': Color(0xFFDFE3E7),
      'LEFT': Color(0xFFDFE3E7),
      'TOP': Color(0xFFFFFFFF),
      'BOTTOM': Color(0xFFC7CCD1),
      'FRONT': Color(0xFFEEF1F3),
      'BACK': Color(0xFFEEF1F3),
    };
    final faces = <(double, String, Vec3, List<Offset>)>[];
    for (final (label, n) in _cubeFaces) {
      if (n.dot(cam.dir) <= 0.02) continue; // back faces of the cube
      final (u, v) = faceBasis(n);
      final centre = n * 0.5;
      final quad = [
        cam.project(centre + u * -0.5 + v * -0.5),
        cam.project(centre + u * 0.5 + v * -0.5),
        cam.project(centre + u * 0.5 + v * 0.5),
        cam.project(centre + u * -0.5 + v * 0.5),
      ];
      faces.add((cam.depth(centre), label, n, quad));
    }
    faces.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, label, n, quad) in faces) {
      final path = Path()..addPolygon(quad, true);
      canvas.drawPath(path, Paint()..color = tint[label]!);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFAAB1B8));
      if (lit.contains(_nkey(n))) {
        canvas.drawPath(path, Paint()..color = const Color(0x8C7EC0F0));
      }
      // Label painted ON the face like a decal. Its basis is the face's FIXED
      // (u, v) axes, so the text turns, tilts and foreshortens exactly with the
      // face it belongs to. The old version rotated by the angle of ONE quad
      // edge; which edge that was changed as the cube turned, so the text
      // re-oriented on screen and could come out upside down (TOP read "dOT").
      final (fu, fv) = faceBasis(n);
      final fc = n * 0.5;
      final c0 = cam.project(fc);
      // Screen delta of a unit step along each face axis, normalised by the
      // head-on projected length: the glyphs keep their size when a face looks
      // straight at you and only compress as it turns away.
      final s0 = size.height / 2 / 0.86;
      final ex = (cam.project(fc + fu * 0.5) - cam.project(fc - fu * 0.5)) / s0;
      final ey = (cam.project(fc + fv * 0.5) - cam.project(fc - fv * 0.5)) / s0;
      final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF565B61))),
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
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => true;
}

class _TriadPainter extends CustomPainter {
  final PartCamera camera;
  _TriadPainter(this.camera);

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

    arrow(const Vec3(1, 0, 0), const Color(0xFFE0554F), 'X');
    arrow(const Vec3(0, 1, 0), const Color(0xFF54B24C), 'Y');
    arrow(const Vec3(0, 0, 1), const Color(0xFF3D7BD6), 'Z');
  }

  @override
  bool shouldRepaint(covariant _TriadPainter old) => true;
}
