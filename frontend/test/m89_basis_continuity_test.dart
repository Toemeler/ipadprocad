// M89 — the camera basis must be CONTINUOUS, including at the poles.
//
// The sketch-entry swing animated cleanly and then snapped right at the end.
// Cause: the basis fell back to `fwd x (0,0,1)` when `fwd x (0,1,0)` got
// short, and that fallback points somewhere unrelated to the limit the
// approach was heading for. A sketch on a top or bottom face lands exactly
// there (pol = acos(+/-1) = 0 or pi), so it hit every single time.
//
// Writing the cross product out with dir = (sin p sin a, cos p, sin p cos a):
//   fwd x (0,1,0) = (sin p cos a, 0, -sin p sin a)
// the LENGTH vanishes at the poles but the DIRECTION converges to
// (cos a, 0, -sin a). That limit is what both implementations now use.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

const _size = Size(800, 600);

Vec3 dirOf(double az, double pol) => Vec3(
    math.sin(pol) * math.sin(az), math.cos(pol), math.sin(pol) * math.cos(az));

void main() {
  group('basis continuity at the poles', () {
    test('the right vector is independent of pol — no pole case at all', () {
      // This is the property that removes the snap: the OLD form was
      // normalize(fwd x (0,1,0)), whose sin(pol) factor cancels, so the
      // result never depended on pol in the first place. Deriving it from az
      // makes that explicit and leaves nothing to degenerate.
      for (final az in [0.0, 0.9, 2.4, -1.7]) {
        final want = PartCamera.rightFor(az);
        for (final pol in [
          0.0,
          1e-6,
          0.2,
          math.pi / 2,
          math.pi - 1e-6,
          math.pi
        ]) {
          final f = dirOf(az, pol) * -1;
          final cross = f.cross(const Vec3(0, 1, 0));
          if (cross.length > 1e-7) {
            // where the old cross product was usable, the closed form agrees
            final old = cross.normalized();
            expect((old - want).length, lessThan(1e-6),
                reason: 'closed form disagrees with the cross product at '
                    'az=$az pol=$pol');
          }
        }
      }
    });

    test('it matches the closed form exactly', () {
      for (final az in [0.0, 1.1, -2.2, 3.0]) {
        final r = PartCamera.rightFor(az);
        expect(r.x, closeTo(math.cos(az), 1e-9));
        expect(r.y, closeTo(0, 1e-9));
        expect(r.z, closeTo(-math.sin(az), 1e-9));
      }
    });

    test('it is always a unit vector', () {
      for (final az in [0.0, 1.3, -2.9, 6.0]) {
        expect(PartCamera.rightFor(az).length, closeTo(1, 1e-9));
      }
    });
  });

  group('the sketch camera survives the pole cases', () {
    // A sketch on the TOP face is n = (0,1,0) -> pol = 0, the exact case that
    // used to flip. Also the bottom face, and a plane whose u is rotated.
    final cases = <String, PlaneFrame>{
      'top': const PlaneFrame(
          'xz', Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(0, 1, 0), Vec3.zero),
      'bottom': const PlaneFrame(
          'xz', Vec3(1, 0, 0), Vec3(0, 0, 1), Vec3(0, -1, 0), Vec3.zero),
      'top, u rotated 90': const PlaneFrame(
          'xz', Vec3(0, 0, -1), Vec3(-1, 0, 0), Vec3(0, 1, 0), Vec3.zero),
    };

    cases.forEach((name, fr) {
      test('$name: the frame axes land on screen x/y as 2D draws them', () {
        const pan = Offset(1.5, -2.0);
        const zoom = 3.0;
        final cam = Cam3(PartCamera.forSketch(fr, _size, pan, zoom), _size);
        Offset map2d(Offset p) => Offset(
            _size.width / 2 + (p.dx - pan.dx) * zoom,
            _size.height / 2 - (p.dy - pan.dy) * zoom);
        for (final sk in const [
          Offset(0, 0),
          Offset(10, 0), // +u must go RIGHT
          Offset(0, 10), // +v must go UP
          Offset(-6, 4),
        ]) {
          final got = cam.project(fr.toWorld(sk));
          final want = map2d(sk);
          expect(got.dx, closeTo(want.dx, 1e-5), reason: '$name x');
          expect(got.dy, closeTo(want.dy, 1e-5),
              reason: '$name y — a mirrored or 180-rotated sketch shows up '
                  'here, which is the "wrong side" symptom');
        }
      });
    });
  });
}
