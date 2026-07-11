// iPadProCAD — Modify tools (Move, Copy, Rotate, Scale, Stretch, Offset,
// Trim, Extend, Split). All operations work on the Dart-side geometry list;
// the engine document is rebuilt afterwards (the C-API is add-only).
//
// Trim/Extend/Split are intersection-driven exactly like Inventor: Trim
// removes the clicked span up to the nearest intersections (deletes the
// entity if nothing intersects), Extend prolongs the clicked end to the
// next intersection, Split cuts at the clicked point (circles split at
// their intersections with other geometry).
import 'dart:math' as math;
import 'dart:ui';

import 'ffi/qcad_engine.dart';
import 'snap.dart';

const double _eps = 1e-9;

// ---------------------------------------------------------------------------
// transforms (Move/Copy/Rotate/Scale/Stretch)
// ---------------------------------------------------------------------------
Geo transformGeo(Geo g, Offset Function(Offset) f) {
  switch (g.type) {
    case Geo.line:
      final a = f(Offset(g.data[0], g.data[1]));
      final b = f(Offset(g.data[2], g.data[3]));
      return Geo(Geo.line, [a.dx, a.dy, b.dx, b.dy]);
    case Geo.circle:
      final c = f(Offset(g.data[0], g.data[1]));
      final rp = f(Offset(g.data[0] + g.data[2], g.data[1]));
      return Geo(Geo.circle, [c.dx, c.dy, (rp - c).distance]);
    case Geo.arc:
      final c0 = Offset(g.data[0], g.data[1]);
      final c = f(c0);
      final s = f(c0 +
          Offset(math.cos(g.data[3]), math.sin(g.data[3])) * g.data[2]);
      final e = f(c0 +
          Offset(math.cos(g.data[4]), math.sin(g.data[4])) * g.data[2]);
      final m0ang = g.data[5] != 0
          ? g.data[3] - _sweepOf(g) / 2
          : g.data[3] + _sweepOf(g) / 2;
      final m = f(c0 + Offset(math.cos(m0ang), math.sin(m0ang)) * g.data[2]);
      final arc = arcThrough(s, m, e);
      return arc ?? Geo(Geo.line, [s.dx, s.dy, e.dx, e.dy]);
    case Geo.polyline:
      final n = g.data[1].toInt();
      final out = <double>[g.data[0], g.data[1]];
      for (var i = 0; i < n; i++) {
        final p = f(Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]));
        out.addAll([p.dx, p.dy]);
      }
      return Geo(Geo.polyline, out);
  }
  return g;
}

/// Circumscribed arc through 3 points as a Geo, or null if collinear.
Geo? arcThrough(Offset a, Offset b, Offset c) {
  final d = 2 *
      (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
  if (d.abs() < _eps) return null;
  final ux = ((a.dx * a.dx + a.dy * a.dy) * (b.dy - c.dy) +
          (b.dx * b.dx + b.dy * b.dy) * (c.dy - a.dy) +
          (c.dx * c.dx + c.dy * c.dy) * (a.dy - b.dy)) /
      d;
  final uy = ((a.dx * a.dx + a.dy * a.dy) * (c.dx - b.dx) +
          (b.dx * b.dx + b.dy * b.dy) * (a.dx - c.dx) +
          (c.dx * c.dx + c.dy * c.dy) * (b.dx - a.dx)) /
      d;
  final ce = Offset(ux, uy);
  final r = (a - ce).distance;
  double ang(Offset p) => math.atan2(p.dy - ce.dy, p.dx - ce.dx);
  final a1 = ang(a), am = ang(b), a2 = ang(c);
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final reversed = norm(am - a1) > norm(a2 - a1);
  return Geo(Geo.arc, [ce.dx, ce.dy, r, a1, a2, reversed ? 1.0 : 0.0]);
}

double _sweepOf(Geo arc) {
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  return arc.data[5] != 0
      ? norm(arc.data[3] - arc.data[4])
      : norm(arc.data[4] - arc.data[3]);
}

Offset Function(Offset) translation(Offset d) => (p) => p + d;
Offset Function(Offset) rotation(Offset c, double ang) => (p) {
      final v = p - c;
      return c +
          Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang),
              v.dx * math.sin(ang) + v.dy * math.cos(ang));
    };
