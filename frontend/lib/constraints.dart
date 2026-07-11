// iPadProCAD — sketch constraints + dimensions (Inventor's Constrain panel).
//
// Model: constraints reference entities by index and points by (entity,
// point-index) using the same point numbering as grips: line 0/1 = ends,
// circle 0 = center, arc 0 = center / 1 = start / 2 = end, polyline i =
// vertex i.
//
// Solver: iterative projection (position-based). Each constraint projects
// its participants toward satisfaction; ~40 sweeps converge for typical
// sketches. Points in [pinned] never move (Fix constraints, the grip being
// dragged). Not Inventor's DOF solver, but it maintains constraints live
// during grip drags and drives dimension edits.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'ffi/qcad_engine.dart';
import 'snap.dart';

enum CType {
  coincident, collinear, concentric, fix, parallel, perpendicular,
  horizontal, vertical, tangent, smooth, symmetric, equal, dimension,
}

class PRef {
  final int ent, pt;
  const PRef(this.ent, this.pt);
  Map<String, int> toJson() => {'e': ent, 'p': pt};
  static PRef fromJson(Map<String, dynamic> j) => PRef(j['e'], j['p']);
}

class Constraint {
  final CType type;
  final List<PRef> pts; // point-based participants
  final List<int> ents; // entity-based participants
  double? value; // dimensions (driving value)
  final String dimKind; // dist|rad|dia|ang
  Offset? textPos; // dimension text placement (world)
  Constraint(this.type,
      {this.pts = const [], this.ents = const [], this.value,
      this.dimKind = '', this.textPos});

  Map<String, dynamic> toJson() => {
        't': type.index,
        'p': [for (final p in pts) p.toJson()],
        'e': ents,
        if (value != null) 'v': value,
        if (dimKind.isNotEmpty) 'k': dimKind,
        if (textPos != null) 'x': textPos!.dx,
        if (textPos != null) 'y': textPos!.dy,
      };
  static Constraint fromJson(Map<String, dynamic> j) => Constraint(
        CType.values[j['t']],
        pts: [for (final p in (j['p'] as List)) PRef.fromJson(p)],
        ents: List<int>.from(j['e'] ?? const []),
        value: (j['v'] as num?)?.toDouble(),
        dimKind: j['k'] ?? '',
        textPos: j['x'] != null
            ? Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble())
            : null,
      );
}

String encodeConstraints(List<Constraint> cs) =>
    jsonEncode([for (final c in cs) c.toJson()]);
List<Constraint> decodeConstraints(String s) {
  try {
    return [for (final j in (jsonDecode(s) as List)) Constraint.fromJson(j)];
  } catch (_) {
    return [];
  }
}

// ---------------------------------------------------------------------------
// point access (shared numbering with grips)
// ---------------------------------------------------------------------------
Offset getPt(Geo g, int i) {
  switch (g.type) {
    case Geo.line:
      return i == 0
          ? Offset(g.data[0], g.data[1])
          : Offset(g.data[2], g.data[3]);
    case Geo.circle:
      return Offset(g.data[0], g.data[1]);
    case Geo.arc:
      if (i == 0) return Offset(g.data[0], g.data[1]);
      final a = i == 1 ? g.data[3] : g.data[4];
      return Offset(g.data[0] + math.cos(a) * g.data[2],
          g.data[1] + math.sin(a) * g.data[2]);
    case Geo.polyline:
      return Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]);
  }
  return Offset.zero;
}

