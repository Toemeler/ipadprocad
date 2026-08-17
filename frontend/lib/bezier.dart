// Cubic Bézier chains — the exact form of every spline in this sketcher.
//
// WHY THIS EXISTS. A spline here is a POLYLINE of control/fit points plus a
// Dart-side tag (see Geo.splineCv / splineFit / ellipseTag): the vendored QCAD
// core is built without OpenNURBS, so there is no spline entity to trim. Trim
// and Split therefore used to fall through to the plain-polyline branch and
// cut the CONTROL POLYGON — a chain of straight lines that, for a CV spline,
// does not even touch the curve. What came back was a straight-line fragment
// re-tagged as a spline, i.e. a different curve in a different place. That is
// the whole of "I can't trim splines".
//
// The fix is to give every spline kind ONE exact intermediate form that can be
// cut without loss. Every curve this app draws through a polyline carrier is
// piecewise CUBIC, so a chain of cubic Bézier segments represents ALL of them
// exactly (verified to ~1e-13 against the samplers in spline.dart):
//
//   * clamped cubic B-spline (splineCv, open)  -> Bézier by knot insertion
//   * periodic cubic B-spline (splineCv, closed) -> the classic uniform
//     B-spline-to-Bézier basis change, one Bézier per span
//   * Catmull-Rom (splineFit, open & closed)   -> b1 = p1 + (p2-p0)/6,
//                                                 b2 = p2 - (p3-p1)/6
//   * ellipse (ellipseTag)                     -> [_ellipseSegs] arcs, each a
//     cubic with the standard 4/3·tan(θ/4) handle (6.6e-8·r at 16 segments)
//
// And a Bézier chain CUTS exactly: de Casteljau splits a segment at any
// parameter with no approximation at all. So a trimmed spline is still the
// very same curve, just shorter.
//
// The cut result is stored back as [Geo.splineBez] — a polyline whose vertices
// ARE the chain's control points (3s+1 of them for s segments, 3s when it
// closes). That needs no new entity type, no new sidecar and no knot vector in
// the data block: the tag alone says how to read the vertices, exactly like
// every other spline kind here, so it round-trips through the DXF, the solver,
// the undo journal and the .splines.json sidecar with no further work.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ffi/qcad_engine.dart';

/// Cubic segments an ellipse is cut into. The handle length 4/3·tan(θ/4) is
/// exact at the segment ends and worst in the middle; 16 segments put that
/// worst case at 6.6e-8 of the radius — four orders below the tightest
/// tolerance anything in this app compares against, and far below the
/// modelling tolerance of the kernel the profile ends up in.
const int _ellipseSegs = 16;

/// A chain of cubic Bézier segments. Each entry of [segs] holds exactly four
/// control points; consecutive segments share their end point.
///
/// The chain is parameterised by `u ∈ [0, segs.length]`, where the integer
/// part selects the segment and the fraction is that segment's own parameter.
/// That parameter is monotone along the curve — which is all Trim and Split
/// need — and unlike arc length it is exact and free to evaluate.
class BezPath {
  final List<List<Offset>> segs;
  final bool closed;

  const BezPath(this.segs, {this.closed = false});

  int get count => segs.length;
  bool get isEmpty => segs.isEmpty;

  /// Point at chain parameter [u] (clamped for an open chain, wrapped when
  /// [closed]).
  Offset at(double u) {
    if (segs.isEmpty) return Offset.zero;
    var v = u;
    if (closed) {
      v = v % count;
      if (v < 0) v += count;
    } else {
      v = v.clamp(0.0, count.toDouble());
    }
    var i = v.floor();
    var t = v - i;
    if (i >= count) {
      i = count - 1;
      t = 1.0;
    }
    return bezAt(segs[i], t);
  }

  /// Tangent direction at [u] (never normalised; may be zero on a degenerate
  /// segment).
  Offset tangentAt(double u) {
    if (segs.isEmpty) return Offset.zero;
    var v = u;
    if (closed) {
      v = v % count;
      if (v < 0) v += count;
    } else {
      v = v.clamp(0.0, count.toDouble());
    }
    var i = v.floor();
    var t = v - i;
    if (i >= count) {
      i = count - 1;
      t = 1.0;
    }
    return bezTangent(segs[i], t);
  }