Offset Function(Offset) scaling(Offset c, double f) => (p) => c + (p - c) * f;

/// Stretch: vertices inside [box] translate by [d], the rest stay (Inventor
/// stretch with a crossing window). Circles translate only if their center
/// is inside.
Geo stretchGeo(Geo g, Rect box, Offset d) {
  Offset f(Offset p) => box.contains(p) ? p + d : p;
  switch (g.type) {
    case Geo.line:
    case Geo.polyline:
      return transformGeo(g, f);
    case Geo.circle:
      return box.contains(Offset(g.data[0], g.data[1]))
          ? transformGeo(g, translation(d))
          : g;
    case Geo.arc:
      // endpoints in/out: move whole arc only if both ends inside
      final c = Offset(g.data[0], g.data[1]);
      final s = c + Offset(math.cos(g.data[3]), math.sin(g.data[3])) * g.data[2];
      final e = c + Offset(math.cos(g.data[4]), math.sin(g.data[4])) * g.data[2];
      if (box.contains(s) && box.contains(e)) {
        return transformGeo(g, translation(d));
      }
      return g;
  }
  return g;
}

// ---------------------------------------------------------------------------
// Offset (parallel copy)
// ---------------------------------------------------------------------------
Geo? offsetEntity(Geo g, Offset side) {
  switch (g.type) {
    case Geo.line:
      final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
      final dvec = b - a;
      if (dvec.distance < _eps) return null;
      var n = Offset(-dvec.dy, dvec.dx) / dvec.distance;
      final dist = (side - closestOnSegment(side, a, b)).distance;
      if ((side - a).dx * n.dx + (side - a).dy * n.dy < 0) n = -n;
      final o = n * dist;
      return Geo(Geo.line,
          [a.dx + o.dx, a.dy + o.dy, b.dx + o.dx, b.dy + o.dy]);
    case Geo.circle:
      final c = Offset(g.data[0], g.data[1]);
      final r2 = (side - c).distance;
      return r2 > _eps ? Geo(Geo.circle, [c.dx, c.dy, r2]) : null;
    case Geo.arc:
      final c = Offset(g.data[0], g.data[1]);
      final r2 = (side - c).distance;
      return r2 > _eps
          ? Geo(Geo.arc, [c.dx, c.dy, r2, g.data[3], g.data[4], g.data[5]])
          : null;
    case Geo.polyline:
      final n = g.data[1].toInt();
      if (n < 2) return null;
      final closed = g.data[0] != 0;
      final pts = [
        for (var i = 0; i < n; i++)
          Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
      ];
      // distance & side from nearest segment
      var bestD = double.infinity;
      var sideSign = 1.0;
      for (var i = 0; i + 1 < pts.length + (closed ? 1 : 0); i++) {
        final a = pts[i % n], b = pts[(i + 1) % n];
        final q = closestOnSegment(side, a, b);
        final d = (side - q).distance;
        if (d < bestD) {
          bestD = d;
          final dir = b - a;
          sideSign =
              (dir.dx * (side - a).dy - dir.dy * (side - a).dx) >= 0 ? 1 : -1;
        }
      }
      // per-vertex miter offset
      Offset segN(int i) {
        final a = pts[i % n], b = pts[(i + 1) % n];
        final dvec = b - a;
        final nn = Offset(-dvec.dy, dvec.dx) / dvec.distance;
        return nn * sideSign;
      }

      final segs = closed ? n : n - 1;
      final out = <Offset>[];
      for (var i = 0; i < n; i++) {
        Offset nn;
        if (!closed && i == 0) {
          nn = segN(0);
        } else if (!closed && i == n - 1) {
          nn = segN(n - 2);
        } else {
          final n1 = segN((i - 1 + segs) % segs), n2 = segN(i % segs);
          nn = n1 + n2;
          final l = nn.distance;
          if (l < 1e-6) {
            nn = n2;
          } else {
            nn = nn / l;
            final cosHalf = (n1.dx * nn.dx + n1.dy * nn.dy).clamp(0.2, 1.0);
            nn = nn / cosHalf; // miter
          }
        }
        out.add(pts[i] + nn * bestD);
      }
      return Geo(Geo.polyline, [
        closed ? 1.0 : 0.0,
        n.toDouble(),
        for (final q in out) ...[q.dx, q.dy]
      ]);
  }
  return null;
}