Geo setPt(Geo g, int i, Offset to) {
  final d = List<double>.from(g.data);
  switch (g.type) {
    case Geo.line:
      d[i == 0 ? 0 : 2] = to.dx;
      d[i == 0 ? 1 : 3] = to.dy;
      break;
    case Geo.circle:
      d[0] = to.dx;
      d[1] = to.dy;
      break;
    case Geo.arc:
      if (i == 0) {
        // move whole arc with its center
        d[0] = to.dx;
        d[1] = to.dy;
      } else {
        final c = Offset(d[0], d[1]);
        final v = to - c;
        if (v.distance > 1e-9) {
          d[2] = v.distance;
          d[i == 1 ? 3 : 4] = math.atan2(v.dy, v.dx);
        }
      }
      break;
    case Geo.polyline:
      d[2 + 2 * i] = to.dx;
      d[3 + 2 * i] = to.dy;
      break;
  }
  return Geo(g.type, d);
}

int ptCount(Geo g) {
  switch (g.type) {
    case Geo.line:
      return 2;
    case Geo.circle:
      return 1;
    case Geo.arc:
      return 3;
    case Geo.polyline:
      return g.data[1].toInt();
  }
  return 0;
}

double _dir(Geo line) => math.atan2(
    line.data[3] - line.data[1], line.data[2] - line.data[0]);

