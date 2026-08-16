// Spline sampling (Inventor-style).
//
// The vendored QCAD core is built with splines deferred (R_NO_OPENNURBS), so a
// spline cannot be a backend entity. Instead a spline is stored as a POLYLINE
// whose vertices are the FEW control/fit points, tagged Dart-side as
// Geo.splineCv (control-vertex B-spline), Geo.splineFit (interpolation /
// fit-point) or Geo.splineBez (a cubic Bézier chain — what Trim and Split
// produce, see bezier.dart). That means the user edits only those points —
// exactly like Inventor — while these functions turn them into the smooth
// curve used for rendering, hit-testing and on-curve snapping. The vertices
// still round-trip through the backend as an ordinary polyline; the tag is
// restored from the sidecar (and preserved across the engine refresh) so the
// curve survives.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'bezier.dart';
import 'ffi/qcad_engine.dart';
import 'gear.dart' show gearCurve, arcChainResample;

/// The control/fit points of a (possibly spline-tagged) polyline [g].
List<Offset> polyPoints(Geo g) {
  if (g.type != Geo.polyline) return const [];
  final n = g.data[1].toInt();
  return [
    for (var i = 0; i < n; i++)
      Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
  ];
}

/// Sampled curve for a spline-tagged polyline. For a plain polyline (or a
/// degenerate spline with < 3 points) this returns the control points unchanged,
/// so callers can treat every polyline uniformly.
///
/// [tolMm] is the largest distance the returned chain may deviate from the
/// true curve. Leave it null for the MODEL tolerance ([_modelTol]) — the right
/// choice for hit-testing, snapping, intersections and trimming. The painter
/// passes a tolerance derived from the ZOOM instead, so the curve is smooth at
/// whatever magnification it is actually being looked at.
///
/// M219 — this used to return `arcChainResample(dense, ...)`, i.e. the curve
/// decimated onto a chain of true arcs with FIVE points per arc. That chain
/// exists for the 3D path (see [splineArcChain]) and it is a terrible display
/// curve: the tolerance it respects is the ARC's deviation, not the deviation
/// of the five chords drawn between its points. A gentle 200 mm S-spline came
/// out as 25 points with 10 mm chords — a visible polygon at any working zoom,
/// which is the whole of "splines are low resolution sometimes". Rendering,
/// picking and snapping now get the real curve; only the profile chain that
/// feeds the kernel still gets arcs.
List<Offset> splineCurveFor(Geo g, {double? tolMm}) {
  final pts = polyPoints(g);
  // A gear stores only [centre, handle] + a parameter block; the full involute
  // tooth outline is generated from them (gear.dart). Everything that draws or
  // snaps a curve funnels through here, so this one line makes gears render,
  // hit-test, snap and extrude like any other closed curve.
  if (g.spline == Geo.gearTag) return gearCurve(g);
  if (g.spline == Geo.straight || pts.length < 3) return pts;
  final tol = _sanitiseTol(tolMm ?? _modelTol(pts));
  final key = _key(g, tol);
  final cached = _recall(key, g, tol);
  if (cached != null) return cached;
  final closed = g.data[0] != 0;
  final List<Offset> curve;
  if (g.spline == Geo.ellipseTag) {
    // The ellipse stays ANALYTIC: its sampler is exact, so there is nothing to
    // gain from routing it through the (very slightly approximate) Bézier arc
    // form that the trim path needs.
    curve = ellipseCurve(pts, tolMm: tol);
  } else {
    final path = bezPathOf(g);
    curve = path == null
        ? (g.spline == Geo.splineCv
            ? bsplineCurve(pts, closed: closed)
            : fitCurve(pts, closed: closed))
        : path.flatten(tol, maxDepth: _maxDepth(path.count));
  }
  _remember(key, g, tol, curve);
  return curve;
}

/// The curve of [g] put on a chain of TRUE arcs, for the 3D profile path only.
///
/// Sampled as a plain polyline a spline extrudes into a prism of flat strips,
/// and every strip boundary is a genuine crease that the tangent filter cannot
/// hide. Points that lie on arcs give `arcFitLoop` exact bulges instead, so the
/// prism gets near-tangent cylindrical faces (same reason the gear flank is an
/// arc chain, see gear.dart). The tolerance scales with the curve so a 2 mm
/// detail and a 200 mm outline are both handled sensibly.
///
/// The arc budget is generous on purpose: at the old default of 64 a long or
/// wiggly spline spent it before reaching the end, and `_greedySpans` then
/// covered the whole remainder with ONE arc — the tail of the profile simply
/// left the curve.
List<Offset> splineArcChain(Geo g) {
  final dense = splineCurveFor(g);
  if (dense.length < 4) return dense;
  return arcChainResample(dense, tolMm: _splineArcTol(dense), maxArcs: 512);
}