  /// Chain parameter of the point on the curve nearest [p].
  ///
  /// Coarse scan first (the curve may fold back on itself, so the bracket has
  /// to come from a global look), then a ternary search inside the winning
  /// sample interval — distance² along a cubic is smooth, and the bracket is
  /// one sample wide, so the refinement lands on the true minimum.
  double paramOf(Offset p) {
    if (segs.isEmpty) return 0;
    const per = 24;
    var bestU = 0.0, bestD = double.infinity;
    for (var i = 0; i < count; i++) {
      for (var j = 0; j <= per; j++) {
        final u = i + j / per;
        final d = (at(u) - p).distanceSquared;
        if (d < bestD) {
          bestD = d;
          bestU = u;
        }
      }
    }
    final step = 1.0 / per;
    var lo = bestU - step, hi = bestU + step;
    if (!closed) {
      lo = lo.clamp(0.0, count.toDouble());
      hi = hi.clamp(0.0, count.toDouble());
    }
    for (var k = 0; k < 60 && hi - lo > 1e-13; k++) {
      final a = lo + (hi - lo) / 3, b = hi - (hi - lo) / 3;
      if ((at(a) - p).distanceSquared <= (at(b) - p).distanceSquared) {
        hi = b;
      } else {
        lo = a;
      }
    }
    final u = (lo + hi) / 2;
    if (!closed) return u.clamp(0.0, count.toDouble());
    var v = u % count;
    if (v < 0) v += count;
    return v;
  }

  /// The OPEN sub-chain running forward from [u0] to [u1] — wrapping past the
  /// end when the chain is [closed], clamped when it is not. Exact: every
  /// partial segment is a de Casteljau split of the original.
  ///
  /// Returns an empty path when the span has no extent.
  BezPath sub(double u0, double u1) {
    if (segs.isEmpty) return const BezPath([]);
    const eps = 1e-12;
    var start = u0, span = u1 - u0;
    if (closed) {
      start = start % count;
      if (start < 0) start += count;
      while (span <= eps) {
        span += count;
      }
      if (span > count) span = count.toDouble();
    } else {
      if (span < 0) {
        start = u1;
        span = -span;
      }
      start = start.clamp(0.0, count.toDouble());
      span = math.min(span, count - start);
    }
    if (span <= eps) return const BezPath([]);
    final out = <List<Offset>>[];
    var s = start, left = span;
    // Bounded by construction (each pass consumes at least the rest of a
    // segment), but a hard stop keeps a rounding pathology from spinning.
    for (var guard = 0; guard <= count + 2 && left > eps; guard++) {
      var i = s.floor();
      var t0 = s - i;
      if (t0 >= 1 - eps) {
        i += 1;
        t0 = 0;
      }
      i %= count;
      if (i < 0) i += count;
      final take = math.min(1 - t0, left);
      if (take <= eps) break;
      out.add(bezSub(segs[i], t0, t0 + take));
      s += take;
      left -= take;
    }
    return BezPath(out);
  }

  /// The chain as polyline vertices: 3·s+1 points for an open chain, 3·s when
  /// it closes (the closing segment's end point IS vertex 0). This is exactly
  /// the layout [Geo.splineBez] stores and [bezPathOf] reads back.
  List<Offset> get vertices {
    final v = <Offset>[];
    for (final s in segs) {
      v..add(s[0])..add(s[1])..add(s[2]);
    }
    if (!closed && segs.isNotEmpty) v.add(segs.last[3]);
    return v;
  }

  /// Adaptive polyline approximation, everywhere within [tol] of the true
  /// curve. Subdivision is recursive and LOCAL: a straight stretch costs two
  /// points while a tight bend gets as many as it needs, which is what a fixed
  /// sample count could never do.
  List<Offset> flatten(double tol, {int maxDepth = 8}) {
    if (segs.isEmpty) return const [];
    final t = tol.isFinite && tol > 1e-12 ? tol : 1e-12;
    final out = <Offset>[segs.first[0]];
    for (final s in segs) {
      _flattenInto(s, t, maxDepth, out);
    }
    if (closed && out.length > 1) out.add(out.first);
    return out;
  }

