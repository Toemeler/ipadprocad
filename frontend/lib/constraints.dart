// iPadProCAD — sketch constraints + dimensions (Inventor's Constrain panel).
//
// Model: constraints reference entities by index and points by (entity,
// point-index) using the same point numbering as grips: line 0/1 = ends,
// circle 0 = center, arc 0 = center / 1 = start / 2 = end, polyline i =
// vertex i.
//
// Solver: libslvs (SolveSpace) via FFI, with a Levenberg-Marquardt fallback in
// solver.dart that is used whenever the native result cannot be verified.
// Fix constraints ground geometry where it is; the grip being dragged is a soft
// wish (SolveSpace's dragged[] params) that never overrides a constraint.
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

  // Value equality: the dimension tool's pick set dedups refs with
  // contains(), and identity equality made every re-click look "new".
  @override
  bool operator ==(Object other) =>
      other is PRef && other.ent == ent && other.pt == pt;
  @override
  int get hashCode => Object.hash(ent, pt);
  @override
  String toString() => 'PRef($ent,$pt)';
}

/// Entity index of the PROJECTED CENTER POINT. Inventor projects it into every
/// sketch as FIXED reference geometry sitting on the world origin. It is not a
/// sketch entity here (the viewport paints it directly at map(0,0)), so it gets
/// a negative sentinel index instead of a slot in the geometry list.
///
/// Both solvers resolve it to a hard (0,0) with NO free parameters: the Dart
/// Levenberg-Marquardt path via `_pointAt` (ent < 0 -> Offset.zero) and the
/// libslvs path via a point added with `fix: true`. A coincidence against it
/// therefore grounds the sketch point — which is exactly what Inventor does.
const int kProjCenter = -1;

/// True for point refs that live in the geometry list (i.e. not the projected
/// center point). Anything dereferencing `gs[ref.ent]` must check this first.
bool isRealPt(PRef r, List<Geo> gs) => r.ent >= 0 && r.ent < gs.length;

class Constraint {
  final CType type;
  final List<PRef> pts; // point-based participants
  final List<int> ents; // entity-based participants
  double? value; // dimensions (driving value)
  final String dimKind; // dist|distx|disty|rad|dia|ang
  Offset? textPos; // dimension text placement (world)
  /// Driven (reference) dimension: measures but does not drive. Inventor
  /// offers this when a dimension would over-constrain, and shows it in
  /// parentheses.
  bool driven;
  /// Fix: the coordinates/parameters the geometry is pinned to.
  final List<double> anchors;
  Constraint(this.type,
      {this.pts = const [], this.ents = const [], this.value,
      this.dimKind = '', this.textPos, this.driven = false,
      this.anchors = const []});

  Map<String, dynamic> toJson() => {
        't': type.index,
        'p': [for (final p in pts) p.toJson()],
        'e': ents,
        if (value != null) 'v': value,
        if (dimKind.isNotEmpty) 'k': dimKind,
        if (textPos != null) 'x': textPos!.dx,
        if (textPos != null) 'y': textPos!.dy,
        if (driven) 'dr': true,
        if (anchors.isNotEmpty) 'an': anchors,
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
        driven: j['dr'] == true,
        anchors: [
          for (final a in (j['an'] as List? ?? const []))
            (a as num).toDouble()
        ],
      );
}

