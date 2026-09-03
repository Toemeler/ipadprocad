// M371 — the measurement arithmetic, on the host.
//
// Every case here is a scenario the tool has to answer on a device, reduced
// to the numbers: "click on a line and get its length, on 2 faces and get the
// distance, on 2 points, on a cylinder, just every possible scenario should
// work" (device brief, 2026-09-03). The point of the file is that NONE of
// them need a camera, a widget tree or the kernel — measure.dart is
// deliberately pure so that the answers can be pinned here rather than only
// seen on glass.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/measure.dart';
import 'package:prototype/part_model.dart' show Vec3;

/// mm tolerance for the analytic cases. Generous by measurement standards and
/// still four orders tighter than anything the panel shows.
const double eps = 1e-9;

double deg(double radians) => radians * 180 / math.pi;

/// The value of [role] in [r], or a failure that names what was actually
/// there — a missing row is the commonest way one of these regresses.
double valueOf(MeasureReading r, MeasureRole role) {
  final v = r.valueOf(role);
  expect(v, isNotNull,
      reason: 'no $role in ${r.values.map((e) => e.role.name).toList()}');
  return v!.value;
}

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------

/// A 10 x 20 x 30 box at the origin, as the six planar faces, the twelve
/// edges and a body. The one fixture that covers most of the brief.
MeasureRef boxFaceZ0() =>
    MeasureRef.plane(const Vec3(5, 10, 0), const Vec3(0, 0, -1),
        oriented: true, area: 200, perimeter: 60);

MeasureRef boxFaceZ30() =>
    MeasureRef.plane(const Vec3(5, 10, 30), const Vec3(0, 0, 1),
        oriented: true, area: 200, perimeter: 60);

/// The unit cube's mesh, offset by [at]. Twelve triangles, twelve edges.
MeasureMesh cubeMesh(Vec3 at, double size) {
  final c = [
    for (final x in [0.0, size])
      for (final y in [0.0, size])
        for (final z in [0.0, size]) Vec3(at.x + x, at.y + y, at.z + z)
  ];
  // index = 4*ix + 2*iy + iz
  int i(int ix, int iy, int iz) => 4 * ix + 2 * iy + iz;
  final quads = <List<int>>[
    [i(0, 0, 0), i(0, 1, 0), i(0, 1, 1), i(0, 0, 1)], // x = 0
    [i(1, 0, 0), i(1, 0, 1), i(1, 1, 1), i(1, 1, 0)], // x = size
    [i(0, 0, 0), i(0, 0, 1), i(1, 0, 1), i(1, 0, 0)], // y = 0
    [i(0, 1, 0), i(1, 1, 0), i(1, 1, 1), i(0, 1, 1)], // y = size
    [i(0, 0, 0), i(1, 0, 0), i(1, 1, 0), i(0, 1, 0)], // z = 0
    [i(0, 0, 1), i(0, 1, 1), i(1, 1, 1), i(1, 0, 1)], // z = size
  ];
  final tris = <Vec3>[];
  final curves = <List<Vec3>>[];
  for (final q in quads) {
    tris.addAll([c[q[0]], c[q[1]], c[q[2]]]);
    tris.addAll([c[q[0]], c[q[2]], c[q[3]]]);
    for (var k = 0; k < 4; k++) {
      curves.add([c[q[k]], c[q[(k + 1) % 4]]]);
    }
  }
  return MeasureMesh(tris, curves, at, Vec3(at.x + size, at.y + size, at.z + size));
}