  /// Total control-polygon length — an upper bound on arc length, and enough
  /// to tell a real span from a rounding artefact.
  double get polygonLength {
    var sum = 0.0;
    for (final s in segs) {
      for (var i = 0; i + 1 < 4; i++) {
        sum += (s[i + 1] - s[i]).distance;
      }
    }
    return sum;
  }
}

// ---------------------------------------------------------------------------
// single-segment algebra
// ---------------------------------------------------------------------------

Offset bezAt(List<Offset> b, double t) {
  final mt = 1 - t;
  final a = mt * mt * mt, c = 3 * mt * mt * t, d = 3 * mt * t * t, e = t * t * t;
  return Offset(
    a * b[0].dx + c * b[1].dx + d * b[2].dx + e * b[3].dx,
    a * b[0].dy + c * b[1].dy + d * b[2].dy + e * b[3].dy,
  );
}

Offset bezTangent(List<Offset> b, double t) {
  final mt = 1 - t;
  final v = (b[1] - b[0]) * (3 * mt * mt) +
      (b[2] - b[1]) * (6 * mt * t) +
      (b[3] - b[2]) * (3 * t * t);
  if (v.distance > 1e-12) return v;
  // A cusped/degenerate handle: fall back to the chord, which is still the
  // direction a tangent constraint or an end-tangent read wants.
  return b[3] - b[0];
}

/// The left/right halves of [b] split at [t] (de Casteljau).
(List<Offset>, List<Offset>) bezSplit(List<Offset> b, double t) {
  Offset lerp(Offset a, Offset c) => a + (c - a) * t;
  final p01 = lerp(b[0], b[1]), p12 = lerp(b[1], b[2]), p23 = lerp(b[2], b[3]);
  final q0 = lerp(p01, p12), q1 = lerp(p12, p23);
  final r = lerp(q0, q1);
  return ([b[0], p01, q0, r], [r, q1, p23, b[3]]);
}

/// The exact piece of [b] between parameters [t0] and [t1].
List<Offset> bezSub(List<Offset> b, double t0, double t1) {
  var seg = b;
  var a = t0, c = t1;
  if (a > 0) {
    seg = bezSplit(seg, a).$2;
    c = a < 1 ? (c - a) / (1 - a) : 1.0;
  }
  if (c < 1) seg = bezSplit(seg, c.clamp(0.0, 1.0)).$1;
  return seg;
}

/// How far the control points 1 and 2 sit off the chord — an upper bound on
/// the segment's deviation from that chord up to a factor of 3/4, which is why
/// the flattener compares it against the tolerance directly (conservative).
double _chordError(List<Offset> b) {
  final d = b[3] - b[0];
  final len = d.distance;
  if (len < 1e-12) {
    return math.max((b[1] - b[0]).distance, (b[2] - b[0]).distance);
  }
  double off(Offset p) =>
      ((p - b[0]).dx * d.dy - (p - b[0]).dy * d.dx).abs() / len;
  return math.max(off(b[1]), off(b[2]));
}

void _flattenInto(List<Offset> b, double tol, int depth, List<Offset> out) {
  if (depth <= 0 || _chordError(b) <= tol) {
    out.add(b[3]);
    return;
  }
  final (l, r) = bezSplit(b, 0.5);
  _flattenInto(l, tol, depth - 1, out);
  _flattenInto(r, tol, depth - 1, out);
}

// ---------------------------------------------------------------------------
// Geo <-> Bézier chain
// ---------------------------------------------------------------------------

/// Vertices of a polyline-carried entity.
List<Offset> _verts(Geo g) {
  if (g.type != Geo.polyline || g.data.length < 2) return const [];
  final n = g.data[1].toInt();
  if (n < 0 || g.data.length < 2 + 2 * n) return const [];
  return [
    for (var i = 0; i < n; i++) Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
  ];
}