/// Glyph for a constraint type (also used for the cursor hint while drawing).
String constraintLabel(CType t) => const {
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
      CType.dimension: 'D',
    }[t]!;

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
  return g.withData(d); // KEEPS the layer
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
  // Rectangles / polygons are a single closed polyline entity, so the
  // per-line inference above never sees their edges. Infer horizontal /
  // vertical per segment instead: a normal (axis-aligned) rectangle then
  // picks up two horizontal + two vertical constraints, exactly as Inventor
  // does when you draw one.
  if (g.type == Geo.polyline) {
    final n = g.data[1].toInt();
    final closed = g.data[0] != 0;
    final segs = closed ? n : n - 1;
    for (var si = 0; si < segs; si++) {
      final i = si, k = (si + 1) % n;
      final d = getPt(g, k) - getPt(g, i);
      if (d.distance < 1e-9) continue;
      var m = math.atan2(d.dy, d.dx) % math.pi;
      if (m < 0) m += math.pi;
      if (m < _angTol || math.pi - m < _angTol) {
        out.add(Constraint(CType.horizontal,
            pts: [PRef(newIdx, i), PRef(newIdx, k)]));
      } else if ((m - math.pi / 2).abs() < _angTol) {
        out.add(Constraint(CType.vertical,
            pts: [PRef(newIdx, i), PRef(newIdx, k)]));
      }
    }
  }
  // coincident endpoints (snapping already made them exactly equal); if a new
  // point instead lands on the interior of an existing straight edge, add a
  // point-on-line coincidence rather than point-on-point.
  for (var p = 0; p < ptCount(g); p++) {
    final q = getPt(g, p);
    // Highest priority: the projected center point. Snapping onto it ('origin'
    // snap) put the point EXACTLY on (0,0), but the center point is not in the
    // geometry list, so the loops below could never see it and the point stayed
    // free. Bind it to the fixed sentinel ref instead -> the point is grounded.
    if (q.distance < 1e-6) {
      out.add(Constraint(CType.coincident,
          pts: [const PRef(kProjCenter, 0), PRef(newIdx, p)]));
      continue;
    }
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
    if (done) continue;
    for (var j = 0; j < newIdx; j++) {
      if (gs[j].type != Geo.line) continue;
      final a = getPt(gs[j], 0), b = getPt(gs[j], 1);
      if ((q - a).distance < 1e-6 || (q - b).distance < 1e-6) continue;
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      if (len2 < 1e-18) continue;
      final tPar = ((q - a).dx * ab.dx + (q - a).dy * ab.dy) / len2;
      if (tPar <= 1e-6 || tPar >= 1 - 1e-6) continue; // interior only
      if ((q - (a + ab * tPar)).distance < 1e-6) {
        out.add(Constraint(CType.coincident,
            pts: [PRef(newIdx, p)], ents: [j]));
        break;
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
        // kProjCenter (-1) is never > removed, so the sentinel survives intact.
        pts: [
          for (final p in c.pts) PRef(p.ent > removed ? p.ent - 1 : p.ent, p.pt)
        ],
        ents: [for (final e in c.ents) e > removed ? e - 1 : e],
        value: c.value,
        dimKind: c.dimKind,
        textPos: c.textPos,
        driven: c.driven, // was dropped: reference dims turned driving again
        anchors: c.anchors)); // was dropped: Fix silently lost its anchor
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
    case 'pline':
      // pts = [measured point, line point A, line point B] — the perpendicular
      // distance to the INFINITE line through A,B (Inventor measures the same
      // way; the witness line is extended when the foot falls off the segment).
      if (c.pts.length < 3) return 0;
      final p = getPt(gs[c.pts[0].ent], c.pts[0].pt);
      final a = getPt(gs[c.pts[1].ent], c.pts[1].pt);
      final b = getPt(gs[c.pts[2].ent], c.pts[2].pt);
      final d = b - a;
      final len = d.distance;
      if (len < 1e-12) return (p - a).distance;
      return ((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / len;
    case 'ang3':
      // pts = [ray end A, VERTEX, ray end B] — Inventor's 3-point angle.
      if (c.pts.length < 3) return 0;
      final a = getPt(gs[c.pts[0].ent], c.pts[0].pt);
      final o = getPt(gs[c.pts[1].ent], c.pts[1].pt);
      final b = getPt(gs[c.pts[2].ent], c.pts[2].pt);
      final d1 = a - o, d2 = b - o;
      final s = d1.distance * d2.distance;
      if (s < 1e-12) return 0;
      final cross = (d1.dx * d2.dy - d1.dy * d2.dx) / s;
      final dot = (d1.dx * d2.dx + d1.dy * d2.dy) / s;
      return math.atan2(cross.abs(), dot) * 180 / math.pi;
  }
  return 0;
}

/// Glyph list (world position + label) for Show Constraints.
List<(Offset, String)> constraintGlyphs(List<Geo> gs, List<Constraint> cs) {
  Offset mid(Geo g) {
    final pts = sampleEntity(g, arcSamples: 8);
    return pts[pts.length ~/ 2];
  }

  final out = <(Offset, String)>[];
  final stack = <int, int>{};
  for (final c in cs) {
    if (c.type == CType.dimension) continue;
    final lb = constraintLabel(c.type);
    if (c.pts.isNotEmpty && c.type == CType.coincident) {
      // pts[0] may be the projected center point (kProjCenter), which has no
      // slot in gs — indexing it would throw. The glyph then belongs on the
      // sketch point, i.e. the first ref that IS real.
      for (final r in c.pts) {
        if (isRealPt(r, gs)) {
          out.add((getPt(gs[r.ent], r.pt), lb));
          break;
        }
      }
      continue;
    }
    for (final e in c.ents.isNotEmpty
        ? c.ents
        : [for (final p in c.pts) p.ent]) {
      if (e < 0 || e >= gs.length) continue;
      final n = stack[e] = (stack[e] ?? 0) + 1;
      out.add((mid(gs[e]), '$lb#$n')); // '#n' = stacking slot, painter strips
    }
  }
  return out;
}
