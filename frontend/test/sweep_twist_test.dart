// A twisted sweep, built as a loft through the section placed along the path
// (lib/sweep_twist.dart): the frame math, and the solid on the real kernel.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/sweep_twist.dart';

const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];

/// Where the placement [m] puts the section point (x, y).
List<double> _place(List<double> m, double x, double y) =>
    [m[0] * x + m[1] * y + m[3], m[4] * x + m[5] * y + m[7], m[8] * x + m[9] * y + m[11]];

void main() {
  group('frames', () {
    test('a straight path: the end is turned by the whole twist, about it',
        () {
      final mats = twistedSweepMats(_identity, [0, 0, 0, 0, 0, 50],
          twistDeg: 90, stations: 4)!;
      expect(mats, hasLength(5));
      expect(_place(mats.first, 5, 0), [closeTo(5, 1e-9), closeTo(0, 1e-9), closeTo(0, 1e-9)]);
      // +90° right-handed about +z: (5, 0) goes to (0, 5), 50 mm along.
      final end = _place(mats.last, 5, 0);
      expect(end[0], closeTo(0, 1e-9));
      expect(end[1], closeTo(5, 1e-9));
      expect(end[2], closeTo(50, 1e-9));
      final mid = _place(mats[2], 5, 0);
      expect(mid[0], closeTo(5 * math.cos(math.pi / 4), 1e-9));
    });

    test('no twist on a bending path: the section does not spin by itself',
        () {
      // A quarter circle in the XZ plane, the section in XY at its start.
      final path = <double>[
        for (var i = 0; i <= 32; i++) ...[
          40 - 40 * math.cos(i / 32 * math.pi / 2),
          0,
          40 * math.sin(i / 32 * math.pi / 2),
        ]
      ];
      final mats = twistedSweepMats(_identity, path, twistDeg: 0, stations: 16)!;
      // Section y (world +y) is perpendicular to the bend plane: it stays +y.
      final m = mats.last;
      expect([m[1], m[5], m[9]], [closeTo(0, 1e-6), closeTo(1, 1e-6), closeTo(0, 1e-6)]);
      // And the section faces the last path segment (1.4° short of +x).
      expect([m[2], m[6], m[10]].map((v) => v.abs()).toList(), [closeTo(1, 0.002), closeTo(0, 1e-6), closeTo(0, 0.05)]);
    });

    test('a path with no length has nothing to twist along', () {
      expect(twistedSweepMats(_identity, [1, 2, 3, 1, 2, 3], twistDeg: 30), isNull);
    });
  });

  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'needs PROTOTYPE_NATIVE_DIR';

  test('the kernel sweeps a square with a twist; area x length is kept',
      () {
    final square = [
      const Offset(-5, -5), const Offset(5, -5),
      const Offset(5, 5), const Offset(-5, 5),
    ];
    final s = kernel.sweep([
      [square]
    ], _identity, [0, 0, 0, 0, 0, 50], twistDeg: 90)!;
    expect(s.volume, closeTo(5000, 5000 * 0.01));
    final bb = s.shape!.bbox()!;
    // Turned 45° half way, so wider than the 10 mm square somewhere.
    expect(bb[3] - bb[0], greaterThan(12));
    expect(bb[5] - bb[2], closeTo(50, 1e-6));
  }, skip: skip);

  test('a twisted ring keeps its hole', () {
    List<Offset> sq(double h) =>
        [Offset(-h, -h), Offset(h, -h), Offset(h, h), Offset(-h, h)];
    final s = kernel.sweep([
      [sq(5), sq(2)]
    ], _identity, [0, 0, 0, 0, 0, 40], twistDeg: 60)!;
    expect(s.volume, closeTo((100 - 16) * 40, (100 - 16) * 40 * 0.01));
  }, skip: skip);

  test('twist and taper together: the end is turned AND scaled', () {
    final k = 1 + math.tan(10 * math.pi / 180);
    final taper =
        twistedSweepTaper(_identity, [0, 0, 0, 0, 0, 50], 10, 5);
    expect(taper.scales.first, 1);
    expect(taper.scales.last, closeTo(k, 1e-12));
    expect(taper.pivot, (0.0, 0.0));
    final square = [
      const Offset(-5, -5), const Offset(5, -5),
      const Offset(5, 5), const Offset(-5, 5),
    ];
    final s = kernel.sweep([
      [square]
    ], _identity, [0, 0, 0, 0, 0, 50], twistDeg: 90, taperDeg: 10);
    expect(s, isNotNull, reason: kernel.lastError);
    if (s == null) return;
    // Side 10 -> 10k, linearly: V = L/3 (A0 + sqrt(A0 A1) + A1).
    const a0 = 100.0;
    final a1 = 100 * k * k;
    expect(s.volume, closeTo(50 / 3 * (a0 + math.sqrt(a0 * a1) + a1), 60));
  }, skip: skip);
}