/// The EXACT cubic Bézier chain of [g], or null when [g] is not a curve this
/// module can represent (a plain polyline, a gear's baked outline, a sketch
/// point, or a spline with too few vertices to define a curve).
///
/// A gear is deliberately excluded: its outline is generated from a parameter
/// block, not from cubics, so cutting it has to bake — see the trim path.
BezPath? bezPathOf(Geo g) {
  if (g.type != Geo.polyline) return null;
  final p = _verts(g);
  if (p.length < 2) return null;
  final closed = g.data[0] != 0;
  switch (g.spline) {
    case Geo.splineBez:
      return bezChainFromVertices(p, closed: closed);
    case Geo.ellipseTag:
      return p.length < 3 ? null : ellipseBezPath(p[0], p[1], p[2]);
    case Geo.splineFit:
      return p.length < 3 ? null : catmullRomBezPath(p, closed: closed);
    case Geo.splineCv:
      // Mirrors bsplineCurve's own dispatch exactly, or a trim would cut a
      // curve the sketch never drew: closed needs 3 CVs for the periodic
      // form, and 3 or fewer CVs fall back to the fit-point curve.
      if (closed && p.length >= 3) return periodicBezPath(p);
      if (p.length <= 3) {
        return p.length < 3 ? null : catmullRomBezPath(p, closed: closed);
      }
      return clampedBezPath(p);
    default:
      return null;
  }
}

/// Reads back the vertex layout [BezPath.vertices] writes.
///
/// A vertex count that is not 3·s+1 (open) / 3·s (closed) cannot be a chain —
/// that only happens if something outside this module rewrote the point list —
/// so it is read as a fit-point curve instead of throwing away the entity.
BezPath? bezChainFromVertices(List<Offset> v, {bool closed = false}) {
  final n = v.length;
  final s = closed ? n ~/ 3 : (n - 1) ~/ 3;
  final ok = s >= 1 && (closed ? n == 3 * s : n == 3 * s + 1);
  if (!ok) {
    return v.length < 3 ? null : catmullRomBezPath(v, closed: closed);
  }
  return BezPath([
    for (var i = 0; i < s; i++)
      [v[3 * i], v[3 * i + 1], v[3 * i + 2], v[(3 * i + 3) % n]]
  ], closed: closed);
}

/// Catmull-Rom (the [Geo.splineFit] curve) as Bézier segments. Same phantom
/// endpoints as the sampler: an open curve repeats its first/last point, a
/// closed one wraps.
BezPath catmullRomBezPath(List<Offset> p, {bool closed = false}) {
  final q = closed
      ? [p[p.length - 1], ...p, p[0], p[1]]
      : [p[0], ...p, p[p.length - 1]];
  final n = closed ? p.length : p.length - 1;
  return BezPath([
    for (var i = 0; i < n; i++)
      [
        q[i + 1],
        q[i + 1] + (q[i + 2] - q[i]) / 6,
        q[i + 2] - (q[i + 3] - q[i + 1]) / 6,
        q[i + 2],
      ]
  ], closed: closed);
}

/// The PERIODIC uniform cubic B-spline through [cv] (the closed [Geo.splineCv]
/// curve) as Bézier segments — the textbook uniform basis change, one segment
/// per control point.
///
/// The span indexing matches bsplineCurve's periodic branch exactly (it wraps
/// the first 3 CVs onto the end and evaluates on [k, n]), so segment i is built
/// from cv[i..i+3] and the chain STARTS where the sampled curve starts. Off by
/// one segment the curve would be the same closed shape traced from a different
/// point, which nothing would catch until a trim cut in the wrong place.
BezPath periodicBezPath(List<Offset> cv) {
  final m = cv.length;
  Offset at(int i) => cv[((i % m) + m) % m];
  return BezPath([
    for (var i = 0; i < m; i++)
      () {
        final p0 = at(i), p1 = at(i + 1), p2 = at(i + 2), p3 = at(i + 3);
        return [
          (p0 + p1 * 4 + p2) / 6,
          (p1 * 2 + p2) / 3,
          (p1 + p2 * 2) / 3,
          (p1 + p2 * 4 + p3) / 6,
        ];
      }()
  ], closed: true);
}

