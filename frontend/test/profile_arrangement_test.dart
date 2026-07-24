// The planar ARRANGEMENT that turns sketch curves into selectable faces.
//
// These are pure geometry, so they pin down on the host exactly what used to
// need a device build: that crossing lines bound a region at all, that the
// stubs sticking out of a crossing are pruned, and that a sketch holding
// several areas offers every one of them.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart' show Geo;
import 'package:ipadprocad/part_model.dart';

Geo ln(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);

SketchModel sketch(List<Geo> gs) {
  final s = SketchModel('t');
  s.geometry.addAll(gs);
  return s;
}

/// 10 x 6 rectangle from four separate lines.
List<Geo> rect() => [
      ln(0, 0, 10, 0),
      ln(10, 0, 10, 6),
      ln(10, 6, 0, 6),
      ln(0, 6, 0, 0),
    ];

void main() {
  test('four lines meeting at their ends give one face', () {
    final loops = arrangementLoops(sketch(rect()));
    expect(loops.length, 1);
    expect(loops.single.area, closeTo(60, 1e-6));
  });

  test('a line CROSSING the rectangle splits it into two faces', () {
    // the cut runs clear through and sticks out on both sides: the stubs are
    // dangling ends and must be pruned, the two halves must both survive
    final loops = arrangementLoops(sketch([...rect(), ln(-4, 3, 14, 3)]));
    expect(loops.length, 2);
    final areas = [for (final l in loops) l.area]..sort();
    expect(areas[0], closeTo(30, 1e-6));
    expect(areas[1], closeTo(30, 1e-6));
  });

  test('an X of two lines encloses nothing', () {
    final loops = arrangementLoops(sketch([ln(0, 0, 10, 10), ln(0, 10, 10, 0)]));
    expect(loops, isEmpty, reason: 'every arm is a dangling end');
  });

  test('a lone open chain encloses nothing', () {
    final loops = arrangementLoops(sketch([ln(0, 0, 10, 0), ln(10, 0, 10, 6)]));
    expect(loops, isEmpty);
  });

  test('two crossing cuts give four faces', () {
    final loops = arrangementLoops(
        sketch([...rect(), ln(-4, 3, 14, 3), ln(5, -4, 5, 10)]));
    expect(loops.length, 4);
    var total = 0.0;
    for (final l in loops) {
      total += l.area;
    }
    expect(total, closeTo(60, 1e-6));
  });

  test('every face is offered as a region, nested loops included', () {
    // a small square sitting inside the big one: the ring AND the island are
    // both pickable, the way Inventor behaves
    final inner = [
      ln(3, 2, 6, 2),
      ln(6, 2, 6, 4),
      ln(6, 4, 3, 4),
      ln(3, 4, 3, 2),
    ];
    final regions = regionsFrom(arrangementLoops(sketch([...rect(), ...inner])));
    expect(regions.length, 2);
    final ring = regions.firstWhere((r) => r.outer.area > 50);
    expect(ring.holes.length, 1, reason: 'the island is the ring\'s hole');
    final island = regions.firstWhere((r) => r.outer.area < 50);
    expect(island.outer.area, closeTo(6, 1e-6));
    expect(island.holes, isEmpty);
  });
}
