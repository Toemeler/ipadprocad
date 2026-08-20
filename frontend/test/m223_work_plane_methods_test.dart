// M223 — the rest of Inventor's Work Plane list, on M215's machinery.
//
// The Plane flyout has carried Inventor's thirteen entries since M56. Three
// were real: the generic "Plane" and "Offset from Plane" (M151/M157, both the
// offset flow) and "Midplane between Two Planes". The other ten did nothing at
// all — the exact shape M216 spent a commit removing from the part ribbon.
//
// Five of them are pure geometry and need nothing but picks, so they run on
// the WorkRef machinery that already carries Work Axis and Work Point. The
// other five say why they are not built instead of staying silent, because a
// control that does nothing reads as broken (M157).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart';
import 'package:prototype/l10n/l.dart';

import 'm56_part_test.dart' show FakeKernel;

WorkRef _pt(String label, double x, double y, double z) =>
    WorkRef.point(label, Vec3(x, y, z));

WorkRef _line(String label, Vec3 a, Vec3 b) => WorkRef.line(label, a, b);

WorkRef _plane(String label, Vec3 at, Vec3 n) =>
    WorkRef.plane(label, at, n);

WorkPlaneSolution _solve(WorkPlaneMethod m, List<WorkRef> refs) {
  final r = solveWorkPlane(m, refs);
  expect(r.outcome, WorkPickOutcome.complete,
      reason: 'expected a plane, got: ${r.message}');
  return r.solution!;
}

/// The plane really does contain [p].
void _contains(WorkPlaneSolution s, Vec3 p) {
  expect((p - s.at).dot(s.n).abs(), lessThan(1e-9),
      reason: 'the point must lie ON the plane, not near it');
}

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m223_');
  app.partKernel = FakeKernel();
  return app;
}

