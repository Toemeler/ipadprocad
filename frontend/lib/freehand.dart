// Prototype — freehand stroke → spline fit points (M87).
//
// PURE math, no Flutter state: a raw pointer stroke goes in, the fit points of
// an ordinary interpolation spline come out. Keeping it pure is what lets the
// dialog re-fit live on every slider change (the raw stroke is never
// destroyed, so Points and Smoothing are both non-destructive and reversible)
// and lets the host suite exercise the real algorithm.
//
// Pipeline, in this order — the order matters:
//   1. dedupe        raw pointer samples repeat the same pixel while the hand
//                    pauses; duplicates would skew arc-length spacing.
//   2. smooth        moving average over the RAW stroke, before resampling.
//                    Smoothing after resampling would fight the fit points and
//                    round off the very corners the user aimed at.
//   3. resample      by ARC LENGTH into n points, so the fit points are evenly
//                    spread along the curve rather than clustered wherever the
//                    hand happened to move slowly.
//   4. snap          start/end onto a target, or onto each other to close.
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Fewest fit points a freehand curve can be reduced to and still be a curve.
const int kFreehandMinPoints = 2;

/// Ceiling for the Points slider. Beyond this the "spline" is just the raw
/// stroke with every sample as an editable grip, which is unusable as sketch
/// geometry (and is what the M63 gear work had to undo elsewhere).
const int kFreehandMaxPoints = 120;

/// Default fit-point count — enough for a signature-like stroke, few enough
/// that the result is still editable by hand.
const int kFreehandDefaultPoints = 16;

/// Consecutive raw samples closer than this (world mm) are the same point.
const double _kDedupeEps = 1e-6;

/// Drops repeated samples. A stationary pointer emits the same position many
/// times per second, and those duplicates carry no shape.
List<Offset> dedupeStroke(List<Offset> raw) {
  final out = <Offset>[];
  for (final p in raw) {
    if (out.isEmpty || (p - out.last).distance > _kDedupeEps) out.add(p);
  }
  return out;
}

/// Total length of the polyline.
double strokeLength(List<Offset> pts) {
  var len = 0.0;
  for (var i = 1; i < pts.length; i++) {
    len += (pts[i] - pts[i - 1]).distance;
  }
  return len;
}

/// Moving-average smoothing with the ENDS PINNED.
///
/// [amount] is 0..1; 0 returns the stroke untouched. The window grows with the
/// stroke's own sample count, so the same slider position means the same
/// visual smoothing whether the stroke has 80 samples or 800 — a fixed window
/// would barely touch a long stroke and destroy a short one.
///
/// The endpoints never move: they are where the user started and stopped, and
/// they are what start/end snapping attaches to.
List<Offset> smoothStroke(List<Offset> pts, double amount) {
  if (pts.length < 3 || amount <= 0) return List.of(pts);
  final a = amount.clamp(0.0, 1.0);
  // Half-window: up to 12% of the stroke on each side at full strength.
  final half = math.max(1, (pts.length * 0.12 * a).round());
  final passes = a > 0.66 ? 3 : (a > 0.33 ? 2 : 1);
  var cur = List.of(pts);
  for (var pass = 0; pass < passes; pass++) {
    final next = List<Offset>.of(cur);
    for (var i = 1; i < cur.length - 1; i++) {
      // The window shrinks near the ends so the pinned endpoints are not
      // dragged inward by a lopsided average.
      final w = math.min(half, math.min(i, cur.length - 1 - i));
      var sx = 0.0, sy = 0.0;
      for (var j = i - w; j <= i + w; j++) {
        sx += cur[j].dx;
        sy += cur[j].dy;
      }
      final n = 2 * w + 1;
      next[i] = Offset(sx / n, sy / n);
    }
    cur = next;
  }
  return cur;
}

