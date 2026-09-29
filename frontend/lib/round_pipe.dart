// A round tube's path, recovered as lines and circular arcs.
//
// A sweep's path reaches the kernel as points: a sketch's lines and arcs
// sampled into one polyline (24 samples an arc). For a CIRCLE swept along
// lines and tangent arcs — a mug's handle, a rail, a bent rod — the exact
// solid is a cylinder per line and a torus segment per arc (occt_round_pipe),
// which the kernel fuses onto other bodies far faster than the B-spline
// pipe MakePipeShell makes (8-12 s against well under one on a smooth cup,
// AI lab). This file turns the points back into those pieces, or says they
// are not such a path.
import 'dart:math' as math;

/// The path [pts] (3 doubles a point) as round-pipe segments: 10 doubles a
/// segment — kind (0 line, 1 arc), start xyz, end xyz, centre xyz — or null
/// when it is not made of straight runs and circular arcs meeting
/// TANGENTIALLY (a sharp corner is left to the ordinary sweep, which mitres
/// it), or has fewer than two points.
List<double>? roundPipeSegments(List<double> pts, {double tol = 1e-4}) {
  final n = pts.length ~/ 3;
  if (n < 2) return null;
  List<double> p(int i) => [pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]];
  List<double> sub(List<double> a, List<double> b) =>
      [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  List<double> cross(List<double> a, List<double> b) => [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0]
      ];
  double dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  double len(List<double> a) => math.sqrt(dot(a, a));
  // Remove repeated points.
  final q = <List<double>>[p(0)];
  for (var i = 1; i < n; i++) {
    if (len(sub(p(i), q.last)) > tol) q.add(p(i));
  }
  if (q.length < 2) return null;
  var extent = 0.0;
  for (final a in q) {
    extent = math.max(extent, len(sub(a, q.first)));
  }
  final eps = math.max(tol, extent * 1e-6);

  bool collinear(List<double> a, List<double> b, List<double> c) {
    final u = sub(b, a), v = sub(c, a);
    final lu = len(u), lv = len(v);
    if (lu < eps || lv < eps) return true;
    return len(cross(u, v)) / lv <= eps && dot(u, v) > 0;
  }

  // The circle through three points: its centre, or null when they are
  // (nearly) on a line.
  List<double>? centre(List<double> a, List<double> b, List<double> c) {
    final u = sub(b, a), v = sub(c, a);
    final w = cross(u, v);
    final w2 = dot(w, w);
    if (w2 < 1e-18) return null;
    final uu = dot(u, u), vv = dot(v, v);
    final t1 = cross(w, u), t2 = cross(v, w);
    return [
      a[0] + (vv * t1[0] + uu * t2[0]) / (2 * w2),
      a[1] + (vv * t1[1] + uu * t2[1]) / (2 * w2),
      a[2] + (vv * t1[2] + uu * t2[2]) / (2 * w2),
    ];
  }

  final segs = <double>[];
  final dirs = <(List<double>, List<double>)>[]; // tangent at start, at end
  var i = 0;
  while (i < q.length - 1) {
    // A straight run as far as it goes.
    var j = i + 1;
    while (j + 1 < q.length && collinear(q[i], q[j], q[j + 1])) {
      j++;
    }
    if (j > i + 1 || i + 2 >= q.length) {
      final d = sub(q[j], q[i]);
      final l = len(d);
      segs.addAll([0, ...q[i], ...q[j], 0, 0, 0]);
      dirs.add(([d[0] / l, d[1] / l, d[2] / l], [d[0] / l, d[1] / l, d[2] / l]));
      i = j;
      continue;
    }
    // An arc: the longest run of points on one circle, in one plane, turning
    // one way.
    final c = centre(q[i], q[i + 1], q[i + 2]);
    if (c == null) {
      final d = sub(q[i + 1], q[i]);
      final l = len(d);
      segs.addAll([0, ...q[i], ...q[i + 1], 0, 0, 0]);
      dirs.add(([d[0] / l, d[1] / l, d[2] / l], [d[0] / l, d[1] / l, d[2] / l]));
      i = i + 1;
      continue;
    }
    final r = len(sub(q[i], c));
    final nrm = cross(sub(q[i], c), sub(q[i + 1], c));
    final nl = len(nrm);
    final axis = [nrm[0] / nl, nrm[1] / nl, nrm[2] / nl];
    var k = i + 2;
    var turned = math.atan2(
        len(cross(sub(q[i], c), sub(q[k], c))), dot(sub(q[i], c), sub(q[k], c)));
    while (k + 1 < q.length) {
      final nx = q[k + 1];
      if ((len(sub(nx, c)) - r).abs() > math.max(eps, r * 1e-5)) break;
      final off = dot(sub(nx, c), axis);
      if (off.abs() > eps) break;
      // Same way round.
      if (dot(cross(sub(q[k], c), sub(nx, c)), axis) <= 0) break;
      final step = math.atan2(len(cross(sub(q[k], c), sub(nx, c))),
          dot(sub(q[k], c), sub(nx, c)));
      if (turned + step > math.pi * 0.95) break; // pieces under 180°
      turned += step;
      k++;
    }
    if (k < i + 3) {
      // Three points are on SOME circle; an arc of the path is sampled
      // finer than that. A short straight run before a bend.
      final d = sub(q[i + 1], q[i]);
      final l = len(d);
      segs.addAll([0, ...q[i], ...q[i + 1], 0, 0, 0]);
      dirs.add(([d[0] / l, d[1] / l, d[2] / l], [d[0] / l, d[1] / l, d[2] / l]));
      i = i + 1;
      continue;
    }
    List<double> tangentAt(List<double> x) {
      final t = cross(axis, sub(x, c));
      final l = len(t);
      return [t[0] / l, t[1] / l, t[2] / l];
    }

    segs.addAll([1, ...q[i], ...q[k], ...c]);
    dirs.add((tangentAt(q[i]), tangentAt(q[k])));
    i = k;
  }
  // Pieces must meet tangentially: a corner is the ordinary sweep's.
  for (var s = 1; s < dirs.length; s++) {
    if (dot(dirs[s - 1].$2, dirs[s].$1) < math.cos(2 * math.pi / 180)) {
      return null;
    }
  }
  return segs;
}