/// Arc-fit tolerance for a spline: 0.02% of its bounding box, clamped to a
/// sane absolute band. Below this nothing is visible at any usable zoom.
double _splineArcTol(List<Offset> pts) {
  final span = _extentOf(pts);
  if (span <= 0) return 5e-3;
  return (span * 2e-4).clamp(1e-3, 5e-2).toDouble();
}

/// Largest side of the bounding box of [pts].
double _extentOf(List<Offset> pts) {
  if (pts.isEmpty) return 0;
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final p in pts) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return math.max(maxX - minX, maxY - minY);
}

/// The MODEL tolerance for a curve of this size: 0.001% of its extent, in a
/// band that keeps a 2 mm fillet-sized curve honest without turning a 2 m
/// outline into tens of thousands of points. Everything geometric — picking,
/// snapping, intersecting, trimming — is accurate to this.
double _modelTol(List<Offset> pts) =>
    (_extentOf(pts) * 1e-5).clamp(2e-4, 5e-3).toDouble();

/// Screen-driven tolerance: [pxPerUnit] is the viewport scale, and a curve
/// that is within a fifth of a pixel of straight IS straight on that screen.
/// Bucketed to powers of two so a pinch-zoom does not miss the cache on every
/// single frame.
double splineDisplayTol(double pxPerUnit) {
  if (!pxPerUnit.isFinite || pxPerUnit <= 0) return 1e-3;
  final raw = 0.2 / pxPerUnit;
  final e = (math.log(raw) / math.ln2).floor();
  return math.pow(2.0, e).toDouble();
}

double _sanitiseTol(double t) =>
    (t.isFinite && t > 1e-9 ? t : 1e-9).clamp(1e-9, 1e3).toDouble();

/// Subdivision budget per Bézier segment. A short chain may spend 2^10 = 1024
/// points on ONE segment — a deeply zoomed 4-point spline is a single cubic and
/// deserves them; a 40-point spline (dozens of segments) is held to less, so
/// the total stays in the low thousands however far in the user zooms.
///
/// Local subdivision means the budget is a ceiling, not a cost: a curve that
/// meets its tolerance early stops there, so only the genuinely tight bends
/// ever reach it.
int _maxDepth(int segments) =>
    segments <= 4 ? 10 : (segments <= 16 ? 8 : (segments <= 48 ? 7 : 6));

// --- curve memo -------------------------------------------------------------
// splineCurveFor is on the hot path three times over: the painter calls it for
// every visible spline every frame, hover calls it for every entity on every
// pointer move, and the modify tools call it inside an O(n²) intersection
// sweep. The entry is the entity's full geometric identity plus the tolerance,
// so a dragged control point misses exactly once.
//
// Keyed by a HASH and verified by comparing the numbers, never by a formatted
// string: a 500-point freehand spline would otherwise format a thousand doubles
// per lookup, on every entity, on every frame. A hash collision costs a miss
// and nothing else, because the hit is only taken when the data really matches.
class _Cached {
  final List<double> data;
  final int tag;
  final double tol;
  final List<Offset> curve;
  const _Cached(this.data, this.tag, this.tol, this.curve);

  bool matches(Geo g, double t) {
    if (tag != g.spline || tol != t || data.length != g.data.length) {
      return false;
    }
    for (var i = 0; i < data.length; i++) {
      if (data[i] != g.data[i]) return false;
    }
    return true;
  }
}

final Map<int, _Cached> _cache = {};
const int _cacheMax = 192;

int _key(Geo g, double tol) =>
    Object.hash(g.spline, tol, Object.hashAll(g.data));

List<Offset>? _recall(int k, Geo g, double tol) {
  final e = _cache[k];
  return (e != null && e.matches(g, tol)) ? e.curve : null;
}

void _remember(int k, Geo g, double tol, List<Offset> curve) {
  if (_cache.length >= _cacheMax) _cache.clear();
  // A COPY of the numbers: the entry outlives the Geo, and a comparison
  // against a list something else could still write into is not a comparison.
  _cache[k] = _Cached(List<double>.of(g.data), g.spline, tol, curve);
}

