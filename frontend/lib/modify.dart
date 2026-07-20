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

/// Every modify operation DERIVES its result from a source entity, so the result
/// must land on the source's layer. Rebuilding a Geo by type (which is what all
/// the constructions below do) would silently drop it onto layer 0 — geometry
/// belongs to a layer, and a trim must not smuggle it out of one. Stamped at the
/// function boundaries so a new construction inside cannot leak.
Geo _sameLayer(Geo src, Geo out) => _carry(src, out);
List<Geo> _sameLayerAll(Geo src, List<Geo> out) =>
    [for (final g in out) _carry(src, g)];

/// Copy layer (always), the LINE STYLE (always — centerline/construction are
/// entity tags exactly like the layer; before M40 every trim/move/rotate/
/// mirror/stretch/offset silently reverted a styled entity to normal), and the
/// spline tag (when the result is still a polyline) from [src] onto [out].
/// A spline is a tagged polyline, so those ops must keep the tag or the curve
/// reverts to a straight polygon.
Geo _carry(Geo src, Geo out) {
  var o = out.onLayer(src.layer);
  if (src.style != Geo.styleNormal && out.style == Geo.styleNormal) {
    o = o.withStyle(src.style);
  }
  return (src.spline != Geo.straight &&
          out.type == Geo.polyline &&
          out.spline == Geo.straight)
      ? o.asSpline(src.spline)
      : o;
}

Geo transformGeo(Geo g, Offset Function(Offset) f) {
  return _sameLayer(g, _transformGeoRaw(g, f));
}

