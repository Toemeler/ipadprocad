// M247 — Work Plane / Work Axis / Work Point in an ASSEMBLY.
//
// m215/m223/m229/m231 pin the arithmetic, and it is the same arithmetic here:
// the assembly feeds work_features.dart the same WorkRefs and takes the same
// answers. What this file pins is the part that is NOT the same, plus the
// wiring that reaches it:
//
//   * THE REFERENCES MOVE. A part's work plane bakes its frame; an assembly's
//     cannot, because the solver moves the component it was built on. This is
//     the load-bearing claim of the milestone and it is invisible on screen —
//     a baked frame looks exactly right until the first drag.
//   * THE ANCHOR, NOT THE RECORD POINT. OCCT's plane point is the sketch
//     origin, routinely a quarter of a metre from the face. facedBox lies the
//     same way on purpose (M242/M244), so a plane built on its front face
//     lands where the finger was or 250 mm to one side, and nothing in
//     between.
//   * ONE PICKER, TWO COMMANDS. The same pickAsmRef serves Place Constraint
//     and this; an assembly work feature is offered back through it, so it can
//     be built on and mated to.
//   * THE COMMANDS ROUTE. startWorkAxis and its siblings arm whichever
//     document is open, and every one of Inventor's methods is reachable.
//   * THE DOCUMENT. Saved, read back, and cleaned up when a component goes.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_pick.dart';
import 'package:prototype/asm_work_features.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/l10n/cad_terms.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/widgets/native_browser.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/work_features.dart';

// ---------------------------------------------------------------------------
// fakes — m242_asm_ui_test's, and deliberately including its lie
// ---------------------------------------------------------------------------

/// A box centred on the origin whose face records put the plane's point 250 mm
/// along the plane, exactly as OCCT does. See m242_asm_ui_test.facedBox: a
/// fake that put the point on its own face would make every test here pass
/// while the app drew the plane beside the model.
KernelSolid facedBox({double h = 10}) {
  final c = [
    [-h, -h, -h],
    [h, -h, -h],
    [h, h, -h],
    [-h, h, -h],
    [-h, -h, h],
    [h, -h, h],
    [h, h, h],
    [-h, h, h],
  ];
  const quads = [
    [0, 3, 2, 1], // -Z
    [4, 5, 6, 7], // +Z
    [0, 1, 5, 4], // -Y
    [3, 7, 6, 2], // +Y
    [0, 4, 7, 3], // -X
    [1, 2, 6, 5], // +X
  ];
  const normals = [
    [0.0, 0.0, -1.0],
    [0.0, 0.0, 1.0],
    [0.0, -1.0, 0.0],
    [0.0, 1.0, 0.0],
    [-1.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
  ];
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  final triFaces = <int>[];
  final infos = <double>[];
  for (var f = 0; f < quads.length; f++) {
    final base = pos.length ~/ 3;
    for (final vi in quads[f]) {
      pos.addAll(c[vi]);
      nor.addAll(normals[f]);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    triFaces.addAll([f, f]);
    final n = normals[f];
    final away = [n[1], n[2], n[0]];
    infos.addAll([
      0, // plane
      n[0] * h + away[0] * 250, n[1] * h + away[1] * 250,
      n[2] * h + away[2] * 250,
      n[0], n[1], n[2],
      0, 0, 0,
      0,
      0, 0, 0, 0,
    ]);
  }
  return KernelSolid(
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(nor),
      Int32List.fromList(idx),
      Int32List.fromList([0]),
      Float64List(0),
      triFaces: Int32List.fromList(triFaces),
      faceInfos: Float64List.fromList(infos),
    ),
    8 * h * h * h,
    null,
  );
}

PartModel boxPart(String name, {double h = 10}) {
  final p = PartModel(name);
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)],
    direction: ExtrudeDirection.defaultDir,
    distanceA: 2 * h,
    distanceB: 0,
    extent: FeatureExtent.distance,
  )..solid = facedBox(h: h));
  return p;
}

