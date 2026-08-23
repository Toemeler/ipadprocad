// M240 — the ASSEMBLY viewport.
//
// Deliberately the part viewport's navigation, verbatim: the same orthographic
// turntable camera (PartCamera / Cam3), the same trackball orbit, the same
// zoom-to-cursor, the same trackpad and mouse handling, the same ViewCube and
// the same triad — the last two IMPORTED from viewport3d.dart rather than
// copied, because "snap to TOP" must not be able to mean two things in one
// app. What is not shared is everything a part viewport does that an assembly
// has no idea of: plane picking, profile regions, sketch overlays, work-plane
// dragging, edge and face picking. None of it is here.
//
// WHAT IS NEW: components, and dragging them.
//
//   * A component is drawn through [paintAssemblySolids], which is
//     [paintPartSolids] under a SHIFTED CAMERA (see part_render.dart for the
//     identity that makes that exact). No mesh is copied, so a drag costs a
//     repaint and not a vertex-buffer rebuild.
//
//   * Dragging moves the component in the plane of the screen, which is what
//     Inventor's free drag does. The world delta comes straight out of the
//     camera basis, so the component tracks the finger exactly at any
//     orientation and any zoom — an orthographic projection makes that a
//     constant, not an approximation.
//
// M241 — REALITYKIT, exactly as in part mode.
//
// M240 drew the assembly with the CPU painter on device as well, because the
// scene payload addressed solids by id in one world space and had no
// per-solid placement: two occurrences of a part would have arrived as one
// solid drawn once, at the origin. The payload carries `at` now and the
// renderer puts it on the solid's holder Entity, so this viewport drives the
// same RealityView the part viewport does, over the same three calls.
//
// The CPU painter stays as the OFF-IOS renderer — the host tests and any
// desktop run go through it, exactly as they do for a part.
//
// The split between the two pushes is the thing to keep straight:
//
//   setScene    the assembly's STRUCTURE — which components exist, their
//               meshes, the origin planes sized to their extent. Fires when
//               [assemblySceneSignature] moves.
//   setOverlays WHERE each component is and what colour it is. Fires every
//               frame. This is the drag path: no mesh crosses the channel.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_menu/native_menu.dart' show GlassBrowser;
import 'package:reality_view/reality_view.dart';

import '../app_state.dart';
import '../assembly.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../part_model.dart';
import '../part_render.dart';
import '../perf.dart';
import '../reality_assembly.dart';
import '../reality_payload.dart';
import '../reality_scene.dart' show RealityPush, logMeshConvention;
import '../theme.dart';
import 'bottom_tabbar.dart';
import 'native_browser_host.dart';
import 'ribbon_chrome.dart';
import 'viewport3d.dart' show ViewCube, TriadPainter;

/// Palette reads, not constants — same rule as viewport3d.dart: a `final`
/// would freeze whichever scheme happened to be active when it was first read.
Color get _orange => T.previewFill;
Color get _orangeEdge => T.previewEdge;

class ViewportAssembly extends StatefulWidget {
  final AppState app;
  const ViewportAssembly({super.key, required this.app});
  @override
  State<ViewportAssembly> createState() => _ViewportAssemblyState();
}

class _ViewportAssemblyState extends State<ViewportAssembly> {
  AssemblyModel? get asm => widget.app.currentAssembly;

  // ---- navigation state (mirrors _Viewport3DState) ----
  bool _mmb = false, _mmbPan = false;
  Offset _mmbLast = Offset.zero;
  double _scaleStartH = 27;
  bool _tpActive = false;
  Offset _tpLastPan = Offset.zero;
  PointerDeviceKind _dragKind = PointerDeviceKind.touch;

  // ---- component drag ----
  AssemblyOccurrence? _drag;
  Offset _dragFrom = Offset.zero;
  bool _dragMoved = false;

