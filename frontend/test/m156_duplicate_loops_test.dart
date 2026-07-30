// M156 — the zero-thickness ring that appeared instead of a solid cylinder.
//
// From the device log (build 684d35e), recomputing Extrusion3:
//   loop[0] pts=96 signedArea=176.59 bbox=-7.5,-7.5..7.5,7.5  <-- OUTER
//   loop[1] pts=96 signedArea=176.12 bbox=-7.5,-7.5..7.5,7.5  <-- hole
// Two loops for ONE Ø15 circle: Sketch3 held a projected model edge and a
// circle drawn over it, constrained equal. The region between them is a ring
// about 5 um wide, and that is what got extruded — the ring in the screenshot.
//
// The pair is not bit-identical (separate tessellation, and the projection
// re-derives from the model on every rebuild), so only the enclosed AREA
// identifies them as the same boundary.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

/// A closed polygon sampled on a circle, like the sketcher's own tessellation.
List<Offset> _circle(double r, {int n = 96, double phase = 0, Offset c = Offset.zero}) => [
      for (var i = 0; i < n; i++)
        c + Offset(r * math.cos(2 * math.pi * i / n + phase),
                   r * math.sin(2 * math.pi * i / n + phase))
    ];

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a.abs() / 2;
}

Offset _centroid(List<Offset> p) {
  var x = 0.0, y = 0.0;
  for (final q in p) {
    x += q.dx;
    y += q.dy;
  }
  return Offset(x / p.length, y / p.length);
}

ProfileLoop _loop(int id, List<Offset> pts) =>
    ProfileLoop(id, pts, _area(pts), _centroid(pts), {id});

void main() {
  group('M156 — a duplicated loop is not a hole', () {
    test('the exact device case collapses to ONE loop', () {
      // The two areas straight out of the log.
      final drawn = _loop(0, _circle(7.5));
      final projected = _loop(1, _circle(7.4900, phase: 0.017));
      expect(drawn.area, closeTo(176.588, 0.05));
      expect(projected.area, closeTo(176.12, 0.05));

      final kept = dropDuplicateLoops([drawn, projected]);
      expect(kept.length, 1, reason: 'one circle, one loop');
      expect(kept.single.id, 0, reason: 'the outer twin survives');

      final regions = regionsFrom(kept);
      expect(regions.length, 1);
      expect(regions.single.holes, isEmpty,
          reason: 'a solid disc — this is what produced the ring');
    });

    test('without the twin the region WOULD have been a ring', () {
      // Guards the diagnosis itself: the nesting logic is right, the input
      // was wrong. Both loops present and undeduped = outer with a hole.
      final regions = regionsFrom(
          [_loop(0, _circle(7.5)), _loop(1, _circle(7.4900, phase: 0.017))]);
      final outer = regions.firstWhere((r) => r.outer.id == 0);
      expect(outer.holes.length, 1);
      final ringArea = outer.outer.area - outer.holes.single.area;
      expect(ringArea, lessThan(0.6),
          reason: 'a 94 mm perimeter enclosing 0.5 mm2 is ~5 um thick');
    });

    test('a GENUINE ring is untouched', () {
      final kept =
          dropDuplicateLoops([_loop(0, _circle(10)), _loop(1, _circle(8))]);
      expect(kept.length, 2, reason: 'a real 2 mm wall is not a duplicate');
      final regions = regionsFrom(kept);
      final outer = regions.firstWhere((r) => r.outer.id == 0);
      expect(outer.holes.length, 1, reason: 'still a ring');
    });

    test('a thin but real ring is still kept', () {
      // 0.1 mm wall on a Ø20 circle: 1 % of the area, ten times the cutoff.
      final kept =
          dropDuplicateLoops([_loop(0, _circle(10)), _loop(1, _circle(9.9))]);
      expect(kept.length, 2);
    });

    test('two SEPARATE circles side by side are both kept', () {
      final kept = dropDuplicateLoops([
        _loop(0, _circle(5, c: const Offset(-20, 0))),
        _loop(1, _circle(5, c: const Offset(20, 0))),
      ]);
      expect(kept.length, 2, reason: 'equal areas, but neither is inside the '
          'other — area alone must not merge them');
    });

    test('a real hole inside a rectangle survives', () {
      final rect = _loop(0, const [
        Offset(-20, -20), Offset(20, -20), Offset(20, 20), Offset(-20, 20)
      ]);
      final hole = _loop(1, _circle(5));
      final kept = dropDuplicateLoops([rect, hole]);
      expect(kept.length, 2);
      final regions = regionsFrom(kept);
      expect(regions.firstWhere((r) => r.outer.id == 0).holes.length, 1);
    });

    test('three coincident copies collapse to one', () {
      final kept = dropDuplicateLoops([
        _loop(0, _circle(7.5)),
        _loop(1, _circle(7.4960, phase: 0.01)),
        _loop(2, _circle(7.4930, phase: 0.02)),
      ]);
      expect(kept.length, 1);
      expect(kept.single.id, 0);
    });

    test('an empty or single-loop sketch is returned unchanged', () {
      expect(dropDuplicateLoops(const []), isEmpty);
      final one = [_loop(0, _circle(5))];
      expect(dropDuplicateLoops(one), same(one));
    });
  });
}