/// Resamples [pts] into exactly [n] points spaced evenly by ARC LENGTH.
///
/// The first and last points are preserved exactly; the rest are linearly
/// interpolated along the polyline. A degenerate stroke (zero length) returns
/// its single position repeated, which the caller rejects.
List<Offset> resampleByArcLength(List<Offset> pts, int n) {
  if (pts.isEmpty) return const [];
  final want = n.clamp(kFreehandMinPoints, kFreehandMaxPoints);
  if (pts.length == 1) return [pts.first, pts.first];
  final total = strokeLength(pts);
  if (total <= 0) return [pts.first, pts.last];
  final step = total / (want - 1);
  final out = <Offset>[pts.first];
  var seg = 0;
  var walked = 0.0; // arc length consumed up to the START of segment `seg`
  for (var i = 1; i < want - 1; i++) {
    final target = step * i;
    while (seg < pts.length - 2) {
      final segLen = (pts[seg + 1] - pts[seg]).distance;
      if (walked + segLen >= target) break;
      walked += segLen;
      seg++;
    }
    final segLen = (pts[seg + 1] - pts[seg]).distance;
    final t = segLen <= 0 ? 0.0 : ((target - walked) / segLen).clamp(0.0, 1.0);
    out.add(Offset.lerp(pts[seg], pts[seg + 1], t)!);
  }
  out.add(pts.last);
  return out;
}

/// The result of fitting a stroke: the spline's fit points, and whether the
/// curve closed onto its own start.
class FreehandFit {
  /// Fit points. When [closed] is true the LAST point equals the first
  /// exactly, which is the convention `buildToolGeometry` already uses to
  /// close a spline (see `_spline` in tools.dart) — so a freehand curve
  /// commits through the ordinary tool pipeline with no special case.
  final List<Offset> points;
  final bool closed;

  /// True when an endpoint was pulled onto an existing sketch point, so the
  /// UI can say so rather than leaving the user guessing.
  final bool snappedStart, snappedEnd;

  const FreehandFit(this.points, this.closed,
      {this.snappedStart = false, this.snappedEnd = false});

  bool get isUsable => points.length >= kFreehandMinPoints;
  static const FreehandFit empty = FreehandFit([], false);
}

/// Fits a raw stroke into spline fit points.
///
/// [points] is the requested fit-point count, [smoothing] 0..1. When
/// [snapClosed] is on and the two ends are within [snapTol], the curve is
/// closed exactly. When [snapTargets] is non-empty the two ENDPOINTS are
/// pulled onto the nearest target within [snapTol] — endpoints only, because
/// snapping interior fit points would drag the curve off the stroke the user
/// actually drew.
///
/// Closing wins over endpoint snapping: a user who asked for a closed curve
/// gets one, rather than two ends stuck to two different neighbours.
FreehandFit fitFreehandStroke(
  List<Offset> raw, {
  int points = kFreehandDefaultPoints,
  double smoothing = 0.35,
  bool snapClosed = false,
  bool snapToPoints = false,
  List<Offset> snapTargets = const [],
  double snapTol = 2.0,
}) {
  final clean = dedupeStroke(raw);
  if (clean.length < 2) return FreehandFit.empty;
  final smoothed = smoothStroke(clean, smoothing);
  final fit = resampleByArcLength(smoothed, points);
  if (fit.length < 2) return FreehandFit.empty;

  // 1. close onto the start?
  if (snapClosed && (fit.first - fit.last).distance <= snapTol) {
    final closed = List<Offset>.of(fit);
    closed[closed.length - 1] = closed.first; // EXACT — the close convention
    return FreehandFit(closed, true);
  }

  // 2. otherwise pull the free ends onto nearby existing points
  if (!snapToPoints || snapTargets.isEmpty) return FreehandFit(fit, false);
  Offset? nearest(Offset p) {
    Offset? best;
    var bestD = snapTol;
    for (final t in snapTargets) {
      final d = (t - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = t;
      }
    }
    return best;
  }

  final out = List<Offset>.of(fit);
  final a = nearest(out.first), b = nearest(out.last);
  if (a != null) out[0] = a;
  if (b != null) out[out.length - 1] = b;
  // Snapping both ends to the SAME target closes the curve — the user drew a
  // loop back to where they started and it should behave like one.
  if (out.length >= 3 && (out.first - out.last).distance < 1e-9) {
    return FreehandFit(out, true, snappedStart: a != null, snappedEnd: b != null);
  }
  return FreehandFit(out, false,
      snappedStart: a != null, snappedEnd: b != null);
}