/// The CLAMPED cubic B-spline over [cv] with the uniform interior knots
/// [splineCurveFor] uses, as Bézier segments — obtained by inserting every
/// interior knot up to multiplicity 3 (Boehm), which is an exact change of
/// basis, not a fit.
BezPath clampedBezPath(List<Offset> cv) {
  const k = 3;
  final n = cv.length;
  if (n <= k) return catmullRomBezPath(cv);
  var pts = List<Offset>.of(cv);
  var knots = <double>[
    for (var i = 0; i <= k; i++) 0.0,
    for (var i = 1; i < n - k; i++) i / (n - k),
    for (var i = 0; i <= k; i++) 1.0,
  ];
  // Raise every interior knot to multiplicity k. The loop is finite: each pass
  // adds exactly one multiplicity to one interior knot, and there are
  // (n-k-1)·k of them at most.
  for (var guard = 0; guard < (n - k) * k + 4; guard++) {
    double? target;
    for (var i = k + 1; i < knots.length - k - 1; i++) {
      final u = knots[i];
      var mult = 0;
      for (final x in knots) {
        if ((x - u).abs() < 1e-12) mult++;
      }
      if (mult < k) {
        target = u;
        break;
      }
    }
    if (target == null) break;
    final ins = _insertKnot(pts, knots, target);
    pts = ins.$1;
    knots = ins.$2;
  }
  return BezPath([
    for (var i = 0; i + 3 < pts.length; i += 3)
      [pts[i], pts[i + 1], pts[i + 2], pts[i + 3]]
  ]);
}

/// One Boehm knot insertion into a cubic B-spline.
(List<Offset>, List<double>) _insertKnot(
    List<Offset> cv, List<double> knots, double u) {
  const k = 3;
  final n = cv.length;
  var s = 0;
  for (var i = 0; i < knots.length; i++) {
    if (knots[i] <= u) s = i;
  }
  s = s.clamp(k, n - 1);
  final out = <Offset>[];
  for (var i = 0; i <= n; i++) {
    if (i <= s - k) {
      out.add(cv[i]);
    } else if (i >= s + 1) {
      out.add(cv[i - 1]);
    } else {
      final den = knots[i + k] - knots[i];
      final a = den.abs() < 1e-12 ? 0.0 : (u - knots[i]) / den;
      out.add(cv[i - 1] * (1 - a) + cv[i] * a);
    }
  }
  return (out, [...knots.sublist(0, s + 1), u, ...knots.sublist(s + 1)]);
}

/// The ellipse [center, major vertex, minor vertex] as a closed Bézier chain.
/// The minor vertex contributes only its perpendicular component, exactly as
/// [ellipseCurve] reads it, so a sheared point pair can never shear the curve.
BezPath? ellipseBezPath(Offset c, Offset major, Offset minor) {
  final u = major - c;
  final a = u.distance;
  if (a < 1e-12) return null;
  final un = u / a;
  final vn = Offset(-un.dy, un.dx);
  final b = ((minor - c).dx * vn.dx + (minor - c).dy * vn.dy).abs();
  if (b < 1e-12) return null;
  Offset at(double t) => c + un * (a * math.cos(t)) + vn * (b * math.sin(t));
  Offset der(double t) => un * (-a * math.sin(t)) + vn * (b * math.cos(t));
  const n = _ellipseSegs;
  const step = 2 * math.pi / n;
  // Hermite handles of length der·Δ/3 reproduce the exact tangent AND the
  // exact end points; over a 22.5° step that is the standard 4/3·tan(θ/4)
  // circle approximation generalised to the ellipse.
  final h = 4 / 3 * math.tan(step / 4);
  return BezPath([
    for (var i = 0; i < n; i++)
      () {
        final t0 = step * i, t1 = step * (i + 1);
        final p0 = at(t0), p1 = at(t1);
        return [p0, p0 + der(t0) * h, p1 - der(t1) * h, p1];
      }()
  ], closed: true);
}

/// A [Geo] for the chain [path], tagged [Geo.splineBez] so every reader knows
/// its vertices are Bézier control points. Returns null for a chain with no
/// extent (a cut that landed on an end leaves one of those).
Geo? bezGeo(BezPath path, {double minExtent = 1e-9}) {
  if (path.isEmpty) return null;
  if (path.polygonLength <= minExtent) return null;
  final v = path.vertices;
  if (v.length < 4) return null;
  return Geo(
    Geo.polyline,
    [
      path.closed ? 1.0 : 0.0,
      v.length.toDouble(),
      for (final p in v) ...[p.dx, p.dy],
    ],
    spline: Geo.splineBez,
  );
}