// ---------------------------------------------------------------------------
// intersections (analytic: segments + circles/arcs)
// ---------------------------------------------------------------------------
List<Offset> _segSeg(Offset p1, Offset p2, Offset p3, Offset p4) {
  final r = p2 - p1, s = p4 - p3;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < _eps) return const [];
  final t = ((p3 - p1).dx * s.dy - (p3 - p1).dy * s.dx) / den;
  final u = ((p3 - p1).dx * r.dy - (p3 - p1).dy * r.dx) / den;
  if (t < -1e-9 || t > 1 + 1e-9 || u < -1e-9 || u > 1 + 1e-9) return const [];
  return [p1 + r * t];
}

List<Offset> _segCircle(Offset a, Offset b, Offset c, double r) {
  final d = b - a, f = a - c;
  final aa = d.dx * d.dx + d.dy * d.dy;
  if (aa < _eps) return const [];
  final bb = 2 * (f.dx * d.dx + f.dy * d.dy);
  final cc = f.dx * f.dx + f.dy * f.dy - r * r;
  var disc = bb * bb - 4 * aa * cc;
  if (disc < 0) return const [];
  disc = math.sqrt(disc);
  final out = <Offset>[];
  for (final t in [(-bb - disc) / (2 * aa), (-bb + disc) / (2 * aa)]) {
    if (t >= -1e-9 && t <= 1 + 1e-9) out.add(a + d * t);
  }
  return out;
}

List<Offset> _circleCircle(Offset c1, double r1, Offset c2, double r2) {
  final d = (c2 - c1).distance;
  if (d < _eps || d > r1 + r2 + _eps || d < (r1 - r2).abs() - _eps) {
    return const [];
  }
  final a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
  final h2 = r1 * r1 - a * a;
  final h = h2 <= 0 ? 0.0 : math.sqrt(h2);
  final pm = c1 + (c2 - c1) * (a / d);
  final n = Offset(-(c2 - c1).dy, (c2 - c1).dx) / d;
  return h < _eps ? [pm] : [pm + n * h, pm - n * h];
}

/// Segment chains for an entity (circle/arc handled analytically elsewhere).
List<(Offset, Offset)> _segments(Geo g) {
  final pts = sampleEntity(g, arcSamples: 48);
  return [for (var i = 0; i + 1 < pts.length; i++) (pts[i], pts[i + 1])];
}

bool _isRound(Geo g) => g.type == Geo.circle || g.type == Geo.arc;

bool _onArcRange(Geo arc, Offset p) {
  final a = math.atan2(p.dy - arc.data[1], p.dx - arc.data[0]);
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final rev = arc.data[5] != 0;
  final sweep =
      rev ? norm(arc.data[3] - arc.data[4]) : norm(arc.data[4] - arc.data[3]);
  final rel = rev ? norm(arc.data[3] - a) : norm(a - arc.data[3]);
  return rel <= sweep + 1e-6;
}

List<Offset> intersections(Geo a, Geo b) {
  if (_isRound(a) && _isRound(b)) {
    var pts = _circleCircle(Offset(a.data[0], a.data[1]), a.data[2],
        Offset(b.data[0], b.data[1]), b.data[2]);
    if (a.type == Geo.arc) pts = pts.where((p) => _onArcRange(a, p)).toList();
    if (b.type == Geo.arc) pts = pts.where((p) => _onArcRange(b, p)).toList();
    return pts;
  }
  if (_isRound(a)) return intersections(b, a);
  final out = <Offset>[];
  for (final s in _segments(a)) {
    if (_isRound(b)) {
      var pts =
          _segCircle(s.$1, s.$2, Offset(b.data[0], b.data[1]), b.data[2]);
      if (b.type == Geo.arc) {
        pts = pts.where((p) => _onArcRange(b, p)).toList();
      }
      out.addAll(pts);
    } else {
      for (final t in _segments(b)) {
        out.addAll(_segSeg(s.$1, s.$2, t.$1, t.$2));
      }
    }
  }
  return out;
}