  /// Pointers currently down. A component drag is a ONE-pointer gesture: the
  /// moment a second finger lands the gesture is a pinch or a two-finger
  /// orbit, and the component has to be let go — otherwise it travels with the
  /// focal point while the camera moves under it, and both are wrong.
  final Set<int> _down = {};

  /// The occurrence under the pointer, for the hover cursor and the hover tint.
  AssemblyOccurrence? _hover;

  // ---- RealityKit (iOS) ----
  RealityViewController? _reality;
  String? _lastSceneSig;
  Map<String, int> _sentRevs = const {};

  /// Push the camera (always), the scene (only when its signature moved) and
  /// the placements + tints (always) to RealityKit.
  ///
  /// The same shape as _Viewport3DState._pushReality, and for the same reason:
  /// meshes are large and the camera is three doubles, so they cannot travel
  /// on the same schedule.
  void _pushReality(AssemblyModel a, Size size) =>
      Perf.span('3d.push', () => _pushRealityInner(a, size));

  void _pushRealityInner(AssemblyModel a, Size size) {
    final c = _reality;
    if (c == null) return;
    c.setCamera(cameraPayload(a.camera, size));
    // The same diagnostics the part viewport records. RealityKit composites
    // outside Flutter, so it never appears in a bug bundle's screenshot and
    // Dart cannot read back what it drew — this is the last word before the
    // boundary, and without it an "the assembly is empty" report is
    // unanswerable (bug_capture.dart carries RealityPush.dump()).
    RealityPush.recordCamera('assembly on ${size.width.toInt()}x'
        '${size.height.toInt()}');
    final sig = assemblySceneSignature(a);
    if (sig != _lastSceneSig) {
      _lastSceneSig = sig;
      final pushed = <String>[];
      for (final (id, o, sol) in assemblyPieces(a)) {
        logMeshConvention(id, sol.mesh);
        pushed.add('$id @ ${o.offset.x.toStringAsFixed(2)},'
            '${o.offset.y.toStringAsFixed(2)},'
            '${o.offset.z.toStringAsFixed(2)}: '
            'tris=${sol.mesh.indices.length ~/ 3} '
            'verts=${sol.mesh.positions.length ~/ 3} '
            'rev=${identityHashCode(sol.mesh)}');
      }
      RealityPush.recordScene(sig, pushed);
      c.setScene(Perf.span(
          '3d.payload',
          () => buildAssemblyScenePayload(a,
              hoverId: _hover?.id, knownRevs: _sentRevs)));
      _sentRevs = assemblySceneRevs(a);
    }
    c.setOverlays(buildAssemblyOverlaysPayload(a, hoverId: _hover?.id));
  }

  // ---- mesh refinement -----------------------------------------------------
  //
  // M241 — the part viewport re-tessellates its solids as you zoom in, so a
  // cylinder stays round instead of keeping the facet count it was built at.
  // A component IS a part's solids, so an assembly needs the same pass or
  // zooming into one shows faceting the part viewport would have smoothed
  // away — "just like part mode" has to include this or it is not.
  //
  // Every occurrence holds its OWN PartModel (see assembly.dart), so two
  // placements of one part refine independently. Wasteful and correct; sharing
  // one model between occurrences is the fix, and it only pays off once
  // occurrences can differ from each other.
  Timer? _refineTimer;

  Iterable<KernelSolid> _refinableSolids() sync* {
    final a = asm;
    if (a == null) return;
    for (final o in a.occurrences) {
      if (!o.visible) continue;
      yield* o.solids;
    }
  }

  int _sceneTriangles() {
    var n = 0;
    for (final s in _refinableSolids()) {
      n += s.mesh.indices.length ~/ 3;
    }
    return n;
  }

