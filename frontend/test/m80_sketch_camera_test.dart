// M80 — the sketch camera must reproduce the 2D editor's projection exactly.
//
// This is the whole risk of keeping the live 3D scene behind a sketch: if the
// camera disagrees with Viewport2D.map() by even a little, the model slides
// away from the cursor, which is worse than the stutter it replaces. So the
// agreement is pinned here rather than eyeballed on device.
//
// The case that actually matters is a TILTED face. On xy/xz/yz a missing roll
// is invisible, which is exactly how such a bug survives review.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

const _size = Size(800, 600);

PlaneFrame _tilted(double deg) {
  final a = deg * math.pi / 180;
  // rotate the xy frame about its x axis
  final v = Vec3(0, math.cos(a), math.sin(a));
  final n = Vec3(0, -math.sin(a), math.cos(a));
  return PlaneFrame('face', const Vec3(1, 0, 0), v, n, const Vec3(3, -2, 5));
}

/// Where Viewport2D.map() puts a sketch point.
Offset map2d(Offset p, Offset pan, double zoom, Size s) => Offset(
    s.width / 2 + (p.dx - pan.dx) * zoom,
    s.height / 2 - (p.dy - pan.dy) * zoom);

void main() {
  group('the sketch camera matches the 2D editor', () {
    for (final deg in [0.0, 15.0, 42.0, 90.0, 137.0]) {
      test('on a face tilted $deg degrees', () {
        final fr = _tilted(deg);
        const pan = Offset(2.5, -1.25);
        const zoom = 4.0;
        final cam = Cam3(
            PartCamera.forSketch(fr, _size, pan, zoom), _size);

        for (final sk in const [
          Offset(0, 0),
          Offset(12, 7),
          Offset(-8.5, 3.25),
          Offset(4, -11),
        ]) {
          // the same point, once through the 2D map and once through the 3D
          // camera after being placed in world space on the sketch plane
          final want = map2d(sk, pan, zoom, _size);
          final got = cam.project(fr.toWorld(sk));
          expect(got.dx, closeTo(want.dx, 1e-6),
              reason: 'x drifts at $deg deg');
          expect(got.dy, closeTo(want.dy, 1e-6),
              reason: 'y drifts at $deg deg — this is what a missing roll '
                  'does, and it is invisible on the origin planes');
        }
      });
    }

    test('the view direction is the sketch normal', () {
      final fr = _tilted(37);
      final c = PartCamera.forSketch(fr, _size, Offset.zero, 1);
      expect(c.dir.x, closeTo(fr.n.x, 1e-9));
      expect(c.dir.y, closeTo(fr.n.y, 1e-9));
      expect(c.dir.z, closeTo(fr.n.z, 1e-9));
    });

    test('zoom maps to halfH so screen scale matches', () {
      final fr = _tilted(0);
      for (final z in [0.5, 1.0, 7.5]) {
        final c = PartCamera.forSketch(fr, _size, Offset.zero, z);
        expect(c.halfH, closeTo(_size.height / (2 * z), 1e-9));
      }
    });

    test('a degenerate zoom cannot produce a broken camera', () {
      final c = PartCamera.forSketch(_tilted(0), _size, Offset.zero, 0);
      expect(c.halfH.isFinite, isTrue);
      expect(c.halfH, greaterThan(0));
    });
  });

  group('roll is opt-in', () {
    test('roll 0 leaves the derived basis exactly as it was', () {
      final c = PartCamera(az: 0.7, pol: 1.1, halfH: 27);
      expect(c.roll, 0);
      final cam = Cam3(c, _size);
      // basis must be orthonormal and consistent with the direction
      expect(cam.s.dot(cam.u), closeTo(0, 1e-9));
      expect(cam.s.length, closeTo(1, 1e-9));
      expect(cam.u.length, closeTo(1, 1e-9));
      expect(cam.s.dot(cam.dir), closeTo(0, 1e-9));
    });

    test('a rolled basis stays orthonormal', () {
      final c = PartCamera(az: 0.3, pol: 0.9, halfH: 10, roll: 1.234);
      final cam = Cam3(c, _size);
      expect(cam.s.dot(cam.u), closeTo(0, 1e-9));
      expect(cam.s.length, closeTo(1, 1e-9));
      expect(cam.u.length, closeTo(1, 1e-9));
    });
  });
}
