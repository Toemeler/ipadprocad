// #63 / #60 — "i couldnt make a dimension from the line to the top of the
// circle or to the bottom of the circcle i had to make a dimension to the
// middle".
//
// bug-2026-09-16T152626 (build 4245449) has the whole of it. The sketch is a
// circle of r=0.4 pinned at the origin and a horizontal CHORD across it, both
// ends bound to the rim:
//
//   [0] circle data=[0.0000, 0.0000, 0.4000]
//   [1] line   data=[-0.2299, 0.3273, 0.2299, 0.3273]
//   [3] coincident/ pts=e1.p0 ents=0
//   [4] coincident/ pts=e1.p1 ents=0
//
// The user dimensions the line to the circle's rim — M202's tangent kind —
// and types 0.3. What the log says:
//
//   slvs: bail: unsupported dimKind=plinetan
//   lm: ... err=2.71e-1 satisfied=false
//   solve: solveAndRebuild: unsatisfied — sketch left unchanged
//   ui: notice: Value cannot be satisfied with the current constraints.
//
// and the sketch it had thrashed its way to on the way there, with the circle
// off its pin, the radius off its diameter dimension and the chord collapsed
// to a fifth of a millimetre:
//
//   [0] circle data=[-0.0006, -0.0873, 0.3718]
//   [1] line   data=[-0.0127, 0.3561, 0.0129, 0.3558]
//
// THE SYSTEM REALLY WAS UNSATISFIABLE, and the solver is not at fault for
// failing to satisfy it. M202 measures the tangent gap as `centre distance
// less the radius` — right for a line that passes OUTSIDE the circle, which
// is the only case it was written against. A chord is inside: its centre
// distance is 0.3273 against a radius of 0.4, so that expression is NEGATIVE,
// and `measureDim` clamped it to 0 rather than report a negative gap.
//
// So driving it to 0.3 asked for a centre distance of 0.7 on a chord whose
// own ends are pinned to a rim 0.4 away. No such sketch exists. The solver
// went looking anyway, and wrecked the four constraints that WERE satisfiable
// trying to buy the one that was not.
//
// The gap the user is pointing at is the other one: from the chord out to the
// quadrant point BEYOND the centre — `radius less the centre distance`, 0.0727
// here, and 0.3 once driven. It is the distance the painter has been drawing
// the whole time, because `_paintDim` already walks from the centre toward the
// line by a full radius and lands on that quadrant point. Only the number
// disagreed with the picture.
//
// Both readings are "the nearest point of the circle"; which one applies is
// decided by whether the line cuts, and it is frozen per solve exactly like
// the side is, because the two swap at tangency.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';

Geo circle(double x, double y, double r) => Geo(Geo.circle, [x, y, r]);
Geo line(double x0, double y0, double x1, double y1) =>
    Geo(Geo.line, [x0, y0, x1, y1]);

/// The device's sketch: r=0.4 at the origin, a horizontal chord at [h] with
/// both ends on the rim. [h] is signed, so a negative one is the chord below
/// the centre — the "or to the bottom of the circcle" half of the report.
(List<Geo>, List<Constraint>) chordSketch(double h) {
  // sqrt(0.4^2 - h^2) — at the device's h this is 0.2299, to the digit.
  final half = math.sqrt(0.16 - h * h);
  final gs = [circle(0, 0, 0.4), line(-half, h, half, h)];
  final cs = <Constraint>[
    // `coincident/ pts=projCP,e0.p0` on the device: the circle is on the
    // sketch's own origin and cannot drift.
    Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [0, 0]),
    Constraint(CType.dimension, ents: [0], dimKind: 'dia')..value = 0.8,
    Constraint(CType.horizontal, ents: [1]),
    Constraint(CType.coincident, pts: [PRef(1, 0)], ents: [0]),
    Constraint(CType.coincident, pts: [PRef(1, 1)], ents: [0]),
  ];
  return (gs, cs);
}

Constraint tangentDim(double v) => Constraint(CType.dimension,
    pts: [PRef(0, 0), PRef(1, 0), PRef(1, 1)],
    ents: [0],
    dimKind: 'plinetan')
  ..value = v;

