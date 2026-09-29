// A round tube's path, recovered as lines and circular arcs.
//
// A sweep's path reaches the kernel as points: a sketch's lines and arcs
// sampled into one polyline — and resampled, so no sample need land on the
// point where a line turns into an arc. For a CIRCLE swept along lines and
// tangent arcs — a mug's handle, a rail, a bent rod — the exact solid is a
// cylinder per line and a torus segment per arc (occt_round_pipe), which the
// kernel fuses onto other bodies far faster than the B-spline pipe
// MakePipeShell makes (8-12 s on a smooth cup, AI lab). This file finds the
// straight runs and circular runs in the points and the exact tangent points
// between them, or says the path is not made that way.
import 'dart:math' as math;

typedef _V = List<double>;

_V _sub(_V a, _V b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
_V _add(_V a, _V b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
_V _mul(_V a, double k) => [a[0] * k, a[1] * k, a[2] * k];
_V _cross(_V a, _V b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0]
    ];
double _dot(_V a, _V b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
double _len(_V a) => math.sqrt(_dot(a, a));
_V _unit(_V a) => _mul(a, 1 / _len(a));

/// The circle through three points: its centre, or null when they are
/// (nearly) on a line.
_V? _centre(_V a, _V b, _V c) {
  final u = _sub(b, a), v = _sub(c, a);
  final w = _cross(u, v);
  final w2 = _dot(w, w);
  if (w2 < 1e-18) return null;
  final uu = _dot(u, u), vv = _dot(v, v);
  final t1 = _cross(w, u), t2 = _cross(v, w);
  return _add(a, _mul(_add(_mul(t1, vv), _mul(t2, uu)), 1 / (2 * w2)));
}

class _Run {
  _Run.line(this.from, this.to)
      : centre = null,
        axis = null,
        r = 0;
  _Run.arc(this.from, this.to, this.centre, this.axis, this.r);
  final int from, to; // point indices
  final _V? centre, axis;
  final double r;
  bool get isArc => centre != null;
}

/// The path [pts] (3 doubles a point) as round-pipe segments: 10 doubles a
/// segment — kind (0 line, 1 arc), start xyz, end xyz, centre xyz — or null
/// when it is not straight runs and circular arcs meeting TANGENTIALLY (a
/// sharp corner is left to the ordinary sweep, which mitres it).
List<double>? roundPipeSegments(List<double> pts) {
  final n0 = pts.length ~/ 3;
  if (n0 < 2) return null;
  final q = <_V>[];
  for (var i = 0; i < n0; i++) {
    final p = [pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]];
    if (q.isEmpty || _len(_sub(p, q.last)) > 1e-9) q.add(p);
  }
  final n = q.length;
  if (n < 2) return null;
  var extent = 0.0;
  for (final a in q) {
    extent = math.max(extent, _len(_sub(a, q.first)));
  }
  final eps = math.max(1e-6, extent * 1e-6);

  bool onLine(_V a, _V b, _V c) {
    final u = _sub(b, a), v = _sub(c, a);
    if (_len(v) < eps) return true;
    return _len(_cross(u, v)) / _len(u) <= eps * 10 && _dot(u, v) > 0;
  }

  // 1. The runs: circular where four or more points share a circle and a
  // plane, straight where they share a line. A point between two runs (the
  // sample that straddles a join) belongs to neither.
  final runs = <_Run>[];
  var i = 0;
  while (i < n - 1) {
    if (i + 3 < n) {
      final c = _centre(q[i], q[i + 1], q[i + 2]);
      if (c != null) {
        final r = _len(_sub(q[i], c));
        final axis = _unit(_cross(_sub(q[i], c), _sub(q[i + 1], c)));
        bool onCircle(_V p) =>
            (_len(_sub(p, c)) - r).abs() <= math.max(eps * 10, r * 1e-5) &&
            _dot(_sub(p, c), axis).abs() <= eps * 10;
        var k = i + 2;
        while (k + 1 < n &&
            onCircle(q[k + 1]) &&
            _dot(_cross(_sub(q[k], c), _sub(q[k + 1], c)), axis) > 0) {
          k++;
        }
        if (k >= i + 3 && r < extent * 100) {
          runs.add(_Run.arc(i, k, c, axis, r));
          i = k;
          continue;
        }
      }
    }
    var j = i + 1;
    while (j + 1 < n && onLine(q[i], q[j], q[j + 1])) {
      j++;
    }
    runs.add(_Run.line(i, j));
    i = j;
  }
  if (runs.isEmpty) return null;
  // A two-point step between a straight run and an arc is the sample that
  // straddles their join: dropped (the join is computed below). One running
  // on in the straight run's direction is part of it.
  _V dirOf(_Run l) => _unit(_sub(q[l.to], q[l.from]));
  for (var k = 0; k < runs.length; k++) {
    final r = runs[k];
    if (r.isArc || r.to - r.from != 1) continue;
    final prev = k > 0 ? runs[k - 1] : null, next = k + 1 < runs.length ? runs[k + 1] : null;
    final longLine = [prev, next].where((x) => x != null && !x.isArc && x.to - x.from > 1).firstOrNull;
    final arcNear = [prev, next].any((x) => x != null && x.isArc);
    if (longLine != null && _dot(dirOf(longLine), dirOf(r)) > math.cos(1e-3)) {
      // Same line: merged.
      runs[k] = _Run.line(math.min(longLine.from, r.from), math.max(longLine.to, r.to));
      runs.remove(longLine);
      k = -1;
      continue;
    }
    if (arcNear && (longLine != null || prev?.isArc == true && next?.isArc == true)) {
      runs.removeAt(k);
      k = -1;
    }
  }

  // 2. The joins. Line -> arc and arc -> line meet where the arc's centre
  // drops square onto the line, which must lie at the arc's radius
  // (tangent); anything else is not a round pipe's path.
  _V lineDir(_Run l) => _unit(_sub(q[l.to], q[l.from]));
  _V? foot(_Run l, _V c) {
    final u = lineDir(l);
    final p = _add(q[l.from], _mul(u, _dot(_sub(c, q[l.from]), u)));
    return p;
  }

  final joins = <_V>[q.first];
  for (var k = 0; k + 1 < runs.length; k++) {
    final a = runs[k], b = runs[k + 1];
    if (!a.isArc && !b.isArc) {
      // Two lines: one straight line split by a sample? Else a corner.
      if (_dot(lineDir(a), lineDir(b)) < math.cos(1e-3)) return null;
      joins.add(q[a.to]);
      continue;
    }
    if (a.isArc && b.isArc) return null; // arc to arc: not needed here
    final arc = a.isArc ? a : b, line = a.isArc ? b : a;
    final t = foot(line, arc.centre!)!;
    final tol = math.max(1e-3, arc.r * 2e-3);
    if ((_len(_sub(t, arc.centre!)) - arc.r).abs() > tol) return null;
    if (_dot(_sub(t, arc.centre!), arc.axis!).abs() > tol) return null;
    joins.add(t);
  }
  joins.add(q.last);

  // 3. Segments between the joins; arcs cut into pieces under 180°.
  final segs = <double>[];
  for (var k = 0; k < runs.length; k++) {
    final s = joins[k], e = joins[k + 1];
    final run = runs[k];
    if (!run.isArc) {
      if (_len(_sub(e, s)) < eps) continue;
      segs.addAll([0, ...s, ...e, 0, 0, 0]);
      continue;
    }
    final c = run.centre!, axis = run.axis!;
    final u = _sub(s, c), w = _sub(e, c);
    var ang = math.atan2(_dot(_cross(u, w), axis), _dot(u, w));
    if (ang <= 0) ang += 2 * math.pi;
    final pieces = (ang / (math.pi * 0.9)).ceil();
    var from = s;
    for (var m = 1; m <= pieces; m++) {
      final t = ang * m / pieces;
      // Rotate u about axis by t (Rodrigues).
      final ct = math.cos(t), st = math.sin(t);
      final rot = _add(
          _add(_mul(u, ct), _mul(_cross(axis, u), st)),
          _mul(axis, _dot(axis, u) * (1 - ct)));
      final to = m == pieces ? e : _add(c, rot);
      segs.addAll([1, ...from, ...to, ...c]);
      from = to;
    }
  }
  return segs.isEmpty ? null : segs;
}

/// [segs] (see [roundPipeSegments]) with every arc of 162° or more cut into
/// pieces under that (occt_round_pipe takes arcs under 180°).
List<double> splitRoundArcs(List<double> segs) {
  final out = <double>[];
  for (var i = 0; i + 9 < segs.length; i += 10) {
    if (segs[i] < 0.5) {
      out.addAll(segs.sublist(i, i + 10));
      continue;
    }
    final s = segs.sublist(i + 1, i + 4), e = segs.sublist(i + 4, i + 7);
    final c = segs.sublist(i + 7, i + 10);
    final u = _sub(s, c), w = _sub(e, c);
    final cr = _cross(u, w);
    final ang = math.atan2(_len(cr), _dot(u, w));
    if (ang < math.pi * 0.9 || _len(cr) < 1e-12) {
      out.addAll(segs.sublist(i, i + 10));
      continue;
    }
    final axis = _unit(cr);
    final pieces = (ang / (math.pi * 0.9)).ceil();
    var from = s;
    for (var m = 1; m <= pieces; m++) {
      final t = ang * m / pieces;
      final ct = math.cos(t), st = math.sin(t);
      final rot = _add(_add(_mul(u, ct), _mul(_cross(axis, u), st)),
          _mul(axis, _dot(axis, u) * (1 - ct)));
      final to = m == pieces ? e : _add(c, rot);
      out.addAll([1, ...from, ...to, ...c]);
      from = to;
    }
  }
  return out;
}

/// [segs] run the other way.
List<double> reverseRoundPath(List<double> segs) {
  final out = <double>[];
  for (var i = segs.length - 10; i >= 0; i -= 10) {
    out.addAll([
      segs[i],
      ...segs.sublist(i + 4, i + 7),
      ...segs.sublist(i + 1, i + 4),
      ...segs.sublist(i + 7, i + 10),
    ]);
  }
  return out;
}
