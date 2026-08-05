// Prototype — shared picking arithmetic.
//
// A LEAF file on purpose: `dart:math` and `dart:ui` and nothing else. Three
// separate copies of point-to-segment distance had grown up here (the 2D
// sketcher's `_distToSegment` in tools.dart, the 3D viewport's `_distToSeg`,
// and a third in part_pick.dart), and they could not be merged into any of
// those files without an import cycle — part_model imports tools, so anything
// tools imports must not reach back into part_model.
//
// Everything here is pure arithmetic over Offsets and doubles.
import 'dart:math';
import 'dart:ui';

/// Squared distance from [p] to the segment [a]-[b], and the parameter in
/// 0..1 of the closest point along it.
///
/// Squared, because every caller compares against a tolerance and the square
/// root is only needed for the one candidate that actually wins.
///
/// [eps] is the SQUARED length below which the segment counts as a point.
/// It is a parameter rather than a constant because the callers genuinely
/// disagree: the pickers use 1e-12, while the constraint solver and the 2D
/// modify tools use 1e-18 and depend on that — collapsing them to one value
/// would quietly change solver behaviour for segments between 1e-9 and 1e-6
/// long.
(double, double) segDistSq(Offset p, Offset a, Offset b,
    {double eps = 1e-12}) {
  final vx = b.dx - a.dx, vy = b.dy - a.dy;
  final len2 = vx * vx + vy * vy;
  if (len2 < eps) {
    final dx = p.dx - a.dx, dy = p.dy - a.dy;
    return (dx * dx + dy * dy, 0.0);
  }
  var t = ((p.dx - a.dx) * vx + (p.dy - a.dy) * vy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final cx = a.dx + vx * t, cy = a.dy + vy * t;
  final dx = p.dx - cx, dy = p.dy - cy;
  return (dx * dx + dy * dy, t);
}

/// Keeps the best candidate under the ONE tie-break rule every 3D picker
/// uses: nearest to the camera wins, and pixel distance only decides between
/// candidates at equal depth.
///
/// On any real model the silhouette of a near face and a curve on the far
/// side of the same body project within a few pixels of each other
/// constantly, so choosing purely by pixel distance hands back the thing you
/// cannot see roughly half the time. Face picking already resolved overlaps
/// by depth; edge and sketch-curve picking now do too, where sketch curves
/// previously used pixels alone and really did select hidden geometry.
class PickBest<T> {
  T? value;
  double depth = double.infinity;
  double pixels = double.infinity;

  bool get isEmpty => value == null;

  /// True when a candidate at depth [d], [px] pixels away, would win. Lets a
  /// caller skip building an expensive candidate object that would lose.
  bool wouldTake(double d, double px) =>
      value == null ||
      d < depth - 1e-9 ||
      ((d - depth).abs() <= 1e-9 && px < pixels);

  /// Offers a candidate; returns true when it became the new best.
  bool offer(T candidate, double d, double px) {
    if (!wouldTake(d, px)) return false;
    value = candidate;
    depth = d;
    pixels = px;
    return true;
  }
}

/// M209 — which sweep an ANGLE DIMENSION's arc draws, between two legs.
///
/// "Angle dimensions work good but they look very weird ... currently it's
/// possible to move the dimension so it's not clear that the chosen angle is
/// meant, also no arrows."
///
/// The arc used to be centred on the direction of the LABEL and swept the
/// measured value about it. That draws an arc of the right SIZE at an
/// arbitrary bearing: drag the text around the vertex and the arc follows it,
/// so the picture stops saying which of the four angles at that crossing the
/// number belongs to. Inventor draws the arc from one leg to the other; the
/// text only chooses the radius, and which side it is on.
///
/// Two legs crossing make four angles, and each leg has two directions from
/// the vertex. This picks the pair whose sweep both MEASURES the dimension's
/// value and CONTAINS the label — so the arc always runs between the two real
/// legs, and dragging the text across the vertex switches to the adjacent
/// angle rather than spinning the same one somewhere new.
///
/// [aDir] and [bDir] are the legs' bearings (radians, screen space — y down),
/// [labelDir] the bearing of the text from the vertex, [valueDeg] the measured
/// angle. Returns the arc's start bearing and signed sweep, both in radians.
(double, double) angleArcSpan(
    double aDir, double bDir, double labelDir, double valueDeg) {
  double norm(double a) {
    var v = a;
    while (v <= -pi) {
      v += 2 * pi;
    }
    while (v > pi) {
      v -= 2 * pi;
    }
    return v;
  }

  /// Is [x] inside the sweep that runs from [start] by [sweep]?
  bool contains(double start, double sweep, double x) {
    final rel = sweep >= 0 ? norm(x - start) : norm(start - x);
    final mag = sweep.abs();
    // A hair of slack at both ends: the label sits exactly on a leg when the
    // dimension is first placed, and a strict test would then match nothing.
    return rel >= -1e-9 && rel <= mag + 1e-9;
  }

  final want = valueDeg * pi / 180;
  (double, double)? best;
  var bestErr = double.infinity;
  for (final sa in [aDir, aDir + pi]) {
    for (final sb in [bDir, bDir + pi]) {
      final start = norm(sa);
      final sweep = norm(norm(sb) - start);
      final err = (sweep.abs() - want).abs();
      // Measuring the right angle is the FIRST requirement — an arc of the
      // wrong size under a number is the one lie worse than an arc on the
      // wrong side. Among the pairs that measure it, the one the label sits
      // inside wins. (err is in radians, so at most pi; scaling it past the
      // containment bonus is what makes that ordering hold.)
      final score =
          err * 100 + (contains(start, sweep, labelDir) ? 0.0 : 1.0);
      if (score < bestErr) {
        bestErr = score;
        best = (start, sweep);
      }
    }
  }
  // Nothing matched (parallel legs, a value that is not the angle between
  // them): fall back to the old label-centred arc, which at least draws.
  return best ?? (labelDir - want / 2, want);
}
