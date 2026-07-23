// Spline sampling (Inventor-style).
//
// The vendored QCAD core is built with splines deferred (R_NO_OPENNURBS), so a
// spline cannot be a backend entity. Instead a spline is stored as a POLYLINE
// whose vertices are the FEW control/fit points, tagged Dart-side as
// Geo.splineCv (control-vertex B-spline) or Geo.splineFit (interpolation /
// fit-point). That means the user edits only those points — exactly like
// Inventor — while these functions turn them into the smooth curve used for
// rendering, hit-testing and on-curve snapping. The vertices still round-trip
// through the backend as an ordinary polyline; the tag is restored from the
// sidecar (and preserved across the engine refresh) so the curve survives.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ffi/qcad_engine.dart';
import 'gear.dart' show gearCurve;

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
List<Offset> splineCurveFor(Geo g) {
  final pts = polyPoints(g);
  // A gear stores only [centre, handle] + a parameter block; the full involute
  // tooth outline is generated from them (gear.dart). Everything that draws or
  // snaps a curve funnels through here, so this one line makes gears render,
  // hit-test, snap and extrude like any other closed curve.
  if (g.spline == Geo.gearTag) return gearCurve(g);
  if (g.spline == Geo.ellipseTag) return ellipseCurve(pts);
  if (g.spline == Geo.straight || pts.length < 3) return pts;
  final closed = g.data[0] != 0;
  return g.spline == Geo.splineCv
      ? bsplineCurve(pts, closed: closed)
      : fitCurve(pts, closed: closed);
}

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
List<Offset> ellipseCurve(List<Offset> p, {int samples = 96}) {
  if (p.length < 3) return List.of(p);
  final c = p[0];
  final u = p[1] - c;
  final a = u.distance;
  if (a < 1e-12) return List.of(p);
  final un = u / a;
  final vn = Offset(-un.dy, un.dx);
  final b = ((p[2] - c).dx * vn.dx + (p[2] - c).dy * vn.dy).abs();
  if (b < 1e-12) return List.of(p);
  return [
    for (var i = 0; i <= samples; i++)
      c +
          un * (a * math.cos(2 * math.pi * i / samples)) +
          vn * (b * math.sin(2 * math.pi * i / samples))
  ];
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
List<Offset> bsplineCurve(List<Offset> cvIn,
    {bool closed = false, int samples = 64}) {
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

    final out = <Offset>[
      for (var i = 0; i < samples; i++)
        deBoor(k + (n - k) * (i / samples))
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

  return [
    for (var i = 0; i <= samples; i++)
      deBoor(i == samples ? 1.0 - 1e-12 : i / samples)
  ];
}
