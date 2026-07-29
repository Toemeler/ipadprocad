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