/// Drops the sampled-curve memo. Normal code never needs this — the key is the
/// complete geometric identity — but tests that assert on sampling density
/// across tolerance changes want a clean slate.
void clearSplineCurveCache() => _cache.clear();

/// Canonical form of an ellipse-tagged polyline: the minor vertex is put back
/// EXACTLY on the minor axis (center + perp(major) * b). Grip drags and the
/// solver move the raw points freely; this keeps the stored geometry on the
/// curve. Returns [g] unchanged when it is not a valid ellipse triple.
Geo normalizedEllipse(Geo g) {
  final p = polyPoints(g);
  if (g.spline != Geo.ellipseTag || p.length < 3) return g;
  final c = p[0];
  final u = p[1] - c;
  final a = u.distance;
  if (a < 1e-12) return g;
  final un = u / a;
  final vn = Offset(-un.dy, un.dx);
  final rel = p[2] - c;
  final b = (rel.dx * vn.dx + rel.dy * vn.dy).abs();
  if (b < 1e-12) return g;
  final mi = c + vn * b;
  if ((mi - p[2]).distance < 1e-12) return g; // already canonical
  return g.withData([
    g.data[0], g.data[1], // closed flag + count stay
    c.dx, c.dy, p[1].dx, p[1].dy, mi.dx, mi.dy,
  ]);
}

/// Ellipse from its 3 defining vertices [center, major vertex, minor vertex].
///
/// The minor vertex only contributes its component PERPENDICULAR to the major
/// axis: dragging it along the major axis is ignored (it is the "minor
/// extent" handle), and dragging the MAJOR vertex rotates/stretches the whole
/// ellipse — so the ellipse can never shear, whatever the solver or a grip
/// drag does to the raw points. Degenerate axes fall back to the raw points.
///
/// With [tolMm] the sample count is chosen so the polygon stays within that
/// distance of the true ellipse (M219: a fixed 96 was a visible polygon on a
/// zoomed-in 200 mm ellipse and wasteful on a 2 mm one). [samples] still wins
/// when given, so callers that need a specific count keep it.
List<Offset> ellipseCurve(List<Offset> p, {int? samples, double? tolMm}) {
  if (p.length < 3) return List.of(p);
  final c = p[0];
  final u = p[1] - c;
  final a = u.distance;
  if (a < 1e-12) return List.of(p);
  final un = u / a;
  final vn = Offset(-un.dy, un.dx);
  final b = ((p[2] - c).dx * vn.dx + (p[2] - c).dy * vn.dy).abs();
  if (b < 1e-12) return List.of(p);
  final n = samples ?? _ellipseSamples(math.max(a, b), tolMm);
  return [
    for (var i = 0; i <= n; i++)
      c +
          un * (a * math.cos(2 * math.pi * i / n)) +
          vn * (b * math.sin(2 * math.pi * i / n))
  ];
}

/// Samples for an ellipse of largest radius [r] within [tol]. The sagitta of a
/// chord subtending θ on radius r is r·(1-cos(θ/2)); solving that for θ gives
/// the count directly. Floored at the historical 96 so nothing gets coarser
/// than it used to be, capped so a deep zoom cannot run away.
int _ellipseSamples(double r, double? tol) {
  if (tol == null || tol <= 0 || r <= 0) return 96;
  final ratio = (1 - tol / r).clamp(-1.0, 1.0);
  final theta = 2 * math.acos(ratio);
  if (theta <= 1e-9) return 4096;
  return (2 * math.pi / theta).ceil().clamp(96, 4096);
}