// ---------------------------------------------------------------------------
// solver
// ---------------------------------------------------------------------------
void solveConstraints(List<Geo> gs, List<Constraint> cs,
    {Set<(int, int)> pinned = const {}, int iterations = 40}) {
  if (cs.isEmpty) return;
  bool pin(int e, int p) =>
      pinned.contains((e, p)) ||
      cs.any((c) =>
          c.type == CType.fix &&
          ((c.pts.isNotEmpty &&
                  c.pts.any((q) => q.ent == e && (q.pt == p))) ||
              c.ents.contains(e)));

  void put(int e, int p, Offset to) {
    if (e < 0 || e >= gs.length) return;
    if (pin(e, p)) return;
    gs[e] = setPt(gs[e], p, to);
  }

  void pair(int e1, int p1, int e2, int p2, Offset t1, Offset t2) {
    final f1 = pin(e1, p1), f2 = pin(e2, p2);
    if (f1 && f2) return;
    if (f1) {
      put(e2, p2, t2 + (getPt(gs[e1], p1) - t1)); // shift target by residual
    } else if (f2) {
      put(e1, p1, t1 + (getPt(gs[e2], p2) - t2));
    } else {
      put(e1, p1, t1);
      put(e2, p2, t2);
    }
  }

  void rotateLine(int e, double target) {
    final g = gs[e];
    if (g.type != Geo.line) return;
    final a = getPt(g, 0), b = getPt(g, 1);
    final m = (a + b) / 2;
    final len = (b - a).distance / 2;
    final d = Offset(math.cos(target), math.sin(target)) * len;
    pair(e, 0, e, 1, m - d, m + d);
  }

  double angDiff(double a, double b) {
    var d = (a - b) % math.pi;
    if (d > math.pi / 2) d -= math.pi;
    if (d < -math.pi / 2) d += math.pi;
    return d;
  }

  for (var it = 0; it < iterations; it++) {
    for (final c in cs) {
      switch (c.type) {
        case CType.fix:
          break; // handled via pin()
        case CType.coincident:
          if (c.pts.length < 2) break;
          final a = c.pts[0], b = c.pts[1];
          if (a.ent >= gs.length || b.ent >= gs.length) break;
          final pa = getPt(gs[a.ent], a.pt), pb = getPt(gs[b.ent], b.pt);
          final m = (pa + pb) / 2;
          pair(a.ent, a.pt, b.ent, b.pt, m, m);
          break;
        case CType.horizontal:
        case CType.vertical:
          final horiz = c.type == CType.horizontal;
          if (c.pts.length >= 2) {
            final a = c.pts[0], b = c.pts[1];
            final pa = getPt(gs[a.ent], a.pt), pb = getPt(gs[b.ent], b.pt);
            if (horiz) {
              final y = (pa.dy + pb.dy) / 2;
              pair(a.ent, a.pt, b.ent, b.pt, Offset(pa.dx, y), Offset(pb.dx, y));
            } else {
              final x = (pa.dx + pb.dx) / 2;
              pair(a.ent, a.pt, b.ent, b.pt, Offset(x, pa.dy), Offset(x, pb.dy));
            }
          } else if (c.ents.isNotEmpty && c.ents[0] < gs.length) {
            rotateLine(c.ents[0], horiz ? 0 : math.pi / 2);
          }
          break;
        case CType.parallel:
        case CType.perpendicular:
          if (c.ents.length < 2 ||
              c.ents.any((e) => e >= gs.length || gs[e].type != Geo.line)) {
            break;
          }
          final t1 = _dir(gs[c.ents[0]]);
          var t2 = _dir(gs[c.ents[1]]);
          if (c.type == CType.perpendicular) t2 -= math.pi / 2;
          final d = angDiff(t2, t1) / 2;
          rotateLine(c.ents[0], t1 + d);
          rotateLine(c.ents[1],
              _dir(gs[c.ents[1]]) - d);
          break;
        case CType.collinear:
          if (c.ents.length < 2 ||
              c.ents.any((e) => e >= gs.length || gs[e].type != Geo.line)) {
            break;
          }
          final ref = gs[c.ents[0]];
          final a = getPt(ref, 0), b = getPt(ref, 1);
          for (final p in [0, 1]) {
            final q = getPt(gs[c.ents[1]], p);
            put(c.ents[1], p, _projInf(q, a, b));
          }
          break;
        case CType.concentric:
          if (c.ents.length < 2 || c.ents.any((e) => e >= gs.length)) break;
          final c1 = getPt(gs[c.ents[0]], 0), c2 = getPt(gs[c.ents[1]], 0);
          final m = (c1 + c2) / 2;
          pair(c.ents[0], 0, c.ents[1], 0, m, m);
          break;
        case CType.tangent:
        case CType.smooth:
          _applyTangent(gs, c, put);
          break;
        case CType.symmetric:
          if (c.pts.length < 2 || c.ents.isEmpty) break;
          final ax = gs[c.ents[0]];
          if (ax.type != Geo.line) break;
          final a = getPt(ax, 0), b = getPt(ax, 1);
          final p1 = getPt(gs[c.pts[0].ent], c.pts[0].pt);
          final p2 = getPt(gs[c.pts[1].ent], c.pts[1].pt);
          final m = (p1 + _reflect(p2, a, b)) / 2;
          pair(c.pts[0].ent, c.pts[0].pt, c.pts[1].ent, c.pts[1].pt, m,
              _reflect(m, a, b));
          break;
        case CType.equal:
          if (c.ents.length < 2 || c.ents.any((e) => e >= gs.length)) break;
          final g1 = gs[c.ents[0]], g2 = gs[c.ents[1]];
          if (g1.type == Geo.line && g2.type == Geo.line) {
            final l1 = (getPt(g1, 1) - getPt(g1, 0)).distance;
            final l2 = (getPt(g2, 1) - getPt(g2, 0)).distance;
            final target = (l1 + l2) / 2;
            _setLineLength(gs, c.ents[0], target, pair);
            _setLineLength(gs, c.ents[1], target, pair);
          } else if (g1.type != Geo.line && g2.type != Geo.line) {
            final r = (g1.data[2] + g2.data[2]) / 2;
            gs[c.ents[0]] = _withRadius(g1, r);
            gs[c.ents[1]] = _withRadius(g2, r);
          }
          break;
        case CType.dimension:
          _applyDimension(gs, c, pair, put);
          break;
      }
    }
  }
}

Offset _projInf(Offset p, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 < 1e-12) return a;
  final t = ((p - a).dx * d.dx + (p - a).dy * d.dy) / l2;
  return a + d * t;
}

Offset _reflect(Offset p, Offset a, Offset b) {
  final q = _projInf(p, a, b);
  return q * 2 - p;
}

Geo _withRadius(Geo g, double r) {
  final d = List<double>.from(g.data);
  d[2] = math.max(1e-6, r);
  return Geo(g.type, d);
}