AssemblyOccurrence occ(String id, Vec3 at,
        {bool grounded = false, Quat rot = Quat.identity, double h = 10}) =>
    AssemblyOccurrence(
        id: id,
        source: id.split(':').first,
        part: boxPart(id.split(':').first, h: h),
        offset: at,
        grounded: grounded)
      ..rot = rot;

AppState freshApp(String tag) =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync(tag);

AppState asmApp(String tag, List<AssemblyOccurrence> os) {
  final app = freshApp(tag);
  final a = AssemblyModel('Gearbox');
  a.occurrences.addAll(os);
  app.assemblies['Gearbox'] = a;
  app.openTabs.add('Gearbox');
  app.curTab = 'Gearbox';
  return app;
}

/// The front view: the eye on the +Z side looking down -Z, 120 mm across — so
/// the box's +Z face is the one under the middle of the screen. `dir` points
/// AT the eye (see Cam3), which is what makes it the +Z one and not the far
/// face behind it.
Cam3 frontCam([Size size = const Size(800, 600)]) =>
    Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 60), size);

/// A reference to [o]'s -Z FACE, in the shape the picker stores one: the
/// plane's own point 250 mm off the face (facedBox lies the way OCCT lies) and
/// the anchor on it. The far face on purpose — these are tests of the RE-SOLVE,
/// and a stored reference does not care which side it was picked from.
AsmRef faceRef(AssemblyOccurrence o) => AsmRef(
    o.id, const AsmGeom.plane(Vec3(0, -250, -10), Vec3(0, 0, -1)), 'Face',
    anchor: const Vec3(0, 0, -10), extent: 10);

/// A reference to a VERTEX of [o], in the component's own frame.
AsmRef vertexRef(AssemblyOccurrence o, Vec3 local) =>
    AsmRef(o.id, AsmGeom.point(local), 'Vertex', anchor: local);

