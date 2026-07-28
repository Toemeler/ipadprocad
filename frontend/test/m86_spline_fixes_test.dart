// M86 — two reported spline defects, pinned.
//
// (1) THE PHANTOM POINT. While drawing, the preview appends the hover point to
//     the picked points, which is correct for a mouse. A finger and a no-hover
//     Pencil have no cursor once they lift, but hoverWorld was never cleared,
//     so the stale contact point kept acting as an extra fit point — a stray
//     tail past the last grip that vanished on finish. The viewport now clears
//     it on pointer up; what is testable here is the state contract:
//     setHover(null) really does drop the point the preview reads.
//
// (2) LONG SPLINES WENT COARSE. bsplineCurve sampled a FIXED 64 points over
//     the whole curve regardless of how many control vertices it had, so a
//     long spline got under two samples per span and rendered as a polygon.
//     Sampling now scales with the span count, like fitCurve's per-segment
//     sampling always did.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/spline.dart';

/// Control points on a circle of radius [r] — a curve whose true shape is
/// known, so "coarse" can be measured instead of eyeballed.
List<Offset> _ring(int n, {double r = 50}) => [
      for (var i = 0; i < n; i++)
        Offset(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n))
    ];

/// Largest gap between consecutive samples — the visible facet length.
double _maxGap(List<Offset> pts) {
  var worst = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final d = (pts[i] - pts[i - 1]).distance;
    if (d > worst) worst = d;
  }
  return worst;
}

void main() {
  group('long splines stay smooth', () {
    test('sample count grows with the control points', () {
      final short = bsplineCurve(_ring(5));
      final long = bsplineCurve(_ring(60));
      expect(long.length, greaterThan(short.length),
          reason: 'a 60-CV spline must not get the same budget as a 5-CV one');
    });

    test('facet length does not blow up on a long spline', () {
      // Before the fix this was the failure: same 64 samples spread over ten
      // times the curve, so each facet was ~10x longer and visibly straight.
      final short = _maxGap(bsplineCurve(_ring(5, r: 50)));
      final long = _maxGap(bsplineCurve(_ring(60, r: 50)));
      expect(long, lessThan(short * 2),
          reason: 'facets must stay comparable, not scale with CV count');
    });

    test('short splines are unchanged (the old floor still applies)', () {
      expect(bsplineCurve(_ring(5)).length, greaterThanOrEqualTo(65));
    });

    test('an explicit sample count still wins', () {
      expect(bsplineCurve(_ring(8), closed: true, samples: 200).length, 201);
    });

    test('a very long spline is capped, so paint/hit-test stay bounded', () {
      expect(bsplineCurve(_ring(400)).length, lessThanOrEqualTo(4001));
    });

    test('the closed periodic curve still closes exactly', () {
      final c = bsplineCurve(_ring(40), closed: true);
      expect((c.first - c.last).distance, lessThan(1e-9));
    });

    test('the fit spline already scaled and is untouched', () {
      // 24 samples per segment, both before and after M86.
      expect(fitCurve(_ring(5)).length, 1 + 4 * 24);
      expect(fitCurve(_ring(60)).length, 1 + 59 * 24);
    });
  });

  group('the phantom point', () {
    test('clearing the hover drops the extra preview point', () {
      final app = AppState();
      app.setHover(const Offset(10, 10));
      expect(app.hoverWorld, isNotNull);
      // Lifting a finger / no-hover Pencil.
      app.setHover(null);
      expect(app.hoverWorld, isNull,
          reason: 'a lifted finger has no cursor, so the preview must not '
              'append one as a spline fit point');
    });
  });
}