List<Offset> intersectionsWithOthers(List<Geo> geos, int i) {
  final out = <Offset>[];
  for (var j = 0; j < geos.length; j++) {
    if (j == i) continue;
    out.addAll(intersections(geos[i], geos[j]));
  }
  return out;
}

// ---------------------------------------------------------------------------
// param helpers (position along an entity)
// ---------------------------------------------------------------------------
double _lineParam(Geo g, Offset p) {
  final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 < _eps) return 0;
  return (((p - a).dx * d.dx + (p - a).dy * d.dy) / l2).clamp(0.0, 1.0);
}

double _arcParam(Geo g, Offset p) {
  // 0..sweep along direction of travel
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final a = math.atan2(p.dy - g.data[1], p.dx - g.data[0]);
  return g.data[5] != 0 ? norm(g.data[3] - a) : norm(a - g.data[3]);
}

Geo _subArc(Geo g, double u0, double u1) {
  // u in travel direction (0..sweep)
  final rev = g.data[5] != 0;
  final a1 = rev ? g.data[3] - u0 : g.data[3] + u0;
  final a2 = rev ? g.data[3] - u1 : g.data[3] + u1;
  return Geo(Geo.arc, [g.data[0], g.data[1], g.data[2], a1, a2, g.data[5]]);
}

