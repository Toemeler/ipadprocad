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