/// Interpolation (fit-point) spline: a Catmull-Rom curve passing THROUGH [p].
List<Offset> fitCurve(List<Offset> p, {bool closed = false, int perSeg = 24}) {
  if (p.length < 3) return List.of(p);
  // Phantom endpoints for an open curve; wrap-around control points for closed.
  final q = closed
      ? [p[p.length - 1], ...p, p[0], p[1]]
      : [p[0], ...p, p[p.length - 1]];
  final segs = closed ? p.length : p.length - 1;
  final out = <Offset>[p[0]];
  for (var i = 0; i < segs; i++) {
    final p0 = q[i], p1 = q[i + 1], p2 = q[i + 2], p3 = q[i + 3];
    for (var j = 1; j <= perSeg; j++) {
      final t = j / perSeg, t2 = t * t, t3 = t2 * t;
      out.add(Offset(
        0.5 *
            ((2 * p1.dx) +
                (-p0.dx + p2.dx) * t +
                (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
                (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
        0.5 *
            ((2 * p1.dy) +
                (-p0.dy + p2.dy) * t +
                (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
                (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
      ));
    }
  }
  if (closed) out.add(p[0]);
  return out;
}

/// Control-vertex cubic B-spline via De Boor.
///
/// Open: clamped (the curve starts/ends ON the first/last CV, like Inventor).
/// Closed: PERIODIC — uniform knots, the first k CVs wrapped onto the end,
/// evaluated on [knot_k, knot_n]. The previous "clamped + wrap 3 CVs" hack
/// started the curve on cv[0] but ENDED it on cv[2] (a clamped curve ends on
/// its last CV), so a closed spline visibly failed to meet its start point
/// and had a corner there. Periodic closes exactly and C2-smooth.
/// [samples] is the TOTAL number of samples along the whole curve. Passing a
/// fixed value is what made long splines go coarse (M86): a 40-CV spline got
/// the same 64 samples as a 4-CV one — under two samples per span — so it
/// rendered as a visible polygon with kinks. Left null it scales with the span
/// count instead ([_bsplineSamples]).
///
/// This uniform sampler is the reference implementation and the fallback;
/// [splineCurveFor] evaluates the identical curve through its exact Bézier
/// form (bezier.dart) so it can subdivide where the curve actually bends.
List<Offset> bsplineCurve(List<Offset> cvIn,
    {bool closed = false, int? samples}) {
  const k = 3; // cubic
  if (closed && cvIn.length >= 3) {
    final cv = [...cvIn, cvIn[0], cvIn[1], cvIn[2]];
    final n = cv.length;
    // uniform knots 0..n+k; the curve is defined (and periodic) on [k, n]
    Offset deBoor(double u) {
      var s = u.floor();
      s = s.clamp(k, n - 1);
      final d = [for (var j = 0; j <= k; j++) cv[j + s - k]];
      for (var r = 1; r <= k; r++) {
        for (var j = k; j >= r; j--) {
          final den = (j + 1 + s - r) - (j + s - k); // uniform: integer knots
          final alpha = (u - (j + s - k)) / den;
          d[j] = d[j - 1] * (1 - alpha) + d[j] * alpha;
        }
      }
      return d[k];
    }

    final ns = samples ?? _bsplineSamples(n - k);
    final out = <Offset>[
      for (var i = 0; i < ns; i++) deBoor(k + (n - k) * (i / ns))
    ];
    out.add(out[0]); // close EXACTLY (deBoor(n) == deBoor(k) up to rounding)
    return out;
  }
  final cv = cvIn;
  final n = cv.length;
  if (n <= k) return fitCurve(cvIn, closed: closed);
  final knots = <double>[
    for (var i = 0; i <= k; i++) 0.0,
    for (var i = 1; i < n - k; i++) i / (n - k),
    for (var i = 0; i <= k; i++) 1.0,
  ];
  Offset deBoor(double u) {
    var s = knots.lastIndexWhere((x) => x <= u);
    s = s.clamp(k, n - 1);
    final d = [for (var j = 0; j <= k; j++) cv[j + s - k]];
    for (var r = 1; r <= k; r++) {
      for (var j = k; j >= r; j--) {
        final den = knots[j + 1 + s - r] - knots[j + s - k];
        final alpha = den.abs() < 1e-12 ? 0.0 : (u - knots[j + s - k]) / den;
        d[j] = d[j - 1] * (1 - alpha) + d[j] * alpha;
      }
    }
    return d[k];
  }

  final ns = samples ?? _bsplineSamples(n - k);
  return [
    for (var i = 0; i <= ns; i++)
      deBoor(i == ns ? 1.0 - 1e-12 : i / ns)
  ];
}

/// Total samples for a B-spline with [spans] polynomial spans.
///
/// 24 per span matches [fitCurve]'s `perSeg`, so the two spline kinds are
/// equally smooth for the same number of points — before M86 the fit spline
/// scaled and the CV spline did not, which is why only CV splines degraded.
/// The floor keeps short splines exactly as smooth as they were; the ceiling
/// keeps a 500-point freehand curve from producing 12 000 samples on a path
/// that every paint, hit-test and snap query runs through.
int _bsplineSamples(int spans) =>
    (spans <= 0 ? 64 : (spans * 24)).clamp(64, 4000);