  bool _anyCoarse(Size size) {
    final a = asm;
    if (a == null) return false;
    final target = budgetedLinDeflection(
        viewLinearDeflection(a.camera.halfH, size.height), _sceneTriangles());
    for (final s in _refinableSolids()) {
      if (meshNeedsRefine(s.meshLin, steppedLinDeflection(s.meshLin, target))) {
        return true;
      }
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
    final a = asm;
    if (a == null) return;
    // Refinement only ever makes meshes FINER, so without a budget every zoom
    // step ratchets the scene up and nothing gives it back.
    final target = budgetedLinDeflection(
        viewLinearDeflection(a.camera.halfH, size.height), _sceneTriangles());
    var remeshed = 0;
    final sw = Stopwatch()..start();
    for (final s in _refinableSolids()) {
      final step = steppedLinDeflection(s.meshLin, target);
      if (meshNeedsRefine(s.meshLin, step) &&
          s.refine(step, viewAngularDeflection(step))) {
        remeshed++;
      }
    }
    sw.stop();
    if (remeshed == 0) return;
    // A re-mesh replaces the mesh OBJECT, so its identityHashCode changes and
    // the scene signature moves with it — which is exactly what makes the new
    // buffers travel on the next push. Nothing else has to notice.
    Perf.record('kernel.remesh', sw.elapsedMicroseconds / 1000.0);
    Perf.gauge('sceneTris', _sceneTriangles());
    Log.i(
        'perf',
        'asm remesh n=$remeshed lin=${target.toStringAsExponential(2)} '
        'tris=${_sceneTriangles()} in ${sw.elapsedMilliseconds}ms');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refineTimer?.cancel();
    super.dispose();
  }

  /// M170's rule, unchanged: the tap/drag threshold belongs to the INPUT. A
  /// finger wobbles several pixels just resting on the glass; a Pencil does
  /// not, and 8 px under one feels like lag.
  double get _dragSlop => switch (_dragKind) {
        PointerDeviceKind.touch => 8,
        PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 3,
        _ => 3,
      };

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final a = asm;
    if (a == null) return ColoredBox(color: T.viewport);
    return LayoutBuilder(builder: (context, bc) {
      final size = Size(bc.maxWidth, bc.maxHeight);
      // Zoom All, when a placement asked for one. Here and not in AppState
      // because framing needs the viewport's size — see AssemblyModel.needsFit.
      if (a.needsFit) {
        a.needsFit = false;
        fitAssemblyView(a.camera, placedComponents(a), size);
      }
      final cam = Cam3(a.camera, size);
      // Keep the components at screen resolution: refine on the first frame,
      // on resize, and after every zoom. Cheap no-op once smooth.
      _armRefine(size);
      // Drive the RealityKit surface (iOS). Off iOS this is a no-op and the
      // CustomPaint fallback below renders instead.
      if (RealityView.isSupported) _pushReality(a, size);
      return Stack(children: [
        // The render surface sits at the BOTTOM and is never hit-tested; the
        // gesture layer is stacked on top of it (viewport3d does the same, and
        // for the same reason — see the note there about platform views).
        Positioned.fill(
          child: ClipRect(
            child: Stack(children: [
              Positioned.fill(
                child: RealityView.isSupported
                    // IgnorePointer: the ARView is a pure output surface. A
                    // platform view must never be the topmost hit target — on
                    // iOS its touch interception swallows taps before the
                    // Flutter gesture arena sees them.
                    ? IgnorePointer(
                        child: RealityView(
                          placeholder: ColoredBox(color: T.viewport),
                          onCreated: (c) {
                            _reality = c;
                            // A FRESH platform view starts empty. Without
                            // clearing these the signature would still match
                            // the old view's contents, setScene would never
                            // fire and the viewport would stay blank forever
                            // (app resume, tab switch, document switch).
                            _lastSceneSig = null;
                            _sentRevs = const {};
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() {});
                            });
                          },
                        ),
                      )
                    : CustomPaint(
                        painter: _AssemblyPainter(a, _hover),
                        size: Size.infinite,
                      ),
              ),
              // Screen-space decorations. On iOS the scene is RealityKit and
              // _AssemblyPainter never runs, so anything that is pure HUD has
              // to be drawn here or it would be visible on the host and
              // invisible on the device it was built for.
              if (RealityView.isSupported)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MissingPartPainter(a),
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
              _down.add(e.pointer);
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons == kMiddleMouseButton) {
                _mmb = true;
                _mmbPan = HardwareKeyboard.instance.isShiftPressed;
                _mmbLast = e.localPosition;
                return;
              }
              // A second finger turns this into a navigation gesture.
              if (_down.length > 1) {
                _endDrag();
                return;
              }
              // A right- or secondary-button press is a menu gesture
              // everywhere else in this app; it must not grab a component.
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons != kPrimaryMouseButton) {
                return;
              }
              // Grab a component. The pick happens on DOWN, not on the first
              // move, so the selection highlight appears the moment you touch
              // it — that is the feedback that says "this is what will move".
              final hit = pickOccurrence(a, cam, e.localPosition);
              if (hit != null) {
                app.selectOccurrence(hit);
                if (hit.grounded) {
                  // Inventor grounds the first component and refuses to drag
                  // it. Saying so is the difference between a rule and a bug:
                  // silence here reads as "dragging is broken".
                  app.toast(L.of(context).msgAsmGrounded(hit.id));
                } else {
                  _drag = hit;
                  _dragFrom = e.localPosition;
                  _dragMoved = false;
                }
              } else {
                app.selectOccurrence(null);
              }
            },
            onPointerMove: (e) {
              final d = _drag;
              if (d != null) {
                if (!_dragMoved &&
                    (e.localPosition - _dragFrom).distance <= _dragSlop) {
                  return;
                }
                _dragMoved = true;
                // Screen-parallel translation: the world points the two pixels
                // unproject to on the camera plane differ by exactly the
                // motion the user asked for. Ortho, so this is exact at every
                // depth — there is no "how far away is it" to get wrong.
                app.moveOccurrence(
                    d,
                    cam.unprojectOnCamPlane(e.localPosition) -
                        cam.unprojectOnCamPlane(_dragFrom));
                _dragFrom = e.localPosition;
                return; // the drag owns this pointer
              }
              if (_mmb) {
                final delta = e.localPosition - _mmbLast;
                _mmbLast = e.localPosition;
                setState(() {
                  if (_mmbPan) {
                    _pan(a, delta, size);
                  } else {
                    _orbit(a, delta);
                  }
                });
              }
            },
            onPointerUp: (e) {
              _mmb = false;
              _down.remove(e.pointer);
              _endDrag();
            },
            onPointerCancel: (e) {
              _mmb = false;
              _down.remove(e.pointer);
              _endDrag();
            },
            // Trackpad gestures arrive as PointerPanZoom, never as extra
            // pointers: two fingers orbit, two fingers + shift pan, pinch
            // zooms. Identical to the part viewport, deliberately.
            onPointerPanZoomStart: (e) {
              _tpActive = true;
              _tpLastPan = Offset.zero;
              _scaleStartH = a.camera.halfH;
            },
            onPointerPanZoomUpdate: (e) {
              if (!_tpActive) return;
              setState(() {
                if (e.scale > 0 && (e.scale - 1).abs() > 1e-4) {
                  final f = (_scaleStartH / e.scale) / a.camera.halfH;
                  _zoomAt(a, Cam3(a.camera, size), e.localPosition, f);
                }
                final d = e.pan - _tpLastPan;
                _tpLastPan = e.pan;
                if (d == Offset.zero) return;
                if (HardwareKeyboard.instance.isShiftPressed) {
                  _pan(a, d, size);
                } else {
                  _orbit(a, d);
                }
              });
            },
            onPointerPanZoomEnd: (_) => _tpActive = false,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() => _zoomAt(
                    a, cam, e.localPosition, e.scrollDelta.dy > 0 ? 1.1 : 0.9));
              }
            },
            child: MouseRegion(
              cursor: _hover != null
                  ? SystemMouseCursors.grab
                  : MouseCursor.defer,
              onHover: (e) {
                final h = pickOccurrence(a, cam, e.localPosition);
                if (!identical(h, _hover)) setState(() => _hover = h);
              },
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _scaleStartH = a.camera.halfH;
                  _mmbLast = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  if (_tpActive) return; // handled on the trackpad path
                  if (d.pointerCount >= 2) {
                    if (d.scale > 0) {
                      final f = (_scaleStartH / d.scale) / a.camera.halfH;
                      _zoomAt(a, Cam3(a.camera, size), d.localFocalPoint, f);
                    }
                    _pan(a, d.localFocalPoint - _mmbLast, size);
                  } else if (!_mmb &&
                      // NOT while a component is being dragged: that drag
                      // lives in the raw Listener above, which never enters
                      // the gesture arena, so without this a finger moving a
                      // component would orbit the camera at the same time.
                      // Exactly the trap M170 documented for work planes.
                      _drag == null &&
                      _dragKind == PointerDeviceKind.touch) {
                    // One finger orbits ON TOUCH only. A single trackpad or
                    // mouse drag is a pick and must not move the view.
                    _orbit(a, d.localFocalPoint - _mmbLast);
                  }
                  _mmbLast = d.localFocalPoint;
                }),
                // Transparent hit surface over the render layer below.
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        // ViewCube + Home, below the floating ribbon (M146).
        RibbonMetrics.build((_, top) => Positioned(
            top: top + 8,
            right: 10,
            child:
                ViewCube(camera: a.camera, onChanged: () => setState(() {})))),
        // The triad follows the model browser card, as in the part viewport.
        if (GlassBrowser.isSupported)
          ValueListenableBuilder<double>(
            valueListenable: NativeModelBrowser.occupied,
            builder: (_, w, child) => Positioned(
              left: w,
              bottom: BottomTabBar.floatingHeight,
              child: child!,
            ),
            child: IgnorePointer(
                child: CustomPaint(
                    painter: TriadPainter(a.camera),
                    size: const Size(118, 118))),
          )
        else
          Positioned(
              left: 0,
              bottom: BottomTabBar.floatingHeight,
              child: IgnorePointer(
                  child: CustomPaint(
                      painter: TriadPainter(a.camera),
                      size: const Size(118, 118)))),
        if (app.message != null)
          Positioned(
            left: 0,
            right: 0,
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
                child: Text(app.message!, style: ts(12, T.toastText)),
              ),
            ),
          ),
      ]);
    });
  }

  /// Ends a component drag, persisting the new placement only if the component
  /// actually moved — a tap that merely selected one must not rewrite the
  /// document.
  void _endDrag() {
    if (_drag == null) return;
    if (_dragMoved) widget.app.endOccurrenceDrag();
    _drag = null;
    _dragMoved = false;
  }

  void _orbit(AssemblyModel a, Offset d) =>
      a.camera.orbitScreen(-d.dx * 0.01, -d.dy * 0.01);

  void _pan(AssemblyModel a, Offset d, Size size) {
    final wpp = (2 * a.camera.halfH) / size.height;
    a.camera.ox -= d.dx * wpp;
    a.camera.oy += d.dy * wpp;
  }

  void _zoomAt(AssemblyModel a, Cam3 cam, Offset px, double factor) {
    final aspect = cam.aspect;
    final nx = (px.dx / cam.size.width) * 2 - 1;
    final ny = -((px.dy / cam.size.height) * 2 - 1);
    final old = a.camera.halfH;
    a.camera.halfH = PartCamera.clampHalfH(old * factor);
    final dH = old - a.camera.halfH;
    if (dH.isFinite) {
      a.camera.ox += nx * aspect * dH;
      a.camera.oy += ny * dH;
    }
    _armRefine(cam.size); // re-tessellate to the new screen resolution
  }
}