void main() {
  group('THE REPORT: a chord, dimensioned to the top of the circle', () {
    test('reads the gap to the quadrant point, not a clamped zero', () {
      final (gs, _) = chordSketch(0.3273);
      // 0.4 - 0.3273. The old measure said 0, which is why the value box
      // opened on 0 and why "to the middle" was the only thing that worked.
      expect(measureDim(gs, tangentDim(0)), closeTo(0.0727, 1e-4));
    });

    test('and driving it to 0.3 SOLVES, instead of "cannot be satisfied"', () {
      final (gs, cs) = chordSketch(0.3273);
      cs.add(tangentDim(0.3));

      expect(solveConstraints(gs, cs), isTrue,
          reason: 'the whole report: this came back false and the edit was '
              'rolled back with a toast');

      // The chord at 0.1 stands 0.3 below the top of a circle of radius 0.4.
      expect(gs[1].data[1], closeTo(0.1, 1e-3));
      expect(gs[1].data[3], closeTo(0.1, 1e-3));
      expect(measureDim(gs, cs.last), closeTo(0.3, 1e-3));
    });

    test('...without paying for it out of the other constraints', () {
      // resid=0.0873 on the centre pin, 0.0564 on the diameter and 0.0718 on
      // a point-on-circle is what the failing solve left behind. A solve that
      // reaches its target and breaks four binds on the way is not a fix.
      final (gs, cs) = chordSketch(0.3273);
      cs.add(tangentDim(0.3));
      expect(solveConstraints(gs, cs), isTrue);

      expect(gs[0].data[0], closeTo(0, 1e-6), reason: 'centre still pinned');
      expect(gs[0].data[1], closeTo(0, 1e-6));
      expect(gs[0].data[2], closeTo(0.4, 1e-6), reason: 'dia 0.8 still held');
      for (final k in [0, 2]) {
        final x = gs[1].data[k], y = gs[1].data[k + 1];
        expect(math.sqrt(x * x + y * y), closeTo(0.4, 1e-3),
            reason: 'ends still on the rim');
      }
    });

    test('and the bottom of the circle works the same way', () {
      final (gs, cs) = chordSketch(-0.3273);
      cs.add(tangentDim(0.3));
      expect(solveConstraints(gs, cs), isTrue);
      // Still below the centre: a distance is never satisfied by mirroring the
      // chord through to the other side.
      expect(gs[1].data[1], closeTo(-0.1, 1e-3));
      expect(measureDim(gs, cs.last), closeTo(0.3, 1e-3));
    });
  });

  group('#61 — "and the line is gone now"', () {
    // The same clamp, one step earlier and far more destructive.
    // `confirmDimension` creates the dimension at its MEASURED value before
    // the typed one is applied. Measured 0 on a chord, so the sketch was
    // committed with `plinetan == 0` — which says the line is TANGENT to the
    // circle. The solver did exactly as it was told:
    //
    //   [1] line data=[-0.0003, 0.4000, 0.0003, 0.4000]
    //
    // a chord of 0.0006 sitting on the top quadrant point. That is the line
    // the reporter could not find. bug-2026-09-15T170254's state.txt, and its
    // `[5] dimension/plinetan ... value=0.0000` beside it.
    test('creating the dimension at its measured value is a no-op', () {
      final (gs, cs) = chordSketch(0.3273);
      final d = tangentDim(measureDim(gs, tangentDim(0)));
      cs.add(d);

      expect(solveConstraints(gs, cs), isTrue);
      final dx = gs[1].data[2] - gs[1].data[0];
      expect(dx.abs(), closeTo(2 * math.sqrt(0.16 - 0.3273 * 0.3273), 1e-3),
          reason: 'THE REPORT: the chord collapsed to 0.0006 long and the '
              'reporter went looking for a line that was still there');
      expect(gs[1].data[1], closeTo(0.3273, 1e-3),
          reason: 'and it did not climb to the top of the circle');
    });
  });

  group('and the line that does NOT cut the circle is untouched', () {
    // M202's own fixture: a line on y=0 and a circle of r=5 centred 20 above,
    // so the tangent gap is 15. Everything in this group must read exactly as
    // it did before, because that case was always right.
    test('still measures the centre distance less the radius', () {
      final gs = [line(-40, 0, 40, 0), circle(0, 20, 5)];
      final d = Constraint(CType.dimension,
          pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
          ents: [1],
          dimKind: 'plinetan')
        ..value = 0;
      expect(measureDim(gs, d), closeTo(15, 1e-9));
    });

    test('and still drives from outside, on its own side', () {
      final gs = [line(-40, 0, 40, 0), circle(0, 20, 5)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [-40, 0, 40, 0]),
        Constraint(CType.dimension, ents: [1], dimKind: 'rad')..value = 5,
        Constraint(CType.dimension,
            pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
            ents: [1],
            dimKind: 'plinetan')
          ..value = 25,
      ];
      expect(solveConstraints(gs, cs), isTrue);
      expect(gs[1].data[1], closeTo(30, 1e-3), reason: 'centre 25+5 up');
      expect(gs[1].data[1], greaterThan(0), reason: 'not mirrored below');
    });
  });
}