/// Taps [world] in [a] and hands the pick to the armed command.
bool tapAt(AppState app, AssemblyModel a, Cam3 cam, Vec3 world) {
  final pick = pickAsmRef(a, cam, cam.project(world));
  expect(pick, isNotNull, reason: 'nothing under the tap at $world');
  return app.asmWorkFeaturePick(pick!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('the references move', () {
    test('a work plane built on a face follows that face when the component '
        'is moved', () {
      final o = occ('Bracket:1', const Vec3(40, 0, 0));
      final app = asmApp('ipc_m247_move', [o]);
      final a = app.currentAssembly!;
      final cam = frontCam();

      app.startWorkPlane(WorkPlaneKind.offset); // 10 mm, the default
      expect(app.asmPickWorkGeometry, isTrue);
      tapAt(app, a, cam, const Vec3(40, 0, 0));
      expect(a.workPlanes, hasLength(1));
      final w = a.workPlanes.first;
      final before = w.frame.origin;

      // The picked face is the box's +Z face — the one facing the eye — at
      // local z = +10, so an offset of +10 along its OUTWARD normal puts the
      // plane at world z = +20.
      expect(before.z, closeTo(20, 1e-6));

      // Now move the component 50 mm along +Z and re-derive. A baked frame
      // would still be at z = 20; this one is not.
      o.offset = const Vec3(40, 0, 50);
      resolveAsmWorkFeatures(a);
      expect(w.error, isNull);
      expect(w.frame.origin.z, closeTo(70, 1e-6),
          reason: 'the plane travels with the face it was built from');
      expect((w.frame.origin - before).length, closeTo(50, 1e-6));
    });

    test('and when the component is TURNED, the normal turns with it', () {
      final o = occ('Bracket:1', Vec3.zero);
      final app = asmApp('ipc_m247_turn', [o]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, Vec3.zero);
      final w = a.workPlanes.single;
      expect((w.frame.n - const Vec3(0, 0, 1)).length, lessThan(1e-6));

      // A quarter turn about Y takes +Z to +X.
      o.rot = Quat.axisAngle(const Vec3(0, 1, 0), 1.5707963267948966);
      resolveAsmWorkFeatures(a);
      expect((w.frame.n - const Vec3(1, 0, 0)).length, lessThan(1e-6),
          reason: 'a baked normal would still point along +Z');
    });

    test('solving the assembly re-derives them — the one funnel', () {
      final o = occ('Bracket:1', Vec3.zero);
      final app = asmApp('ipc_m247_solve', [o]);
      final a = app.currentAssembly!;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, frontCam(), Vec3.zero);
      final w = a.workPlanes.single;
      o.offset = const Vec3(0, 0, 25);
      // Nothing has asked for a re-solve yet, so the plane is still stale...
      expect(w.frame.origin.z, closeTo(20, 1e-6));
      // ...and the solve is what fixes it, which is the point: every command
      // that can move a component goes through it.
      app.solveCurrentAssembly();
      expect(w.frame.origin.z, closeTo(45, 1e-6));
    });

    test('a work AXIS and a work POINT follow too', () {
      // Built from stored references directly rather than through the picker:
      // this is a test of the RE-SOLVE, and facedBox carries no edges or
      // vertices to point at. The references are the shape the picker stores.
      final o = occ('Bracket:1', Vec3.zero);
      final a = AssemblyModel('A')..occurrences.add(o);
      final axis = AsmWorkAxis('Work Axis1', 1, '', Vec3.zero,
          const Vec3(1, 0, 0),
          method: WorkAxisMethod.throughTwoPoints,
          refs: [
            vertexRef(o, const Vec3(-10, 0, -10)),
            vertexRef(o, const Vec3(10, 0, -10)),
          ]);
      final pt = AsmWorkPoint('Work Point1', 2, '', Vec3.zero,
          method: WorkPointMethod.onVertex,
          refs: [vertexRef(o, const Vec3(10, 10, -10))]);
      a.workAxes.add(axis);
      a.workPoints.add(pt);
      resolveAsmWorkFeatures(a);
      expect(axis.error, isNull);
      expect((pt.at - const Vec3(10, 10, -10)).length, lessThan(1e-9));

      // Translate: the point goes with it, and so does the axis's own point.
      o.offset = const Vec3(0, 0, 30);
      resolveAsmWorkFeatures(a);
      expect(pt.at.z, closeTo(20, 1e-9));
      expect(axis.at.z, closeTo(20, 1e-9));

      // Turn: the axis DIRECTION turns too, which a baked one could not.
      o.rot = Quat.axisAngle(const Vec3(0, 0, 1), 1.5707963267948966);
      resolveAsmWorkFeatures(a);
      expect((axis.dir - const Vec3(0, 1, 0)).length, lessThan(1e-9),
          reason: 'the two points it runs through have swung a quarter turn');
      // And the SIGN the method gave it survives the re-solve: "Through Two
      // Points" runs first to second, and a revolve or a pattern that took
      // this axis inherited that choice.
      expect(axis.dir.dot(const Vec3(0, 1, 0)), greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('the anchor, not the record point', () {
    test('a plane built on a face lands on the face, not 250 mm beside it', () {
      final o = occ('Bracket:1', Vec3.zero);
      final app = asmApp('ipc_m247_anchor', [o]);
      final a = app.currentAssembly!;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, frontCam(), Vec3.zero);
      final origin = a.workPlanes.single.frame.origin;
      // facedBox's +Z face records its point at y = +250. Anything that used
      // the record point lands there; the anchor is on the face.
      expect(origin.y.abs(), lessThan(11),
          reason: 'the frame origin must sit on the picked face (M244)');
      expect(origin.x.abs(), lessThan(11));
    });

    test('"parallel through a point" measures from the picked face too', () {
      // The component sits clear of the origin so the assembly's own centre
      // point is out in the open and can be tapped — inside a box it would
      // lose the depth test to the face in front of it, which is right.
      final o = occ('Bracket:1', const Vec3(40, 0, 0));
      final app = asmApp('ipc_m247_parallel', [o]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      a.vis['cp'] = true;
      app.startWorkPlaneMethod(WorkPlaneMethod.parallelToPlaneThroughPoint);
      tapAt(app, a, cam, const Vec3(40, 0, 0)); // the face
      tapAt(app, a, cam, Vec3.zero); // the assembly's centre point
      final w = a.workPlanes.single;
      // The plane passes through the origin with the face's normal.
      expect(w.frame.origin.length, lessThan(1e-6));
      expect((w.frame.n - const Vec3(0, 0, 1)).length, lessThan(1e-6));
    });
  });

  // -------------------------------------------------------------------------
  group('the pick carries what it WAS', () {
    // AsmGeom reduces a circle, a cylinder and an edge all to "an axis",
    // because a constraint treats them alike. A work feature cannot.
    WorkRef bridge(AsmGeom g,
        {String label = 'X', double extent = 0, Vec3 anchor = Vec3.zero}) {
      final a = AssemblyModel('A');
      return workRefOf(
          a, AsmRef(kAssemblyOrigin, g, label, anchor: anchor, extent: extent))!;
    }

    test('a circular edge offers its centre, its axis AND its plane', () {
      final r = bridge(const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1),
          radius: 5, source: WorkRefSource.circle));
      expect(r.source, WorkRefSource.circle);
      expect(r.hasPoint && r.hasLine && r.hasPlane, isTrue);
      expect(solveWorkAxis(WorkAxisMethod.throughCenterOfCircularEdge, [r])
          .outcome, WorkPickOutcome.complete);
    });

    test('a CYLINDER refuses that method and carries its radius and side', () {
      final r = bridge(
          const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1),
              radius: 5, source: WorkRefSource.revolved),
          anchor: const Vec3(5, 0, 0));
      expect(r.source, WorkRefSource.revolved);
      expect(r.radius, 5);
      expect(r.hitAt, const Vec3(5, 0, 0),
          reason: 'M224 — the tangent methods choose the side by the tap');
      expect(solveWorkAxis(WorkAxisMethod.throughCenterOfCircularEdge, [r])
          .outcome, WorkPickOutcome.rejected);
      expect(solveWorkAxis(WorkAxisMethod.throughRevolvedFace, [r]).outcome,
          WorkPickOutcome.complete);
    });

    test('a straight edge comes back with its ENDS, so it has a midpoint', () {
      // AsmGeom stores an edge as a line; the anchor is its midpoint and the
      // extent its half-length, both recorded for the highlight. Together
      // they are the segment.
      final r = bridge(
          const AsmGeom.axis(Vec3(0, 0, 0), Vec3(1, 0, 0),
              source: WorkRefSource.edge),
          anchor: const Vec3(10, 0, 0),
          extent: 10);
      expect(r.hasPoint, isTrue);
      expect(r.point!.x, closeTo(10, 1e-9),
          reason: 'Inventor reaches "On ... Midpoint" by pointing at an edge');
    });

    test('a sphere and a torus keep their own methods apart', () {
      final s = bridge(const AsmGeom.point(Vec3(1, 2, 3),
          source: WorkRefSource.sphere));
      final t = bridge(const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1),
          source: WorkRefSource.torus));
      expect(solveWorkPoint(WorkPointMethod.centerOfSphere, [s]).outcome,
          WorkPickOutcome.complete);
      expect(solveWorkPoint(WorkPointMethod.centerOfSphere, [t]).outcome,
          WorkPickOutcome.rejected);
      expect(solveWorkPlane(WorkPlaneMethod.midplaneOfTorus, [t]).outcome,
          WorkPickOutcome.complete);
    });

    test('a reference written before M247 still reads, by its kind', () {
      // No `source` at all — a constraint saved by M242. A radius is the only
      // thing left that can tell a circle from a bare axis.
      final circle =
          bridge(const AsmGeom(AsmGeomKind.axis, Vec3.zero, Vec3(0, 0, 1),
              radius: 4));
      expect(circle.source, WorkRefSource.circle);
      final plane = bridge(
          const AsmGeom(AsmGeomKind.plane, Vec3(0, 0, 5), Vec3(0, 0, 1)));
      expect(plane.hasPlane, isTrue);
    });

    test('the picker records the source on a real face pick', () {
      final a = AssemblyModel('A')..occurrences.add(occ('Bracket:1', Vec3.zero));
      final cam = frontCam();
      final pick = pickAsmRef(a, cam, cam.project(Vec3.zero))!;
      expect(pick.ref.geom.source, WorkRefSource.plane);
      // ...and it survives the document.
      final back = AsmRef.fromJson(pick.ref.toJson())!;
      expect(back.geom.source, WorkRefSource.plane);
    });
  });

  // -------------------------------------------------------------------------
  group('one picker, two commands', () {
    test('a visible assembly work plane is offered back by pickAsmRef, '
        'BY ID', () {
      final o = occ('Bracket:1', Vec3.zero);
      final app = asmApp('ipc_m247_offer', [o]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, Vec3.zero);
      final w = a.workPlanes.single;

      // It sits at z = +20, NEARER the camera (which is on the +Z side) than
      // the box's +Z face at +10, so a tap in the middle lands on it.
      final pick = pickAsmRef(a, cam, cam.project(w.frame.origin));
      expect(pick, isNotNull);
      expect(pick!.ref.feature, w.id,
          reason: 'the reference names the feature, never bakes its frame');
      expect(pick.ref.isAssemblyOrigin, isTrue,
          reason: 'it belongs to the assembly, not to any component');

      // And the world geometry a constraint reads is the CURRENT one.
      o.offset = const Vec3(0, 0, 60);
      resolveAsmWorkFeatures(a);
      final live = worldGeomOf(a, pick.ref);
      expect(live.at.z, closeTo(w.frame.origin.z, 1e-6));
      expect(live.at.z, closeTo(80, 1e-6));
    });

    test('a hidden one is not offered — only what is drawn can be picked', () {
      final app = asmApp('ipc_m247_hidden', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, Vec3.zero);
      final w = a.workPlanes.single;
      expect(pickAsmRef(a, cam, cam.project(w.frame.origin))!.ref.feature,
          w.id);
      w.visible = false;
      expect(pickAsmRef(a, cam, cam.project(w.frame.origin))!.ref.feature,
          isNull);
    });

    test('a work plane can be built ON another work plane', () {
      final app = asmApp('ipc_m247_stack', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, Vec3.zero);
      final first = a.workPlanes.single;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, first.frame.origin);
      expect(a.workPlanes, hasLength(2));
      final second = a.workPlanes.last;
      expect(second.refs.single.feature, first.id);
      expect(second.frame.origin.z, closeTo(30, 1e-6));
      // ...and the chain re-derives in one pass, because creation order is
      // dependency order.
      a.occurrences.single.offset = const Vec3(0, 0, 100);
      resolveAsmWorkFeatures(a);
      expect(first.frame.origin.z, closeTo(120, 1e-6));
      expect(second.frame.origin.z, closeTo(130, 1e-6));
    });
  });

  // -------------------------------------------------------------------------
  group('the commands', () {
    test('with an assembly open they arm the ASSEMBLY, not a part', () {
      final app = asmApp('ipc_m247_route', [occ('Bracket:1', Vec3.zero)]);
      app.parts['Bracket'] = boxPart('Bracket');
      app.startWorkAxis(WorkAxisMethod.throughTwoPoints);
      expect(app.asmPickWorkGeometry, isTrue);
      expect(app.workFeaturePrompt, isNotEmpty);
      expect(app.parts['Bracket']!.workAxes, isEmpty);
    });

    test('the same entry twice cancels — every one of them is a toggle', () {
      final app = asmApp('ipc_m247_toggle', [occ('Bracket:1', Vec3.zero)]);
      app.startWorkPoint(WorkPointMethod.onVertex);
      expect(app.asmPickWorkGeometry, isTrue);
      app.startWorkPoint(WorkPointMethod.onVertex);
      expect(app.asmPickWorkGeometry, isFalse);
      expect(app.workFeaturePrompt, isEmpty);
    });

    test('arming one cancels the others', () {
      final app = asmApp('ipc_m247_excl', [occ('Bracket:1', Vec3.zero)]);
      app.startWorkAxis(WorkAxisMethod.auto);
      app.startWorkPoint(WorkPointMethod.auto);
      expect(app.workAxisArm, isNull);
      expect(app.workPointArm, WorkPointMethod.auto);
      app.startWorkPlane(WorkPlaneKind.midplane);
      expect(app.workPointArm, isNull);
      expect(app.workPlaneArm, WorkPlaneKind.midplane);
    });

    test('every Inventor method arms and prompts', () {
      final app = asmApp('ipc_m247_all', [occ('Bracket:1', Vec3.zero)]);
      void check(void Function() arm, String what) {
        arm();
        expect(app.asmPickWorkGeometry, isTrue, reason: what);
        expect(app.workFeaturePrompt, isNotEmpty, reason: what);
        app.cancelWorkFeature();
      }

      for (final m in WorkPlaneMethod.values) {
        check(() => app.startWorkPlaneMethod(m), 'plane $m');
      }
      for (final k in const [WorkPlaneKind.offset, WorkPlaneKind.midplane]) {
        check(() => app.startWorkPlane(k), 'plane $k');
      }
      for (final m in WorkAxisMethod.values) {
        check(() => app.startWorkAxis(m), 'axis $m');
      }
      for (final m in WorkPointMethod.values) {
        check(() => app.startWorkPoint(m), 'point $m');
      }
    });

    test('a mis-tap costs that tap and nothing else', () {
      final app = asmApp('ipc_m247_mistap', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      // "Through Center of Circular Edge" cannot take a planar face.
      app.startWorkAxis(WorkAxisMethod.throughCenterOfCircularEdge);
      final took = tapAt(app, a, cam, Vec3.zero);
      expect(took, isFalse);
      expect(a.workAxes, isEmpty);
      expect(app.asmPickWorkGeometry, isTrue,
          reason: 'the command stays armed — one bad tap is not a restart');
      expect(app.asmWorkFeaturePickCount, 0,
          reason: 'and the rejected pick is dropped, not kept');
    });

    test('an empty assembly shows its origin geometry for the duration', () {
      final app = asmApp('ipc_m247_origin', []);
      final a = app.currentAssembly!;
      expect(a.vis.values.any((v) => v), isFalse);
      app.startWorkPoint(WorkPointMethod.grounded);
      expect(a.vis.values.every((v) => v), isTrue,
          reason: 'otherwise there is nothing at all to point at');
      app.cancelWorkFeature();
      expect(a.vis.values.any((v) => v), isFalse);
    });

    test('what has been collected is what the viewport draws', () {
      final app = asmApp('ipc_m247_marks', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      app.startWorkPlaneMethod(WorkPlaneMethod.parallelToPlaneThroughPoint);
      expect(app.asmMarkers, isEmpty);
      tapAt(app, a, frontCam(), Vec3.zero);
      expect(app.asmMarkers, hasLength(1),
          reason: 'the first pick has to be visible before the second is made');
    });
  });

  // -------------------------------------------------------------------------
  group('the document', () {
    test('work features round-trip through the .pas, methods and picks and '
        'all', () {
      final app = asmApp('ipc_m247_json', [occ('Bracket:1', const Vec3(40, 0, 0))]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      // The point FIRST: a work plane spans the whole assembly and would then
      // be the nearest thing under a tap on the centre point, which is right
      // in the app and inconvenient in a test.
      a.vis['cp'] = true;
      app.startWorkPoint(WorkPointMethod.auto);
      tapAt(app, a, cam, Vec3.zero);
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, const Vec3(40, 0, 0));

      final back = AssemblyModel('Gearbox')
        ..loadJson(a.toJson().cast<String, dynamic>());
      // The occurrence has to be relinked before the features can be derived,
      // exactly as AppState does after reading a document.
      back.occurrences.single.part = boxPart('Bracket');
      expect(back.workPlanes, hasLength(1));
      expect(back.workPoints, hasLength(1));
      final w = back.workPlanes.single;
      expect(w.kind, WorkPlaneKind.offset);
      expect(w.offset, 10);
      expect(w.refs, hasLength(1));
      expect(w.refs.single.occurrence, 'Bracket:1');
      expect(w.refs.single.geom.source, WorkRefSource.plane);
      expect(back.workPoints.single.method, WorkPointMethod.auto);
      // And it re-derives to where it was saved.
      final wasAt = a.workPlanes.single.frame.origin;
      resolveAsmWorkFeatures(back);
      expect((back.workPlanes.single.frame.origin - wasAt).length,
          lessThan(1e-6));
    });

    test('an assembly with no work features writes no new keys', () {
      final a = AssemblyModel('Gearbox')..occurrences.add(occ('B:1', Vec3.zero));
      final j = a.toJson();
      expect(j.containsKey('workPlanes'), isFalse);
      expect(j.containsKey('workAxes'), isFalse);
      expect(j.containsKey('workPoints'), isFalse);
    });

    test('deleting a component takes the work features built on it, and '
        'whatever was built on those', () {
      final app = asmApp('ipc_m247_del', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, Vec3.zero);
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, a.workPlanes.single.frame.origin);
      expect(a.workPlanes, hasLength(2));
      a.remove(a.occurrences.single);
      expect(a.workPlanes, isEmpty,
          reason: 'a plane whose face has gone can never be re-derived, and '
              'nor can the plane built on that plane');
    });

    test('a re-solve that fails keeps the last good frame and says why', () {
      // Two parallel faces, a midplane between them, and then one component
      // turned so they are not parallel any more — which is exactly what a
      // drag can do momentarily.
      final b = occ('Base:1', const Vec3(60, 0, 40));
      final app = asmApp('ipc_m247_sick', [occ('Bracket:1', Vec3.zero), b]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      app.startWorkPlane(WorkPlaneKind.midplane);
      tapAt(app, a, cam, Vec3.zero);
      tapAt(app, a, cam, const Vec3(60, 0, 40));
      expect(a.workPlanes, hasLength(1));
      final w = a.workPlanes.single;
      final was = w.frame.origin;
      expect(was.z, closeTo(30, 1e-6),
          reason: 'halfway between the two picked faces, +10 and +50 — the '
              'faces on the side the camera is on');

      b.rot = Quat.axisAngle(const Vec3(1, 0, 0), 0.5);
      resolveAsmWorkFeatures(a);
      expect(w.error, isNotNull);
      expect(w.frame.origin, was,
          reason: 'a transient must not delete the user\'s work');
      // And the browser marks it the way it marks a sick constraint.
      expect(workFeatureError(w), isNotNull);

      // Put it back and it recovers on its own — no repair command needed.
      b.rot = Quat.identity;
      resolveAsmWorkFeatures(a);
      expect(w.error, isNull);
      expect(w.frame.origin.z, closeTo(30, 1e-6));
    });

    test('the browser lists them, with an eye and a selection', () {
      final app = asmApp('ipc_m247_rows', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, frontCam(), Vec3.zero);
      final rows = buildBrowserRows(app, expanded: {});
      final row = rows.firstWhere((r) => r.id == 'wp:${a.workPlanes.single.seq}');
      expect(row.label, a.workPlanes.single.name);
      expect(row.hasEye, isTrue);
      expect(row.selected, isTrue, reason: 'a new plane is selected');
    });

    test('the seq is shared across all three, so no two rows collide', () {
      final app = asmApp('ipc_m247_seq', [occ('Bracket:1', const Vec3(40, 0, 0))]);
      final a = app.currentAssembly!;
      final cam = frontCam();
      a.vis['cp'] = true;
      app.startWorkPoint(WorkPointMethod.onVertex);
      tapAt(app, a, cam, Vec3.zero); // the assembly's centre point
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, cam, const Vec3(40, 0, 0));
      expect(a.workPlanes, hasLength(1));
      expect(a.workPoints, hasLength(1));
      expect(a.workPlanes.single.seq, isNot(a.workPoints.single.seq));
      expect(a.nextWorkSeq(), greaterThan(a.workPoints.single.seq));
      // A plane, an axis and a point can never share a browser row id, which
      // is what the shared numbering is for.
      expect(a.workPlanes.single.id, isNot(a.workPoints.single.id));
    });
  });

  // -------------------------------------------------------------------------
  group('the ribbon reaches them', () {
    // The panel's own labels and enabled state are m240's; this is the wiring
    // behind them — that the flyout the assembly tab shows is the PART's list
    // and that picking an entry arms the assembly, not nothing.
    setUp(resetFlyoutCacheForTest);
    tearDown(() => L.set(kDe));

    testWidgets('the Plane flyout carries all thirteen Inventor methods and '
        'arms the assembly', (t) async {
      L.set(kEn);
      resetFlyoutCacheForTest();
      final app = asmApp('ipc_m247_fly', [occ('Bracket:1', Vec3.zero)]);
      await t.binding.setSurfaceSize(const Size(1500, 700));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(height: 120, child: Ribbon(app: app)))));
      await t.pump();

      // The drop chip under the Plane button, which is the only way in.
      // The drop chip sits directly under the button's label; the label is
      // the only thing in the panel with a name to find it by.
      final chip = t.getCenter(find.text('Plane')) + const Offset(0, 20);
      await t.tapAt(chip);
      await t.pump();
      // The test font is a monospaced stand-in whose glyphs are far wider than
      // the real one's, so "Tangent to Surface and Parallel to Plane" overflows
      // the flyout row here and fits on the device. Diagnostics about a font
      // that does not ship — the same drain m180 and m209 use.
      while (t.takeException() != null) {}
      for (final m in const [
        'Plane',
        'Offset from Plane',
        'Parallel to Plane through Point',
        'Midplane between Two Planes',
        'Midplane of Torus',
        'Angle to Plane around Edge',
        'Three Points',
        'Two Coplanar Edges',
        'Tangent to Surface through Edge',
        'Tangent to Surface through Point',
        'Tangent to Surface and Parallel to Plane',
        'Normal to Axis through Point',
        'Normal to Curve at Point',
      ]) {
        expect(find.text(m), findsWidgets, reason: 'flyout entry "$m"');
      }

      await t.tap(find.text('Three Points'));
      await t.pump();
      while (t.takeException() != null) {}
      expect(app.workPlaneMethodArm, WorkPlaneMethod.threePoints);
      expect(app.asmPickWorkGeometry, isTrue,
          reason: 'the flyout entry armed the ASSEMBLY command');
      // The prompt toast clears itself on a 4 s timer; let it run out before
      // the tree is torn down.
      await t.pump(const Duration(seconds: 5));
      await t.binding.setSurfaceSize(null);
    });
  });

  // -------------------------------------------------------------------------
  group('both renderers', () {
    test('a work plane rides the RealityKit scene payload beside the origin '
        'planes', () {
      final app = asmApp('ipc_m247_payload', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, frontCam(), Vec3.zero);
      final w = a.workPlanes.single;
      final planes = assemblyPlanePayloads(a);
      final mine = planes.firstWhere((p) => p['key'] == w.id);
      expect(mine['visible'], isTrue);
      // Framed by the assembly's extent, exactly as an origin plane is — not
      // a fixed square.
      expect((mine['uMax'] as double) - (mine['uMin'] as double),
          greaterThan(0));
      // The eye also travels on the LIGHT push, or toggling one would wait for
      // whatever next moved the scene signature.
      final light = buildAssemblyOverlaysPayload(a)['planes'] as List;
      expect(light.any((p) => (p as Map)['key'] == w.id), isTrue);
    });

    test('moving a work plane moves the scene signature', () {
      final app = asmApp('ipc_m247_sig', [occ('Bracket:1', Vec3.zero)]);
      final a = app.currentAssembly!;
      app.startWorkPlane(WorkPlaneKind.offset);
      tapAt(app, a, frontCam(), Vec3.zero);
      final before = assemblySceneSignature(a);
      a.occurrences.single.offset = const Vec3(0, 0, 5);
      resolveAsmWorkFeatures(a);
      expect(assemblySceneSignature(a), isNot(before),
          reason: 'a re-solve changes the quad, which the renderer cannot '
              'apply itself');
    });
  });
}