void _setLineLength(List<Geo> gs, int e, double len,
    void Function(int, int, int, int, Offset, Offset) pair) {
  final g = gs[e];
  final a = getPt(g, 0), b = getPt(g, 1);
  final d = b - a;
  if (d.distance < 1e-9) return;
  final m = (a + b) / 2;
  final h = d / d.distance * (len / 2);
  pair(e, 0, e, 1, m - h, m + h);
}

void _applyTangent(
    List<Geo> gs, Constraint c, void Function(int, int, Offset) put) {
  if (c.ents.length < 2 || c.ents.any((e) => e >= gs.length)) return;
  var e1 = c.ents[0], e2 = c.ents[1];
  var g1 = gs[e1], g2 = gs[e2];
  // normalize: line first if present
  if (g1.type != Geo.line && g2.type == Geo.line) {
    final t = e1;
    e1 = e2;
    e2 = t;
    g1 = gs[e1];
    g2 = gs[e2];
  }
  if (g1.type == Geo.line && g2.type != Geo.line) {
    // move the circle/arc center perpendicular to the line to distance r
    final a = getPt(g1, 0), b = getPt(g1, 1);
    final ce = getPt(g2, 0);
    final q = _projInf(ce, a, b);
    final n = ce - q;
    final dist = n.distance;
    final r = g2.data[2];
    if (dist < 1e-9) return;
    put(e2, 0, q + n / dist * r);
  } else if (g1.type != Geo.line && g2.type != Geo.line) {
    // circle-circle: |c1c2| -> r1+r2 (outer) or |r1-r2| (inner), nearest
    final c1 = getPt(g1, 0), c2 = getPt(g2, 0);
    final d = (c2 - c1).distance;
    if (d < 1e-9) return;
    final outer = g1.data[2] + g2.data[2];
    final inner = (g1.data[2] - g2.data[2]).abs();
    final target =
        (d - outer).abs() <= (d - inner).abs() ? outer : inner;
    put(e2, 0, c1 + (c2 - c1) / d * target);
  }
}

void _applyDimension(
    List<Geo> gs,
    Constraint c,
    void Function(int, int, int, int, Offset, Offset) pair,
    void Function(int, int, Offset) put) {
  final v = c.value;
  if (v == null) return;
  switch (c.dimKind) {
    case 'dist':
      if (c.pts.length < 2) return;
      final a = c.pts[0], b = c.pts[1];
      if (a.ent >= gs.length || b.ent >= gs.length) return;
      final pa = getPt(gs[a.ent], a.pt), pb = getPt(gs[b.ent], b.pt);
      final d = pb - pa;
      if (d.distance < 1e-9) return;
      final m = (pa + pb) / 2;
      final h = d / d.distance * (v / 2);
      pair(a.ent, a.pt, b.ent, b.pt, m - h, m + h);
      break;
    case 'distx':
    case 'disty':
      if (c.pts.length < 2) return;
      final a2 = c.pts[0], b2 = c.pts[1];
      if (a2.ent >= gs.length || b2.ent >= gs.length) return;
      final pa2 = getPt(gs[a2.ent], a2.pt), pb2 = getPt(gs[b2.ent], b2.pt);
      final horiz = c.dimKind == 'distx';
      final cur2 = horiz ? pb2.dx - pa2.dx : pb2.dy - pa2.dy;
      if (cur2.abs() < 1e-9) return;
      final target2 = v * (cur2 < 0 ? -1 : 1);
      final dd = (target2 - cur2) / 2;
      pair(
          a2.ent,
          a2.pt,
          b2.ent,
          b2.pt,
          horiz ? Offset(pa2.dx - dd, pa2.dy) : Offset(pa2.dx, pa2.dy - dd),
          horiz ? Offset(pb2.dx + dd, pb2.dy) : Offset(pb2.dx, pb2.dy + dd));
      break;
    case 'rad':
    case 'dia':
      if (c.ents.isEmpty || c.ents[0] >= gs.length) return;
      final r = c.dimKind == 'rad' ? v : v / 2;
      gs[c.ents[0]] = _withRadius(gs[c.ents[0]], r);
      break;
    case 'ang':
      if (c.ents.length < 2 ||
          c.ents.any((e) => e >= gs.length || gs[e].type != Geo.line)) {
        return;
      }
      final t1 = _dir(gs[c.ents[0]]), t2 = _dir(gs[c.ents[1]]);
      var cur = t2 - t1;
      while (cur <= -math.pi) {
        cur += 2 * math.pi;
      }
      while (cur > math.pi) {
        cur -= 2 * math.pi;
      }
      final target = v * math.pi / 180 * (cur < 0 ? -1 : 1);
      final corr = (target - cur) / 2;
      _rotAbout(gs, c.ents[0], -corr, put);
      _rotAbout(gs, c.ents[1], corr, put);
      break;
  }
}

