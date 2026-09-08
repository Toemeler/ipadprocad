// M401 — #27: "i want to make a center plane between these 2 chamfers but it
// says the faces are not parallel. but they shouldn't need to be parallel
// since it should just make a middle plane like it would with parallel faces."
//
// `midPlaneFrame` refused anything but parallel, on the reasoning that "an
// angled bisector is a different feature". It is not a different feature — it
// is the same one, the locus of points equidistant from both faces, evaluated
// where the faces happen to meet. A chamfer pair is what it is most often
// asked for, and Inventor answers it.
//
// The two properties that make an answer correct, and both are tested against
// the definition rather than against the formula:
//
//   * every point of the result is the SAME signed distance from both input
//     planes — that is what "midway" means, and it is what the parallel case
//     has always delivered;
//   * the result contains the line the two planes share, so it sits between
//     them rather than beside them.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

PlaneFrame plane(Vec3 at, Vec3 n) => workPlaneFrameAt(at, n.normalized());

/// Signed distance of [p] from the plane through [f].
double dist(PlaneFrame f, Vec3 p) => (p - f.origin).dot(f.n);

/// A few points spread over [f]'s own surface.
List<Vec3> onPlane(PlaneFrame f) => [
      f.origin,
      f.origin + f.u * 12,
      f.origin + f.v * -7,
      f.origin + f.u * 3 + f.v * 9,
    ];

void main() {
  group('parallel faces answer exactly as they always did', () {
    test('two opposite faces of a block', () {
      final a = plane(const Vec3(0, 0, 0), const Vec3(0, 0, -1));
      final b = plane(const Vec3(0, 0, 20), const Vec3(0, 0, 1));
      final mid = midPlaneFrame(a, b)!;
      expect(mid.n.dot(const Vec3(0, 0, 1)).abs(), closeTo(1, 1e-9));
      expect(mid.origin.dot(mid.n).abs(), closeTo(10, 1e-9));
    });

    test('two faces looking the same way', () {
      final a = plane(const Vec3(0, 0, 4), const Vec3(0, 0, 1));
      final b = plane(const Vec3(0, 0, 10), const Vec3(0, 0, 1));
      final mid = midPlaneFrame(a, b)!;
      expect(mid.origin.dot(const Vec3(0, 0, 1)), closeTo(7, 1e-9));
    });
  });

  group('THE REPORT: two chamfers that meet at an angle', () {
    // A 90-degree corner chamfered from both sides: two planar faces whose
    // outward normals are a right angle apart, meeting along the z axis. The
    // solid is the quadrant x < 0, y < 0, so each face's ANCHOR — the point on
    // the face the pick contributes — sits on the other's negative side.
    final a = plane(const Vec3(0, -7, 0), const Vec3(1, 0, 0));
    final b = plane(const Vec3(-5, 0, 0), const Vec3(0, 1, 0));

    test('there is an answer at all', () {
      expect(midPlaneFrame(a, b), isNotNull,
          reason: 'it said "those two are not parallel" and gave up');
    });

    test('every point on it is equidistant from both faces', () {
      final mid = midPlaneFrame(a, b)!;
      for (final p in onPlane(mid)) {
        expect(dist(a, p), closeTo(dist(b, p), 1e-9),
            reason: 'the definition of midway, at $p');
      }
    });

    test('it contains the line the two faces share', () {
      final mid = midPlaneFrame(a, b)!;
      // The z axis lies in both inputs, so it must lie in the bisector.
      for (final t in [-30.0, 0.0, 17.0]) {
        expect(dist(mid, Vec3(0, 0, t)).abs(), lessThan(1e-9));
      }
    });

    test('it is the bisector BETWEEN the faces, not the other one', () {
      final mid = midPlaneFrame(a, b)!;
      // Two intersecting planes have TWO bisectors, at right angles to each
      // other, and both make equal angles with the inputs — so equal angles
      // alone does not pick one.
      expect(mid.n.dot(a.n).abs(), closeTo(mid.n.dot(b.n).abs(), 1e-9));

      // What separates them is the SIGN. A point is equidistant either with
      // `d_a == d_b` or with `d_a == -d_b`, and the two readings are the two
      // planes. The one wanted is the one the two faces sit on OPPOSITE sides
      // of, which here — both anchors on the other face's negative side — is
      // the `d_a == d_b` reading, the bisector whose normal is along
      // `a.n - b.n`. M412: it is the ANCHORS that say so and not the normals,
      // which is the whole of #29; see the test below.
      final internal = (a.n - b.n).normalized();
      final external = (a.n + b.n).normalized();
      expect(mid.n.dot(internal).abs(), closeTo(1, 1e-9));
      expect(mid.n.dot(external).abs(), lessThan(1e-9));

      // And the other one really is a different plane: its points are as far
      // from one face as they are from the far side of the other.
      final onExternal = external.cross(a.n.cross(b.n)).normalized() * 5;
      expect(dist(a, onExternal), closeTo(-dist(b, onExternal), 1e-9));
      expect(dist(mid, onExternal).abs(), greaterThan(1),
          reason: 'the two bisectors must not have come out the same plane');
    });
  });

  group('a shallow chamfer pair — the awkward end of the range', () {
    test('ten degrees apart still bisects', () {
      final r = 10 * math.pi / 180;
      final a = plane(const Vec3(0, 0, 0), const Vec3(0, 1, 0));
      final b = plane(
          const Vec3(0, 0, 0), Vec3(math.sin(r), math.cos(r), 0));
      final mid = midPlaneFrame(a, b)!;
      for (final p in onPlane(mid)) {
        expect(dist(a, p), closeTo(dist(b, p), 1e-9));
      }
      // Half of ten degrees off each input.
      final half = math.acos(mid.n.dot(a.n).abs());
      expect(half * 180 / math.pi, closeTo(85, 1e-6),
          reason: 'the bisector normal is 90 - 5 degrees from each face normal');
    });

    test('planes that do not pass through the world origin', () {
      // The offsets have to survive: the bisector of two shifted planes is
      // not the bisector of two planes through the origin. The corner is the
      // solid x < 5, y < -3, and each anchor is on its own face out beyond the
      // other one — the same arrangement as the chamfer pair above, moved.
      final a = plane(const Vec3(5, -10, 0), const Vec3(1, 0, 0));
      final b = plane(const Vec3(0, -3, 0), const Vec3(0, 1, 0));
      final mid = midPlaneFrame(a, b)!;
      for (final p in onPlane(mid)) {
        expect(dist(a, p), closeTo(dist(b, p), 1e-9), reason: 'at $p');
      }
      // The shared line is x=5, y=-3; it must lie in the result.
      expect(dist(mid, const Vec3(5, -3, 41)).abs(), lessThan(1e-9));
    });
  });

  test('the frame is a usable one — orthonormal, right-handed', () {
    final a = plane(const Vec3(2, 0, 0), const Vec3(1, 0, 0));
    final b = plane(const Vec3(0, 0, 6), const Vec3(0, 0.6, 0.8));
    final mid = midPlaneFrame(a, b)!;
    expect(mid.u.length, closeTo(1, 1e-9));
    expect(mid.v.length, closeTo(1, 1e-9));
    expect(mid.n.length, closeTo(1, 1e-9));
    expect(mid.u.dot(mid.v).abs(), lessThan(1e-9));
    expect(mid.u.dot(mid.n).abs(), lessThan(1e-9));
    expect((mid.u.cross(mid.v) - mid.n).length, lessThan(1e-9));
    // A sketch placed on it must know it is a work plane, not an origin one.
    expect(mid.key, kWorkPlaneKey);
  });
}
