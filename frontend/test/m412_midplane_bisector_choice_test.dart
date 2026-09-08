// M412 — #29: "the midplane between two non parallel faces does not make a
// vertical plane. it makes a horizontal plane where the other 2 planes cross
// each other. but instead it should make like a symetry plane vertical between
// the selected faces."
//
// The numbers in this file are the reported part's, read off the bug bundle
// rather than invented: a 310 x 336 x 50 bracket with a 50 mm chamfer taken
// off both of its long edges, so the two chamfer faces are
//
//   A:  n = (1, 0, -1)/root2   through (0, y, -310)   — the z = -310 end
//   B:  n = (1, 0,  1)/root2   through (0, y,    0)   — the z = 0 end
//
// They cross on the line x = 155, z = -155, which is 105 mm outside a part
// 50 mm thick, and that is where the plane came out: the app answered with the
// bisector at right angles to the one wanted. state.txt from the report:
//
//   {"name":"Work Plane1","def":"Midplane between Face and Face",
//    "o":[155.00005,-8.7e-14,-155.0], "n":[1.0,~0,~0]}
//
// The plane the user asked for is z = -155 — the part's own symmetry plane,
// with the two chamfers mirrored across it.
//
// WHY IT PICKED THE OTHER ONE. M401 chose between the two bisectors by normal
// sign: `a.n - b.n` is the one through the wedge the faces enclose PROVIDED
// both normals point out of the solid. The kernel does not promise that. The
// face record carries `pl.Axis()` flipped by the face's own orientation, and
// on this part — a chamfer over a boolean, whose mesh reports 13% of its
// vertex normals pointing inward — one of the two came back inverted. One
// flipped normal swaps `a.n - b.n` for `a.n + b.n`, which is exactly the plane
// that was drawn.
//
// So the choice is made from WHERE THE FACES ARE, which no sign convention can
// spoil: the bisector between two faces is the one they sit on opposite sides
// of. Every test below is run BOTH WAYS ROUND on the normals, because "the
// same answer whichever way the kernel happened to point" is the property.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

const _r2 = 0.7071067811865476;

/// The reported part's two chamfer faces. [anchorA] and [anchorB] are the
/// points on them the pick contributes; [flipA] and [flipB] invert the normals
/// the way the kernel did.
(PlaneFrame, PlaneFrame) _chamfers({
  bool flipA = false,
  bool flipB = false,
  Vec3 anchorA = const Vec3(25, 168, -285),
  Vec3 anchorB = const Vec3(25, 168, -25),
}) {
  const na = Vec3(_r2, 0, -_r2), nb = Vec3(_r2, 0, _r2);
  return (
    workPlaneFrameAt(anchorA, flipA ? na * -1 : na),
    workPlaneFrameAt(anchorB, flipB ? nb * -1 : nb),
  );
}

/// Signed distance of [p] from the plane through [f].
double _dist(PlaneFrame f, Vec3 p) => (p - f.origin).dot(f.n);

void main() {
  group('the reported part', () {
    for (final (label, flipA, flipB) in const [
      ('both normals outward', false, false),
      ('the second face inverted — what the kernel sent', false, true),
      ('the first face inverted', true, false),
      ('both inverted', true, true),
    ]) {
      test('$label: the plane is the symmetry plane z = -155', () {
        final (a, b) = _chamfers(flipA: flipA, flipB: flipB);
        final mid = midPlaneFrame(a, b)!;
        expect(mid.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9),
            reason: 'the plane in the report faced +X, 105 mm off the part');
        expect(mid.n.dot(mid.origin).abs(), closeTo(155, 1e-6));
      });

      test('$label: the two chamfers land on opposite sides of it', () {
        final (a, b) = _chamfers(flipA: flipA, flipB: flipB);
        final mid = midPlaneFrame(a, b)!;
        // "a symetry plane vertical between the selected faces": each face is
        // on its own side, so mirroring across it carries one onto the other.
        expect(_dist(mid, a.origin) * _dist(mid, b.origin), lessThan(0));
      });
    }

    test('it passes through the solid, not 105 mm outside it', () {
      // The part occupies x in 0..50. Every point of a plane that is BETWEEN
      // two of its faces has to be reachable inside that range; the plane in
      // the report was x = 155.00005 and had no point in the solid at all.
      final (a, b) = _chamfers(flipB: true);
      final mid = midPlaneFrame(a, b)!;
      expect(_dist(mid, const Vec3(25, 168, -155)).abs(), lessThan(1e-6),
          reason: 'the middle of the bracket is on the plane');
    });

    test('the answer does not depend on the pick order', () {
      final (a, b) = _chamfers(flipB: true);
      final one = midPlaneFrame(a, b)!, two = midPlaneFrame(b, a)!;
      expect(one.n.cross(two.n).length, lessThan(1e-9));
      expect(one.n.dot(one.origin).abs() - two.n.dot(two.origin).abs(),
          closeTo(0, 1e-9));
    });

    test('and it still contains the line the two faces share', () {
      // The property M401 was built on does not get traded away: whichever
      // bisector is chosen, it holds the crossing line.
      final (a, b) = _chamfers(flipB: true);
      final mid = midPlaneFrame(a, b)!;
      for (final y in [-8.0, 168.0, 344.0]) {
        expect(_dist(mid, Vec3(155, y, -155)).abs(), lessThan(1e-6));
      }
    });
  });

  group('the rule itself', () {
    test('anchors on the same side choose the other bisector', () {
      // Move face B's anchor across the crossing line — now both faces are on
      // the same side of z = -155 and it is x = 155 that separates them. The
      // rule is not "always the z one"; it is "the one they straddle".
      final (a, b) = _chamfers(anchorB: const Vec3(285, 168, -415));
      final mid = midPlaneFrame(a, b)!;
      expect(mid.n.cross(const Vec3(1, 0, 0)).length, lessThan(1e-9));
      expect(_dist(mid, a.origin) * _dist(mid, b.origin), lessThan(0));
    });

    test('an anchor ON the crossing line falls back to the normals', () {
      // Nothing to read: a point on the shared line is on both planes and
      // says nothing about sides. The M401 reading stands, which is what a
      // synthetic frame built straight through the crossing point wants.
      final (a, b) = _chamfers(
          anchorA: const Vec3(155, 0, -155), anchorB: const Vec3(155, 0, -155));
      final mid = midPlaneFrame(a, b)!;
      expect(mid.n.cross((a.n - b.n).normalized()).length, lessThan(1e-9));
    });

    test('parallel faces are untouched by any of this', () {
      // The parallel branch projects both origins onto ONE normal, so an
      // inverted input averages to the same plane either way — no anchor
      // rule needed, and none applied.
      final a = workPlaneFrameAt(const Vec3(3, 9, 0), const Vec3(0, 0, 1));
      final b = workPlaneFrameAt(const Vec3(-40, 2, 20), const Vec3(0, 0, -1));
      final mid = midPlaneFrame(a, b)!;
      expect(mid.n.dot(mid.origin).abs(), closeTo(10, 1e-9));
    });
  });
}