Geo _transformGeoRaw(Geo g, Offset Function(Offset) f) {
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

  return (arc.data.length > 5 && arc.data[5] != 0)
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
Geo stretchGeo(Geo g, Rect box, Offset d) =>
    _sameLayer(g, _stretchGeoRaw(g, box, d));

Geo _stretchGeoRaw(Geo g, Rect box, Offset d) {
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
  final r = _offsetEntityRaw(g, side);
  return r == null ? null : _sameLayer(g, r);
}

Geo? _offsetEntityRaw(Geo g, Offset side) {
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
          ? Geo(Geo.arc, [
              c.dx,
              c.dy,
              r2,
              g.data[3],
              g.data[4],
              g.data.length > 5 ? g.data[5] : 0.0
            ])
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
// Offset CHAIN — Inventor's "Loop Select" (ON by default): one pick offsets
// the whole connected run of edges, not just the clicked one. A chain follows
// shared endpoints; it continues through a corner that has exactly ONE other
// edge and STOPS at a branch (a vertex where 2+ other edges meet), exactly as
// Inventor/Abaqus define a chain ("each edge connected to at most one other at
// each endpoint"). A closed run (rectangle, polygon, any closed profile) comes
// back to the seed and offsets as one loop.
//
// Only LINE and ARC entities chain. A circle, spline, ellipse or single
// polyline still offsets as its own whole shape via [offsetEntity] (they are
// already one entity), so the seed-type is handled first, before the walk.
//
// The offset geometry is built with real mitred corners (adjacent offsets
// intersected: line∩line, line∩circle, circle∩circle) so the corners are
// coincident from the start; the caller then pins coincident corners +
// parallel/concentric to source + the offset distance, and the solver settles
// the exact result. Because the result is solved, the initial miter only has
// to be topologically right, not numerically perfect.
// ---------------------------------------------------------------------------

/// One offset chain: [sources] are the source entity indices in traversal
/// order, [offsets] the parallel copy of each (same type, layer already
/// carried), and [enterPt]/[exitPt] the NEW-geometry point indices of each
/// segment's incoming/outgoing corner (so the caller can wire coincidences and
/// perpendicular-distance dimensions without re-deriving orientation).
class OffsetChain {
  final List<int> sources;
  final List<Geo> offsets;
  final List<int> enterPt;
  final List<int> exitPt;
  final bool closed;
  final double offsetDist; // uniform perpendicular offset magnitude
  const OffsetChain(this.sources, this.offsets, this.enterPt, this.exitPt,
      this.closed, this.offsetDist);
}

Offset _ptOf(Geo g, int i) {
  switch (g.type) {
    case Geo.line:
      return i == 0
          ? Offset(g.data[0], g.data[1])
          : Offset(g.data[2], g.data[3]);
    case Geo.arc:
      if (i == 0) return Offset(g.data[0], g.data[1]);
      final a = i == 1 ? g.data[3] : g.data[4];
      return Offset(
          g.data[0] + math.cos(a) * g.data[2], g.data[1] + math.sin(a) * g.data[2]);
  }
  return Offset.zero;
}

/// The two CHAIN endpoints of an entity (only line & arc participate): the
/// point index and its world position. Line ends are 0/1, arc ends are its
/// start/end (1/2) — never the centre.
List<(int, Offset)> _chainEnds(Geo g) {
  switch (g.type) {
    case Geo.line:
      return [(0, _ptOf(g, 0)), (1, _ptOf(g, 1))];
    case Geo.arc:
      return [(1, _ptOf(g, 1)), (2, _ptOf(g, 2))];
    default:
      return const [];
  }
}

/// Infinite line ∩ infinite line (miter point), or null if parallel.
Offset? _infX(Offset a1, Offset a2, Offset b1, Offset b2) {
  final r = a2 - a1, s = b2 - b1;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < _eps) return null;
  final t = ((b1 - a1).dx * s.dy - (b1 - a1).dy * s.dx) / den;
  return a1 + r * t;
}

/// Infinite line ∩ circle, both solutions (0..2).
List<Offset> _infLineCircle(Offset a, Offset b, Offset c, double r) {
  final d = b - a, f = a - c;
  final aa = d.dx * d.dx + d.dy * d.dy;
  if (aa < _eps) return const [];
  final bb = 2 * (f.dx * d.dx + f.dy * d.dy);
  final cc = f.dx * f.dx + f.dy * f.dy - r * r;
  var disc = bb * bb - 4 * aa * cc;
  if (disc < 0) return const [];
  disc = math.sqrt(disc);
  return [
    a + d * ((-bb - disc) / (2 * aa)),
    a + d * ((-bb + disc) / (2 * aa)),
  ];
}

Offset? _nearestOf(List<Offset> cands, Offset to) {
  Offset? best;
  var bd = double.infinity;
  for (final p in cands) {
    final dd = (p - to).distance;
    if (dd < bd) {
      bd = dd;
      best = p;
    }
  }
  return best;
}

/// Build the maximal offset chain through [seed], offset toward [pick].
/// [allowed] is the set of chain-eligible entity indices (line/arc, on the
/// editing layer, not projected) — the caller's scope rules. Returns null when
/// the seed cannot be offset at all.
OffsetChain? offsetChainAt(
    List<Geo> gs, int seed, Offset pick, Set<int> allowed) {
  if (seed < 0 || seed >= gs.length) return null;
  final st = gs[seed].type;
  // Non line/arc seeds are single whole-shape entities already.
  if (st != Geo.line && st != Geo.arc) {
    final o = offsetEntity(gs[seed], pick);
    return o == null
        ? null
        : OffsetChain([seed], [o], [0], [0], false, 0);
  }
  if (!allowed.contains(seed)) return null;

  const tol = 1e-4;
  List<(int, int)> nbrsAt(Offset p, Set<int> exclude) {
    final out = <(int, int)>[];
    for (final e in allowed) {
      if (exclude.contains(e)) continue;
      for (final end in _chainEnds(gs[e])) {
        if ((end.$2 - p).distance <= tol) out.add((e, end.$1));
      }
    }
    return out;
  }

  int otherEnd(int e, int enterPi) {
    final ends = _chainEnds(gs[e]);
    return ends[0].$1 == enterPi ? ends[1].$1 : ends[0].$1;
  }

  var closed = false;
  // Walk away from the seed, leaving through [startExitPt]; [homeEnterPt] is the
  // seed's OTHER end — reaching it again means the run closed into a loop. Each
  // step needs EXACTLY one unvisited neighbour (a branch stops the chain).
  List<(int, int, int)> walk(
      int startExitPt, int homeEnterPt, Set<int> visited) {
    final home = _ptOf(gs[seed], homeEnterPt);
    final chain = <(int, int, int)>[];
    var curEnt = seed, curExit = startExitPt;
    while (true) {
      final exitPos = _ptOf(gs[curEnt], curExit);
      if (chain.isNotEmpty && (exitPos - home).distance <= tol) {
        closed = true; // wrapped back to the seed
        break;
      }
      final nb = nbrsAt(exitPos, visited);
      if (nb.length != 1) break;
      final ne = nb.first.$1, nEnter = nb.first.$2;
      final nExit = otherEnd(ne, nEnter);
      chain.add((ne, nEnter, nExit));
      visited.add(ne);
      curEnt = ne;
      curExit = nExit;
    }
    return chain;
  }

  final ends = _chainEnds(gs[seed]);
  final aPi = ends[0].$1, bPi = ends[1].$1;
  final visited = <int>{seed};
  final fwd = walk(bPi, aPi, visited); // out through b; home is the a-end
  final bwd = closed ? const <(int, int, int)>[] : walk(aPi, bPi, visited);

  // Assemble in traversal order: reversed backward run, seed (a->b), forward.
  final elems = <(int, int, int)>[]; // (ent, enterPt, exitPt)
  for (final e in bwd.reversed) {
    elems.add((e.$1, e.$3, e.$2)); // reverse orientation
  }
  elems.add((seed, aPi, bPi));
  elems.addAll(fwd);

  // ---- distance + side, measured against the nearest element ----
  var nearIdx = 0;
  var nearBounded = double.infinity;
  for (var i = 0; i < elems.length; i++) {
    final g = gs[elems[i].$1];
    double db;
    if (g.type == Geo.line) {
      db = (pick - closestOnSegment(pick, _ptOf(g, 0), _ptOf(g, 1))).distance;
    } else {
      db = ((pick - Offset(g.data[0], g.data[1])).distance - g.data[2]).abs();
    }
    if (db < nearBounded) {
      nearBounded = db;
      nearIdx = i;
    }
  }
  final ng = gs[elems[nearIdx].$1];
  double dist; // uniform offset magnitude (perpendicular to the support)
  double sideSign; // +1 left / -1 right of TRAVERSAL direction
  if (ng.type == Geo.line) {
    final en = _ptOf(ng, elems[nearIdx].$2), ex = _ptOf(ng, elems[nearIdx].$3);
    final u = ex - en;
    dist = (pick - _infProj(pick, en, ex)).distance;
    sideSign = (u.dx * (pick - en).dy - u.dy * (pick - en).dx) >= 0 ? 1 : -1;
  } else {
    final c = Offset(ng.data[0], ng.data[1]);
    dist = ((pick - c).distance - ng.data[2]).abs();
    final pn = c + (pick - c) / (pick - c).distance * ng.data[2];
    final ccw = _ccwInTraversal(ng, elems[nearIdx].$2);
    final rad = (pn - c);
    final u = ccw
        ? Offset(-rad.dy, rad.dx)
        : Offset(rad.dy, -rad.dx); // traversal tangent
    sideSign = (u.dx * (pick - pn).dy - u.dy * (pick - pn).dx) >= 0 ? 1 : -1;
  }
  if (dist < 1e-7) return null;

  // ---- offset each segment (pre-miter) as parallel line / concentric arc ----
  final off = <Geo>[]; // aligned with elems
  final enterPt = <int>[];
  final exitPt = <int>[];
  final segEnter = <Offset>[]; // world corner (enter) after building/mitering
  final segExit = <Offset>[];
  for (final el in elems) {
    final g = gs[el.$1];
    if (g.type == Geo.line) {
      final en = _ptOf(g, el.$2), ex = _ptOf(g, el.$3);
      final u = ex - en;
      final nL = Offset(-u.dy, u.dx) / u.distance; // left normal
      final delta = nL * (sideSign * dist);
      final oe = en + delta, ox = ex + delta;
      off.add(Geo(Geo.line, [oe.dx, oe.dy, ox.dx, ox.dy]));
      enterPt.add(0);
      exitPt.add(1);
      segEnter.add(oe);
      segExit.add(ox);
    } else {
      final c = Offset(g.data[0], g.data[1]);
      final r = g.data[2];
      final ccw = _ccwInTraversal(g, el.$2);
      final rp = r - (ccw ? 1 : -1) * sideSign * dist;
      if (rp < 1e-6) return null; // segment collapses -> abandon chain
      final enPt = _ptOf(g, el.$2), exPt = _ptOf(g, el.$3);
      final oe = c + (enPt - c) / r * rp, ox = c + (exPt - c) / r * rp;
      // preserve the source's stored start/end mapping and sweep direction
      final startPt = el.$2 == 1 ? oe : ox; // maps to data[3]
      final endPt = el.$2 == 1 ? ox : oe; // maps to data[4]
      off.add(Geo(Geo.arc, [
        c.dx,
        c.dy,
        rp,
        math.atan2(startPt.dy - c.dy, startPt.dx - c.dx),
        math.atan2(endPt.dy - c.dy, endPt.dx - c.dx),
        g.data.length > 5 ? g.data[5] : 0.0,
      ]));
      // NEW arc: start=pt1, end=pt2. enter maps back to whichever holds it.
      enterPt.add(el.$2 == 1 ? 1 : 2);
      exitPt.add(el.$2 == 1 ? 2 : 1);
      segEnter.add(oe);
      segExit.add(ox);
    }
  }

  // ---- mitre corners: exit[i] meets enter[i+1] (wrap if closed) ----
  bool miter(int i, int j) {
    final gi = gs[elems[i].$1], gj = gs[elems[j].$1];
    final corner = _ptOf(gi, elems[i].$3); // original shared vertex
    Offset? p;
    if (gi.type == Geo.line && gj.type == Geo.line) {
      p = _infX(segEnter[i], segExit[i], segEnter[j], segExit[j]);
    } else if (gi.type == Geo.line && gj.type == Geo.arc) {
      p = _nearestOf(
          _infLineCircle(segEnter[i], segExit[i],
              Offset(off[j].data[0], off[j].data[1]), off[j].data[2]),
          corner);
    } else if (gi.type == Geo.arc && gj.type == Geo.line) {
      p = _nearestOf(
          _infLineCircle(segEnter[j], segExit[j],
              Offset(off[i].data[0], off[i].data[1]), off[i].data[2]),
          corner);
    } else {
      p = _nearestOf(
          _circleCircle(Offset(off[i].data[0], off[i].data[1]), off[i].data[2],
              Offset(off[j].data[0], off[j].data[1]), off[j].data[2]),
          corner);
    }
    if (p == null) return false;
    segExit[i] = p;
    segEnter[j] = p;
    return true;
  }

  final pairs = <(int, int)>[];
  for (var i = 0; i + 1 < elems.length; i++) {
    pairs.add((i, i + 1));
  }
  if (closed && elems.length >= 2) pairs.add((elems.length - 1, 0));
  for (final pr in pairs) {
    if (!miter(pr.$1, pr.$2)) return null; // a corner has no miter -> abandon
  }

  // ---- rebuild each offset Geo from its (mitered) corner points ----
  for (var i = 0; i < elems.length; i++) {
    final srcG = gs[elems[i].$1];
    if (off[i].type == Geo.line) {
      off[i] = _sameLayer(
          srcG, Geo(Geo.line, [segEnter[i].dx, segEnter[i].dy, segExit[i].dx, segExit[i].dy]));
    } else {
      final c = Offset(off[i].data[0], off[i].data[1]);
      final rp = off[i].data[2];
      final startPt = enterPt[i] == 1 ? segEnter[i] : segExit[i];
      final endPt = enterPt[i] == 1 ? segExit[i] : segEnter[i];
      off[i] = _sameLayer(
          srcG,
          Geo(Geo.arc, [
            c.dx,
            c.dy,
            rp,
            math.atan2(startPt.dy - c.dy, startPt.dx - c.dx),
            math.atan2(endPt.dy - c.dy, endPt.dx - c.dx),
            off[i].data[5],
          ]));
    }
  }

  return OffsetChain(
      [for (final e in elems) e.$1], off, enterPt, exitPt, closed, dist);
}

/// Foot of the perpendicular from [p] to the INFINITE line a->b.
Offset _infProj(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 < _eps) return a;
  final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2;
  return a + ab * t;
}

