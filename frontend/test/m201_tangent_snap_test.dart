// M201 — a rectangle side should land TANGENT to a circle.
//
//   "the rect i draw should also snap to tangent of the circle while i draw.
//    the second side did not snap to that"
//
// bug20260805T112412 has the asymmetry in its numbers: a circle of r=9.7239 at
// the origin, and a rectangle whose LEFT side sits at exactly -9.7239 while
// the right one sits at 10.0391 instead of 9.7239. The left side landed on the
// tangent by luck — the first corner was placed on the quadrant POINT, which
// was already a snap target — and the second corner had nothing to catch it.
//
// A side is tangent exactly when it sits at x = cx ± r or y = cy ± r, which is
// the vertical/horizontal line through a quadrant point. So this is not a new
// kind of snap: it is the alignment guide that was already there, pointed at
// the four points that were already snap targets.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';

const double kR = 9.7239;

/// The device's circle: r=9.7239 at the origin.
List<Geo> deviceCircle() => [
      Geo(Geo.circle, [0, 0, kR])
    ];

void main() {
  test('THE REPORT: the second corner snaps to the tangent x', () {
    // Where the device ended up: 10.0391, a third of a millimetre off the
    // tangent at 9.7239.
    final s = computeSnap(deviceCircle(), const Offset(10.0391, 19.3653), 1.0);
    expect(s, isNotNull);
    expect(s!.pos.dx, closeTo(kR, 1e-9),
        reason: 'the right side is now tangent');
    expect(s.pos.dy, closeTo(19.3653, 1e-9),
        reason: 'and the height the user dragged to is untouched');
  });

  test('it aligns in y as well, for a horizontal side', () {
    final s = computeSnap(deviceCircle(), const Offset(30, -9.5), 1.0);
    expect(s!.pos.dy, closeTo(-kR, 1e-9));
    expect(s.pos.dx, closeTo(30, 1e-9));
  });

  test('the guide says WHICH point it lined up with', () {
    // The dotted line the viewport draws needs an origin, or the snap is
    // magic: the user has to see that it is the circle's quadrant.
    final s = computeSnap(deviceCircle(), const Offset(10.0391, 19.3653), 1.0);
    expect(s!.kind, 'align');
    expect(s.alignRefs, isNotEmpty);
    expect(s.alignRefs.first.dx, closeTo(kR, 1e-9));
    expect(s.alignRefs.first.dy, closeTo(0, 1e-9));
  });

  test('out of tolerance it does not pull', () {
    // A snap that reaches too far is worse than none: it moves geometry the
    // user did not aim at.
    final s = computeSnap(deviceCircle(), const Offset(14, 19.3653), 1.0);
    expect(s?.pos.dx ?? 14, closeTo(14, 1e-9));
  });

  test('a real point snap still wins over an alignment', () {
    // Priority is unchanged: quadrant/endpoint/centre are placed points, the
    // guides are only a fallback.
    final s = computeSnap(deviceCircle(), const Offset(kR + 0.2, 0.2), 1.0);
    expect(s!.kind, 'quadrant');
    expect(s.pos.dx, closeTo(kR, 1e-9));
    expect(s.pos.dy, closeTo(0, 1e-9));
  });

  test('the previous pick and the origin still align first', () {
    // Ref and origin lead the list, so nothing that used to align stops.
    final s = computeSnap(deviceCircle(), const Offset(40.2, 25),
        1.0, ref: const Offset(40, 3));
    expect(s!.pos.dx, closeTo(40, 1e-9), reason: 'the ref, not a quadrant');
  });

  test('an arc only offers the quadrants it actually reaches', () {
    // A tangent line to the missing part of a circle is tangent to nothing.
    // Upper half only: 0 -> pi, so +x, +y and -x are on it and -y is not.
    final arc = [
      Geo(Geo.arc, [0, 0, 10, 0, 3.14159265358979, 0])
    ];
    expect(computeSnap(arc, const Offset(30, 10.2), 1.0)?.pos.dy,
        closeTo(10, 1e-6),
        reason: 'the +y quadrant is on the arc');
    final below = computeSnap(arc, const Offset(30, -10.2), 1.0);
    expect(below?.pos.dy ?? -10.2, closeTo(-10.2, 1e-9),
        reason: 'the -y quadrant is not');
  });

  test('two circles both offer their tangents', () {
    final gs = [
      Geo(Geo.circle, [0, 0, 5]),
      Geo(Geo.circle, [40, 0, 7]),
    ];
    expect(computeSnap(gs, const Offset(5.1, 20), 1.0)!.pos.dx,
        closeTo(5, 1e-9));
    expect(computeSnap(gs, const Offset(47.1, 20), 1.0)!.pos.dx,
        closeTo(47, 1e-9));
  });
}
