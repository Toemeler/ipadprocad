// M229 — Angle to Plane around Edge: the twelfth of Inventor's thirteen work
// plane methods, and the one that needed a NUMBER as well as picks.
//
// M223 built the five that need nothing but picks and M224 the three that
// needed the side of the face you tapped. This one was left with its reason
// written down: "needs an angle to type. That is the offset field's twin
// (M169), a UI job rather than a geometric one."
//
// It turned out not to need a twin. A work plane carries at most ONE editable
// number — millimetres for an offset, degrees for an angle — so the field asks
// the PLANE which it is (WorkPlane.valueUnit) and there is still one field.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart';

import 'm56_part_test.dart' show FakeKernel;

/// The XY plane, and the X axis lying in it.
WorkRef _xy() => WorkRef.plane('XY Plane', Vec3.zero, const Vec3(0, 0, 1));
WorkRef _xEdge() =>
    WorkRef.line('Edge', const Vec3(-10, 0, 0), const Vec3(10, 0, 0));

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m229_');
  app.partKernel = FakeKernel();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _curveTests();

  group('M229 — the geometry', () {
    test('the normal turns about the edge by the angle asked for', () {
      final r = solveWorkPlane(
          WorkPlaneMethod.angleToPlaneAroundEdge, [_xy(), _xEdge()],
          angleDeg: 30);
      expect(r.outcome, WorkPickOutcome.complete, reason: r.message);
      final s = r.solution!;
      // Turning the +z normal about +x by 30 deg: z -> (0, -sin30, cos30) or
      // (0, +sin30, cos30) depending on the sense; either way the ANGLE to the
      // original is 30 and the edge stays in the plane.
      final cos = s.n.dot(const Vec3(0, 0, 1));
      expect(math.acos(cos) * 180 / math.pi, closeTo(30, 1e-9));
      expect(s.n.dot(const Vec3(1, 0, 0)).abs(), lessThan(1e-12),
          reason: 'the edge must still LIE in the plane after the turn');
      expect(s.n.length, closeTo(1, 1e-12));
    });

    test('the plane passes through the edge', () {
      final r = solveWorkPlane(
          WorkPlaneMethod.angleToPlaneAroundEdge, [_xy(), _xEdge()],
          angleDeg: 62);
      final s = r.solution!;
      for (final p in [const Vec3(-10, 0, 0), const Vec3(10, 0, 0)]) {
        expect((p - s.at).dot(s.n).abs(), lessThan(1e-9),
            reason: 'both ends of the edge are ON the new plane');
      }
    });

    test('zero degrees is the plane it came from', () {
      final r = solveWorkPlane(
          WorkPlaneMethod.angleToPlaneAroundEdge, [_xy(), _xEdge()],
          angleDeg: 0);
      expect(r.solution!.n.dot(const Vec3(0, 0, 1)), closeTo(1, 1e-12));
    });

    test('an edge NOT in the plane is refused, with the reason', () {
      final r = solveWorkPlane(WorkPlaneMethod.angleToPlaneAroundEdge, [
        _xy(),
        WorkRef.line('Edge', Vec3.zero, const Vec3(0, 0, 10)), // along z
      ]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('not parallel'));
    });

    test('it waits for the edge, and the def says both', () {
      final one = solveWorkPlane(
          WorkPlaneMethod.angleToPlaneAroundEdge, [_xy()]);
      expect(one.outcome, WorkPickOutcome.needMore);
      expect(one.message, contains('edge'));

      final two = solveWorkPlane(
          WorkPlaneMethod.angleToPlaneAroundEdge, [_xy(), _xEdge()],
          angleDeg: 45);
      expect(two.solution!.def, contains('45.00 deg'));
      expect(two.solution!.def, contains('XY Plane'));
      expect(two.solution!.def, contains('Edge'));
    });

    test('the label and arity join the others', () {
      expect(workPlaneMethodLabel(WorkPlaneMethod.angleToPlaneAroundEdge),
          'Angle to Plane around Edge');
      expect(workPlaneArity(WorkPlaneMethod.angleToPlaneAroundEdge), 2);
    });
  });

  group('M229 — the plane keeps its number', () {
    test('anglePlaneFrame turns the whole frame, not just the normal', () {
      final f = anglePlaneFrame(
          planeFrame('xy'), Vec3.zero, const Vec3(1, 0, 0), 90);
      expect(f.n.dot(f.u).abs(), lessThan(1e-12));
      expect(f.n.dot(f.v).abs(), lessThan(1e-12));
      expect(f.u.length, closeTo(1, 1e-12));
      // u lay along x and pivots ABOUT x, so it does not move.
      expect(f.u.dot(const Vec3(1, 0, 0)).abs(), closeTo(1, 1e-9));
    });

    test('setAngle moves an existing plane and re-words it', () {
      final wp = WorkPlane(
        'Work Plane1',
        1,
        WorkPlaneKind.angle,
        '45.00 deg from XY Plane',
        anglePlaneFrame(planeFrame('xy'), Vec3.zero, const Vec3(1, 0, 0), 45),
        base: planeFrame('xy'),
        axisAt: Vec3.zero,
        axisDir: const Vec3(1, 0, 0),
        angle: 45,
      );
      expect(wp.angleEditable, isTrue);
      expect(wp.valueEditable, isTrue);
      expect(wp.valueUnit, 'deg');
      expect(wp.value, 45);

      expect(wp.setAngle(20), isTrue);
      expect(wp.angle, 20);
      expect(
          math.acos(wp.frame.n.dot(const Vec3(0, 0, 1))) * 180 / math.pi,
          closeTo(20, 1e-9));
      expect(wp.def, contains('20.00 deg'));
    });

    test('an offset plane still speaks millimetres', () {
      final wp = WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
          'Offset 10.00 mm from XY', offsetPlaneFrame(planeFrame('xy'), 10),
          base: planeFrame('xy'), offset: 10);
      expect(wp.valueUnit, 'mm');
      expect(wp.value, 10);
      expect(wp.angleEditable, isFalse,
          reason: 'and setAngle must not touch it');
      expect(wp.setAngle(30), isFalse);
    });

    test('a constructed plane carries no number at all', () {
      final wp = WorkPlane('Work Plane1', 1, WorkPlaneKind.constructed,
          'Through A, B and C', planeFrame('xy'));
      expect(wp.valueEditable, isFalse);
      expect(wp.value, isNull);
    });

    test('round-trips through JSON with its pivot', () {
      final wp = WorkPlane(
        'Work Plane2',
        3,
        WorkPlaneKind.angle,
        '45.00 deg from XY Plane',
        anglePlaneFrame(planeFrame('xy'), Vec3.zero, const Vec3(1, 0, 0), 45),
        base: planeFrame('xy'),
        axisAt: const Vec3(1, 2, 3),
        axisDir: const Vec3(1, 0, 0),
        angle: 45,
      );
      final back = WorkPlane.fromJson(wp.toJson())!;
      expect(back.kind, WorkPlaneKind.angle);
      expect(back.angle, 45);
      expect(back.axisAt!.y, 2);
      expect(back.axisDir!.x, 1);
      expect(back.angleEditable, isTrue,
          reason: 'still re-typable after a save and load');
    });
  });

  group('M229 — the command', () {
    test('two picks build it, and the value field opens on it', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.angleToPlaneAroundEdge);
      expect(app.workFeaturePick(_xy()), isTrue);
      expect(app.currentPart!.workPlanes, isEmpty, reason: 'one pick is not two');
      expect(app.workFeaturePick(_xEdge()), isTrue);

      final wp = app.currentPart!.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.angle);
      expect(wp.angle, 45, reason: 'the angle it starts at');
      expect(wp.angleEditable, isTrue);
      expect(app.selectedWorkPlane, same(wp));
      expect(app.workPlaneOffsetEditing, isTrue,
          reason: 'dynamic input: the number is there the moment the plane is');
    });

    test('typing a new angle moves it, and the next one remembers', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.angleToPlaneAroundEdge);
      app.workFeaturePick(_xy());
      app.workFeaturePick(_xEdge());

      expect(app.commitWorkPlaneOffset('30 deg'), isTrue);
      final wp = app.currentPart!.workPlanes.single;
      expect(wp.angle, 30);
      expect(app.workPlaneAngle, 30,
          reason: 'the next plane starts from what was last used — the same '
              'rule M162 gave the offset');
      expect(app.workPlaneOffsetEditing, isFalse, reason: 'the field closes');
    });

    test('a plane through three points is NOT re-typable', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.threePoints);
      app.workFeaturePick(WorkRef.point('A', Vec3.zero));
      app.workFeaturePick(WorkRef.point('B', const Vec3(10, 0, 0)));
      app.workFeaturePick(WorkRef.point('C', const Vec3(0, 10, 0)));
      final wp = app.currentPart!.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.constructed);
      expect(wp.valueEditable, isFalse);
      expect(app.workPlaneOffsetEditing, isFalse,
          reason: 'no number, no field');
    });
  });
}