/// The frontmost visible component under [px], or null.
///
/// A screen-space barycentric test over the component's own triangles, the
/// same method [Viewport3D] picks a body with — and for the same reason: it
/// asks "did you touch this shape", which is independent of what kind of
/// surface is there. The camera is SHIFTED per component instead of the mesh
/// being offset, so the test costs no allocation.
///
/// Top-level and pure so a host test can drive it with a real camera and a
/// real mesh: "the drag grabs the component you pointed at" is the whole
/// interaction, and it should not need a device to check.
AssemblyOccurrence? pickOccurrence(AssemblyModel a, Cam3 cam, Offset px) {
  AssemblyOccurrence? best;
  var bestDepth = double.negativeInfinity;
  for (final o in a.occurrences) {
    if (!o.visible) continue;
    final sc = shiftedCam(cam, o.offset);
    for (final s in o.solids) {
      final m = s.mesh;
      for (var t = 0; t + 2 < m.indices.length; t += 3) {
        final i0 = m.indices[t] * 3,
            i1 = m.indices[t + 1] * 3,
            i2 = m.indices[t + 2] * 3;
        if (i0 + 2 >= m.positions.length ||
            i1 + 2 >= m.positions.length ||
            i2 + 2 >= m.positions.length) {
          continue;
        }
        final w0 =
            Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
        final w1 =
            Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
        final w2 =
            Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
        final n = (w1 - w0).cross(w2 - w0);
        // Camera-facing only, same convention as the part viewport's body
        // pick: a back face is never the thing you pointed at.
        if (n.length < 1e-12 || n.normalized().dot(cam.dir) >= 0) continue;
        final pa = sc.project(w0), pb = sc.project(w1), pc = sc.project(w2);
        final d = (pb.dx - pa.dx) * (pc.dy - pa.dy) -
            (pc.dx - pa.dx) * (pb.dy - pa.dy);
        if (d.abs() < 1e-9) continue;
        final u = ((px.dx - pa.dx) * (pc.dy - pa.dy) -
                (pc.dx - pa.dx) * (px.dy - pa.dy)) /
            d;
        final v = ((pb.dx - pa.dx) * (px.dy - pa.dy) -
                (px.dx - pa.dx) * (pb.dy - pa.dy)) /
            d;
        if (u < -1e-6 || v < -1e-6 || u + v > 1 + 1e-6) continue;
        // NEARER the camera is a LARGER depth (Cam3.depth), and the depth of
        // the placed point is the unshifted one plus the placement — the
        // shifted camera moves the PROJECTION, not the view axis.
        final depth = (cam.depth(w0) * (1 - u - v) +
                cam.depth(w1) * u +
                cam.depth(w2) * v) +
            cam.depth(o.offset);
        if (depth > bestDepth) {
          bestDepth = depth;
          best = o;
        }
      }
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// scene painters
// ---------------------------------------------------------------------------

/// A component whose SOURCE PART has gone — deleted from the gallery since the
/// assembly was saved — drawn as a marker at its placement.
///
/// Screen space, and called from BOTH painters. That is the point: on iOS the
/// scene is RealityKit and [_AssemblyPainter] never runs, so a marker drawn
/// only there would be perfectly visible on the host and invisible on the
/// device it exists for. (The same trap paintWorkFeatures documents on the
/// part side.)
///
/// Drawing nothing would be the confusing version: the browser still lists the
/// component, so an empty viewport reads as a broken renderer rather than as a
/// missing file.
void paintMissingComponents(Canvas canvas, Cam3 cam, AssemblyModel asm) {
  for (final o in asm.occurrences) {
    if (o.loaded || !o.visible) continue;
    final c = cam.project(o.offset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = T.err;
    const r = 7.0;
    canvas.drawCircle(c, r, paint);
    final k = r * math.sqrt1_2;
    canvas.drawLine(c + Offset(-k, -k), c + Offset(k, k), paint);
    canvas.drawLine(c + Offset(k, -k), c + Offset(-k, k), paint);
  }
}

/// The iOS overlay: RealityKit draws the scene, this draws what is pure HUD.
class _MissingPartPainter extends CustomPainter {
  final AssemblyModel asm;
  _MissingPartPainter(this.asm);

  @override
  void paint(Canvas canvas, Size size) =>
      paintMissingComponents(canvas, Cam3(asm.camera, size), asm);

  @override
  bool shouldRepaint(covariant _MissingPartPainter old) => true;
}

/// The OFF-IOS renderer, and the one the host tests exercise.
///
/// It says the same things RealityKit says: a selected component is washed in
/// the selection tone and a hovered one in a lighter pass of it, because a
/// viewport where selection means one thing on the iPad and another on a
/// desktop run is a viewport nobody can reason about. See
/// [paintAssemblySolids] for how the wash avoids touching the shared shading
/// path — and for what it adds on top of RealityKit's, which is the accented
/// edge on the selected component.
class _AssemblyPainter extends CustomPainter {
  final AssemblyModel asm;

  /// The component under the pointer, washed the way RealityKit tints it.
  final AssemblyOccurrence? hover;
  _AssemblyPainter(this.asm, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    final cam = Cam3(asm.camera, size);

    // Components first, then the origin scaffolding over them — the part
    // viewport's order, and for its reason: an origin plane lying exactly on a
    // component's face must layer ON TOP rather than z-fight it, while a plane
    // genuinely BEHIND the model is removed per pixel by the occluder the
    // component pass hands back.
    final visible = [
      for (final o in asm.occurrences)
        if (o.visible) o
    ];
    int indexOf(AssemblyOccurrence? o) =>
        o == null ? -1 : visible.indexWhere((v) => identical(v, o));
    final occ = paintAssemblySolids(
      canvas,
      cam,
      [for (final o in visible) (o.offset, o.solids.toList())],
      selected: indexOf(asm.selected),
      hovered: indexOf(hover),
      accentColor: kEdgeAccent,
    );

    // ---- origin planes ----
    for (final key in kPlaneKeys) {
      if (asm.vis[key] != true) continue;
      final f = planeFrame(key);
      final (uMin, uMax, vMin, vMax) = assemblyPlaneRect(asm, key);
      final c0 = f.toWorld(Offset(uMin, vMin));
      final c1 = f.toWorld(Offset(uMax, vMin));
      final c2 = f.toWorld(Offset(uMax, vMax));
      final c3 = f.toWorld(Offset(uMin, vMax));
      drawOccludedQuadFill(
          canvas, cam, c0, c1, c2, c3, _orange.withValues(alpha: 0.28),
          occ: occ);
      drawOccludedPolyline(
          canvas,
          cam,
          [c0, c1, c2, c3],
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _orangeEdge,
          occ: occ,
          close: true,
          extra: occ?.edgeMargin ?? 0);
    }

    // ---- axes + centre point ----
    for (final (key, dir) in const [
      ('x', Vec3(1, 0, 0)),
      ('y', Vec3(0, 1, 0)),
      ('z', Vec3(0, 0, 1)),
    ]) {
      if (asm.vis[key] != true) continue;
      final (lo, hi) = assemblyAxisSpan(asm, dir);
      drawOccludedPolyline(
          canvas,
          cam,
          [dir * lo, dir * hi],
          Paint()
            ..strokeWidth = 1
            ..color = _orange,
          occ: occ,
          extra: occ?.edgeMargin ?? 0);
    }
    if (asm.vis['cp'] == true) {
      canvas.drawCircle(cam.project(Vec3.zero), 3.5, Paint()..color = _orange);
    }

    paintMissingComponents(canvas, cam, asm);
  }

  @override
  bool shouldRepaint(covariant _AssemblyPainter old) => true;
}