// ---------------------------------------------------------------------------
// Trim / Extend / Split
// ---------------------------------------------------------------------------
/// Trims the clicked span of entity [i] up to the nearest intersections.
/// Returns the replacement entities (empty list = delete whole entity, like
/// Inventor when nothing intersects).
List<Geo> trimEntity(List<Geo> geos, int i, Offset click) {
  final g = geos[i];
  final xs = intersectionsWithOthers(geos, i);
  switch (g.type) {
    case Geo.line:
      final tc = _lineParam(g, click);
      final ts = xs.map((p) => _lineParam(g, p)).toList()..sort();
      double lo = 0, hi = 1;
      var hasLo = false, hasHi = false;
      for (final t in ts) {
        if (t < tc - 1e-7 && t > lo - 1e-12) {
          lo = t;
          hasLo = true;
        }
        if (t > tc + 1e-7 && t < hi + 1e-12) {
          hi = math.min(hi, t);
          hasHi = true;
        }
      }
      if (!hasLo && !hasHi) return const []; // nothing crosses: delete
      final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
      Offset at(double t) => a + (b - a) * t;
      return [
        if (hasLo) Geo(Geo.line, [a.dx, a.dy, at(lo).dx, at(lo).dy]),
        if (hasHi) Geo(Geo.line, [at(hi).dx, at(hi).dy, b.dx, b.dy]),
      ];
    case Geo.circle:
      if (xs.length < 2) return const [];
      final c = Offset(g.data[0], g.data[1]);
      double ang(Offset p) => math.atan2(p.dy - c.dy, p.dx - c.dx);
      double norm(double x) {
        var v = x % (2 * math.pi);
        if (v < 0) v += 2 * math.pi;
        return v;
      }

      final ac = norm(ang(click));
      final as = xs.map((p) => norm(ang(p))).toList()..sort();
      // find bracketing angles around the click (cyclic)
      double lo = as.last, hi = as.first;
      for (var k = 0; k < as.length; k++) {
        final a0 = as[k], a1 = as[(k + 1) % as.length];
        final inSpan = a0 <= a1
            ? (ac >= a0 && ac <= a1)
            : (ac >= a0 || ac <= a1);
        if (inSpan) {
          lo = a0;
          hi = a1;
          break;
        }
      }
      // keep the complement arc hi -> lo (CCW)
      return [Geo(Geo.arc, [c.dx, c.dy, g.data[2], hi, lo, 0.0])];
    case Geo.arc:
      final sweep = _sweepOf(g);
      final uc = _arcParam(g, click);
      final us = xs
          .map((p) => _arcParam(g, p))
          .where((u) => u > 1e-7 && u < sweep - 1e-7)
          .toList()
        ..sort();
      double lo = 0, hi = sweep;
      var hasLo = false, hasHi = false;
      for (final u in us) {
        if (u < uc - 1e-7) {
          lo = math.max(lo, u);
          hasLo = true;
        }
        if (u > uc + 1e-7) {
          hi = math.min(hi, u);
          hasHi = true;
        }
      }
      if (!hasLo && !hasHi) return const [];
      return [
        if (hasLo) _subArc(g, 0, lo),
        if (hasHi) _subArc(g, hi, sweep),
      ];
    case Geo.polyline:
      // treat the clicked SEGMENT like a line trim; other segments survive
      final n = g.data[1].toInt();
      final closed = g.data[0] != 0;
      final pts = [
        for (var k = 0; k < n; k++) Offset(g.data[2 + 2 * k], g.data[3 + 2 * k])
      ];
      final segs = closed ? n : n - 1;
      var bestSeg = 0;
      var bd = double.infinity;
      for (var k = 0; k < segs; k++) {
        final q = closestOnSegment(click, pts[k], pts[(k + 1) % n]);
        final d = (click - q).distance;
        if (d < bd) {
          bd = d;
          bestSeg = k;
        }
      }
      final segGeo = Geo(Geo.line, [
        pts[bestSeg].dx,
        pts[bestSeg].dy,
        pts[(bestSeg + 1) % n].dx,
        pts[(bestSeg + 1) % n].dy
      ]);
      final replaced = trimEntity([...geos]..[i] = segGeo, i, click);
      // stitch: polyline minus that segment (split into open chains) + trims
      final chains = <List<Offset>>[];
      if (closed) {
        final chain = <Offset>[];
        for (var k = 1; k <= n; k++) {
          chain.add(pts[(bestSeg + k) % n]);
        }
        chains.add(chain);
      } else {
        if (bestSeg > 0) chains.add(pts.sublist(0, bestSeg + 1));
        if (bestSeg + 1 < n - 0 && bestSeg + 1 <= n - 1) {
          final rest = pts.sublist(bestSeg + 1);
          if (rest.length > 1) chains.add(rest);
        }
      }
      return [
        for (final ch in chains)
          if (ch.length == 2)
            Geo(Geo.line, [ch[0].dx, ch[0].dy, ch[1].dx, ch[1].dy])
          else if (ch.length > 2)
            Geo(Geo.polyline, [
              0.0,
              ch.length.toDouble(),
              for (final q in ch) ...[q.dx, q.dy]
            ]),
        ...replaced,
      ];
  }
  return [g];
}

