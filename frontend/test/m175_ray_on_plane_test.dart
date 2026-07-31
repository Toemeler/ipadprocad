// M175 — the pick ray must meet the plane you tapped, not a parallel one
// through the world origin.
//
// `Cam3.rayOnPlane` intersected `n·X = 0`. Its own doc said so. That is right
// for the three ORIGIN planes and wrong for every other frame in the app: a
// work plane offset from XY, and a sketch on a solid face, are planes that do
// not pass through the origin, and both were hit-tested against a parallel
// plane through it.
//
// Two consequences, one survivable and one fatal:
//   * the hit POINT drifts, but only off-axis — looking straight down a
//     frame's normal the ray runs along the offset and the u/v are unchanged,
//     which is why face sketches seemed fine (the app orients the camera to
//     the face before you draw on it);
//   * the DEPTH returned is that of the wrong plane. The sketch-plane pick
//     compares plane depth against face depth to decide which surface you
//     meant, so a work plane in front of a solid reported the depth of a plane
//     through the origin — behind the solid — and the FACE won every time.
//     That is why a work plane could never be sketched on.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

Cam3 _camLookingDownY({double halfH = 50}) {
  final c = PartCamera()
    ..az = 0
    ..pol = 0 // straight down +Y
    ..halfH = halfH
    ..ox = 0
    ..oy = 0;
  return Cam3(c, const Size(800, 800));
}

Cam3 _camAtAnAngle({double halfH = 50}) {
  final c = PartCamera()
    ..az = 0.7
    ..pol = 0.9
    ..halfH = halfH
    ..ox = 0
    ..oy = 0;
  return Cam3(c, const Size(800, 800));
}

void main() {
  group('M175 — the ray meets the right plane', () {
    test('a plane through the origin is unchanged', () {
      final cam = _camAtAnAngle();
      const px = Offset(400, 400);
      final a = cam.rayOnPlane(px, const Vec3(0, 1, 0));
      final b = cam.rayOnPlane(px, const Vec3(0, 1, 0), Vec3.zero);
      expect(a, isNotNull);
      expect((a! - b!).length, lessThan(1e-9),
          reason: 'the default must be exactly the old behaviour');
    });

    test('an OFFSET plane is met at its own height', () {
      final cam = _camAtAnAngle();
      final hit = cam.rayOnPlane(
          const Offset(430, 380), const Vec3(0, 1, 0), const Vec3(0, 25, 0));
      expect(hit, isNotNull);
      expect(hit!.y, closeTo(25, 1e-9),
          reason: 'the whole bug: it used to come back on y=0');
    });

    test('the old behaviour landed on the WRONG plane', () {
      // Guards the diagnosis itself.
      final cam = _camAtAnAngle();
      final wrong = cam.rayOnPlane(const Offset(430, 380), const Vec3(0, 1, 0));
      expect(wrong!.y, closeTo(0, 1e-9));
    });

    test('looking straight down the normal, u/v are the SAME either way', () {
      // Why it survived: on-axis the ray runs along the offset, so a sketch
      // on a face picked correctly as long as you were facing it.
      final cam = _camLookingDownY();
      final fr = PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 0, 1),
          const Vec3(0, 1, 0), const Vec3(0, 25, 0));
      const px = Offset(512, 300);
      final onAxisWrong = cam.rayOnPlane(px, fr.n)!;
      final onAxisRight = cam.rayOnPlane(px, fr.n, fr.origin)!;
      expect((fr.toSketch(onAxisWrong) - fr.toSketch(onAxisRight)).distance,
          lessThan(1e-9));
    });

    test('OFF-axis they differ, which is the drift', () {
      final cam = _camAtAnAngle();
      final fr = PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 0, 1),
          const Vec3(0, 1, 0), const Vec3(0, 25, 0));
      const px = Offset(512, 300);
      final wrong = fr.toSketch(cam.rayOnPlane(px, fr.n)!);
      final right = fr.toSketch(cam.rayOnPlane(px, fr.n, fr.origin)!);
      expect((wrong - right).distance, greaterThan(1.0),
          reason: 'millimetres of error at a working zoom');
    });

    test('the DEPTH now belongs to the plane you tapped', () {
      // The fatal half. A work plane 25 mm ABOVE the origin, camera above:
      // it must read as NEARER than the plane through the origin, or the face
      // behind it wins the sketch-plane pick.
      final cam = _camLookingDownY();
      const px = Offset(400, 400);
      final near = cam.depth(cam.rayOnPlane(px, const Vec3(0, 1, 0),
          const Vec3(0, 25, 0))!);
      final far =
          cam.depth(cam.rayOnPlane(px, const Vec3(0, 1, 0), Vec3.zero)!);
      expect(near, lessThan(far),
          reason: 'the offset plane is closer to a camera above it');
    });

    test('edge-on still returns null rather than a wild number', () {
      final cam = _camLookingDownY();
      // Normal perpendicular to the view direction: the ray never meets it.
      expect(
          cam.rayOnPlane(
              const Offset(400, 400), const Vec3(1, 0, 0), const Vec3(9, 0, 0)),
          isNull);
    });
  });
}
