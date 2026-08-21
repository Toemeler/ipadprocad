// M215 — Work Axis and Work Point.
//
// The whole point of putting the geometry in work_features.dart is that it can
// be pinned here, on host, without a device or a kernel: every Inventor
// creation method is arithmetic over a handful of picks, and arithmetic either
// lands on the right point or it does not.
//
// The cases are chosen so a WRONG answer cannot pass. "Intersection of two
// planes" is checked by asserting the result lies on BOTH planes, not by
// comparing it to a number I copied out of my own implementation.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart';
import 'package:prototype/l10n/l.dart';

const _x = Vec3(1, 0, 0);
const _y = Vec3(0, 1, 0);
const _z = Vec3(0, 0, 1);

/// Signed distance of [p] from the plane through [at] with normal [n].
double planeGap(Vec3 p, Vec3 at, Vec3 n) => (p - at).dot(n.normalized());

/// Distance from [p] to the line through [at] along [dir].
double lineGap(Vec3 p, Vec3 at, Vec3 dir) =>
    (p - at).cross(dir.normalized()).length;

WorkAxisSolution axisOf(WorkAttempt<WorkAxisSolution> a) {
  expect(a.outcome, WorkPickOutcome.complete, reason: a.message);
  return a.solution!;
}

WorkPointSolution pointOf(WorkAttempt<WorkPointSolution> a) {
  expect(a.outcome, WorkPickOutcome.complete, reason: a.message);
  return a.solution!;
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
  group('geometry primitives', () {
    test('two planes meet on a line that lies on both', () {
      // x = 5 and y = 3 meet on the vertical line through (5, 3, 0).
      final r = planePlaneLine(_x, 5, _y, 3)!;
      expect(planeGap(r.$1, const Vec3(5, 0, 0), _x).abs(), lessThan(1e-12));
      expect(planeGap(r.$1, const Vec3(0, 3, 0), _y).abs(), lessThan(1e-12));
      expect(r.$2.cross(_z).length, lessThan(1e-12),
          reason: 'the line runs along z');
    });

    test('parallel planes have no intersection line', () {
      expect(planePlaneLine(_z, 0, _z, 10), isNull);
      // anti-parallel counts as parallel too
      expect(planePlaneLine(_z, 0, const Vec3(0, 0, -1), 10), isNull);
    });

    test('a line meets a plane where it should', () {
      final p = linePlanePoint(Vec3.zero, _z, _z, 7)!;
      expect((p - const Vec3(0, 0, 7)).length, lessThan(1e-12));
      // parallel to the plane: no answer, and specifically not a guess
      expect(linePlanePoint(Vec3.zero, _x, _z, 7), isNull);
      // lying IN the plane is an infinity of answers, which is not an answer
      expect(linePlanePoint(Vec3.zero, _x, _z, 0), isNull);
    });

    test('three planes meet at one point', () {
      final p = threePlanePoint(_x, 2, _y, 3, _z, 4)!;
      expect((p - const Vec3(2, 3, 4)).length, lessThan(1e-12));
    });

    test('three planes through a common line have no single point', () {
      // x=0, y=0 and the 45-degree plane between them all contain the z axis.
      final diag = const Vec3(1, -1, 0).normalized();
      expect(threePlanePoint(_x, 0, _y, 0, diag, 0), isNull);
    });

    test('two parallel planes and a third still have no point', () {
      expect(threePlanePoint(_z, 0, _z, 5, _x, 0), isNull);
    });

    test('closest approach finds a real crossing and measures a miss', () {
      // crossing at the origin
      final hit = lineLineClosest(Vec3.zero, _x, Vec3.zero, _y)!;
      expect(hit.$3, lessThan(1e-12));
      // skew by exactly 4 mm in z
      final skew =
          lineLineClosest(Vec3.zero, _x, const Vec3(0, 0, 4), _y)!;
      expect(skew.$3, closeTo(4, 1e-12));
      // parallel: no unique nearest pair at all
      expect(lineLineClosest(Vec3.zero, _x, const Vec3(0, 1, 0), _x), isNull);
    });
  });

  group('work axis — every Inventor method', () {
    test('On Line or Edge is collinear with the edge', () {
      final e = WorkRef.line('Edge', const Vec3(1, 2, 3), const Vec3(1, 2, 9));
      final a = axisOf(solveWorkAxis(WorkAxisMethod.onLineOrEdge, [e]));
      expect(lineGap(const Vec3(1, 2, 50), a.at, a.dir), lessThan(1e-12));
      expect(a.dir.cross(_z).length, lessThan(1e-12));
    });

    test('On Line or Edge refuses a circular edge', () {
      final c = WorkRef.circle('Circular Edge', Vec3.zero, _z);
      final r = solveWorkAxis(WorkAxisMethod.onLineOrEdge, [c]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('straight'));
    });

    test('Intersection of Two Planes lies on both planes', () {
      final p1 = WorkRef.plane('Face A', const Vec3(5, 0, 0), _x);
      final p2 = WorkRef.plane('Face B', const Vec3(0, 3, 0), _y);
      final a = axisOf(
          solveWorkAxis(WorkAxisMethod.intersectionOfTwoPlanes, [p1, p2]));
      expect(planeGap(a.at, const Vec3(5, 0, 0), _x).abs(), lessThan(1e-12));
      expect(planeGap(a.at, const Vec3(0, 3, 0), _y).abs(), lessThan(1e-12));
      expect(a.def, 'Intersection of Face A and Face B');
    });

    test('Intersection of Two Planes refuses parallel faces', () {
      final p1 = WorkRef.plane('Top', const Vec3(0, 0, 10), _z);
      final p2 = WorkRef.plane('Bottom', Vec3.zero, const Vec3(0, 0, -1));
      final r =
          solveWorkAxis(WorkAxisMethod.intersectionOfTwoPlanes, [p1, p2]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('parallel'));
    });

    test('Intersection of Two Planes asks for the second pick', () {
      final p1 = WorkRef.plane('Top', Vec3.zero, _z);
      final r = solveWorkAxis(WorkAxisMethod.intersectionOfTwoPlanes, [p1]);
      expect(r.outcome, WorkPickOutcome.needMore);
      expect(r.message, contains('second'));
    });

    test('Through Two Points runs first -> second, as Inventor documents', () {
      final a = WorkRef.point('P1', const Vec3(1, 1, 1));
      final b = WorkRef.point('P2', const Vec3(1, 1, 5));
      final ax = axisOf(solveWorkAxis(WorkAxisMethod.throughTwoPoints, [a, b]));
      expect(ax.dir.dot(_z), closeTo(1, 1e-12),
          reason: 'first to second, not second to first');
      final flipped =
          axisOf(solveWorkAxis(WorkAxisMethod.throughTwoPoints, [b, a]));
      expect(flipped.dir.dot(_z), closeTo(-1, 1e-12));
    });

    test('Through Two Points refuses coincident points', () {
      final a = WorkRef.point('P1', const Vec3(2, 2, 2));
      final b = WorkRef.point('P2', const Vec3(2, 2, 2));
      final r = solveWorkAxis(WorkAxisMethod.throughTwoPoints, [a, b]);
      expect(r.outcome, WorkPickOutcome.rejected);
    });

    test('Normal to Plane through Point passes through the point', () {
      final pl = WorkRef.plane('XY Plane', Vec3.zero, _z);
      final pt = WorkRef.point('Work Point1', const Vec3(4, 7, 0));
      final a = axisOf(solveWorkAxis(
          WorkAxisMethod.normalToPlaneThroughPoint, [pl, pt]));
      expect((a.at - const Vec3(4, 7, 0)).length, lessThan(1e-12));
      expect(a.dir.cross(_z).length, lessThan(1e-12));
    });

    test('Through Center of Circular Edge is the circle axis', () {
      final c = WorkRef.circle('Circular Edge', const Vec3(3, 4, 5), _z);
      final a = axisOf(solveWorkAxis(
          WorkAxisMethod.throughCenterOfCircularEdge, [c]));
      expect(lineGap(const Vec3(3, 4, 99), a.at, a.dir), lessThan(1e-12));
    });

    test('Through Revolved Face takes the surface axis', () {
      final cyl =
          WorkRef.revolvedFace('Cylindrical Face', const Vec3(2, 0, 0), _z);
      final a =
          axisOf(solveWorkAxis(WorkAxisMethod.throughRevolvedFace, [cyl]));
      expect(lineGap(const Vec3(2, 0, 40), a.at, a.dir), lessThan(1e-12));
      // and refuses a plain planar face
      final flat = WorkRef.plane('Face', Vec3.zero, _z);
      expect(solveWorkAxis(WorkAxisMethod.throughRevolvedFace, [flat]).outcome,
          WorkPickOutcome.rejected);
    });

    test('Parallel to Line through Point takes either pick order', () {
      final line = WorkRef.line('Edge', Vec3.zero, const Vec3(0, 0, 8));
      final pt = WorkRef.point('Vertex', const Vec3(6, 6, 0));
      for (final order in [
        [pt, line],
        [line, pt]
      ]) {
        final a = axisOf(solveWorkAxis(
            WorkAxisMethod.parallelToLineThroughPoint, order));
        expect((a.at - const Vec3(6, 6, 0)).length, lessThan(1e-12));
        expect(a.dir.cross(_z).length, lessThan(1e-12));
      }
    });
  });

  group('work axis — the legacy "Axis" command infers', () {
    test('one edge commits immediately', () {
      final e = WorkRef.line('Edge', Vec3.zero, const Vec3(0, 0, 5));
      final a = axisOf(solveWorkAxis(WorkAxisMethod.auto, [e]));
      expect(a.def, 'On Edge');
    });

    test('one circular edge gives its axis, not its centre', () {
      final c = WorkRef.circle('Circular Edge', const Vec3(1, 1, 0), _z);
      final a = axisOf(solveWorkAxis(WorkAxisMethod.auto, [c]));
      expect(a.def, contains('Through center'));
      expect(a.dir.cross(_z).length, lessThan(1e-12));
    });

    test('one cylinder gives its revolution axis', () {
      final cyl = WorkRef.revolvedFace('Cylindrical Face', Vec3.zero, _y);
      final a = axisOf(solveWorkAxis(WorkAxisMethod.auto, [cyl]));
      expect(a.def, contains('Revolution axis'));
    });

    test('one plane waits, then the second decides', () {
      final p1 = WorkRef.plane('Face A', Vec3.zero, _x);
      expect(solveWorkAxis(WorkAxisMethod.auto, [p1]).outcome,
          WorkPickOutcome.needMore);
      final p2 = WorkRef.plane('Face B', Vec3.zero, _y);
      final a = axisOf(solveWorkAxis(WorkAxisMethod.auto, [p1, p2]));
      expect(a.dir.cross(_z).length, lessThan(1e-12));
    });

    test('a plane then a point gives the normal through it', () {
      final pl = WorkRef.plane('XY Plane', Vec3.zero, _z);
      final pt = WorkRef.point('Vertex', const Vec3(2, 3, 0));
      final a = axisOf(solveWorkAxis(WorkAxisMethod.auto, [pl, pt]));
      expect((a.at - const Vec3(2, 3, 0)).length, lessThan(1e-12));
      // and the other order works too
      final b = axisOf(solveWorkAxis(WorkAxisMethod.auto, [pt, pl]));
      expect((b.at - const Vec3(2, 3, 0)).length, lessThan(1e-12));
    });

    test('two points give the axis through them', () {
      final a = WorkRef.point('P1', Vec3.zero);
      final b = WorkRef.point('P2', const Vec3(0, 5, 0));
      final ax = axisOf(solveWorkAxis(WorkAxisMethod.auto, [a, b]));
      expect(ax.dir.dot(_y), closeTo(1, 1e-12));
    });
  });

  group('work point — every Inventor method', () {
    test('On Vertex takes the point', () {
      final v = WorkRef.point('Vertex', const Vec3(1, 2, 3));
      final p = pointOf(solveWorkPoint(WorkPointMethod.onVertex, [v]));
      expect((p.at - const Vec3(1, 2, 3)).length, lessThan(1e-12));
    });

    test('an edge offers its MIDPOINT, which is what Inventor picks', () {
      final e = WorkRef.line('Edge', Vec3.zero, const Vec3(0, 0, 10));
      final p = pointOf(solveWorkPoint(WorkPointMethod.onVertex, [e]));
      expect((p.at - const Vec3(0, 0, 5)).length, lessThan(1e-12));
    });

    test('an INFINITE axis offers no midpoint', () {
      final ax = WorkRef.axis('Z Axis', Vec3.zero, _z);
      final r = solveWorkPoint(WorkPointMethod.onVertex, [ax]);
      expect(r.outcome, WorkPickOutcome.rejected,
          reason: 'the middle of an infinite line is not a point');
    });

    test('Intersection of Three Planes lands on all three', () {
      final a = WorkRef.plane('A', const Vec3(2, 0, 0), _x);
      final b = WorkRef.plane('B', const Vec3(0, 3, 0), _y);
      final c = WorkRef.plane('C', const Vec3(0, 0, 4), _z);
      final r = solveWorkPoint(WorkPointMethod.intersectionOfThreePlanes,
          [a, b, c]);
      final p = pointOf(r).at;
      expect(planeGap(p, const Vec3(2, 0, 0), _x).abs(), lessThan(1e-12));
      expect(planeGap(p, const Vec3(0, 3, 0), _y).abs(), lessThan(1e-12));
      expect(planeGap(p, const Vec3(0, 0, 4), _z).abs(), lessThan(1e-12));
    });

    test('Intersection of Three Planes prompts twice before building', () {
      final a = WorkRef.plane('A', Vec3.zero, _x);
      final b = WorkRef.plane('B', Vec3.zero, _y);
      expect(solveWorkPoint(WorkPointMethod.intersectionOfThreePlanes, [a])
          .outcome, WorkPickOutcome.needMore);
      expect(solveWorkPoint(WorkPointMethod.intersectionOfThreePlanes, [a, b])
          .outcome, WorkPickOutcome.needMore);
    });

    test('Intersection of Two Lines finds the crossing', () {
      final a =
          WorkRef.line('Edge A', const Vec3(-5, 2, 0), const Vec3(5, 2, 0));
      final b =
          WorkRef.line('Edge B', const Vec3(3, -5, 0), const Vec3(3, 5, 0));
      final p = pointOf(
          solveWorkPoint(WorkPointMethod.intersectionOfTwoLines, [a, b]));
      expect((p.at - const Vec3(3, 2, 0)).length, lessThan(1e-9));
    });

    test('Intersection of Two Lines refuses SKEW lines and says by how much',
        () {
      final a = WorkRef.line('Edge A', Vec3.zero, const Vec3(10, 0, 0));
      final b =
          WorkRef.line('Edge B', const Vec3(0, 0, 4), const Vec3(0, 10, 4));
      final r = solveWorkPoint(WorkPointMethod.intersectionOfTwoLines, [a, b]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('4.00 mm'),
          reason: 'the measured gap is what makes the refusal actionable');
    });

    test('Intersection of Two Lines refuses parallel lines', () {
      final a = WorkRef.line('Edge A', Vec3.zero, const Vec3(10, 0, 0));
      final b =
          WorkRef.line('Edge B', const Vec3(0, 5, 0), const Vec3(10, 5, 0));
      final r = solveWorkPoint(WorkPointMethod.intersectionOfTwoLines, [a, b]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message, contains('parallel'));
    });

    test('Intersection of Plane and Line, either pick order', () {
      final pl = WorkRef.plane('XY Plane', Vec3.zero, _z);
      final ln =
          WorkRef.line('Edge', const Vec3(4, 5, -3), const Vec3(4, 5, 3));
      for (final order in [
        [pl, ln],
        [ln, pl]
      ]) {
        final p = pointOf(solveWorkPoint(
            WorkPointMethod.intersectionOfPlaneAndLine, order));
        expect((p.at - const Vec3(4, 5, 0)).length, lessThan(1e-12));
      }
    });

    test('Center Point of Loop of Edges is the circle centre', () {
      final c = WorkRef.circle('Circular Edge', const Vec3(7, 8, 9), _z);
      final p = pointOf(solveWorkPoint(WorkPointMethod.centerOfLoop, [c]));
      expect((p.at - const Vec3(7, 8, 9)).length, lessThan(1e-12));
    });

    test('Center Point of Sphere / Torus take their own face type only', () {
      final sph = WorkRef.sphere('Spherical Face', const Vec3(1, 1, 1));
      final tor = WorkRef.torus('Toroidal Face', const Vec3(2, 2, 2), _z);
      expect(
          pointOf(solveWorkPoint(WorkPointMethod.centerOfSphere, [sph])).at.x,
          closeTo(1, 1e-12));
      expect(
          pointOf(solveWorkPoint(WorkPointMethod.centerOfTorus, [tor])).at.x,
          closeTo(2, 1e-12));
      // a sphere is not a torus, and saying so beats producing a point
      expect(solveWorkPoint(WorkPointMethod.centerOfTorus, [sph]).outcome,
          WorkPickOutcome.rejected);
    });

    test('Grounded Point records that it was grounded', () {
      final v = WorkRef.point('Vertex', const Vec3(1, 2, 3));
      final p = pointOf(solveWorkPoint(WorkPointMethod.grounded, [v]));
      expect(p.def, contains('Grounded'));
    });
  });

  group('work point — the legacy "Point" command infers', () {
    test('a vertex commits immediately', () {
      final v = WorkRef.point('Vertex', const Vec3(1, 2, 3));
      final p = pointOf(solveWorkPoint(WorkPointMethod.auto, [v]));
      expect((p.at - const Vec3(1, 2, 3)).length, lessThan(1e-12));
    });

    test('a circular edge gives its centre, not its axis', () {
      final c = WorkRef.circle('Circular Edge', const Vec3(5, 5, 0), _z);
      final p = pointOf(solveWorkPoint(WorkPointMethod.auto, [c]));
      expect((p.at - const Vec3(5, 5, 0)).length, lessThan(1e-12));
      expect(p.def, contains('Center'));
    });

    test('a plane waits, then a line crossing it commits', () {
      final pl = WorkRef.plane('XY Plane', Vec3.zero, _z);
      expect(solveWorkPoint(WorkPointMethod.auto, [pl]).outcome,
          WorkPickOutcome.needMore);
      final ax = WorkRef.axis('Z Axis', const Vec3(2, 3, 0), _z);
      final p = pointOf(solveWorkPoint(WorkPointMethod.auto, [pl, ax]));
      expect((p.at - const Vec3(2, 3, 0)).length, lessThan(1e-12));
    });

    test('two planes wait for a third rather than guessing', () {
      final a = WorkRef.plane('A', const Vec3(1, 0, 0), _x);
      final b = WorkRef.plane('B', const Vec3(0, 1, 0), _y);
      final two = solveWorkPoint(WorkPointMethod.auto, [a, b]);
      expect(two.outcome, WorkPickOutcome.needMore);
      expect(two.message, contains('third'));
      final c = WorkRef.plane('C', const Vec3(0, 0, 1), _z);
      final p = pointOf(solveWorkPoint(WorkPointMethod.auto, [a, b, c]));
      expect((p.at - const Vec3(1, 1, 1)).length, lessThan(1e-12));
    });
  });

  group('axis display span', () {
    test('spans the part and sticks out past it', () {
      final (a, b) = workAxisSpan(
          Vec3.zero, _z, const Vec3(-10, -10, 0), const Vec3(10, 10, 40));
      expect(a.z, lessThan(0), reason: 'runs past the low end');
      expect(b.z, greaterThan(40), reason: 'and past the high end');
      // still ON the axis
      expect(lineGap(a, Vec3.zero, _z), lessThan(1e-12));
      expect(lineGap(b, Vec3.zero, _z), lessThan(1e-12));
    });

    test('an empty part still gets a segment you can see and tap', () {
      final (a, b) = workAxisSpan(Vec3.zero, _x, Vec3.zero, Vec3.zero);
      expect((b - a).length, greaterThan(1),
          reason: 'a zero-length axis is unpickable and invisible');
    });
  });

  group('serialization', () {
    test('a work axis round-trips through JSON', () {
      final a = WorkAxis('Work Axis1', 4, 'On Edge', const Vec3(1, 2, 3),
          const Vec3(0, 0, 1));
      final back = WorkAxis.fromJson(a.toJson())!;
      expect(back.name, 'Work Axis1');
      expect(back.seq, 4);
      expect(back.def, 'On Edge');
      expect((back.at - a.at).length, lessThan(1e-12));
      expect((back.dir - a.dir).length, lessThan(1e-12));
      expect(back.visible, isTrue);
    });

    test('a work point round-trips, grounded flag included', () {
      final p = WorkPoint('Work Point1', 7, 'Grounded at Vertex',
          const Vec3(9, 8, 7),
          visible: false, grounded: true);
      final back = WorkPoint.fromJson(p.toJson())!;
      expect(back.grounded, isTrue);
      expect(back.visible, isFalse);
      expect((back.at - p.at).length, lessThan(1e-12));
    });

    test('a corrupt entry is dropped, not fatal', () {
      expect(WorkAxis.fromJson({'name': 'x'}), isNull);
      expect(WorkPoint.fromJson({'name': 'x'}), isNull);
      // a zero direction is not an axis
      expect(
          WorkAxis.fromJson({
            'name': 'A',
            'seq': 1,
            'at': [0, 0, 0],
            'dir': [0, 0, 0]
          }),
          isNull);
    });

    test('a part with no work features writes no work-feature keys', () {
      final p = PartModel('P');
      final j = p.toJson();
      expect(j.containsKey('workAxes'), isFalse);
      expect(j.containsKey('workPoints'), isFalse);
    });

    test('work features survive a part round-trip, in seq order', () {
      final p = PartModel('P');
      p.workAxes.add(WorkAxis('Work Axis1', 2, 'On Edge', Vec3.zero, _z));
      p.workPoints
          .add(WorkPoint('Work Point1', 5, 'On Vertex', const Vec3(1, 1, 1)));
      final back = PartModel('P')..loadJson(p.toJson());
      expect(back.workAxes.single.name, 'Work Axis1');
      expect(back.workPoints.single.seq, 5);
      expect(back.workFeatureSeqs.toList(), [2, 5]);
    });

    test('flip reverses the axis and nothing else', () {
      final a = WorkAxis('Work Axis1', 1, 'On Edge', const Vec3(1, 2, 3), _z);
      a.flip();
      expect(a.dir.dot(_z), closeTo(-1, 1e-12));
      expect((a.at - const Vec3(1, 2, 3)).length, lessThan(1e-12));
    });
  });

  group('menu labels match Inventor', () {
    test('every axis and point method has its Inventor wording', () {
      expect(workAxisMethodLabel(WorkAxisMethod.intersectionOfTwoPlanes),
          'Intersection of Two Planes');
      expect(workAxisMethodLabel(WorkAxisMethod.auto), 'Axis');
      expect(workPointMethodLabel(WorkPointMethod.onVertex),
          'On Vertex, Sketch Point, or Midpoint');
      expect(workPointMethodLabel(WorkPointMethod.grounded), 'Grounded Point');
      // and no method is left without one
      for (final m in WorkAxisMethod.values) {
        expect(workAxisMethodLabel(m), isNotEmpty);
        expect(workAxisPrompt(m, 0), isNotEmpty);
      }
      for (final m in WorkPointMethod.values) {
        expect(workPointMethodLabel(m), isNotEmpty);
        expect(workPointPrompt(m, 0), isNotEmpty);
      }
    });
  });
}