void _rotAbout(List<Geo> gs, int e, double ang,
    void Function(int, int, Offset) put) {
  final g = gs[e];
  final a = getPt(g, 0), b = getPt(g, 1);
  final m = (a + b) / 2;
  Offset rot(Offset p) {
    final v = p - m;
    return m +
        Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang),
            v.dx * math.sin(ang) + v.dy * math.cos(ang));
  }

  put(e, 0, rot(a));
  put(e, 1, rot(b));
}

// ---------------------------------------------------------------------------
// automatic constraint inference while drawing (Inventor behaviour)
// ---------------------------------------------------------------------------
const _angTol = 1.5 * math.pi / 180;

List<Constraint> inferConstraints(List<Geo> gs, int newIdx) {
  final out = <Constraint>[];
  final g = gs[newIdx];
  if (g.type == Geo.line) {
    final t = _dir(g);
    double m(double x) {
      var v = x % math.pi;
      if (v < 0) v += math.pi;
      return v;
    }

    final tm = m(t);
    if (tm < _angTol || math.pi - tm < _angTol) {
      out.add(Constraint(CType.horizontal, ents: [newIdx]));
    } else if ((tm - math.pi / 2).abs() < _angTol) {
      out.add(Constraint(CType.vertical, ents: [newIdx]));
    } else {
      for (var j = 0; j < newIdx; j++) {
        if (gs[j].type != Geo.line) continue;
        final dt = m(t - _dir(gs[j]));
        final dd = math.min(dt, math.pi - dt);
        if (dd < _angTol) {
          out.add(Constraint(CType.parallel, ents: [j, newIdx]));
          break;
        }
        if ((dd - math.pi / 2).abs() < _angTol) {
          out.add(Constraint(CType.perpendicular, ents: [j, newIdx]));
          break;
        }
      }
    }
  }
  // coincident endpoints (snapping already made them exactly equal)
  for (var p = 0; p < ptCount(g); p++) {
    final q = getPt(g, p);
    var done = false;
    for (var j = 0; j < newIdx && !done; j++) {
      for (var pj = 0; pj < ptCount(gs[j]) && !done; pj++) {
        if ((getPt(gs[j], pj) - q).distance < 1e-6) {
          out.add(Constraint(CType.coincident,
              pts: [PRef(j, pj), PRef(newIdx, p)]));
          done = true;
        }
      }
    }
  }
  // tangent for arcs that start exactly on another entity's endpoint with
  // matching tangent direction (the Arc-Tangent tool produces these)
  if (g.type == Geo.arc) {
    for (var j = 0; j < newIdx; j++) {
      if (gs[j].type != Geo.line) continue;
      final a = getPt(gs[j], 0), b = getPt(gs[j], 1);
      final s = getPt(g, 1);
      if ((s - a).distance < 1e-6 || (s - b).distance < 1e-6) {
        final ce = getPt(g, 0);
        final n = s - ce;
        final ld = b - a;
        final dot = (n.dx * ld.dx + n.dy * ld.dy).abs() /
            (n.distance * ld.distance);
        if (dot < 0.02) {
          out.add(Constraint(CType.tangent, ents: [j, newIdx]));
        }
      }
    }
  }
  return out;
}

