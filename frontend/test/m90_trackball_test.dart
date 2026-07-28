// M90 — trackball orbit (Inventor's Free Orbit, Blender's trackball).
//
// The old orbit added onto az/pol and clamped pol to [0.02, pi-0.02], so the
// view could never look straight down and certainly never continue past it.
// These tests are mostly about what USED to be impossible.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

double _ang(Vec3 a, Vec3 b) =>
    math.acos(a.normalized().dot(b.normalized()).clamp(-1.0, 1.0));

void main() {
  group('the pole is no longer a wall', () {
    test('a long pitch drag sweeps through BOTH poles', () {
      // The old clamp held pol in [0.02, pi-0.02], so this trajectory could
      // never touch either pole, let alone pass through. One continuous drag
      // must now reach straight-down AND straight-up and carry on.
      final c = PartCamera(az: 0.7, pol: 0.955);
      var lo = 1.0, hi = -1.0;
      for (var i = 0; i < 300; i++) {
        c.orbitScreen(0, 0.02); // small steps, the way a real drag arrives
        if (c.dir.y < lo) lo = c.dir.y;
        if (c.dir.y > hi) hi = c.dir.y;
      }
      expect(lo, lessThan(-0.999), reason: 'never reached one pole');
      expect(hi, greaterThan(0.999), reason: 'never reached the other');
    });

    test('a full turn of pitch returns to the start', () {
      final c = PartCamera(az: 0.3, pol: 1.2);
      final d0 = c.dir;
      final r0 = c.right;
      const n = 360;
      for (var i = 0; i < n; i++) {
        c.orbitScreen(0, 2 * math.pi / n);
      }
      expect(_ang(c.dir, d0), lessThan(1e-6), reason: 'direction drifted');
      expect(_ang(c.right, r0), lessThan(1e-6), reason: 'roll drifted');
    });

    test('looking exactly straight down is a legal state', () {
      final c = PartCamera()..setBasis(const Vec3(0, 1, 0), const Vec3(1, 0, 0));
      expect(c.pol, closeTo(0, 1e-9));
      expect(c.dir.y, closeTo(1, 1e-9));
      // and orbiting onward from there still works
      c.orbitScreen(0, 0.1);
      expect(c.dir.y, lessThan(1.0));
    });
  });

  group('the basis survives use', () {
    test('stays orthonormal over a thousand drag events', () {
      final c = PartCamera(az: 0.2, pol: 1.0, roll: 0.4);
      final rnd = math.Random(11);
      for (var i = 0; i < 1000; i++) {
        c.orbitScreen(
            (rnd.nextDouble() - 0.5) * 0.2, (rnd.nextDouble() - 0.5) * 0.2);
      }
      expect(c.dir.length, closeTo(1, 1e-9));
      expect(c.right.length, closeTo(1, 1e-9));
      expect(c.right.dot(c.dir).abs(), lessThan(1e-9),
          reason: 'right drifted off perpendicular');
      expect(c.up.length, closeTo(1, 1e-9));
      expect(c.pol.isFinite && c.az.isFinite && c.roll.isFinite, isTrue);
    });

    test('setBasis round-trips direction and right exactly', () {
      final rnd = math.Random(3);
      for (var i = 0; i < 50; i++) {
        final d = Vec3(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1,
                rnd.nextDouble() * 2 - 1)
            .normalized();
        // any vector perpendicular to d
        var t = const Vec3(0, 1, 0);
        if (d.cross(t).length < 1e-3) t = const Vec3(1, 0, 0);
        final r = d.cross(t).normalized();
        final c = PartCamera()..setBasis(d, r);
        expect(_ang(c.dir, d), lessThan(1e-6));
        expect(_ang(c.right, r), lessThan(1e-6));
      }
    });

    test('setBasis re-orthogonalises a sloppy right vector', () {
      final c = PartCamera()
        ..setBasis(const Vec3(0, 0, 1), const Vec3(1, 0, 0.3));
      expect(c.right.dot(c.dir).abs(), lessThan(1e-9));
      expect(c.right.length, closeTo(1, 1e-9));
    });
  });

  group('it behaves like a ball, not a turntable', () {
    test('yaw then pitch differs from pitch then yaw', () {
      // Rotations do not commute; a turntable on two angles cannot show this,
      // and that difference is what makes a trackball feel free.
      final a = PartCamera(az: 0.5, pol: 1.0)
        ..orbitScreen(0.4, 0)
        ..orbitScreen(0, 0.4);
      final b = PartCamera(az: 0.5, pol: 1.0)
        ..orbitScreen(0, 0.4)
        ..orbitScreen(0.4, 0);
      expect(_ang(a.dir, b.dir), greaterThan(0.01));
    });

    test('yaw alone keeps the horizon, pitch alone tilts it', () {
      final c = PartCamera(az: 0.0, pol: math.pi / 2, roll: 0);
      final up0 = c.up;
      c.orbitScreen(0.5, 0);
      expect(_ang(c.up, up0), lessThan(1e-6),
          reason: 'a pure yaw about the camera up must not roll the view');
    });

    test('zero input changes nothing', () {
      final c = PartCamera(az: 0.9, pol: 1.3, roll: -0.2);
      final d0 = c.dir, r0 = c.right;
      c.orbitScreen(0, 0);
      expect(_ang(c.dir, d0), lessThan(1e-12));
      expect(_ang(c.right, r0), lessThan(1e-12));
    });
  });
}