void main() {

  // M234 — this file runs in ENGLISH, deliberately.
  //
  // What it pins is which refusal fires and what it names — "straight",
  // "skew", "7.000", "not a toroidal face". That is geometry, not
  // presentation, and every one of those assertions stays exactly as
  // meaningful when it is read in one fixed language. Translating the
  // fragments into German would have hardcoded German into a geometry test
  // and bought nothing: the German strings are covered by
  // l10n_completeness_test (present, non-empty, same placeholders) and
  // l10n_length_test (short enough to fit).
  setUpAll(() => L.set(kEn));
  tearDownAll(L.resetForTest);
  group('M223 — Three Points', () {
    test('the plane contains all three', () {
      final s = _solve(WorkPlaneMethod.threePoints, [
        _pt('A', 0, 0, 0),
        _pt('B', 10, 0, 0),
        _pt('C', 0, 10, 5),
      ]);
      _contains(s, const Vec3(0, 0, 0));
      _contains(s, const Vec3(10, 0, 0));
      _contains(s, const Vec3(0, 10, 5));
      expect(s.n.length, closeTo(1, 1e-12), reason: 'a unit normal');
      expect(s.def, 'Through A, B and C');
    });

    test('it asks for the second and third, and only then builds', () {
      final one = solveWorkPlane(WorkPlaneMethod.threePoints, [_pt('A', 0, 0, 0)]);
      expect(one.outcome, WorkPickOutcome.needMore);
      final two = solveWorkPlane(WorkPlaneMethod.threePoints,
          [_pt('A', 0, 0, 0), _pt('B', 1, 0, 0)]);
      expect(two.outcome, WorkPickOutcome.needMore);
      expect(two.message, contains('third'));
    });

    test('three points in a line are refused, not guessed at', () {
      final r = solveWorkPlane(WorkPlaneMethod.threePoints, [
        _pt('A', 0, 0, 0),
        _pt('B', 5, 5, 5),
        _pt('C', 10, 10, 10),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('line'),
          reason: 'an infinity of planes contains them, which is not an answer');
    });

    test('a pick with no point is refused by name', () {
      final r = solveWorkPlane(WorkPlaneMethod.threePoints, [
        WorkRef.revolvedFace('Cylindrical Face', Vec3.zero, const Vec3(0, 0, 1)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('Cylindrical Face'));
    });
  });

  group('M223 — Parallel to Plane through Point', () {
    test('same normal, through the point', () {
      final s = _solve(WorkPlaneMethod.parallelToPlaneThroughPoint, [
        _plane('XY Plane', Vec3.zero, const Vec3(0, 0, 1)),
        _pt('Vertex', 3, 4, 12),
      ]);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-12));
      _contains(s, const Vec3(3, 4, 12));
      expect(s.at.z, closeTo(12, 1e-12), reason: '12 mm above XY');
      expect(s.def, 'Parallel to XY Plane through Vertex');
    });

    test('either order works — the picks are not interchangeable, the '
        'ORDER is', () {
      final s = _solve(WorkPlaneMethod.parallelToPlaneThroughPoint, [
        _pt('Vertex', 3, 4, 12),
        _plane('XY Plane', Vec3.zero, const Vec3(0, 0, 1)),
      ]);
      _contains(s, const Vec3(3, 4, 12));
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-12));
    });

    test('two planes and no point cannot build', () {
      final r = solveWorkPlane(WorkPlaneMethod.parallelToPlaneThroughPoint, [
        _plane('XY Plane', Vec3.zero, const Vec3(0, 0, 1)),
        _plane('XZ Plane', Vec3.zero, const Vec3(0, 1, 0)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
    });
  });

  group('M223 — Normal to Axis through Point', () {
    test('the axis direction IS the normal', () {
      final s = _solve(WorkPlaneMethod.normalToAxisThroughPoint, [
        _line('Edge', const Vec3(0, 0, 0), const Vec3(0, 0, 20)),
        _pt('Vertex', 1, 2, 7),
      ]);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-12));
      _contains(s, const Vec3(1, 2, 7));
      expect(s.def, 'Normal to Edge through Vertex');
    });

    test('an edge alone waits for the point', () {
      final r = solveWorkPlane(WorkPlaneMethod.normalToAxisThroughPoint,
          [_line('Edge', Vec3.zero, const Vec3(0, 0, 20))]);
      expect(r.outcome, WorkPickOutcome.needMore);
      expect(r.message, contains('point'));
    });
  });

  group('M223 — Two Coplanar Edges', () {
    test('two edges that meet give the plane they span', () {
      final s = _solve(WorkPlaneMethod.twoCoplanarEdges, [
        _line('Edge1', const Vec3(0, 0, 4), const Vec3(10, 0, 4)),
        _line('Edge2', const Vec3(0, 0, 4), const Vec3(0, 10, 4)),
      ]);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-12));
      _contains(s, const Vec3(10, 0, 4));
      _contains(s, const Vec3(0, 10, 4));
    });

    test('two PARALLEL edges span a plane too', () {
      final s = _solve(WorkPlaneMethod.twoCoplanarEdges, [
        _line('Edge1', const Vec3(0, 0, 0), const Vec3(10, 0, 0)),
        _line('Edge2', const Vec3(0, 5, 0), const Vec3(10, 5, 0)),
      ]);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-12));
      _contains(s, const Vec3(10, 5, 0));
    });

    test('skew edges are refused WITH the gap', () {
      final r = solveWorkPlane(WorkPlaneMethod.twoCoplanarEdges, [
        _line('Edge1', const Vec3(0, 0, 0), const Vec3(10, 0, 0)),
        _line('Edge2', const Vec3(0, 0, 7), const Vec3(0, 10, 7)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('skew'));
      expect(r.message, contains('7.000'),
          reason: 'a refusal that carries the measurement, as M215 set out');
    });

    test('the same line twice is refused', () {
      final r = solveWorkPlane(WorkPlaneMethod.twoCoplanarEdges, [
        _line('Edge1', const Vec3(0, 0, 0), const Vec3(10, 0, 0)),
        _line('Edge2', const Vec3(2, 0, 0), const Vec3(8, 0, 0)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('same line'));
    });
  });

  group('M223 — Midplane of Torus', () {
    test('the torus axis is the normal, its centre the origin', () {
      final s = _solve(WorkPlaneMethod.midplaneOfTorus, [
        WorkRef.torus('Toroidal Face', const Vec3(1, 2, 3), const Vec3(0, 1, 0)),
      ]);
      expect(s.at.x, closeTo(1, 1e-12));
      expect(s.at.y, closeTo(2, 1e-12));
      expect(s.at.z, closeTo(3, 1e-12));
      expect(s.n.cross(const Vec3(0, 1, 0)).length, lessThan(1e-12));
      expect(s.def, 'Midplane of Toroidal Face');
    });

    test('a cylinder is not a torus', () {
      final r = solveWorkPlane(WorkPlaneMethod.midplaneOfTorus, [
        WorkRef.revolvedFace(
            'Cylindrical Face', Vec3.zero, const Vec3(0, 0, 1)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('not a toroidal face'));
    });
  });

  group('M223 — arity and labels', () {
    test('every method has Inventor’s own label and a sane arity', () {
      for (final m in WorkPlaneMethod.values) {
        expect(workPlaneMethodLabel(m), isNotEmpty);
        expect(workPlaneArity(m), inInclusiveRange(1, 3));
        expect(workPlanePrompt(m, 0), isNotEmpty);
      }
      expect(workPlaneMethodLabel(WorkPlaneMethod.threePoints), 'Three Points');
      expect(workPlaneArity(WorkPlaneMethod.threePoints), 3);
      expect(workPlaneArity(WorkPlaneMethod.midplaneOfTorus), 1);
    });
  });

  group('M223 — the command in the app', () {
    test('arming is a toggle and takes the tap', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      expect(app.workPlaneMethodArm, WorkPlaneMethod.threePoints);
      expect(app.pickWorkGeometry, isTrue,
          reason: 'the viewport has to offer geometry while it is armed');
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      expect(app.workPlaneMethodArm, isNull, reason: 'the same entry cancels');
      expect(app.pickWorkGeometry, isFalse);
    });

    test('three picks build a plane, and the browser says how', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      expect(app.workFeaturePick(_pt('A', 0, 0, 0)), isTrue);
      expect(app.workFeaturePick(_pt('B', 10, 0, 0)), isTrue);
      expect(p.workPlanes, isEmpty, reason: 'two points are not a plane');
      expect(app.workFeaturePick(_pt('C', 0, 10, 0)), isTrue);

      expect(p.workPlanes.length, 1);
      final wp = p.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.constructed);
      expect(wp.def, 'Through A, B and C');
      expect(wp.offsetEditable, isFalse,
          reason: 'nothing about it can be re-typed');
      // The frame is a real basis on that plane.
      expect(wp.frame.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9));
      expect(wp.frame.u.dot(wp.frame.n).abs(), lessThan(1e-12));
      expect(wp.frame.v.dot(wp.frame.n).abs(), lessThan(1e-12));
      expect(app.workPlaneMethodArm, isNull, reason: 'the command is done');
    });

    test('a bad pick costs that tap and nothing else', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.midplaneOfTorus);
      expect(
          app.workFeaturePick(WorkRef.sphere('Spherical Face', Vec3.zero)),
          isFalse);
      expect(app.workPlaneMethodArm, WorkPlaneMethod.midplaneOfTorus,
          reason: 'still armed — one mis-tap must not end the command');
      expect(
          app.workFeaturePick(
              WorkRef.torus('Toroidal Face', Vec3.zero, const Vec3(0, 0, 1))),
          isTrue);
      expect(app.currentPart!.workPlanes.length, 1);
    });

    test('arming a plane method cancels an armed axis', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkAxis(WorkAxisMethod.throughTwoPoints);
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      expect(app.workAxisArm, isNull,
          reason: 'three commands competing for one tap is not a UI');
      expect(app.workPlaneMethodArm, WorkPlaneMethod.threePoints);
    });
  });

  // -------------------------------------------------------------------------
  // M224 — the three that needed the side of the face you picked
  // -------------------------------------------------------------------------

  WorkRef cyl({Vec3 hitAt = const Vec3(5, 0, 3), double radius = 5}) =>
      WorkRef.cylinder('Cylindrical Face', Vec3.zero, const Vec3(0, 0, 1),
          radius: radius, hitAt: hitAt);

  group('M224 — Tangent to Surface through Point', () {
    test('the plane touches the cylinder AND contains the point', () {
      // Point out on +x, tapped round on -y: of the two tangents, the one on
      // the tapped side.
      final s = _solve(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        cyl(hitAt: const Vec3(0, -5, 3)),
        _pt('Vertex', 20, 0, 0),
      ]);
      _contains(s, const Vec3(20, 0, 0));
      // Tangency: the plane's distance from the axis is exactly the radius.
      expect(s.at.dot(s.n), closeTo(5, 1e-9));
      expect(s.n.z.abs(), lessThan(1e-12),
          reason: 'a tangent normal is perpendicular to the axis');
      expect(s.n.y, lessThan(0), reason: 'the side that was tapped');
    });

    test('the other side of the same cylinder gives the other plane', () {
      final s = _solve(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        cyl(hitAt: const Vec3(0, 5, 3)),
        _pt('Vertex', 20, 0, 0),
      ]);
      _contains(s, const Vec3(20, 0, 0));
      expect(s.n.y, greaterThan(0));
    });

    test('a point ON the surface needs no side at all', () {
      final s = _solve(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        cyl(hitAt: const Vec3(5, 0, 3)),
        _pt('Vertex', 5, 0, 8),
      ]);
      _contains(s, const Vec3(5, 0, 8));
      expect(s.n.x, closeTo(1, 1e-9));
    });

    test('a point INSIDE the cylinder is refused', () {
      final r = solveWorkPlane(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        cyl(),
        _pt('Vertex', 1, 0, 0),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('inside'));
    });

    test('a tap that says nothing about the side is refused, not guessed', () {
      // Straight towards the point: both tangents are equidistant from it, so
      // the pick carries no side. A coin flip belongs discarded (M158).
      final r = solveWorkPlane(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        cyl(hitAt: const Vec3(5, 0, 3)),
        _pt('Vertex', 20, 0, 0),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('side'));
    });

    test('a face with no radius is not a cylinder', () {
      final r = solveWorkPlane(WorkPlaneMethod.tangentToSurfaceThroughPoint, [
        WorkRef.revolvedFace('Conical Face', Vec3.zero, const Vec3(0, 0, 1)),
        _pt('Vertex', 20, 0, 0),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('cylindrical'));
    });
  });

  group('M224 — Tangent to Surface through Edge', () {
    test('an edge lying along the cylinder gives one plane, no side needed',
        () {
      final s = _solve(WorkPlaneMethod.tangentToSurfaceThroughEdge, [
        cyl(),
        _line('Edge', const Vec3(5, 0, 0), const Vec3(5, 0, 20)),
      ]);
      expect(s.n.x, closeTo(1, 1e-9));
      expect(s.at.dot(s.n), closeTo(5, 1e-9));
      _contains(s, const Vec3(5, 0, 20));
    });

    test('an edge off the surface is refused WITH the distance', () {
      final r = solveWorkPlane(WorkPlaneMethod.tangentToSurfaceThroughEdge, [
        cyl(),
        _line('Edge', const Vec3(9, 0, 0), const Vec3(9, 0, 20)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('4.000'));
    });

    test('an edge across the axis is refused', () {
      final r = solveWorkPlane(WorkPlaneMethod.tangentToSurfaceThroughEdge, [
        cyl(),
        _line('Edge', const Vec3(5, 0, 0), const Vec3(5, 20, 0)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('not parallel'));
    });
  });

  group('M224 — Tangent to Surface and Parallel to Plane', () {
    test('the tangent on the tapped side, parallel to the plane', () {
      final s = _solve(WorkPlaneMethod.tangentToSurfaceParallelToPlane, [
        cyl(hitAt: const Vec3(0, -5, 2)),
        _plane('XZ Plane', Vec3.zero, const Vec3(0, 1, 0)),
      ]);
      expect(s.n.cross(const Vec3(0, 1, 0)).length, lessThan(1e-12),
          reason: 'parallel means the same normal, up to sign');
      expect(s.n.y, closeTo(-1, 1e-12), reason: 'the tapped side');
      expect(s.at.dot(s.n), closeTo(5, 1e-9), reason: 'and it touches');
    });

    test('a plane the axis is not parallel to has no tangent parallel to it',
        () {
      final r =
          solveWorkPlane(WorkPlaneMethod.tangentToSurfaceParallelToPlane, [
        cyl(),
        _plane('XY Plane', Vec3.zero, const Vec3(0, 0, 1)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('not parallel to the axis'));
    });

    test('a tap that straddles both sides is refused', () {
      final r =
          solveWorkPlane(WorkPlaneMethod.tangentToSurfaceParallelToPlane, [
        cyl(hitAt: const Vec3(5, 0, 2)), // 90 degrees from the plane normal
        _plane('XZ Plane', Vec3.zero, const Vec3(0, 1, 0)),
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('side'));
    });
  });

  group('M223 — work planes get a FREE name, not a count', () {
    test('deleting one and making another never repeats a name', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      for (var i = 0; i < 3; i++) {
        app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
        app.workFeaturePick(_pt('A', 0, 0, i.toDouble()));
        app.workFeaturePick(_pt('B', 10, 0, i.toDouble()));
        app.workFeaturePick(_pt('C', 0, 10, i.toDouble()));
      }
      expect(p.workPlanes.map((w) => w.name).toList(),
          ['Work Plane1', 'Work Plane2', 'Work Plane3']);

      p.workPlanes.removeAt(1); // Work Plane2 is gone
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      app.workFeaturePick(_pt('A', 0, 0, 9));
      app.workFeaturePick(_pt('B', 10, 0, 9));
      app.workFeaturePick(_pt('C', 0, 10, 9));
      final names = p.workPlanes.map((w) => w.name).toList();
      expect(names.toSet().length, names.length,
          reason: 'the old rule counted the list and handed out Work Plane3 '
              'a second time — the M155 bug, in the one place it survived');
    });
  });
}