/// Shifts entity references after entity [removed] was deleted; constraints
/// touching it are dropped (Inventor deletes them too).
List<Constraint> remapAfterRemove(List<Constraint> cs, int removed) {
  final out = <Constraint>[];
  for (final c in cs) {
    if (c.ents.contains(removed) || c.pts.any((p) => p.ent == removed)) {
      continue;
    }
    out.add(Constraint(c.type,
        pts: [
          for (final p in c.pts) PRef(p.ent > removed ? p.ent - 1 : p.ent, p.pt)
        ],
        ents: [for (final e in c.ents) e > removed ? e - 1 : e],
        value: c.value,
        dimKind: c.dimKind,
        textPos: c.textPos));
  }
  return out;
}

// ---------------------------------------------------------------------------
// measuring (for dimension defaults)
// ---------------------------------------------------------------------------
double measureDim(List<Geo> gs, Constraint c) {
  switch (c.dimKind) {
    case 'dist':
      if (c.pts.length < 2) return 0;
      return (getPt(gs[c.pts[0].ent], c.pts[0].pt) -
              getPt(gs[c.pts[1].ent], c.pts[1].pt))
          .distance;
    case 'distx':
    case 'disty':
      if (c.pts.length < 2) return 0;
      final d = getPt(gs[c.pts[0].ent], c.pts[0].pt) -
          getPt(gs[c.pts[1].ent], c.pts[1].pt);
      return (c.dimKind == 'distx' ? d.dx : d.dy).abs();
    case 'rad':
      return gs[c.ents[0]].data[2];
    case 'dia':
      return gs[c.ents[0]].data[2] * 2;
    case 'ang':
      final t1 = _dir(gs[c.ents[0]]), t2 = _dir(gs[c.ents[1]]);
      var d = (t2 - t1).abs() % (2 * math.pi);
      if (d > math.pi) d = 2 * math.pi - d;
      return d * 180 / math.pi;
  }
  return 0;
}

/// Glyph list (world position + label) for Show Constraints.
List<(Offset, String)> constraintGlyphs(List<Geo> gs, List<Constraint> cs) {
  const label = {
    CType.coincident: '\u25cf',
    CType.collinear: '\u2261',
    CType.concentric: '\u25ce',
    CType.fix: '\u2313',
    CType.parallel: '\u2225',
    CType.perpendicular: '\u22a5',
    CType.horizontal: '\u2500',
    CType.vertical: '\u2502',
    CType.tangent: '\u25cb',
    CType.smooth: 'G2',
    CType.symmetric: '\u224b',
    CType.equal: '=',
  };
  Offset mid(Geo g) {
    final pts = sampleEntity(g, arcSamples: 8);
    return pts[pts.length ~/ 2];
  }

  final out = <(Offset, String)>[];
  final stack = <int, int>{};
  for (final c in cs) {
    if (c.type == CType.dimension) continue;
    final lb = label[c.type]!;
    if (c.pts.isNotEmpty && c.type == CType.coincident) {
      if (c.pts[0].ent < gs.length) {
        out.add((getPt(gs[c.pts[0].ent], c.pts[0].pt), lb));
      }
      continue;
    }
    for (final e in c.ents.isNotEmpty
        ? c.ents
        : [for (final p in c.pts) p.ent]) {
      if (e >= gs.length) continue;
      final n = stack[e] = (stack[e] ?? 0) + 1;
      out.add((mid(gs[e]), '$lb#$n')); // '#n' = stacking slot, painter strips
    }
  }
  return out;
}
