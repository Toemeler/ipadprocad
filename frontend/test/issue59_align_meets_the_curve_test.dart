// #59 — "the second point of the line didnt snap to be on the circle."
//
// bug-2026-09-15T165950 has the whole of it in five lines of log and four
// constraints. A circle of r=0.4 at the origin, then a line drawn across it:
//
//   click: toolClick tool=Tool.line w=(-0.25,0.31) picks=0
//   click: toolClick tool=Tool.line w=(0.26,0.31)  picks=1
//
// and what came out was
//
//   [1] line data=[-0.2513, 0.3112, 0.2602, 0.3112]
//   [2] horizontal/ ents=1
//   [3] coincident/ pts=e1.p0 ents=0        <- p0 landed on the circle
//                                           <- and p1 did not
//
// |p0| is 0.3999 and |p1| is 0.4056, so the far end finished 0.006 off the rim
// — close enough to look attached and far enough not to be.
//
// THE CAUSE IS NOT THE TOLERANCE. Both targets were comfortably in range; the
// alignment simply returned first. `computeSnap` looks for an H/V alignment
// with the point already placed, and on finding one it returned there without
// ever reaching the on-curve search below it. An alignment pins ONE coordinate
// and leaves the other wherever the cursor was, which is why the point came
// out level with p0 (y=0.3112 exactly) and nowhere near the circle.
//
// Nor is picking a winner the answer: at that cursor the alignment was the
// NEARER target (0.0012 away against the curve's 0.0046), so "closest wins"
// would have chosen it too. Both are right, and there is a point that is both
// — where the guide crosses the curve. For a chord that point is the far end,
// which is exactly what was being drawn.
//
// The three reports are one sequence: the reporter fixed this by hand with a
// coincidence on p1, which made the line a chord with both ends pinned, and
// #60 and #61 are what that over-constrained sketch then did.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';

/// The device's circle: r=0.4 at the origin.
const double kR = 0.4;
List<Geo> circle() => [
      Geo(Geo.circle, [0, 0, kR])
    ];

/// Where the line's first point ended up, on the rim. This is the app's
/// `ref` — `app.toolPoints.last`, the pick the guides are drawn from.
const Offset kP0 = Offset(-0.2513, 0.3112);

/// The second click, as the log recorded it.
const Offset kClick = Offset(0.26, 0.31);

void main() {
  group('THE REPORT: the second end of a chord', () {
    test('lands ON the circle, not merely level with the first end', () {
      final s = computeSnap(circle(), kClick, 0.02, ref: kP0);

      expect(s, isNotNull);
      expect(s!.pos.distance, closeTo(kR, 1e-9),
          reason: 'the whole report: |p1| was 0.4056 against a radius of 0.4');
    });

    test('...and stays level with it, which is the other half', () {
      final s = computeSnap(circle(), kClick, 0.02, ref: kP0);

      expect(s!.pos.dy, closeTo(kP0.dy, 1e-9),
          reason: 'the horizontal the reporter was also drawing is not given '
              'up to get the coincidence — the crossing satisfies both');
      // Which, for a chord level with a point on the rim, is its mirror.
      expect(s.pos.dx, closeTo(-kP0.dx, 1e-4));
    });

    test('and it is the crossing nearest the cursor, not the far one', () {
      // A horizontal guide cuts a circle twice. Clicking on the left of the
      // sketch must not fling the point across to the right-hand crossing.
      final s = computeSnap(circle(), const Offset(-0.26, 0.31), 0.02,
          ref: const Offset(0.2513, 0.3112));

      expect(s!.pos.dx, lessThan(0));
      expect(s.pos.distance, closeTo(kR, 1e-9));
    });
  });

  group('and the alignment is still there when nothing crosses it', () {
    test('a guide that only grazes the circle stays a guide', () {
      // The tangent case, which is M201's whole subject: the guide through a
      // QUADRANT point touches the rim at one point rather than cutting it.
      // Rounding decides which side a tangency lands on, so it is not offered
      // as a crossing and the alignment is returned unchanged.
      final s = computeSnap(circle(), const Offset(0.399, 0.2), 0.02);

      expect(s, isNotNull);
      expect(s!.kind, 'align');
      expect(s.pos.dx, closeTo(kR, 1e-9));
      expect(s.pos.dy, closeTo(0.2, 1e-9),
          reason: 'the free coordinate is left where the cursor put it');
    });

    test('a crossing too far from the cursor is not reached for', () {
      // The guide runs the width of the sketch, so it will cross geometry the
      // cursor is nowhere near. Here the alignment fires off a point at
      // y=0.3112 while the cursor sits far to the right of the circle: the
      // crossings are ~0.25 away, well outside the tolerance.
      final s = computeSnap(circle(), const Offset(2.0, 0.31), 0.02, ref: kP0);

      expect(s!.kind, 'align');
      expect(s.pos.dx, closeTo(2.0, 1e-9));
    });

    test('a point already on both keeps the alignment untouched', () {
      // Nothing to improve: the cursor is already at the crossing.
      final s =
          computeSnap(circle(), Offset(-kP0.dx, kP0.dy), 0.02, ref: kP0);

      expect(s!.pos.dy, closeTo(kP0.dy, 1e-9));
      expect(s.pos.distance, closeTo(kR, 1e-4));
    });
  });
}