void main() {
  // =========================================================================
  group('one pick — the rich single-click reading', () {
    test('a straight edge reports its length and its three deltas', () {
      final e = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(3, 4, 0));
      final r = measureSingle(e)!;
      expect(r.primary.role, MeasureRole.length);
      expect(r.primary.value, closeTo(5, eps));
      expect(valueOf(r, MeasureRole.deltaX), closeTo(3, eps));
      expect(valueOf(r, MeasureRole.deltaY), closeTo(4, eps));
      expect(valueOf(r, MeasureRole.deltaZ), closeTo(0, eps));
    });

    test('a length is a length whichever way round the edge was built', () {
      final ab = measureSingle(
          MeasureRef.segment(const Vec3(1, 2, 3), const Vec3(4, 6, 3)))!;
      final ba = measureSingle(
          MeasureRef.segment(const Vec3(4, 6, 3), const Vec3(1, 2, 3)))!;
      expect(ab.primary.value, closeTo(ba.primary.value, eps));
      expect(ab.primary.value, closeTo(5, eps));
    });

    test('a point reports where it is', () {
      final r = measureSingle(MeasureRef.point(const Vec3(1, -2, 3.5)))!;
      expect(valueOf(r, MeasureRole.positionX), closeTo(1, eps));
      expect(valueOf(r, MeasureRole.positionY), closeTo(-2, eps));
      expect(valueOf(r, MeasureRole.positionZ), closeTo(3.5, eps));
    });

    test('a circular edge leads with the DIAMETER, as Inventor does', () {
      final r = measureSingle(MeasureRef.circle(
          const Vec3(0, 0, 0), const Vec3(0, 0, 1), 4))!;
      expect(r.primary.role, MeasureRole.diameter);
      expect(r.primary.value, closeTo(8, eps));
      expect(valueOf(r, MeasureRole.radius), closeTo(4, eps));
      expect(valueOf(r, MeasureRole.circumference), closeTo(8 * math.pi, eps));
      expect(valueOf(r, MeasureRole.area), closeTo(16 * math.pi, eps));
    });

    test('an arc reports its arc length AND the angle it sweeps', () {
      final quarter = MeasureRef.arc(
          const Vec3(0, 0, 0), const Vec3(0, 0, 1), 2, math.pi / 2);
      final r = measureSingle(quarter)!;
      expect(r.primary.role, MeasureRole.arcLength);
      expect(r.primary.value, closeTo(math.pi, eps));
      expect(deg(valueOf(r, MeasureRole.includedAngle)), closeTo(90, 1e-7));
      expect(valueOf(r, MeasureRole.radius), closeTo(2, eps));
    });

    test('a cylinder answers diameter, radius, height and area at one tap', () {
      final r = measureSingle(MeasureRef.cylinder(
          const Vec3(0, 0, 0), const Vec3(0, 0, 1), 5,
          height: 12, area: 2 * math.pi * 5 * 12))!;
      expect(r.primary.role, MeasureRole.diameter);
      expect(r.primary.value, closeTo(10, eps));
      expect(valueOf(r, MeasureRole.radius), closeTo(5, eps));
      expect(valueOf(r, MeasureRole.height), closeTo(12, eps));
      expect(valueOf(r, MeasureRole.area), closeTo(2 * math.pi * 60, eps));
    });

    test('a planar face reports area and total loop length', () {
      final r = measureSingle(boxFaceZ0())!;
      expect(r.primary.role, MeasureRole.area);
      expect(r.primary.value, closeTo(200, eps));
      expect(valueOf(r, MeasureRole.perimeter), closeTo(60, eps));
    });

    test('a sphere reports diameter and radius', () {
      final r = measureSingle(
          MeasureRef.sphere(const Vec3(1, 1, 1), radius: 3))!;
      expect(r.primary.role, MeasureRole.diameter);
      expect(r.primary.value, closeTo(6, eps));
    });

    test('a body reports volume and the three extents', () {
      final r = measureSingle(MeasureRef.solid(
          const Vec3(0, 0, 0), const Vec3(10, 20, 30),
          component: false, volume: 6000))!;
      expect(r.primary.role, MeasureRole.volume);
      expect(r.primary.value, closeTo(6000, eps));
      expect(valueOf(r, MeasureRole.extentX), closeTo(10, eps));
      expect(valueOf(r, MeasureRole.extentY), closeTo(20, eps));
      expect(valueOf(r, MeasureRole.extentZ), closeTo(30, eps));
    });

    test('a closed sketch loop reports its enclosed area', () {
      final square = [
        const Vec3(0, 0, 0),
        const Vec3(4, 0, 0),
        const Vec3(4, 3, 0),
        const Vec3(0, 3, 0),
        const Vec3(0, 0, 0),
      ];
      final r = measureSingle(MeasureRef.curve(square,
          closed: true, planeNormal: const Vec3(0, 0, 1)))!;
      expect(r.primary.role, MeasureRole.length);
      expect(r.primary.value, closeTo(14, eps));
      expect(valueOf(r, MeasureRole.area), closeTo(12, eps));
    });

    test('an infinite axis alone measures nothing, and says so with null', () {
      expect(
          measureSingle(
              MeasureRef.axis(const Vec3(0, 0, 0), const Vec3(0, 0, 1))),
          isNull);
    });

    test('a work plane alone measures nothing — it is half of a pair', () {
      expect(
          measureSingle(
              MeasureRef.plane(const Vec3(0, 0, 5), const Vec3(0, 0, 1))),
          isNull);
    });
  });

  // =========================================================================
  group('two points', () {
    test('distance and the three deltas', () {
      final r = measurePair(MeasureRef.point(const Vec3(1, 2, 3)),
          MeasureRef.point(const Vec3(4, 6, 3)))!;
      expect(r.primary.value, closeTo(5, eps));
      expect(valueOf(r, MeasureRole.deltaX), closeTo(3, eps));
      expect(valueOf(r, MeasureRole.deltaY), closeTo(4, eps));
      expect(valueOf(r, MeasureRole.deltaZ), closeTo(0, eps));
    });

    test('the marker spans exactly the two points', () {
      final r = measurePair(MeasureRef.point(const Vec3(0, 0, 0)),
          MeasureRef.point(const Vec3(0, 0, 7)))!;
      expect(r.marker!.kind, MeasureMarkerKind.span);
      expect(r.marker!.a!.z, closeTo(0, eps));
      expect(r.marker!.b!.z, closeTo(7, eps));
    });

    test('two points offer Center to Center and Maximum as well', () {
      final r = measurePair(MeasureRef.point(const Vec3(0, 0, 0)),
          MeasureRef.point(const Vec3(0, 0, 7)))!;
      expect(r.modes, contains(MeasureDistanceMode.centre));
      expect(r.modes, contains(MeasureDistanceMode.maximum));
    });
  });

  // =========================================================================
  group('two faces', () {
    test('parallel faces give the gap between them', () {
      final r = measurePair(boxFaceZ0(), boxFaceZ30())!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(30, eps));
    });

    test('parallel faces also report that the angle really is zero', () {
      final r = measurePair(boxFaceZ0(), boxFaceZ30())!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(0, 1e-7));
    });

    test('two faces 0.02 degrees off parallel say so rather than rounding', () {
      // The two walls of a slot, one of them a hair out of square. They FACE
      // each other, so the material between them is a 0.02 degree wedge —
      // which is exactly the number a machinist is measuring for.
      final tilt = 0.02 * math.pi / 180;
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final b = MeasureRef.plane(const Vec3(0, 0, 10),
          Vec3(math.sin(tilt), 0, -math.cos(tilt)),
          oriented: true);
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(0.02, 1e-6));
      expect(deg(valueOf(r, MeasureRole.supplementAngle)),
          closeTo(179.98, 1e-6));
    });

    test('two faces pointing the SAME way read as the flat pair they are', () {
      // Two steps of a staircase, one 0.02 degrees out. There is no material
      // between them, so the dihedral is the reflex-side 179.98 — and the
      // supplement beside it is the 0.02 the user came for. Both numbers are
      // on screen, which is why the convention can be one rule rather than a
      // guess about which face the user meant.
      final tilt = 0.02 * math.pi / 180;
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final b = MeasureRef.plane(const Vec3(0, 0, 10),
          Vec3(math.sin(tilt), 0, math.cos(tilt)),
          oriented: true);
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(179.98, 1e-6));
      expect(deg(valueOf(r, MeasureRole.supplementAngle)), closeTo(0.02, 1e-6));
    });

    test('two faces of a right-angled corner give 90 degrees', () {
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, -1),
          oriented: true);
      final b = MeasureRef.plane(Vec3.zero, const Vec3(-1, 0, 0),
          oriented: true);
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(90, 1e-7));
    });

    test('a 30 degree wedge reads 30, not 150 — outward normals decide', () {
      // Two faces of a wedge whose interior angle is 30 degrees. Their
      // OUTWARD normals are 150 degrees apart; the dihedral is the
      // supplement, which is the number a protractor in the notch reads.
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, -1, 0),
          oriented: true);
      final wedge = 30 * math.pi / 180;
      final b = MeasureRef.plane(
          Vec3.zero, Vec3(math.sin(wedge), -math.cos(wedge), 0) * -1,
          oriented: true);
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(30, 1e-6));
      expect(deg(valueOf(r, MeasureRole.supplementAngle)), closeTo(150, 1e-6));
    });

    test('a 150 degree wedge reads 150 — the case the acute rule gets wrong',
        () {
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, -1, 0),
          oriented: true);
      final wedge = 150 * math.pi / 180;
      final b = MeasureRef.plane(
          Vec3.zero, Vec3(math.sin(wedge), -math.cos(wedge), 0) * -1,
          oriented: true);
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(150, 1e-6));
    });

    test('two UNORIENTED work planes give the unsigned angle instead', () {
      // Nothing says which side of a work plane is "out", so the honest
      // answer is the one in [0, 90] — and the supplement rides along.
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1));
      final b = MeasureRef.plane(Vec3.zero, const Vec3(0, 1, 1));
      final r = measurePair(a, b)!;
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(45, 1e-7));
      expect(deg(valueOf(r, MeasureRole.supplementAngle)), closeTo(135, 1e-7));
    });

    test('the plane-angle marker sits on the line where the two planes meet',
        () {
      final a = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final b = MeasureRef.plane(Vec3.zero, const Vec3(1, 0, 0),
          oriented: true);
      final r = measurePair(a, b)!;
      expect(r.marker!.kind, MeasureMarkerKind.angle);
      // Both planes pass through the origin; the shared line is the y axis.
      expect(r.marker!.apex!.x, closeTo(0, 1e-9));
      expect(r.marker!.apex!.z, closeTo(0, 1e-9));
    });
  });

  // =========================================================================
  group('two edges', () {
    test('two edges of a corner give the INCLUDED angle', () {
      final a = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(0, 10, 0));
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.angle);
      expect(deg(r.primary.value), closeTo(90, 1e-7));
      expect(r.marker!.kind, MeasureMarkerKind.angle);
      expect(r.marker!.apex!.x, closeTo(0, eps));
    });

    test('a 120 degree corner reads 120, not 60', () {
      final a = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, 0, 0),
          Vec3(10 * math.cos(2 * math.pi / 3), 10 * math.sin(2 * math.pi / 3), 0));
      final r = measurePair(a, b)!;
      expect(deg(r.primary.value), closeTo(120, 1e-6));
    });

    test('parallel edges give the distance between them', () {
      final a = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, 4, 0), const Vec3(10, 4, 0));
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(4, eps));
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(0, 1e-7));
    });

    test('SKEW edges lead with the distance — they never meet', () {
      // Along x at z = 0, and along y at z = 6: they never meet, so "how far
      // apart" is the question and "at what angle" is the footnote.
      final a = MeasureRef.segment(const Vec3(-10, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, -10, 6), const Vec3(0, 10, 6));
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(6, eps));
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(90, 1e-7));
    });

    test('COPLANAR edges lead with the angle even when they stop short of '
        'the corner', () {
      // A mitre with the vertex machined away: the two edges do not touch,
      // but their lines cross, so the angle is still what was asked.
      final a = MeasureRef.segment(const Vec3(-10, 0, 0), const Vec3(-1, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, 1, 0), const Vec3(0, 10, 0));
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.angle);
      expect(deg(r.primary.value), closeTo(90, 1e-7));
    });

    test('crossing edges report a distance of zero, which is the proof', () {
      final a = MeasureRef.segment(const Vec3(-10, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(0, -10, 0), const Vec3(0, 10, 0));
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.angle);
      expect(valueOf(r, MeasureRole.distance), closeTo(0, eps));
    });

    test('two separated collinear edges measure end to end, not centre to '
        'centre', () {
      final a = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(25, 0, 0), const Vec3(35, 0, 0));
      final r = measurePair(a, b)!;
      expect(r.primary.value, closeTo(15, eps));
    });
  });

  // =========================================================================
  group('point against everything', () {
    test('point to plane is the perpendicular distance', () {
      final r = measurePair(MeasureRef.point(const Vec3(3, 7, 12)),
          MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1)))!;
      expect(r.primary.value, closeTo(12, eps));
    });

    test('point to an infinite axis is the perpendicular distance', () {
      final r = measurePair(MeasureRef.point(const Vec3(3, 4, 99)),
          MeasureRef.axis(Vec3.zero, const Vec3(0, 0, 1)))!;
      expect(r.primary.value, closeTo(5, eps));
    });

    test('point to a SEGMENT clamps to the end rather than the infinite line',
        () {
      final r = measurePair(MeasureRef.point(const Vec3(20, 0, 0)),
          MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0)))!;
      expect(r.primary.value, closeTo(10, eps));
    });

    test('point to a circle is the distance to the CURVE', () {
      // 10 out along x from a circle of radius 4 in the xy plane: the nearest
      // rim point is at x = 4, so the gap is 6.
      final r = measurePair(MeasureRef.point(const Vec3(10, 0, 0)),
          MeasureRef.circle(Vec3.zero, const Vec3(0, 0, 1), 4))!;
      expect(r.primary.value, closeTo(6, eps));
    });

    test('point to a sphere is the distance to its SURFACE', () {
      final r = measurePair(MeasureRef.point(const Vec3(10, 0, 0)),
          MeasureRef.sphere(Vec3.zero, radius: 4))!;
      expect(r.primary.value, closeTo(6, eps));
    });

    test('point to a cylinder is the distance to its WALL', () {
      final r = measurePair(MeasureRef.point(const Vec3(10, 0, 5)),
          MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 4))!;
      expect(r.primary.value, closeTo(6, eps));
    });

    test('Center to Center on a point and a circle uses the CENTRE', () {
      final r = measurePair(MeasureRef.point(const Vec3(10, 0, 0)),
          MeasureRef.circle(Vec3.zero, const Vec3(0, 0, 1), 4),
          mode: MeasureDistanceMode.centre)!;
      expect(r.primary.role, MeasureRole.centreDistance);
      expect(r.primary.value, closeTo(10, eps));
      // ... and still says how far the wall is.
      expect(valueOf(r, MeasureRole.surfaceDistance), closeTo(6, eps));
    });
  });

  // =========================================================================
  group('holes, shafts and bores', () {
    test('two parallel holes: centre distance, and the wall gap', () {
      final a = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 3);
      final b = MeasureRef.cylinder(
          const Vec3(20, 0, 0), const Vec3(0, 0, 1), 3);
      final min = measurePair(a, b)!;
      // Minimum distance between two barrels is wall to wall.
      expect(min.primary.value, closeTo(14, eps));
      expect(deg(valueOf(min, MeasureRole.angle)), closeTo(0, 1e-7));
    });

    test('two circular EDGES give the rim-to-rim gap by default', () {
      final a = MeasureRef.circle(Vec3.zero, const Vec3(0, 0, 1), 3);
      final b =
          MeasureRef.circle(const Vec3(20, 0, 0), const Vec3(0, 0, 1), 3);
      final r = measurePair(a, b)!;
      expect(r.primary.value, closeTo(14, 1e-3));
    });

    test('two circular EDGES centre to centre give the bolt spacing', () {
      final a = MeasureRef.circle(Vec3.zero, const Vec3(0, 0, 1), 3);
      final b =
          MeasureRef.circle(const Vec3(20, 0, 0), const Vec3(0, 0, 1), 3);
      final r = measurePair(a, b, mode: MeasureDistanceMode.centre)!;
      expect(r.primary.role, MeasureRole.centreDistance);
      expect(r.primary.value, closeTo(20, eps));
    });

    test('two holes at an angle report the DISTANCE, with the angle beside it',
        () {
      final a = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 2);
      final b = MeasureRef.cylinder(
          const Vec3(10, 0, 0), const Vec3(0, 1, 0), 2);
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(deg(valueOf(r, MeasureRole.angle)), closeTo(90, 1e-7));
    });

    test('a bore inside a shaft does not report a negative gap as positive',
        () {
      // Coaxial: the walls overlap, so the wall-to-wall shrink must not fire.
      final outer = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 10);
      final inner = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 3);
      final r = measurePair(outer, inner)!;
      expect(r.primary.value, closeTo(0, eps));
    });

    test('a cylinder against a plane is measured from its wall', () {
      final cyl = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 4);
      final wall = MeasureRef.plane(
          const Vec3(30, 0, 0), const Vec3(1, 0, 0));
      final r = measurePair(cyl, wall)!;
      expect(r.primary.value, closeTo(26, eps));
    });

    test('a hole axis square to a face reports the distance, not 90 degrees',
        () {
      // A perpendicular line and plane HAVE a distance and the right angle
      // between them is not news, so this must not go down the angle branch.
      final axis = MeasureRef.axis(const Vec3(0, 0, 12), const Vec3(0, 0, 1));
      final face = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final r = measurePair(axis, face)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(12, eps));
    });
  });

  // =========================================================================
  group('lines against planes', () {
    test('a line at 30 degrees to a face reads 30', () {
      final a = 30 * math.pi / 180;
      final line = MeasureRef.segment(
          Vec3.zero, Vec3(math.cos(a) * 10, 0, math.sin(a) * 10));
      final face = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final r = measurePair(line, face)!;
      expect(r.primary.role, MeasureRole.angle);
      expect(deg(r.primary.value), closeTo(30, 1e-6));
    });

    test('an edge parallel to a face gives the gap', () {
      final line =
          MeasureRef.segment(const Vec3(0, 0, 8), const Vec3(10, 0, 8));
      final face = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final r = measurePair(line, face)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(8, eps));
    });

    test('an edge that ENDS short of a plane it points at measures from the '
        'end', () {
      final line =
          MeasureRef.segment(const Vec3(0, 0, 10), const Vec3(0, 0, 4));
      final face = MeasureRef.plane(Vec3.zero, const Vec3(0, 0, 1),
          oriented: true);
      final r = measurePair(line, face)!;
      expect(r.primary.value, closeTo(4, eps));
    });
  });

  // =========================================================================
  group('three points', () {
    test('the angle is taken AT the middle pick', () {
      final r = measure([
        MeasureRef.point(const Vec3(10, 0, 0)),
        MeasureRef.point(Vec3.zero),
        MeasureRef.point(const Vec3(0, 10, 0)),
      ])!;
      expect(r.primary.role, MeasureRole.angle);
      expect(deg(r.primary.value), closeTo(90, 1e-7));
    });

    test('the two leg lengths come with it', () {
      final r = measure([
        MeasureRef.point(const Vec3(3, 0, 0)),
        MeasureRef.point(Vec3.zero),
        MeasureRef.point(const Vec3(0, 4, 0)),
      ])!;
      expect(valueOf(r, MeasureRole.distance), closeTo(3, eps));
      expect(valueOf(r, MeasureRole.centreDistance), closeTo(4, eps));
    });
  });

  // =========================================================================
  group('distance modes', () {
    test('Maximum on two segments takes the far ends', () {
      final a = MeasureRef.segment(const Vec3(0, 0, 0), const Vec3(10, 0, 0));
      final b = MeasureRef.segment(const Vec3(20, 0, 0), const Vec3(30, 0, 0));
      final r = measurePair(a, b, mode: MeasureDistanceMode.maximum)!;
      expect(r.primary.role, MeasureRole.maximumDistance);
      expect(r.primary.value, closeTo(30, eps));
    });

    test('Center to Center is refused on a cylinder, which has no centre', () {
      final cyl = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 4);
      final pt = MeasureRef.point(const Vec3(20, 0, 0));
      final r = measurePair(cyl, pt)!;
      expect(r.modes, isNot(contains(MeasureDistanceMode.centre)));
    });

    test('asking for a mode the pair cannot answer falls back rather than '
        'throwing', () {
      final cyl = MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 4);
      final pt = MeasureRef.point(const Vec3(20, 0, 0));
      final r =
          measurePair(cyl, pt, mode: MeasureDistanceMode.centre)!;
      expect(r.mode, MeasureDistanceMode.minimum);
    });

    test('Maximum is refused when one pick is unbounded', () {
      final r = measurePair(MeasureRef.point(Vec3.zero),
          MeasureRef.axis(const Vec3(5, 0, 0), const Vec3(0, 0, 1)))!;
      expect(r.modes, isNot(contains(MeasureDistanceMode.maximum)));
    });
  });

  // =========================================================================
  group('solids', () {
    test('two separated cubes: the true gap, not the box centres', () {
      final a = MeasureRef.solid(Vec3.zero, const Vec3(10, 10, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 10));
      final b = MeasureRef.solid(
          const Vec3(25, 0, 0), const Vec3(35, 10, 10),
          component: false, mesh: cubeMesh(const Vec3(25, 0, 0), 10));
      final r = measurePair(a, b)!;
      expect(r.primary.value, closeTo(15, 1e-6));
      expect(r.primary.approximate, isTrue,
          reason: 'a mesh distance must admit it is a mesh distance');
    });

    test('a small cube hovering over a big one measures the GAP, which no '
        'edge-to-edge search would find', () {
      // The closest pair is a corner of the small cube against the FACE of
      // the big one — 8 mm straight down, while the nearest edges are much
      // further apart diagonally.
      final big = MeasureRef.solid(Vec3.zero, const Vec3(100, 100, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 100)); // z 0..100
      final small = MeasureRef.solid(
          const Vec3(40, 40, 108), const Vec3(50, 50, 118),
          component: false, mesh: cubeMesh(const Vec3(40, 40, 108), 10));
      final r = measurePair(big, small)!;
      expect(r.primary.value, closeTo(8, 1e-6));
    });

    test('a body against a FACE is solved, not anchored on the tap', () {
      // The bracket-and-wall measurement. The face is tapped far from the
      // part of the body nearest it, so an answer anchored on the tap would
      // come out diagonal and too big.
      final body = MeasureRef.solid(Vec3.zero, const Vec3(10, 10, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 10));
      final wall = MeasureRef.plane(
          const Vec3(0, 0, 40), const Vec3(0, 0, 1),
          oriented: true, hitAt: const Vec3(900, 900, 40));
      final r = measurePair(body, wall)!;
      expect(r.primary.value, closeTo(30, 1e-9));
    });

    test('a body PARTLY past a face reports the nearest crossing, not the '
        'far corner', () {
      final body = MeasureRef.solid(Vec3.zero, const Vec3(10, 10, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 10));
      final through = MeasureRef.plane(
          const Vec3(0, 0, 4), const Vec3(0, 0, 1),
          oriented: true);
      final r = measurePair(body, through)!;
      // A vertex sits at z = 0 and another at z = 10; the nearest is 4 away.
      expect(r.primary.value, closeTo(4, 1e-9));
    });

    test('a point against a body lands on the body SURFACE', () {
      final body = MeasureRef.solid(Vec3.zero, const Vec3(10, 10, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 10));
      final r = measurePair(MeasureRef.point(const Vec3(5, 5, 30)), body)!;
      expect(r.primary.value, closeTo(20, 1e-6));
    });

    test('touching solids read zero', () {
      final a = MeasureRef.solid(Vec3.zero, const Vec3(10, 10, 10),
          component: false, mesh: cubeMesh(Vec3.zero, 10));
      final b = MeasureRef.solid(
          const Vec3(10, 0, 0), const Vec3(20, 10, 10),
          component: false, mesh: cubeMesh(const Vec3(10, 0, 0), 10));
      final r = measurePair(a, b)!;
      expect(r.primary.value, closeTo(0, 1e-9));
    });
  });

  // =========================================================================
  group('running totals', () {
    test('each unit kind accumulates on its own', () {
      var t = const MeasureTotals();
      t = t.plus(measureSingle(
          MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)))!);
      t = t.plus(measureSingle(
          MeasureRef.segment(Vec3.zero, const Vec3(0, 0, 10)))!);
      t = t.plus(measureSingle(boxFaceZ0())!);
      expect(t.total(MeasureUnitKind.length), closeTo(15, eps));
      expect(t.count(MeasureUnitKind.length), 2);
      expect(t.total(MeasureUnitKind.area), closeTo(200, eps));
      expect(t.count(MeasureUnitKind.area), 1);
      expect(t.total(MeasureUnitKind.volume), isNull);
    });

    test('only the PRIMARY value of a reading is added', () {
      // A cylinder's reading carries a diameter, a radius, a height and an
      // area; adding all four would make "total length" meaningless.
      var t = const MeasureTotals();
      t = t.plus(measureSingle(MeasureRef.cylinder(
          Vec3.zero, const Vec3(0, 0, 1), 5,
          height: 12, area: 100))!);
      expect(t.total(MeasureUnitKind.length), closeTo(10, eps));
      expect(t.count(MeasureUnitKind.length), 1);
    });
  });

  // =========================================================================
  group('units', () {
    test('lengths convert by the scale, areas by its square, volumes by its '
        'cube', () {
      expect(measureConvert(25.4, MeasureUnitKind.length,
          MeasureUnitSystem.inch), closeTo(1, 1e-12));
      expect(
          measureConvert(
              25.4 * 25.4, MeasureUnitKind.area, MeasureUnitSystem.inch),
          closeTo(1, 1e-12));
      expect(
          measureConvert(math.pow(25.4, 3).toDouble(), MeasureUnitKind.volume,
              MeasureUnitSystem.inch),
          closeTo(1, 1e-9));
    });

    test('angles come out in degrees whatever the length unit is', () {
      expect(
          measureConvert(
              math.pi, MeasureUnitKind.angle, MeasureUnitSystem.inch),
          closeTo(180, 1e-12));
    });

    test('the unit symbol carries the exponent', () {
      expect(measureUnitSymbol(MeasureUnitSystem.millimetre,
          MeasureUnitKind.length), 'mm');
      expect(measureUnitSymbol(MeasureUnitSystem.millimetre,
          MeasureUnitKind.area), 'mm²');
      expect(measureUnitSymbol(MeasureUnitSystem.millimetre,
          MeasureUnitKind.volume), 'mm³');
      expect(measureUnitSymbol(MeasureUnitSystem.inch,
          MeasureUnitKind.angle), '°');
    });
  });

  // =========================================================================
  group('arithmetic helpers', () {
    test('a planar loop area works in any plane, not just z', () {
      // The same 4 x 3 rectangle, stood up in the yz plane.
      final loop = [
        const Vec3(0, 0, 0),
        const Vec3(0, 4, 0),
        const Vec3(0, 4, 3),
        const Vec3(0, 0, 3),
      ];
      expect(planarLoopArea(loop, const Vec3(1, 0, 0)), closeTo(12, eps));
    });

    test('the polyline midpoint is half way ALONG, not the middle index', () {
      // Three points, but the second sits at 90 % of the length.
      final pts = [
        const Vec3(0, 0, 0),
        const Vec3(9, 0, 0),
        const Vec3(10, 0, 0),
      ];
      expect(polylineMidpoint(pts).x, closeTo(5, eps));
    });

    test('Ramanujan matches a circle exactly when the axes are equal', () {
      expect(ellipsePerimeter(5, 5), closeTo(2 * math.pi * 5, 1e-9));
    });

    test('closestOnTriangle answers inside, on an edge and at a corner', () {
      const a = Vec3(0, 0, 0), b = Vec3(10, 0, 0), c = Vec3(0, 10, 0);
      // straight above the middle
      final inside = closestOnTriangle(const Vec3(2, 2, 5), a, b, c);
      expect(inside.z, closeTo(0, eps));
      expect(inside.x, closeTo(2, eps));
      // past the b corner
      expect((closestOnTriangle(const Vec3(20, -5, 0), a, b, c) - b).length,
          closeTo(0, eps));
      // beside the a-b edge
      final onEdge = closestOnTriangle(const Vec3(5, -3, 0), a, b, c);
      expect(onEdge.y, closeTo(0, eps));
      expect(onEdge.x, closeTo(5, eps));
    });

    test('linePlanePoint returns null for a line that runs along the plane',
        () {
      expect(
          linePlanePoint(const Vec3(0, 0, 5), const Vec3(1, 0, 0),
              const Vec3(0, 0, 1), 0),
          isNull);
    });
  });

  // =========================================================================
  group('the dispatcher', () {
    test('an empty pick list measures nothing', () {
      expect(measure(const []), isNull);
    });

    test('a fourth pick measures against the one before it', () {
      // The session trims to two, but the solver must not throw if it does
      // not: it answers for the last pair, which is what a user tapping on
      // and on expects to see.
      final r = measure([
        MeasureRef.point(Vec3.zero),
        MeasureRef.point(const Vec3(1, 0, 0)),
        MeasureRef.point(const Vec3(2, 0, 0)),
        MeasureRef.point(const Vec3(9, 0, 0)),
      ])!;
      expect(r.primary.value, closeTo(7, eps));
    });
  });
}
