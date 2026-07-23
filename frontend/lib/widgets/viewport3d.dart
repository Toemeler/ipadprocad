// iPadProCAD — 3D part viewport (M56), a 1:1 Flutter port of the HTML
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
import '../part_model.dart';
import '../part_render.dart';
import '../reality_scene.dart';
import '../svg_icons.dart' show homeTabIcon;
import '../theme.dart';

const double _ext = 10; // origin half-extent (20mm planes/axes), like the mock
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

class _Viewport3DState extends State<Viewport3D> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _refineTimer?.cancel();
    // The controller itself is owned (and disposed) by the RealityView widget's
    // own State; just drop our reference so late pushes are no-ops.
    _reality = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.app.pickPlane || widget.app.extrudeSession != null) {
        widget.app.escape3D();
        return true;
      }
    }
    return false;
  }

  String? _hover; // 'yz'|'xz'|'xy'|'x'|'y'|'z'|'cp'
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
  String? _pickSketchCurve(Cam3 cam, Offset px) {
    final p = part;
    if (p == null) return null;
    final sess = widget.app.extrudeSession;
    String? best;
    var bestD = 9.0; // px tolerance
    for (final cs in p.childSketches) {
      final showForSession = sess?.sketchName == cs.model.name ||
          (sess != null && sess.sketchName == null);
      if (!cs.visible && !showForSession) continue;
      final frame = sketchFrameOf(cs);
      for (var gi = 0; gi < cs.model.geometry.length; gi++) {
        final g = cs.model.geometry[gi];
        if (cs.model.hiddenLayers.contains(g.layer)) continue;
        final li = cs.model.layers.indexOf(g.layer);
        if (li >= 0 && li >= cs.model.eosAfter) continue;
        final pts = sketchCurve(g);
        if (pts.length < 2) continue;
        var prev = cam.project(frame.toWorld(pts.first));
        for (var i = 1; i < pts.length; i++) {
          final cur = cam.project(frame.toWorld(pts[i]));
          final d = _distToSeg(px, prev, cur);
          if (d < bestD) {
            bestD = d;
            best = sketchKey(cs.model.name, gi);
          }
          prev = cur;
        }
      }
    }
    return best;
  }

  /// Push the current camera (always), the scene (only when its signature
  /// changed — meshes are large) and the light overlay state to RealityKit.
  void _pushReality(AppState app, PartModel p, Size size) {
    final c = _reality;
    if (c == null) return;
    c.setCamera(cameraPayload(p.camera, size));
    final sig = sceneSignature(app, p);
    if (sig != _lastSceneSig) {
      _lastSceneSig = sig;
      for (final (id, s) in visibleSolids(app, p)) {
        logMeshConvention(id, s.mesh);
      }
      c.setScene(buildScenePayload(app, p,
          hover: _hover,
          hoverFace: _hoverFace,
          hoverSketch: _hoverSketch,
          selSketch: _selSketch,
          knownRevs: _sentRevs));
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
      final cam = Cam3(p.camera, size);
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
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons == kMiddleMouseButton) {
                _mmb = true;
                _mmbPan = HardwareKeyboard.instance.isShiftPressed;
                _mmbLast = e.localPosition;
              }
            },
            onPointerMove: (e) {
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
            onPointerUp: (_) => _mmb = false,
            onPointerCancel: (_) => _mmb = false,
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
              cursor: _hover != null || _hoverRegion != null
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onHover: (e) => _updateHover(cam, e.localPosition),
              onExit: (_) => setState(() {
                _hover = null;
                _hoverRegion = null;
                _hoverFace = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tap(cam, d.localPosition),
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
                      _dragKind == PointerDeviceKind.touch) {
                    // One finger orbits ON TOUCH only. A single trackpad or
                    // mouse drag is reserved for picking and must not move the
                    // view; orbiting there is the two-finger gesture.
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
        // ViewCube + Home (top-right)
        Positioned(
            top: 8,
            right: 10,
            child:
                _ViewCube(camera: p.camera, onChanged: () => setState(() {}))),
        // coordinate triad (bottom-left)
        Positioned(
            left: 0,
            bottom: 0,
            child: IgnorePointer(
                child: CustomPaint(
                    painter: _TriadPainter(p.camera),
                    size: const Size(118, 118)))),
        if (app.message != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
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
    p.camera.az -= d.dx * 0.01;
    p.camera.pol = (p.camera.pol - d.dy * 0.01).clamp(0.02, math.pi - 0.02);
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
    for (final f in p.features) {
      if (f.visible && f.solid != null && !f.consumedByJoin) yield f.solid!;
    }
    final prev = widget.app.extrudeSession?.preview;
    if (prev != null) yield prev;
  }

  /// True when any live solid is coarser than this viewport's screen-space
  /// target — i.e. a re-mesh would make a curve visibly smoother.
  bool _anyCoarse(Size size) {
    final p = part;
    if (p == null) return false;
    final target = viewLinearDeflection(p.camera.halfH, size.height);
    for (final s in _liveSolids()) {
      if (meshNeedsRefine(s.meshLin, target)) return true;
    }
    return false;
  }

  /// (Re)arm the debounce so a burst of zoom steps triggers exactly one
  /// kernel re-mesh after the gesture settles.
  void _armRefine(Size size) {
    if (!_anyCoarse(size)) return;
    _refineTimer?.cancel();
    _refineTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) _refineNow(size);
    });
  }

  void _refineNow(Size size) {
    final p = part;
    if (p == null) return;
    final target = viewLinearDeflection(p.camera.halfH, size.height);
    final ang = viewAngularDeflection(target);
    var changed = false;
    for (final s in _liveSolids()) {
      if (meshNeedsRefine(s.meshLin, target) && s.refine(target, ang)) {
        changed = true;
      }
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
        final w = cam.rayOnPlane(px, frame.n);
        if (w != null) {
          final sp = Offset(w.dot(frame.u), w.dot(frame.v));
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
        final a = cam.project(e.$2 * -_ext), b = cam.project(e.$2 * _ext);
        if (_distToSeg(px, a, b) < pickPx) return e.$1;
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
      final w = cam.rayOnPlane(px, f.n);
      if (w == null) continue;
      final uu = w.dot(f.u), vv = w.dot(f.v);
      if (uu.abs() <= _ext && vv.abs() <= _ext) {
        final d = cam.depth(w);
        if (d < bestD) {
          bestD = d;
          best = key;
        }
      }
    }
    return best;
  }

  /// View depth of origin plane [key] directly under the pointer, or null if
  /// the ray misses the plane's bounded extent. Lets hover/tap compare a
  /// plane against a solid face sitting in front of it.
  double? _planeDepthAt(Cam3 cam, Offset px, String key) {
    if (!kPlaneKeys.contains(key)) return null;
    final f = planeFrame(key);
    final w = cam.rayOnPlane(px, f.n);
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
  (KernelSolid, int, PlaneFrame, double)? _pickSolidFace(Cam3 cam, Offset px) {
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
          if (m.faceInfos[15 * faceId].round() != kFacePlane) continue;
        } else {
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

  void _tap(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
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
    // 1. plane pick (Start 2D Sketch): origin planes first, then any planar
    //    face of a solid (Inventor's sketch-on-face)
    if (app.pickPlane) {
      final key = _hitOrigin(cam, px, p, planesOnly: true);
      final face = _pickSolidFace(cam, px);
      // whichever surface is NEARER under the pointer wins — a solid face in
      // front of an origin plane must be the one you sketch on (Inventor).
      final planeD = key != null
          ? (_planeDepthAt(cam, px, key) ?? double.infinity)
          : double.infinity;
      final faceD = face?.$4 ?? double.infinity;
      if (face != null && faceD <= planeD + 1e-6) {
        app.facePicked(face.$3);
        return;
      }
      if (key != null && kPlaneKeys.contains(key)) {
        app.planePicked(key);
        return;
      }
      if (face != null) app.facePicked(face.$3);
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
        final w = cam.rayOnPlane(px, frame.n);
        if (w == null) continue;
        final sp = Offset(w.dot(frame.u), w.dot(frame.v));
        final r = regionAt(app.sessionRegions(cs), sp);
        if (r != null) {
          app.toggleSessionProfile(cs.model.name, r);
          return;
        }
        if (sess.sketchName == cs.model.name) break; // locked, no fallback
      }
      return;
    }
  }

  static double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
            (ab.distance * ab.distance + 1e-12))
        .clamp(0.0, 1.0);
    return (a + ab * t - p).distance;
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
            f != app.extrudeSession?.editing)
          f.solid!
    ];
    final occ = occSolids.isEmpty ? null : solidOccluder(occSolids, cam);

    // Draw the SOLIDS first, then origin planes, then sketches. This gives the
    // Inventor coplanar tie-break — a sketch or plane on the exact plane of a
    // face is not hidden by it (occlusion bias) and, being drawn later, layers
    // ON TOP: sketch > plane > geometry. Overlays genuinely BEHIND the model
    // are still removed per-pixel by [occ]. The edited feature is replaced by
    // its translucent live preview, drawn on top by paintPartSolids.
    {
      final sess = app.extrudeSession;
      final solids = [
        for (final f in part.features)
          if (f.visible &&
              f.solid != null &&
              !f.consumedByJoin &&
              f != sess?.editing)
            f.solid!
      ];
      paintPartSolids(canvas, cam, solids,
          previewSolid: sess?.preview,
          highlightSolid: hoverFace?.$1,
          highlightFace: hoverFace?.$2 ?? -1);
    }

    // ---- origin planes (fills first: everything else draws over them) ----
    for (final key in kPlaneKeys) {
      final visible =
          part.vis[key] == true || (app.pickPlane && !part.hasSolid);
      if (!visible) continue;
      final f = planeFrame(key);
      final corners = [
        f.toWorld(const Offset(-_ext, -_ext)),
        f.toWorld(const Offset(_ext, -_ext)),
        f.toWorld(const Offset(_ext, _ext)),
        f.toWorld(const Offset(-_ext, _ext)),
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
        final p0 = cam.project(f.toWorld(Offset(-_ext + 0.6, -_ext + 1.4)));
        final p1 = cam.project(f.toWorld(Offset(-_ext + 4.6, -_ext + 1.4)));
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
      final a = cam.project(e.$2 * -_ext), b = cam.project(e.$2 * _ext);
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
      final corners = [
        f.toWorld(const Offset(-_ext, -_ext)),
        f.toWorld(const Offset(_ext, -_ext)),
        f.toWorld(const Offset(_ext, _ext)),
        f.toWorld(const Offset(-_ext, _ext)),
      ];
      for (final c in corners) {
        canvas.drawCircle(cam.project(c), 6, ring);
      }
      canvas.drawCircle(
          cam.project(Vec3.zero), 4, Paint()..color = const Color(0xFFFFE07A));
      final p0 = cam.project(f.toWorld(const Offset(-_ext + 0.6, -_ext + 1.4)));
      final p1 = cam.project(f.toWorld(const Offset(-_ext + 4.6, -_ext + 1.4)));
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
      for (final p in [
        cam.project(e.$2 * -_ext),
        cam.project(e.$2 * _ext),
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
    c.pol = math.acos(d.y.clamp(-1.0, 1.0));
    if (d.y.abs() < 0.999) c.az = math.atan2(d.x, d.z);
    if (c.pol < 0.001) c.pol = 0.001;
    if (c.pol > math.pi - 0.001) c.pol = math.pi - 0.001;
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
              switch (key) {
                case 'up':
                  c.pol = (c.pol - math.pi / 2).clamp(0.001, math.pi - 0.001);
                  break;
                case 'down':
                  c.pol = (c.pol + math.pi / 2).clamp(0.001, math.pi - 0.001);
                  break;
                case 'left':
                  c.az -= math.pi / 2;
                  break;
                default:
                  c.az += math.pi / 2;
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