/// Extends the clicked END of entity [i] to the nearest intersection of its
/// prolongation with other geometry. Returns null if nothing to extend to.
Geo? extendEntity(List<Geo> geos, int i, Offset click) {
  final g = geos[i];
  const big = 1e6;
  switch (g.type) {
    case Geo.line:
      final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
      final d = b - a;
      if (d.distance < _eps) return null;
      final dn = d / d.distance;
      final fromB = (click - b).distance <= (click - a).distance;
      final end = fromB ? b : a;
      final dir = fromB ? dn : -dn;
      final probe = Geo(Geo.line,
          [end.dx, end.dy, end.dx + dir.dx * big, end.dy + dir.dy * big]);
      Offset? best;
      var bd = double.infinity;
      for (var j = 0; j < geos.length; j++) {
        if (j == i) continue;
        for (final p in intersections(probe, geos[j])) {
          final dd = (p - end).distance;
          if (dd > 1e-6 && dd < bd) {
            bd = dd;
            best = p;
          }
        }
      }
      if (best == null) return null;
      return fromB
          ? Geo(Geo.line, [a.dx, a.dy, best.dx, best.dy])
          : Geo(Geo.line, [best.dx, best.dy, b.dx, b.dy]);
    case Geo.arc:
      final sweep = _sweepOf(g);
      final uc = _arcParam(g, click);
      final fromEnd = uc >= sweep / 2; // extend the nearer end
      final full = Geo(Geo.circle, [g.data[0], g.data[1], g.data[2]]);
      double bestU = double.infinity;
      for (var j = 0; j < geos.length; j++) {
        if (j == i) continue;
        for (final p in intersections(full, geos[j])) {
          var u = _arcParam(g, p);
          // relative extension beyond the chosen end, in travel direction
          final du = fromEnd ? u - sweep : -u;
          final duN = du <= 1e-6 ? du + 2 * math.pi : du;
          if (duN > 1e-6 && duN < bestU) bestU = duN;
        }
      }
      if (!bestU.isFinite || bestU >= 2 * math.pi - sweep - 1e-6) return null;
      return fromEnd
          ? _subArc(g, 0, sweep + bestU)
          : _subArc(g, -bestU, sweep);
    default:
      return null; // circles/polylines: nothing sensible to extend
  }
}

/// Splits entity [i] at the clicked point (circles: at ALL intersections
/// with other geometry, like Inventor). Returns replacements, or null if a
/// split isn't possible.
List<Geo>? splitEntity(List<Geo> geos, int i, Offset click) {
  final g = geos[i];
  switch (g.type) {
    case Geo.line:
      final t = _lineParam(g, click);
      if (t < 1e-6 || t > 1 - 1e-6) return null;
      final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
      final m = a + (b - a) * t;
      return [
        Geo(Geo.line, [a.dx, a.dy, m.dx, m.dy]),
        Geo(Geo.line, [m.dx, m.dy, b.dx, b.dy]),
      ];
    case Geo.arc:
      final sweep = _sweepOf(g);
      final u = _arcParam(g, click);
      if (u < 1e-6 || u > sweep - 1e-6) return null;
      return [_subArc(g, 0, u), _subArc(g, u, sweep)];
    case Geo.circle:
      final xs = intersectionsWithOthers(geos, i);
      if (xs.length < 2) return null;
      final c = Offset(g.data[0], g.data[1]);
      double norm(double x) {
        var v = x % (2 * math.pi);
        if (v < 0) v += 2 * math.pi;
        return v;
      }

      final as = xs
          .map((p) => norm(math.atan2(p.dy - c.dy, p.dx - c.dx)))
          .toList()
        ..sort();
      return [
        for (var k = 0; k < as.length; k++)
          Geo(Geo.arc,
              [c.dx, c.dy, g.data[2], as[k], as[(k + 1) % as.length], 0.0])
      ];
    case Geo.polyline:
      // split at nearest vertex or on-segment point into two open chains
      final n = g.data[1].toInt();
      final closed = g.data[0] != 0;
      if (closed) return null;
      final pts = [
        for (var k = 0; k < n; k++) Offset(g.data[2 + 2 * k], g.data[3 + 2 * k])
      ];
      var seg = 0;
      var bd = double.infinity;
      Offset m = pts[0];
      for (var k = 0; k + 1 < n; k++) {
        final q = closestOnSegment(click, pts[k], pts[k + 1]);
        final d = (click - q).distance;
        if (d < bd) {
          bd = d;
          seg = k;
          m = q;
        }
      }
      final c1 = [...pts.sublist(0, seg + 1), m];
      final c2 = [m, ...pts.sublist(seg + 1)];
      Geo chain(List<Offset> ch) => ch.length == 2
          ? Geo(Geo.line, [ch[0].dx, ch[0].dy, ch[1].dx, ch[1].dy])
          : Geo(Geo.polyline, [
              0.0,
              ch.length.toDouble(),
              for (final q in ch) ...[q.dx, q.dy]
            ]);
      return [chain(c1), chain(c2)];
  }
  return null;
}
