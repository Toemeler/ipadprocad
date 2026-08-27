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
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:native_menu/native_menu.dart' show GlassBrowser;
import 'package:reality_view/reality_view.dart';

import '../app_state.dart';
import '../materials.dart';
import '../asm_constraints.dart';
import '../asm_pick.dart';
import '../assembly.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../mouse_nav.dart';
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
import 'viewport3d.dart'
    show ViewCube, TriadPainter, paintWorkAxesAndPoints;

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

class _ViewportAssemblyState extends State<ViewportAssembly>
    with TickerProviderStateMixin {
  AssemblyModel? get asm => widget.app.currentAssembly;

  // ---- navigation state (mirrors _Viewport3DState) ----
  // M283 — what the mouse drag in flight is doing to the view: the middle
  // button pans, shift with it orbits. [_navLast] is deliberately its own
  // field and not the [_mmbLast] the scale recognizer writes — the part
  // viewport carries the full account of the jump that caused.
  MouseDrag _mouseNav = MouseDrag.none;
  Offset _navLast = Offset.zero;
  Offset _mmbLast = Offset.zero;
  // M283 — the pending wheel zoom and the ticker paying it out. Identical to
  // the part viewport, deliberately. See mouse_nav.dart.
  final WheelZoom _wheel = WheelZoom();
  Ticker? _wheelTick;
  Duration? _wheelLast;
  Size _viewSize = Size.zero;
  double _scaleStartH = 27;
  bool _tpActive = false;
  Offset _tpLastPan = Offset.zero;
  PointerDeviceKind _dragKind = PointerDeviceKind.touch;

  // ---- component drag ----
  AssemblyOccurrence? _drag;
  Offset _dragFrom = Offset.zero;
  bool _dragMoved = false;

  /// M242 — the view-axis depth of the DRAG PLANE, frozen when the finger
  /// lands.
  ///
  /// The drag is screen-parallel, so the grip has to travel in one plane for
  /// the whole gesture. Reading the component's depth every frame instead
  /// would let the solver's own answer move the plane the finger is being
  /// measured against — a linkage that swings toward the camera would then
  /// pull its own target after it, and the drag would run away.
  double _dragDepth = 0;

  /// Pointers currently down. A component drag is a ONE-pointer gesture: the
  /// moment a second finger lands the gesture is a pinch or a two-finger
  /// orbit, and the component has to be let go — otherwise it travels with the
  /// focal point while the camera moves under it, and both are wrong.
  final Set<int> _down = {};

  // ---- M250: the FREE ROTATE gesture ----
  //
  // Inventor's 3D rotate glyph, and the four things it can be grabbed by. The
  // behaviour is the Autodesk help's, verbatim:
  //
  //     the top or bottom handle, dragged vertically   -> horizontal axis
  //     the left or right handle, dragged horizontally -> vertical axis
  //     anywhere inside the sphere                     -> any direction
  //     the rim                                        -> planar to the screen
  //
  // The axes are the CAMERA's, not the world's or the component's: "the
  // horizontal axis" means the one across the screen, which is what makes the
  // gesture read as turning the thing you can see rather than as arithmetic on
  // a coordinate system. cam.s, cam.u and cam.dir are exactly those three.
  _RotGrab? _rotGrab;
  Offset _rotLast = Offset.zero;

  /// The occurrence under the pointer, for the hover cursor and the hover tint.
  AssemblyOccurrence? _hover;

  /// M242 — the geometry under the pointer while Place Constraint is
  /// collecting, ready to draw. What the next tap would select.
  AsmMark? _hoverGeom;

  /// The reference [_hoverGeom] was built from, so a repeated hover on the
  /// same geometry does not rebuild the viewport sixty times a second.
  AsmRef? _hoverRef;

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
      for (final (id, _, at, sol) in assemblyPieces(a)) {
        logMeshConvention(id, sol.mesh);
        pushed.add('$id @ ${at.at.x.toStringAsFixed(2)},'
            '${at.at.y.toStringAsFixed(2)},'
            '${at.at.z.toStringAsFixed(2)}'
            '${at.mirrored ? " mirrored" : ""}: '
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
  // M245 — every occurrence of one part now SHARES that part's model, so a
  // part placed six times is refined once. The set below is deduplicated for
  // exactly that reason: six occurrences would otherwise ask the kernel to
  // re-tessellate the same solid six times per zoom.
  Timer? _refineTimer;

  Iterable<KernelSolid> _refinableSolids() sync* {
    final a = asm;
    if (a == null) return;
    final seen = <KernelSolid>{};
    for (final o in a.occurrences) {
      if (!o.visible) continue;
      for (final (_, _, s) in o.localSolids) {
        if (seen.add(s)) yield s;
      }
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
    _wheelStop();
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
      _viewSize = size; // the wheel glide runs outside build and needs it
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
                        painter: _AssemblyPainter(
                            a, _hover, app.asmMarkers, _hoverGeom, app),
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
                      painter: _MissingPartPainter(
                          a, app.asmMarkers, _hoverGeom, app),
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
              // M283 — with a mouse the middle button drags the view and
              // shift with it turns the model.
              final nav = mouseDrag(e.kind, e.buttons,
                  shift: HardwareKeyboard.instance.isShiftPressed);
              if (nav != MouseDrag.none) {
                _mouseNav = nav;
                _navLast = e.localPosition;
                _wheel.cancel(); // a drag owns the camera now
                return;
              }
              // A second finger turns this into a navigation gesture.
              if (_down.length > 1) {
                _endTurn(app);
                _endDrag();
                return;
              }
              // A right- or secondary-button press is a menu gesture
              // everywhere else in this app; it must not grab a component.
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons != kPrimaryMouseButton) {
                return;
              }
              // M247 — while a WORK FEATURE command is collecting, a tap is
              // a pick. Checked before the constraint branch and before the
              // grab for the same reason that one is: arming a command and
              // then having the tap move a component instead is not something
              // a user can have meant. The two can never both be armed —
              // openConstraint and the work-feature commands cancel each
              // other — so the order between them is style, not behaviour.
              // M248 — and the same again for Pattern / Mirror Component,
              // ahead of the grab for the reason above: a tap meant for the
              // seed selector must not drag the component instead. The three
              // commands cancel one another, so the order between them is
              // style rather than behaviour.
              if (app.asmPatternPicking &&
                  app.patternSession?.active != PatternField.none) {
                final pick = pickAsmRef(a, cam, e.localPosition);
                if (pick == null) {
                  app.toast(L.of(context).hintAsmPickGeometry);
                } else if (app.asmPatternPick(pick)) {
                  return;
                }
                return;
              }
              if (app.asmPickWorkGeometry) {
                final pick = pickAsmRef(a, cam, e.localPosition);
                if (pick != null) {
                  app.asmWorkFeaturePick(pick);
                } else {
                  app.toast(L.of(context).hintAsmPickGeometry);
                }
                return;
              }
              // M250 — Create Component is collecting the SKETCH PLANE. Ahead
              // of the grab for the reason every branch above is: a tap meant
              // to choose a face must not drag the component out from under
              // the command that is about to build on it.
              if (app.asmCreatePicking) {
                final pick = pickAsmRef(a, cam, e.localPosition);
                if (pick == null) {
                  app.toast(L.of(context).hintAsmCreatePickPlane);
                } else {
                  unawaited(app.createComponentOn(pick));
                }
                return;
              }
              // M250 — FREE ROTATE. The glyph owns the pointer when the
              // pointer is on it; a tap that misses it is an ordinary
              // selection, so a different component can still be chosen to
              // turn. No component DRAG while the command is armed: Free
              // Rotate rotates, and Free Move is the button next to it.
              if (app.asmPositionMode == AsmPositionMode.rotate) {
                final grab = _rotGrabAt(app, cam, e.localPosition);
                if (grab != null) {
                  _rotGrab = grab;
                  _rotLast = e.localPosition;
                  app.beginOccurrenceTurn(app.freeRotateTarget!);
                  return;
                }
                final hit = pickOccurrence(a, cam, e.localPosition);
                app.selectOccurrence(hit);
                return;
              }
              // M242 — while Place Constraint is collecting, a tap is a
              // SELECTION, never a grab: dragging a component out from under
              // the dialog that is about to constrain it is not something a
              // user can have meant. "Pick Part First" is the one exception,
              // and it is Inventor's: with it ticked the tap names the whole
              // component, which is how you disambiguate two parts stacked on
              // one another before pointing at a face.
              if (app.constraintPicking) {
                final s = app.constraintSession!;
                if (s.pickPartFirst) {
                  final occ = pickOccurrence(a, cam, e.localPosition);
                  if (occ != null) app.selectOccurrence(occ);
                  return;
                }
                final pick = pickAsmRef(a, cam, e.localPosition);
                if (pick != null) {
                  app.pickConstraintRef(pick);
                } else {
                  app.toast(L.of(context).hintAsmPickGeometry);
                }
                return;
              }
              // M249 — Show Relationships is armed and waiting for a
              // COMPONENT. Ahead of the grab, for the reason every armed
              // command above is: a tap meant to name the component whose
              // glyphs to draw must not drag it instead.
              //
              // LAST among the armed commands, though, and that is the part
              // worth stating. The three above are modeless DIALOGS and cancel
              // one another, so their order is style; Show is a ribbon toggle
              // that nothing cancels, so an armed Show checked first would
              // quietly swallow every tap meant for a dialog opened after it.
              // Checked here it can only ever take a tap that would otherwise
              // have grabbed a component.
              //
              // It also names a whole component rather than a face, so it goes
              // through pickOccurrence — the one armed command here that does.
              if (app.showRelationshipsPicking) {
                final occ = pickOccurrence(a, cam, e.localPosition);
                if (occ != null) {
                  app.selectOccurrence(occ);
                  app.showRelationshipsOf(occ.id);
                } else {
                  app.toast(L.of(context).hintAsmShowPickComponent);
                }
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
                  // M242 — the GRIP. Where the finger landed, on the plane
                  // through the component's origin, is what the solver pulls
                  // on: grabbing a crank at its far end and grabbing it at
                  // its pivot are different gestures, and a drag that always
                  // pulled on the origin could never turn a linkage.
                  _dragDepth = cam.depth(hit.offset);
                  app.beginOccurrenceDrag(
                      hit, _onDragPlane(cam, e.localPosition));
                }
              } else {
                app.selectOccurrence(null);
              }
            },
            onPointerMove: (e) {
              if (_rotGrab != null) {
                _turn(app, cam, e.localPosition);
                _rotLast = e.localPosition;
                return; // the rotation owns this pointer
              }
              final d = _drag;
              if (d != null) {
                if (!_dragMoved &&
                    (e.localPosition - _dragFrom).distance <= _dragSlop) {
                  return;
                }
                _dragMoved = true;
                // Screen-parallel translation: the world point the pixel
                // unprojects to on the camera plane IS where the grip should
                // go. Ortho, so this is exact at every depth — there is no
                // "how far away is it" to get wrong — and the component's own
                // depth is added back so the grip does not jump to the camera
                // plane the moment the drag starts.
                app.dragOccurrenceTo(_onDragPlane(cam, e.localPosition));
                _dragFrom = e.localPosition;
                return; // the drag owns this pointer
              }
              if (_mouseNav != MouseDrag.none) {
                final delta = e.localPosition - _navLast;
                _navLast = e.localPosition;
                setState(() {
                  if (_mouseNav == MouseDrag.pan) {
                    _pan(a, delta, size);
                  } else {
                    _orbit(a, delta);
                  }
                });
              }
            },
            onPointerUp: (e) {
              _mouseNav = MouseDrag.none;
              _down.remove(e.pointer);
              _endTurn(app);
              _endDrag();
            },
            onPointerCancel: (e) {
              _mouseNav = MouseDrag.none;
              _down.remove(e.pointer);
              _endTurn(app);
              _endDrag();
            },
            // Trackpad gestures arrive as PointerPanZoom, never as extra
            // pointers: two fingers orbit, two fingers + shift pan, pinch
            // zooms. Identical to the part viewport, deliberately.
            onPointerPanZoomStart: (e) {
              _wheel.cancel(); // the trackpad takes over from a wheel glide
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
              // M283 — proportional to the travel and paid out over frames.
              // The part viewport carries the full explanation.
              if (e is PointerScrollEvent) {
                _wheel.add(
                    wheelDoublings(e.scrollDelta.dy), e.localPosition);
                _wheelStart();
              }
            },
            child: MouseRegion(
              cursor: _hover != null
                  ? SystemMouseCursors.grab
                  : MouseCursor.defer,
              onHover: (e) {
                // While Place Constraint collects, hovering pre-highlights the
                // GEOMETRY under the pointer rather than the component: what
                // the next tap would select is the thing worth showing.
                if (app.constraintPicking ||
                    app.asmPickWorkGeometry ||
                    app.asmCreatePicking ||
                    (app.asmPatternPicking &&
                        app.patternSession?.active != PatternField.none)) {
                  final p = pickAsmRef(a, cam, e.localPosition);
                  final g = p == null ? null : app.markFor(a, p.ref);
                  // Compare the REFERENCE, not the mark: markFor builds a
                  // fresh one every call, so identical() on it is never true
                  // and the viewport would rebuild on every mouse move.
                  if (p?.ref.label != _hoverRef?.label ||
                      p?.ref.occurrence != _hoverRef?.occurrence ||
                      (p != null &&
                          _hoverRef != null &&
                          (p.ref.anchor - _hoverRef!.anchor).length > 1e-9) ||
                      (p == null) != (_hoverRef == null)) {
                    setState(() {
                      _hoverRef = p?.ref;
                      _hoverGeom = g;
                    });
                  }
                  if (_hover != null) setState(() => _hover = null);
                  return;
                }
                if (_hoverGeom != null) {
                  setState(() {
                    _hoverGeom = null;
                    _hoverRef = null;
                  });
                }
                final h = pickOccurrence(a, cam, e.localPosition);
                if (!identical(h, _hover)) setState(() => _hover = h);
              },
              onExit: (_) => setState(() {
                _hover = null;
                _hoverGeom = null;
                _hoverRef = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _wheel.cancel(); // M283 — a touch gesture outranks the glide
                  _scaleStartH = a.camera.halfH;
                  _mmbLast = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  if (_tpActive) return; // handled on the trackpad path
                  // M283 — a mouse navigation drag owns the camera outright,
                  // and must return BEFORE the _mmbLast write below.
                  if (_mouseNav != MouseDrag.none) return;
                  if (d.pointerCount >= 2) {
                    if (d.scale > 0) {
                      final f = (_scaleStartH / d.scale) / a.camera.halfH;
                      _zoomAt(a, Cam3(a.camera, size), d.localFocalPoint, f);
                    }
                    _pan(a, d.localFocalPoint - _mmbLast, size);
                  } else if (
                      // NOT while a component is being dragged: that drag
                      // lives in the raw Listener above, which never enters
                      // the gesture arena, so without this a finger moving a
                      // component would orbit the camera at the same time.
                      // Exactly the trap M170 documented for work planes.
                      _drag == null &&
                      // M250 — and not while one is being TURNED, which lives
                      // in the same raw Listener and would otherwise spin the
                      // component and the camera together.
                      _rotGrab == null &&
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
            child: ViewCube(
              camera: a.camera,
              onChanged: () => setState(() {}),
              orient: a.cubeOrient, // M275
              onOrient: app.setCubeOrient,
              // M283 — framed on the placed components, the same rule Zoom All
              // uses when a component is dropped in.
              fit: (c) => fitAssemblyView(c, placedComponents(a), size),
            ))),
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

  /// M250 — which part of the rotate glyph [px] is on, or null when it is not
  /// on the glyph at all.
  ///
  /// The bands are in fractions of the glyph's own screen radius, so they hold
  /// at any zoom, and the outer one runs a little PAST the rim: a rim you can
  /// only hit exactly is a rim nobody hits on a touch screen.
  _RotGrab? _rotGrabAt(AppState app, Cam3 cam, Offset px) {
    final g = rotateGlyphScreen(app, cam);
    if (g == null) return null;
    final (c, r) = g;
    final d = (px - c).distance;
    if (d > r * 1.18) return null;
    if (d < r * 0.78) return _RotGrab.free;
    // On the rim. Which of the four handles, if any: within 32 degrees of
    // straight up/down is a handle, and everything else on the rim is the
    // planar-to-screen ring.
    final ang = math.atan2(-(px.dy - c.dy), px.dx - c.dx);
    const near = math.pi * 32 / 180;
    double away(double target) {
      var t = (ang - target).abs() % (2 * math.pi);
      if (t > math.pi) t = 2 * math.pi - t;
      return t;
    }

    if (away(math.pi / 2) < near || away(-math.pi / 2) < near) {
      return _RotGrab.screenHorizontal;
    }
    if (away(0) < near || away(math.pi) < near) {
      return _RotGrab.screenVertical;
    }
    return _RotGrab.screenPlanar;
  }

  /// One frame of the rotate gesture.
  ///
  /// [_kTurnPerPixel] is the orbit's own sensitivity, so turning a component
  /// and turning the camera feel like the same gesture — which they very
  /// nearly are, and a component that spun twice as fast as the view would
  /// read as a different control.
  void _turn(AppState app, Cam3 cam, Offset px) {
    final d = px - _rotLast;
    switch (_rotGrab!) {
      // Dragging DOWN tips the top of the component toward the viewer.
      // {s, u, dir} is right-handed and the camera sits on the +dir side, so
      // a positive turn about s carries u toward dir — toward you.
      case _RotGrab.screenHorizontal:
        app.turnOccurrenceBy(cam.s, d.dy * _kTurnPerPixel);
      // Dragging RIGHT carries the face you are looking at to the right:
      // u x dir = s, so a positive turn about u moves dir toward s.
      case _RotGrab.screenVertical:
        app.turnOccurrenceBy(cam.u, d.dx * _kTurnPerPixel);
      case _RotGrab.free:
        final len = d.distance;
        if (len < 1e-6) return;
        // The trackball: one rotation about the screen axis perpendicular to
        // the drag, which is the two handle cases composed. orbitScreen does
        // it as yaw-then-pitch; one axis is the same thing to first order and
        // does not need two solves per frame.
        app.turnOccurrenceBy(
            cam.u * d.dx + cam.s * d.dy, len * _kTurnPerPixel);
      case _RotGrab.screenPlanar:
        final g = rotateGlyphScreen(app, cam);
        if (g == null) return;
        final (c, _) = g;
        // The angle SWEPT around the centre. Screen y grows downward, so it is
        // negated to give an ordinary counter-clockwise-positive angle — and
        // counter-clockwise on screen is a positive turn about dir, which
        // points at the viewer.
        double ang(Offset p) => math.atan2(-(p.dy - c.dy), p.dx - c.dx);
        var delta = ang(px) - ang(_rotLast);
        // Across the ±pi seam the raw difference is nearly a full turn the
        // wrong way, which would flip the component every time the pointer
        // crossed due west.
        if (delta > math.pi) delta -= 2 * math.pi;
        if (delta < -math.pi) delta += 2 * math.pi;
        app.turnOccurrenceBy(cam.dir, delta);
    }
  }

  /// Ends the rotate gesture, persisting the placement once.
  void _endTurn(AppState app) {
    if (_rotGrab == null) return;
    _rotGrab = null;
    app.endOccurrenceTurn();
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

  /// The world point pixel [px] names on the frozen drag plane.
  ///
  /// [Cam3.unprojectOnCamPlane] answers on the plane through the ORIGIN, which
  /// is depth zero; pushing it back along the view axis by [_dragDepth] puts
  /// it on the plane the component was grabbed in. Orthographic, so this is
  /// exact rather than an approximation of a perspective ray.
  Vec3 _onDragPlane(Cam3 cam, Offset px) =>
      cam.unprojectOnCamPlane(px) - cam.dir * _dragDepth;

  // M260 — the three camera moves report to the engagement latch, so the
  // bottom bar folds out of the way here exactly as it does in a part.
  void _orbit(AssemblyModel a, Offset d) {
    widget.app.engageView();
    a.camera.orbitScreen(-d.dx * 0.01, -d.dy * 0.01);
  }

  void _pan(AssemblyModel a, Offset d, Size size) {
    widget.app.engageView();
    final wpp = (2 * a.camera.halfH) / size.height;
    a.camera.ox -= d.dx * wpp;
    a.camera.oy += d.dy * wpp;
  }

  void _zoomAt(AssemblyModel a, Cam3 cam, Offset px, double factor) {
    widget.app.engageView();
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

  // ---- M283: the wheel glide, exactly as in the part viewport ------------
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
    final a = asm;
    final last = _wheelLast;
    _wheelLast = elapsed;
    if (a == null || _viewSize.isEmpty || !mounted) {
      _wheel.cancel();
      _wheelStop();
      return;
    }
    final dt =
        last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1000000.0;
    final f = _wheel.takeHalfHeightFactor(dt);
    if (f != 1) {
      setState(() => _zoomAt(a, Cam3(a.camera, _viewSize), _wheel.focus, f));
    }
    if (!_wheel.active) _wheelStop();
  }
}

/// The frontmost visible component under [px], or null.
///
/// A screen-space barycentric test over the component's own triangles, the
/// same method [Viewport3D] picks a body with — and for the same reason: it
/// asks "did you touch this shape", which is independent of what kind of
/// surface is there. The camera is PLACED per component instead of the mesh
/// being transformed, so the test costs no allocation however the component
/// has been turned.
///
/// Top-level and pure so a host test can drive it with a real camera and a
/// real mesh: "the drag grabs the component you pointed at" is the whole
/// interaction, and it should not need a device to check.
AssemblyOccurrence? pickOccurrence(AssemblyModel a, Cam3 cam, Offset px) {
  AssemblyOccurrence? best;
  var bestDepth = double.infinity;
  for (final o in a.occurrences) {
    if (!o.visible) continue;
    for (final (_, pp, s) in o.worldSolids) {
      // M246 — the camera is placed per PIECE. A subassembly's parts each sit
      // somewhere inside it, so one camera for the whole component would
      // hit-test them all at the subassembly's origin.
      final sc = placedCam(cam, pp);
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
        // Camera-facing only, the same convention as the part viewport's body
        // pick (_pickSolidAny): the winding normal is the OUTWARD one and the
        // camera sits at +dir, so a face you can see has n.dir > 0. Against
        // the PLACED camera's direction, because the normal is in the piece's
        // own space and a turned component would otherwise be tested against
        // the world's idea of "toward the viewer".
        //
        // This read `>= 0` until the device report of 2026-08-26 — the same
        // inversion asm_pick's file header now sets out at length. It kept
        // only the faces hidden behind the component, so a tap answered with
        // whichever component's BACK the pointer happened to be over.
        //
        // M248 — UNCHANGED on a mirrored component. The winding reverses in
        // WORLD space and this test is in the piece's own, where the mesh is
        // untouched; see placedCam. A sign here selects the far side.
        if (n.length < 1e-12 || !sc.facesCamera(n)) continue;
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
        // NEARER the camera is a SMALLER depth (Cam3.depth is w.(-dir) and
        // the camera sits at +dir), and the depth of the placed point is the
        // piece-local one plus the piece's own placement — the placed camera
        // moves the PROJECTION, not the view axis.
        final depth = (sc.depth(w0) * (1 - u - v) +
                sc.depth(w1) * u +
                sc.depth(w2) * v) +
            cam.depth(pp.at);
        if (depth < bestDepth) {
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

/// M250 — which part of the Free Rotate glyph a gesture grabbed.
///
/// Named for the SCREEN axis each one turns about, because that is what the
/// user is choosing: "the horizontal axis" is the one lying across the screen,
/// whichever way the model happens to be facing.
enum _RotGrab {
  /// The top or bottom handle: turns about the screen's horizontal axis.
  screenHorizontal,

  /// The left or right handle: turns about the screen's vertical axis.
  screenVertical,

  /// Anywhere inside the sphere: turns in any direction.
  free,

  /// The rim: turns in the plane of the screen.
  screenPlanar,
}

/// Radians per pixel of drag, for the Free Rotate gesture.
///
/// The same number [_ViewportAssemblyState._orbit] turns the CAMERA by, so the
/// two gestures feel like one control. A component that spun at a different
/// rate from the view would read as a different kind of thing entirely.
const double _kTurnPerPixel = 0.01;

/// M250 — where the Free Rotate glyph is on screen, and how big: (centre,
/// radius) in pixels, or null when Free Rotate is not armed on anything.
///
/// ONE definition, read by the painter and by the hit test. Two would be two
/// chances for the glyph to be drawn somewhere it cannot be grabbed — the
/// exact class of defect asm_pick.dart's header opens by naming.
///
/// The radius is measured by projecting a world offset along the camera's own
/// right vector, so it tracks the zoom exactly; the floor keeps a small
/// component's glyph big enough to have four distinguishable handles on it.
(Offset, double)? rotateGlyphScreen(AppState app, Cam3 cam) {
  final g = app.freeRotateGlyph;
  if (g == null) return null;
  final (centre, r) = g;
  final c = cam.project(centre);
  final edge = cam.project(centre + cam.s * r);
  return (c, math.max(34.0, (edge - c).distance * 1.25));
}

/// Draws Inventor's 3D rotate glyph on the component Free Rotate is armed on.
///
/// Pure HUD in screen space, so it is drawn from BOTH painters — the same
/// split paintMissingComponents and paintWorkAxesAndPoints live on, and for
/// the same reason: drawn only in the CPU scene painter it would be visible on
/// the host and invisible on the iPad, where RealityKit owns the scene.
///
/// Un-occluded, deliberately. A handle you cannot see because the component
/// you are about to turn is in front of it is a handle you cannot aim at, and
/// the whole glyph is an instrument rather than geometry.
void paintRotateGlyph(Canvas canvas, Cam3 cam, AppState app) {
  final g = rotateGlyphScreen(app, cam);
  if (g == null) return;
  final (c, r) = g;
  final rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = kEdgeAccent.withValues(alpha: 0.9);
  // The sphere: the rim, and two ellipses across it that read as its equator
  // and meridian. Inventor draws a shaded ball; two arcs say the same thing at
  // a tenth of the cost and do not fight the model behind them.
  canvas.drawCircle(c, r, rim);
  final faint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = kEdgeAccent.withValues(alpha: 0.35);
  canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 0.7),
      faint);
  canvas.drawOval(Rect.fromCenter(center: c, width: r * 0.7, height: r * 2),
      faint);
  // The four handles, at the compass points of the rim — which is exactly
  // where the hit test looks for them.
  final knob = Paint()..color = kEdgeAccent;
  for (final o in [
    Offset(0, -r),
    Offset(0, r),
    Offset(-r, 0),
    Offset(r, 0),
  ]) {
    canvas.drawCircle(c + o, 4.5, knob);
    canvas.drawCircle(
        c + o,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = T.viewport);
  }
}

/// The iOS overlay: RealityKit draws the scene, this draws what is pure HUD.
class _MissingPartPainter extends CustomPainter {
  final AssemblyModel asm;

  /// M242 — the picked and hovered constraint geometry. HUD, so it is drawn
  /// here on iOS (where RealityKit owns the scene) and by [_AssemblyPainter]
  /// off it — the same split paintMissingComponents already lives on.
  final List<AsmMark> marks;
  final AsmMark? hoverGeom;

  /// M247 — for the work axis / work point selection colour. The features
  /// themselves are the assembly's; which one is SELECTED is session state.
  final AppState app;
  _MissingPartPainter(this.asm, this.marks, this.hoverGeom, this.app);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = Cam3(asm.camera, size);
    paintMissingComponents(canvas, cam, asm);
    // M247 — work axes and points are pure HUD, so they are drawn from BOTH
    // painters. Exactly the split paintMissingComponents lives on, and the
    // one paintWorkFeatures documents on the part side: drawn only in the
    // scene painter they would be visible on the host and invisible on the
    // iPad, where RealityKit owns the scene. (Work PLANES do NOT come through
    // here — they are filled quads that must be depth-tested against the
    // components, so they ride the scene payload; see assemblyPlanePayloads.)
    paintWorkAxesAndPoints(canvas, cam,
        axes: asm.workAxes,
        points: asm.workPoints,
        bounds: assemblyContentBounds(asm),
        app: app);
    // M249 — the relationship glyphs are HUD too, and so are drawn from both
    // painters for the reason the line above is.
    paintRelationshipGlyphs(canvas, cam, asm);
    paintConstraintMarks(canvas, cam, marks, hoverGeom);
    // M250 — the Free Rotate glyph is HUD too, and comes through here for the
    // same reason the work axes do.
    paintRotateGlyph(canvas, cam, app);
  }

  @override
  bool shouldRepaint(covariant _MissingPartPainter old) => true;
}

/// M242 — what Place Constraint has collected, and what the next tap would
/// take.
///
/// Drawn in SCREEN space over everything, deliberately un-occluded: a
/// selection you cannot see because the part you are constraining it to is in
/// front of it is a selection you cannot verify. Inventor does the same — its
/// selection highlight reads through the model.
///
/// Every mark is ANCHORED on the point that was tapped (see AsmRef.anchor),
/// so it lands on the surface rather than at whatever reference point the
/// kernel gave the underlying plane or axis.
void paintConstraintMarks(
    Canvas canvas, Cam3 cam, List<AsmMark> marks, AsmMark? hover) {
  if (marks.isEmpty && hover == null) return;
  void draw(AsmMark m, Color color, double width) {
    final (pts, closed) = refMarker(m);
    if (pts.length == 1) {
      canvas.drawCircle(cam.project(pts.first), 4.5, Paint()..color = color);
      return;
    }
    final path = Path();
    final first = cam.project(pts.first);
    path.moveTo(first.dx, first.dy);
    for (final p in pts.skip(1)) {
      final s = cam.project(p);
      path.lineTo(s.dx, s.dy);
    }
    if (closed) {
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color);
  }

  if (hover != null) draw(hover, kEdgeAccent, 1.6);
  for (final m in marks) {
    draw(m, T.accent, 2.2);
  }
}

// ---------------------------------------------------------------------------
// M249 — relationship glyphs
// ---------------------------------------------------------------------------

/// Half the width of a glyph badge, in logical pixels.
///
/// Screen space, not world: a relationship is an annotation on the model and
/// not a part of it, so it has to stay legible at any zoom — exactly as the
/// missing-component marker and the origin centre point already do.
const double kRelGlyphRadius = 9.0;

/// What Show / Show Sick put on screen: a badge at each end of every shown
/// relationship, joined by a dashed leader.
///
/// Called from BOTH painters, and that is the point of it being top-level. On
/// iOS RealityKit owns the scene and [_AssemblyPainter] never runs, so a glyph
/// drawn only there would be perfectly visible on the host and invisible on
/// the device — the trap paintMissingComponents and paintWorkAxesAndPoints are
/// each already written around.
///
/// Anchored on [AsmRef.anchor], like every other assembly annotation since
/// M244: the geometry's own point is wherever the kernel put it, so a badge
/// drawn there lands in mid-air beside the part rather than on the face the
/// relationship is about.
///
/// Un-occluded, for [paintConstraintMarks]'s reason: a glyph you cannot see
/// because the other component is in front of it is a glyph that cannot tell
/// you why the two are stuck together, which is the only reason to draw one.
void paintRelationshipGlyphs(Canvas canvas, Cam3 cam, AssemblyModel asm) {
  final shown = asm.visibleRelationships;
  if (shown.isEmpty) return;
  for (final c in shown) {
    final refs = [c.a, c.b, if (c.c != null) c.c!];
    final pts = [
      for (final r in refs) cam.project(worldAnchorOf(asm, r)),
    ];
    // Sick is said in RED and said twice — the leader and both badges — for
    // the reason the browser's badge exists: "this one could not be met" has
    // to be findable by looking at the model, which is what Show Sick is for.
    final color = c.isSick ? T.err : T.accent;
    for (var i = 1; i < pts.length; i++) {
      _dashedLeader(canvas, pts[i - 1], pts[i], color);
    }
    for (final p in pts) {
      _relGlyphBadge(canvas, p, c.kind, color);
    }
  }
}

/// The leader between the two ends of one relationship.
///
/// Dashed, and drawn short of both badges so it does not run under them: a
/// solid line between two marks reads as geometry, and there is no edge there.
void _dashedLeader(Canvas canvas, Offset a, Offset b, Color color) {
  final d = b - a;
  final len = d.distance;
  // Two badges plus a gap: below that the leader would be all badge and no
  // line, and the two marks already say they belong together by touching.
  if (len < 2 * kRelGlyphRadius + 6) return;
  final u = d / len;
  final from = a + u * (kRelGlyphRadius + 1);
  final to = b - u * (kRelGlyphRadius + 1);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..color = color.withValues(alpha: 0.75);
  const dash = 4.0, gap = 3.0;
  var t = 0.0;
  final span = (to - from).distance;
  while (t < span) {
    final e = math.min(t + dash, span);
    canvas.drawLine(from + u * t, from + u * e, paint);
    t = e + gap;
  }
}

/// One badge: the rounded plate, and the mark that says which relationship.
void _relGlyphBadge(Canvas canvas, Offset at, AsmKind kind, Color color) {
  const r = kRelGlyphRadius;
  final box = Rect.fromCircle(center: at, radius: r);
  final rrect = RRect.fromRectAndRadius(box, const Radius.circular(3));
  canvas.drawRRect(rrect, Paint()..color = T.panel.withValues(alpha: 0.92));
  canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color);
  final ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round
    ..color = color;
  final (lines, circles) = _relGlyphMark(kind);
  // The mark is authored in a unit box and scaled here, so every glyph in the
  // family is drawn at one weight and one size however the badge is sized.
  const s = r * 0.62;
  for (final poly in lines) {
    for (var i = 1; i < poly.length; i++) {
      canvas.drawLine(at + poly[i - 1] * s, at + poly[i] * s, ink);
    }
  }
  for (final (c, rad) in circles) {
    canvas.drawCircle(at + c * s, rad * s, ink);
  }
}

/// The mark for one relationship kind: polylines and circles in a unit box.
///
/// Drawn rather than looked up in [AC], because the ribbon's icons are SVG and
/// a CustomPainter cannot rasterise one inside `paint()` — flutter_svg's decode
/// is asynchronous, and a glyph that appeared a frame late would flicker on
/// every drag. These are the same pictures reduced to what survives at 11 pt:
/// the shape that distinguishes the kind, and nothing else.
(List<List<Offset>>, List<(Offset, double)>) _relGlyphMark(AsmKind kind) {
  const nl = <List<Offset>>[];
  const nc = <(Offset, double)>[];
  switch (kind) {
    // Mate / Flush: two faces meeting.
    case AsmKind.mate:
      return ([
        [Offset(-0.9, -1), Offset(-0.9, 1)],
        [Offset(0.9, -1), Offset(0.9, 1)],
        [Offset(-0.35, 0), Offset(0.35, 0)],
      ], nc);
    // Angle: two edges and the corner between them.
    case AsmKind.angle:
      return ([
        [Offset(-1, 0.9), Offset(1, 0.9)],
        [Offset(-1, 0.9), Offset(0.7, -0.9)],
      ], nc);
    // Tangent: the round face resting on the flat one.
    case AsmKind.tangent:
      return ([
        [Offset(-1, 0.9), Offset(1, 0.9)]
      ], [
        (const Offset(0, -0.1), 1.0)
      ]);
    // Insert: the bore, with the shaft down it.
    case AsmKind.insert:
      return ([
        [Offset(0, -1.1), Offset(0, 1.1)]
      ], [
        (Offset.zero, 0.85)
      ]);
    case AsmKind.symmetry:
      return ([
        [Offset(0, -1.1), Offset(0, 1.1)],
        [Offset(-1, -0.5), Offset(-1, 0.5)],
        [Offset(1, -0.5), Offset(1, 0.5)],
      ], nc);
    // The two motion kinds: a driving wheel and a driven one.
    case AsmKind.rotation:
    case AsmKind.rotationTranslation:
      return (nl, [
        (const Offset(-0.5, 0), 0.6),
        (const Offset(0.6, 0), 0.45),
      ]);
    // Transitional: the follower riding the cam's face.
    case AsmKind.transitional:
      return ([
        [Offset(-1.1, 0.6), Offset(-0.3, -0.4), Offset(0.6, 0.6)]
      ], [
        (const Offset(-0.3, -0.9), 0.4)
      ]);
    // ---- M249: the joints, each drawn as the freedom it LEAVES -------------
    //
    // Which is what a glyph on the model is for: the browser row already says
    // "Rotational:1", and what the picture can add is what the component can
    // still do. A cross is nothing, a circle is a turn, a bar is a slide.
    case AsmKind.jointRigid:
      return ([
        [Offset(-0.9, -0.9), Offset(0.9, 0.9)],
        [Offset(0.9, -0.9), Offset(-0.9, 0.9)],
      ], nc);
    case AsmKind.jointRotational:
      return (nl, [
        (Offset.zero, 0.95),
        (Offset.zero, 0.18),
      ]);
    case AsmKind.jointSlider:
      return ([
        [Offset(-1.1, 0), Offset(1.1, 0)],
        [Offset(-0.5, -0.5), Offset(0.5, -0.5)],
      ], nc);
    case AsmKind.jointCylindrical:
      return ([
        [Offset(-1.1, 0.8), Offset(1.1, 0.8)]
      ], [
        (const Offset(0, -0.2), 0.7)
      ]);
    case AsmKind.jointPlanar:
      return ([
        [Offset(-1.1, 0.7), Offset(1.1, 0.7)],
        [Offset(-0.6, -0.7), Offset(0.6, -0.7), Offset(1.0, 0.2)],
      ], nc);
    case AsmKind.jointBall:
      return (nl, [
        (Offset.zero, 0.95),
        (Offset.zero, 0.5),
      ]);
  }
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

  /// M242 — Place Constraint's collected and hovered geometry.
  final List<AsmMark> marks;
  final AsmMark? hoverGeom;

  /// See [_MissingPartPainter.app].
  final AppState app;
  _AssemblyPainter(this.asm, this.hover, this.marks, this.hoverGeom, this.app);

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
      [
        for (final o in visible)
          PlacedComponent([for (final (_, at, s) in o.worldSolids) (at, s)])
      ],
      selected: indexOf(asm.selected),
      hovered: indexOf(hover),
      accentColor: kEdgeAccent,
      // M272 — the appearance each component was given, so this painter and
      // RealityKit show the same assembly.
      materialOf: (i) {
        final argb = materialArgb(visible[i].material);
        return argb == null ? null : Color(argb);
      },
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

    // ---- work planes (M247) ----
    //
    // With the origin planes and through the same two helpers, for the reason
    // M151 gives on the part side: a work plane has to frame the model exactly
    // as an origin plane does, and one drawn by its own code is one that can
    // drift from the rectangle the picker hit-tests (planeRectInBounds is what
    // both read). Occluded, so a plane passes THROUGH a component rather than
    // floating on it.
    for (final w in asm.workPlanes) {
      if (!w.visible) continue;
      final f = w.frame;
      final (uMin, uMax, vMin, vMax) =
          planeRectInBounds(assemblyOriginExtent(asm), f);
      final c0 = f.toWorld(Offset(uMin, vMin));
      final c1 = f.toWorld(Offset(uMax, vMin));
      final c2 = f.toWorld(Offset(uMax, vMax));
      final c3 = f.toWorld(Offset(uMin, vMax));
      final sel = identical(app.selectedWorkPlane, w);
      drawOccludedQuadFill(canvas, cam, c0, c1, c2, c3,
          (sel ? kEdgeAccent : _orange).withValues(alpha: sel ? 0.42 : 0.22),
          occ: occ);
      drawOccludedPolyline(
          canvas,
          cam,
          [c0, c1, c2, c3],
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 2 : 1
            ..color = sel ? kEdgeAccent : _orangeEdge,
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
    // M247 — see _MissingPartPainter.paint: the HUD half of the work features,
    // drawn from here as well so the host renderer says what the device says.
    paintWorkAxesAndPoints(canvas, cam,
        axes: asm.workAxes,
        points: asm.workPoints,
        bounds: assemblyContentBounds(asm),
        app: app);
    // M249 — see _MissingPartPainter.paint.
    paintRelationshipGlyphs(canvas, cam, asm);
    paintConstraintMarks(canvas, cam, marks, hoverGeom);
    // M250 — and the Free Rotate glyph, so the host renderer says what the
    // device says.
    paintRotateGlyph(canvas, cam, app);
  }

  @override
  bool shouldRepaint(covariant _AssemblyPainter old) => true;
}
