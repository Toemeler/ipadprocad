// M88 — the camera swing into and out of a sketch.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

void main() {
  group('PartCamera.lerp', () {
    test('t=0 and t=1 are the endpoints exactly', () {
      final a = PartCamera(az: 0.3, pol: 1.0, halfH: 27, ox: 1, oy: 2);
      final b = PartCamera(az: 2.1, pol: 0.2, halfH: 5, ox: -4, oy: 8, roll: 1);
      for (final (t, want) in [(0.0, a), (1.0, b)]) {
        final g = PartCamera.lerp(a, b, t);
        expect(g.az, closeTo(want.az, 1e-9));
        expect(g.pol, closeTo(want.pol, 1e-9));
        expect(g.halfH, closeTo(want.halfH, 1e-9));
        expect(g.ox, closeTo(want.ox, 1e-9));
        expect(g.roll, closeTo(want.roll, 1e-9));
      }
    });

    test('angles take the SHORT way round the wrap', () {
      // az comes from atan2, so a pair straddling +/-pi is routine. A plain
      // lerp would spin the model almost a full turn.
      final a = PartCamera(az: 3.0);
      final b = PartCamera(az: -3.0);
      final mid = PartCamera.lerp(a, b, 0.5).az;
      // short way is 0.28 rad across the wrap, so the midpoint sits just
      // beyond +pi (equivalently just under -pi), NOT near 0.
      final viaZero = (mid).abs() < 1.0;
      expect(viaZero, isFalse,
          reason: 'went the long way round: mid=$mid');
      final d = (mid - a.az).abs();
      expect(d, lessThan(0.3));
    });

    test('short way is used for roll too', () {
      final g = PartCamera.lerp(
          PartCamera(roll: 3.1), PartCamera(roll: -3.1), 0.5);
      expect((g.roll.abs() - math.pi).abs(), lessThan(0.1));
    });

    test('zoom interpolates geometrically, not linearly', () {
      // Zoom is multiplicative. Linear halfway between 27 and 2700 is 1363,
      // which already looks fully zoomed out; the true midpoint is 270.
      final g = PartCamera.lerp(
          PartCamera(halfH: 27), PartCamera(halfH: 2700), 0.5);
      expect(g.halfH, closeTo(270, 1e-6));
    });

    test('a degenerate halfH cannot produce a broken camera', () {
      final g = PartCamera.lerp(
          PartCamera(halfH: 0), PartCamera(halfH: 100), 0.5);
      expect(g.halfH.isFinite, isTrue);
      expect(g.halfH, greaterThan(0));
    });

    test('t outside 0..1 is clamped', () {
      final a = PartCamera(ox: 0), b = PartCamera(ox: 10);
      expect(PartCamera.lerp(a, b, -5).ox, closeTo(0, 1e-9));
      expect(PartCamera.lerp(a, b, 5).ox, closeTo(10, 1e-9));
    });
  });
}