// ---------------------------------------------------------------------------
// M231 — Normal to Curve at Point: the thirteenth and last
// ---------------------------------------------------------------------------

void _curveTests() {
  group('M231 — Normal to Curve at Point', () {
    WorkRef curve() => WorkRef.curveAt(
        'Curve', const Vec3(5, 0, 0), const Vec3(0, 1, 0));

    test('the tangent IS the normal, and the point is on the plane', () {
      final r =
          solveWorkPlane(WorkPlaneMethod.normalToCurveAtPoint, [curve()]);
      expect(r.outcome, WorkPickOutcome.complete, reason: r.message);
      final s = r.solution!;
      expect(s.n.dot(const Vec3(0, 1, 0)), closeTo(1, 1e-12));
      expect((const Vec3(5, 0, 0) - s.at).dot(s.n).abs(), lessThan(1e-12));
      expect(s.def, 'Normal to Curve');
    });

    test('the tangent is normalised even when the sample is not', () {
      // The picker hands over a SEGMENT of the sampled curve, whose length is
      // whatever the sampling made it.
      final r = solveWorkPlane(WorkPlaneMethod.normalToCurveAtPoint,
          [WorkRef.curveAt('Curve', Vec3.zero, const Vec3(0, 0, 17))]);
      expect(r.solution!.n.length, closeTo(1, 1e-12));
    });

    test('an EDGE is not a curve, even though it offers the same two things',
        () {
      // A straight edge carries a point (its midpoint) and a direction too.
      // What separates them is what they MEAN, which is the source.
      final r = solveWorkPlane(WorkPlaneMethod.normalToCurveAtPoint,
          [WorkRef.line('Edge', Vec3.zero, const Vec3(10, 0, 0))]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('not a curve'));
    });

    test('one pick is the whole method', () {
      expect(workPlaneArity(WorkPlaneMethod.normalToCurveAtPoint), 1);
      expect(workPlaneMethodLabel(WorkPlaneMethod.normalToCurveAtPoint),
          'Normal to Curve at Point');
      expect(workPlanePrompt(WorkPlaneMethod.normalToCurveAtPoint, 0),
          contains('curve'));
    });

    test('every one of the thirteen flyout entries now leads somewhere', () {
      // The Plane flyout has thirteen entries. TEN of them are these methods;
      // the other three are "Plane" and "Offset from Plane" (both the offset
      // flow, M151/M157) and "Midplane between Two Planes" — those two keep
      // their own flow because they are not pick-only: one is a drag with a
      // live distance and an editable base, the other collects PlaneFrames.
      expect(WorkPlaneMethod.values.length, 10,
          reason: 'offset and midplane are WorkPlaneKind, not a method');
      for (final m in WorkPlaneMethod.values) {
        expect(workPlaneMethodLabel(m), isNotEmpty);
        expect(workPlanePrompt(m, 0), isNotEmpty);
        expect(workPlaneArity(m), inInclusiveRange(1, 3));
      }
    });

    test('it commits through the same path as the others', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.normalToCurveAtPoint);
      expect(app.workFeaturePick(curve()), isTrue);

      final wp = app.currentPart!.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.constructed,
          reason: 'nothing about it can be re-typed');
      expect(wp.def, 'Normal to Curve');
      expect(wp.frame.n.dot(const Vec3(0, 1, 0)).abs(), closeTo(1, 1e-9));
      expect(app.workPlaneOffsetEditing, isFalse);
    });
  });
}