/// Is arc [g] swept CCW when entered at point index [enterPt]? Stored sweep is
/// CCW (start->end) unless the reversed flag (data[5]) is set; entering at the
/// END point reverses that.
bool _ccwInTraversal(Geo g, int enterPt) {
  final baseCcw = !(g.data.length > 5 && g.data[5] != 0);
  final flipped = enterPt != 1; // entered at the end, not the start
  return flipped ? !baseCcw : baseCcw;
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
  // derived from g -> keep its layer
  return _sameLayer(g, _subArcRaw(g, u0, u1));
}

Geo _subArcRaw(Geo g, double u0, double u1) {
  // u in travel direction (0..sweep)
  final rev = g.data.length > 5 && g.data[5] != 0;
  final a1 = rev ? g.data[3] - u0 : g.data[3] + u0;
  final a2 = rev ? g.data[3] - u1 : g.data[3] + u1;
  return Geo(Geo.arc, [
    g.data[0],
    g.data[1],
    g.data[2],
    a1,
    a2,
    g.data.length > 5 ? g.data[5] : 0.0
  ]);
}

// ---------------------------------------------------------------------------
// Trim / Extend / Split
// ---------------------------------------------------------------------------
/// Trims the clicked span of entity [i] up to the nearest intersections.
/// Returns the replacement entities (empty list = delete whole entity, like
/// Inventor when nothing intersects).
List<Geo> trimEntity(List<Geo> geos, int i, Offset click) =>
    _sameLayerAll(geos[i], _trimEntityRaw(geos, i, click));

