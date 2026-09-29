/// Placements for a TWISTED sweep, built as a loft through copies of the
/// section set along the path.
///
/// The OCCT shim refuses a twist (a pipe shell has no twist law), and the
/// sweep panel used to answer every twist with "not supported". A twisted
/// sweep is exactly a loft through the section placed at stations along the
/// path, each turned by its share of the twist, so it is built that way:
///
/// - the section is carried along by ROTATION-MINIMISING frames (the double
///   reflection method of Wang, Jüttler, Zheng and Liu, "Computation of
///   Rotation Minimizing Frames", ACM TOG 27(1), 2008) — the frame that does
///   not spin about the path by itself, so the only turn is the one asked for;
/// - "Fixed" orientation keeps the section's own orientation and turns it
///   about its own normal;
/// - the twist is shared out linearly along the path length, right-handed
///   about the direction of travel.
library;

import 'dart:math' as math;

typedef _V = List<double>;

_V _sub(_V a, _V b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
_V _add(_V a, _V b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
_V _mul(_V a, double k) => [a[0] * k, a[1] * k, a[2] * k];
double _dot(_V a, _V b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
_V _cross(_V a, _V b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];
double _len(_V a) => math.sqrt(_dot(a, a));
_V _unit(_V a) => _mul(a, 1 / _len(a));

/// 3x3 matrices row-major, as List of 9.
List<double> _matMul(List<double> a, List<double> b) => [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
    ];
_V _apply(List<double> m, _V v) => [
      m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
      m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
      m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ];

/// Rotation by [rad] about the unit axis [k] (Rodrigues).
List<double> _rot(_V k, double rad) {
  final c = math.cos(rad), s = math.sin(rad), t = 1 - c;
  final x = k[0], y = k[1], z = k[2];
  return [
    t * x * x + c, t * x * y - s * z, t * x * z + s * y, //
    t * x * y + s * z, t * y * y + c, t * y * z - s * x,
    t * x * z - s * y, t * y * z + s * x, t * z * z + c,
  ];
}

/// The matrix whose COLUMNS are [a], [b], [c].
List<double> _cols(_V a, _V b, _V c) =>
    [a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2]];

List<double> _transpose(List<double> m) =>
    [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];

/// One 3x4 placement (row-major, as the kernel's `mat34`) per station for a
/// section placed by [mat34] swept along the world polyline [pathPts]
/// (x, y, z per point) and turned by [twistDeg] in total. Null when the path
/// has no length.
///
/// [stations] defaults to one per 12° of twist, at least 8 and at most 64.
List<List<double>>? twistedSweepMats(List<double> mat34, List<double> pathPts,
    {required double twistDeg, bool fixed = false, int? stations}) {
  // The path, without repeated points.
  final pts = <_V>[];
  for (var i = 0; i + 2 < pathPts.length; i += 3) {
    final p = [pathPts[i], pathPts[i + 1], pathPts[i + 2]];
    if (pts.isEmpty || _len(_sub(p, pts.last)) > 1e-9) pts.add(p);
  }
  if (pts.length < 2) return null;
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + _len(_sub(pts[i], pts[i - 1])));
  }
  final total = cum.last;
  if (total < 1e-9) return null;
  final n = stations ?? (twistDeg.abs() / 12).ceil().clamp(8, 64);

  // Point and tangent at arc length s.
  (_V, _V) at(double s) {
    var k = 1;
    while (k < pts.length - 1 && cum[k] < s) {
      k++;
    }
    final seg = cum[k] - cum[k - 1];
    final u = seg > 0 ? ((s - cum[k - 1]) / seg).clamp(0.0, 1.0) : 0.0;
    final d = _sub(pts[k], pts[k - 1]);
    return (_add(pts[k - 1], _mul(d, u)), _unit(d));
  }

  final rm = [
    mat34[0], mat34[1], mat34[2], //
    mat34[4], mat34[5], mat34[6],
    mat34[8], mat34[9], mat34[10],
  ];
  final tm = [mat34[3], mat34[7], mat34[11]];
  final normal = _unit([rm[2], rm[5], rm[8]]); // the section's own z
  final p0 = pts.first;
  final (_, t0) = at(0);

  // The reference direction the frame carries: the section's x, made
  // perpendicular to the tangent (its y if x runs along the path).
  _V r = [rm[0], rm[3], rm[6]];
  r = _sub(r, _mul(t0, _dot(r, t0)));
  if (_len(r) < 1e-6) {
    r = [rm[1], rm[4], rm[7]];
    r = _sub(r, _mul(t0, _dot(r, t0)));
  }
  r = _unit(r);
  final f0t = _transpose(_cols(t0, r, _cross(t0, r)));

  final out = <List<double>>[];
  var prevX = p0, prevT = t0;
  for (var j = 0; j <= n; j++) {
    final (x, t) = at(total * j / n);
    if (j > 0) {
      // Double reflection: carry r from the previous station to this one.
      final v1 = _sub(x, prevX);
      final c1 = _dot(v1, v1);
      if (c1 > 1e-18) {
        final rL = _sub(r, _mul(v1, 2 / c1 * _dot(v1, r)));
        final tL = _sub(prevT, _mul(v1, 2 / c1 * _dot(v1, prevT)));
        final v2 = _sub(t, tL);
        final c2 = _dot(v2, v2);
        r = c2 > 1e-18 ? _sub(rL, _mul(v2, 2 / c2 * _dot(v2, rL))) : rL;
      }
      // Keep it exactly perpendicular and unit.
      r = _unit(_sub(r, _mul(t, _dot(r, t))));
    }
    prevX = x;
    prevT = t;
    final carry = fixed
        ? const <double>[1, 0, 0, 0, 1, 0, 0, 0, 1]
        : _matMul(_cols(t, r, _cross(t, r)), f0t);
    final axis = fixed ? normal : t;
    final twist = _rot(axis, twistDeg * math.pi / 180 * j / n);
    final c = _matMul(twist, carry);
    final rot = _matMul(c, rm);
    final tr = _add(_apply(c, _sub(tm, p0)), x);
    out.add([
      rot[0], rot[1], rot[2], tr[0], //
      rot[3], rot[4], rot[5], tr[1],
      rot[6], rot[7], rot[8], tr[2],
    ]);
  }
  return out;
}

/// The taper of a twisted sweep, applied to the SECTION (a loft takes only
/// rigid placements): the scale at each of [count] stations, linear from 1
/// to 1 + tan(taper) as the kernel's own sweep, and the point it scales
/// about — where the path starts, in the section's own (x, y).
({List<double> scales, (double, double) pivot}) twistedSweepTaper(
    List<double> mat34, List<double> pathPts, double taperDeg, int count) {
  final k = math.tan(taperDeg * math.pi / 180);
  final scales = [
    for (var j = 0; j < count; j++) 1 + k * (count == 1 ? 0 : j / (count - 1))
  ];
  // Rm^T (P0 - t): the path start in section coordinates.
  final d = [pathPts[0] - mat34[3], pathPts[1] - mat34[7], pathPts[2] - mat34[11]];
  final px = mat34[0] * d[0] + mat34[4] * d[1] + mat34[8] * d[2];
  final py = mat34[1] * d[0] + mat34[5] * d[1] + mat34[9] * d[2];
  return (scales: scales, pivot: (px, py));
}