List<Geo> _trimEntityRaw(List<Geo> geos, int i, Offset click) {
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
  final r = _extendEntityRaw(geos, i, click);
  return r == null ? null : _sameLayer(geos[i], r);
}

Geo? _extendEntityRaw(List<Geo> geos, int i, Offset click) {
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

// ---------------------------------------------------------------------------
// M49 — Split, exactly as Inventor's 2D sketch Split behaves
// ---------------------------------------------------------------------------
// Autodesk: "the Split command splits a selected curve to the NEAREST
// INTERSECTING CURVE". So the cut does NOT land where you clicked — the click
// only says WHICH curve and WHERE ALONG IT you are, and Inventor then snaps
// the cut to the intersection nearest the cursor. "When multiple intersections
// are possible, Inventor selects the nearest one."
//
// Open carriers (line, arc, open polyline/spline) have endpoints that already
// bound them, so ONE cut at the nearest interior intersection is enough — two
// pieces. Closed carriers (circle, closed polyline) have no ends to bound a
// single cut, so Inventor runs outward from the cursor in BOTH directions
// until it hits something (the LinkedIn/Lynda walkthrough describes exactly
// this): the hovered span between those two hits, plus its complement — again
// two pieces.
//
// Unlike Trim, Split NEVER deletes: with nothing to cut against there is
// simply no split (the preview offers none and the click is a no-op).

/// What a Split at [click] would do — used both to execute the split and to
/// paint Inventor's hover preview before the click.
class SplitPlan {
  /// The cut point(s): one for an open carrier, two for a closed one.
  final List<Offset> cuts;

  /// Always exactly two pieces, in no particular order.
  final List<Geo> pieces;

  /// Index in [pieces] of the span the cursor is actually on — Inventor
  /// highlights it during the hover preview.
  final int hovered;

  const SplitPlan(this.cuts, this.pieces, this.hovered);
}

/// Plans the Inventor split of entity [i] under the cursor at [click].
/// Returns null when the carrier has no usable intersection (no split).
SplitPlan? planSplit(List<Geo> geos, int i, Offset click) {
  final raw = _planSplitRaw(geos, i, click);
  if (raw == null) return null;
  // every piece is DERIVED from the carrier: layer, line style and spline tag
  // must ride along (same rule as trim/extend, see _carry)
  return SplitPlan(raw.cuts, _sameLayerAll(geos[i], raw.pieces), raw.hovered);
}

/// Splits entity [i] at the intersection nearest the cursor. Returns the two
/// replacement entities, or null if a split isn't possible.
List<Geo>? splitEntity(List<Geo> geos, int i, Offset click) =>
    planSplit(geos, i, click)?.pieces;

/// Cut point(s) a Split at [click] would produce — for the hover preview.
List<Offset> splitPoints(List<Geo> geos, int i, Offset click) =>
    planSplit(geos, i, click)?.cuts ?? const [];

SplitPlan? _planSplitRaw(List<Geo> geos, int i, Offset click) {
  final g = geos[i];
  final xs = intersectionsWithOthers(geos, i);
  if (xs.isEmpty) return null;
  switch (g.type) {
    case Geo.line:
      return _splitOpen(
        param: (p) => _lineParam(g, p),
        end: 1.0,
        click: click,
        xs: xs,
        piece: (t0, t1) {
          final a = Offset(g.data[0], g.data[1]),
              b = Offset(g.data[2], g.data[3]);
          Offset at(double t) => a + (b - a) * t;
          final p0 = at(t0), p1 = at(t1);
          return Geo(Geo.line, [p0.dx, p0.dy, p1.dx, p1.dy]);
        },
        at: (t) {
          final a = Offset(g.data[0], g.data[1]),
              b = Offset(g.data[2], g.data[3]);
          return a + (b - a) * t;
        },
      );
    case Geo.arc:
      final sweep = _sweepOf(g);
      if (sweep <= _eps) return null;
      return _splitOpen(
        param: (p) => _arcParam(g, p),
        end: sweep,
        click: click,
        xs: xs,
        piece: (u0, u1) => _subArcRaw(g, u0, u1),
        at: (u) => _arcPointAt(g, u),
      );
    case Geo.circle:
      final c = Offset(g.data[0], g.data[1]);
      final r = g.data[2];
      double ang(Offset p) => _norm2pi(math.atan2(p.dy - c.dy, p.dx - c.dx));
      return _splitClosed(
        param: ang,
        period: 2 * math.pi,
        click: click,
        xs: xs,
        piece: (a0, a1) => Geo(Geo.arc, [c.dx, c.dy, r, a0, a1, 0.0]),
        at: (a) => c + Offset(math.cos(a) * r, math.sin(a) * r),
      );
    case Geo.polyline:
      final closed = g.data[0] != 0;
      final pts = _polyPts(g);
      if (pts.length < 2) return null;
      final lens = _polyCumLen(pts, closed);
      final total = lens.last;
      if (total <= _eps) return null;
      double param(Offset p) => _polyParam(pts, closed, lens, p);
      Geo piece(double s0, double s1) =>
          _polySub(pts, closed, lens, s0, s1);
      Offset at(double s) => _polyPointAt(pts, closed, lens, s);
      return closed
          ? _splitClosed(
              param: param,
              period: total,
              click: click,
              xs: xs,
              piece: piece,
              at: at)
          : _splitOpen(
              param: param,
              end: total,
              click: click,
              xs: xs,
              piece: piece,
              at: at);
  }
  return null;
}

/// One cut on a carrier that already has two ends: the interior intersection
/// nearest the cursor wins ("Inventor selects the nearest one").
SplitPlan? _splitOpen({
  required double Function(Offset) param,
  required double end,
  required Offset click,
  required List<Offset> xs,
  required Geo Function(double, double) piece,
  required Offset Function(double) at,
}) {
  final tol = math.max(1e-7, end * 1e-7);
  final tc = param(click);
  double? best;
  var bd = double.infinity;
  for (final p in xs) {
    final t = param(p);
    // an intersection AT an end does not cut anything — it is already a
    // boundary of the carrier, so Inventor offers no split there
    if (t <= tol || t >= end - tol) continue;
    final d = (t - tc).abs();
    if (d < bd) {
      bd = d;
      best = t;
    }
  }
  if (best == null) return null;
  final cut = at(best);
  final pieces = [piece(0, best), piece(best, end)];
  return SplitPlan([cut], pieces, tc <= best ? 0 : 1);
}

/// Two cuts on a carrier with no ends: run outward from the cursor in both
/// directions to the first intersection each way. The hovered span and its
/// complement are the two resulting entities.
SplitPlan? _splitClosed({
  required double Function(Offset) param,
  required double period,
  required Offset click,
  required List<Offset> xs,
  required Geo Function(double, double) piece,
  required Offset Function(double) at,
}) {
  final tol = math.max(1e-7, period * 1e-7);
  final ts = <double>[];
  for (final p in xs) {
    final t = param(p) % period;
    if (!ts.any((o) => (o - t).abs() <= tol ||
        (period - (o - t).abs()).abs() <= tol)) {
      ts.add(t);
    }
  }
  // one tangential touch cannot separate a closed curve into two spans
  if (ts.length < 2) return null;
  ts.sort();
  final tc = param(click) % period;
  // the bracketing pair around the cursor (cyclic)
  var lo = ts.last, hi = ts.first;
  for (var k = 0; k < ts.length; k++) {
    final a0 = ts[k], a1 = ts[(k + 1) % ts.length];
    final inSpan = a0 <= a1 ? (tc >= a0 && tc <= a1) : (tc >= a0 || tc <= a1);
    if (inSpan) {
      lo = a0;
      hi = a1;
      break;
    }
  }
  // hovered span lo -> hi, complement hi -> lo (both in travel direction)
  return SplitPlan([at(lo), at(hi)], [piece(lo, hi), piece(hi, lo)], 0);
}

double _norm2pi(double x) {
  var v = x % (2 * math.pi);
  if (v < 0) v += 2 * math.pi;
  return v;
}

Offset _arcPointAt(Geo g, double u) {
  final rev = g.data.length > 5 && g.data[5] != 0;
  final a = rev ? g.data[3] - u : g.data[3] + u;
  return Offset(g.data[0], g.data[1]) +
      Offset(math.cos(a) * g.data[2], math.sin(a) * g.data[2]);
}

// --- polyline arc-length parametrisation (shared by open & closed) ---------

List<Offset> _polyPts(Geo g) {
  final n = g.data[1].toInt();
  return [
    for (var k = 0; k < n; k++) Offset(g.data[2 + 2 * k], g.data[3 + 2 * k])
  ];
}

/// Cumulative length at each vertex; the last entry is the total length
/// (including the closing segment when [closed]).
List<double> _polyCumLen(List<Offset> pts, bool closed) {
  final out = <double>[0.0];
  final segs = closed ? pts.length : pts.length - 1;
  for (var k = 0; k < segs; k++) {
    out.add(out.last + (pts[(k + 1) % pts.length] - pts[k]).distance);
  }
  return out;
}

double _polyParam(
    List<Offset> pts, bool closed, List<double> lens, Offset p) {
  final segs = closed ? pts.length : pts.length - 1;
  var best = 0.0;
  var bd = double.infinity;
  for (var k = 0; k < segs; k++) {
    final a = pts[k], b = pts[(k + 1) % pts.length];
    final q = closestOnSegment(p, a, b);
    final d = (p - q).distance;
    if (d < bd) {
      bd = d;
      best = lens[k] + (q - a).distance;
    }
  }
  return best;
}

Offset _polyPointAt(
    List<Offset> pts, bool closed, List<double> lens, double s) {
  final total = lens.last;
  var t = closed ? s % total : s.clamp(0.0, total);
  final segs = closed ? pts.length : pts.length - 1;
  for (var k = 0; k < segs; k++) {
    if (t <= lens[k + 1] + _eps) {
      final a = pts[k], b = pts[(k + 1) % pts.length];
      final segLen = lens[k + 1] - lens[k];
      if (segLen <= _eps) return a;
      return a + (b - a) * ((t - lens[k]) / segLen);
    }
  }
  return closed ? pts.first : pts.last;
}

/// The chain from arc-length [s0] to [s1] walking FORWARD (wrapping when
/// [closed]), as a line (2 points) or polyline. Always an OPEN result: a
/// split piece of a closed polygon is a chain, never a loop again.
Geo _polySub(List<Offset> pts, bool closed, List<double> lens, double s0,
    double s1) {
  final total = lens.last;
  final segs = closed ? pts.length : pts.length - 1;
  var span = s1 - s0;
  if (closed && span <= _eps) span += total;
  if (!closed) span = span.abs();
  final chain = <Offset>[_polyPointAt(pts, closed, lens, s0)];
  // every vertex strictly inside the span, in travel order
  final inner = <(double, Offset)>[];
  for (var k = 0; k < segs; k++) {
    var rel = lens[k] - s0;
    if (closed && rel <= _eps) rel += total;
    if (rel > _eps && rel < span - _eps) inner.add((rel, pts[k % pts.length]));
  }
  inner.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, p) in inner) {
    if ((p - chain.last).distance > _eps) chain.add(p);
  }
  final endPt = _polyPointAt(pts, closed, lens, s0 + span);
  if ((endPt - chain.last).distance > _eps) chain.add(endPt);
  if (chain.length < 2) {
    return Geo(Geo.line,
        [chain.first.dx, chain.first.dy, chain.first.dx, chain.first.dy]);
  }
  if (chain.length == 2) {
    return Geo(Geo.line,
        [chain[0].dx, chain[0].dy, chain[1].dx, chain[1].dy]);
  }
  return Geo(Geo.polyline, [
    0.0,
    chain.length.toDouble(),
    for (final q in chain) ...[q.dx, q.dy]
  ]);
}
