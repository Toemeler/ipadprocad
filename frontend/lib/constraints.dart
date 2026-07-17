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
  // appended at the END: the sidecar stores the enum INDEX, so new types
  // must never reorder the existing ones.
  // pts[0] is the midpoint of line ents[0] (SH_MIDPOINT natively).
  midpoint,
  // Sketch pattern element (M35, Inventor's Pattern panel). Ties a COPY
  // entity rigidly to its SOURCE entity through the pattern's transform:
  //   ents = [source, copy] (same geometry type)
  //   anchors = [0, dx, dy]              rectangular: translation
  //           = [1, cx, cy, angle]       circular: rotation about (cx, cy)
  // Every parameter of the copy equals the transformed parameter of the
  // source, so editing EITHER drives the other through the solver — that is
  // Inventor's "patterned geometry is fully constrained as a group". Not
  // modelled by the slvs shim: always solved on the verified Dart LM path.
  pattern,
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

/// Resolves a point ref to coordinates, INCLUDING the projected center point
/// (kProjCenter -> the fixed origin). Every dimension consumer must use this
/// instead of raw getPt(gs[ref.ent], ...), or dimensioning against the
/// projected CP crashes/never renders.
Offset refPt(List<Geo> gs, PRef r) =>
    isRealPt(r, gs) ? getPt(gs[r.ent], r.pt) : Offset.zero;

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
  /// Tangency BRANCH, persisted (sidecar key 'tb'). A tangency has two
  /// geometrically valid branches — which side of a line the circle sits on,
  /// or inner vs. outer tangency between two circles. Deriving the branch from
  /// the momentary geometry on every solve lets a drag walk CONTINUOUSLY
  /// through the degenerate configuration onto the other branch (that is
  /// exactly how the slot folded into the crossed "teardrop": every frame was
  /// individually satisfied). The branch is therefore captured ONCE — on the
  /// first solve after creation or load — and honoured forever after, like
  /// Inventor: you cannot flip a tangency by dragging.
  /// Line-circle: ±1 = sign of the signed center distance to the line
  /// (p0→p1 left normal). Curve-curve: 1 = outer, 0 = inner.
  double? tanBranch;
  /// M41 — every dimension IS a named parameter (Inventor d0, d1, …;
  /// renamable via "Name = expr" in the edit box). Assigned on creation and
  /// on load; referenced by other dimensions' expressions.
  String? paramName;
  /// M41 — the stored EXPRESSION driving [value] (e.g. "d3*2 + 5 mm").
  /// Null for a plain numeric entry. When set, the painted label carries
  /// Inventors fx: prefix, the edit box shows the raw expression, and the
  /// value is re-evaluated whenever a referenced parameter changes.
  String? expr;
  Constraint(this.type,
      {this.pts = const [], this.ents = const [], this.value,
      this.dimKind = '', this.textPos, this.driven = false,
      this.anchors = const [], this.tanBranch, this.paramName, this.expr});

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
        if (tanBranch != null) 'tb': tanBranch,
        if (paramName != null) 'nm': paramName,
        if (expr != null) 'ex': expr,
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
        tanBranch: (j['tb'] as num?)?.toDouble(),
        paramName: j['nm'] as String?,
        expr: j['ex'] as String?,
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
      CType.midpoint: '\u2ae7', // triangle over bar — Inventor's midpoint glyph
      CType.pattern: '\u25a6', // grid — pattern group membership (M35)
    }[t]!;

// ---------------------------------------------------------------------------
// sketch patterns (M35)
// ---------------------------------------------------------------------------
/// Anchor layouts of a [CType.pattern] constraint.
const patKindTranslate = 0.0, patKindRotate = 1.0;

/// The rigid transform a [CType.pattern] constraint's anchors describe:
/// source point -> copy point. Null when the anchors are malformed (a
/// hand-edited sidecar); the constraint then contributes no equations.
Offset Function(Offset)? patternTransform(List<double> an) {
  if (an.isEmpty) return null;
  if (an[0] == patKindTranslate && an.length >= 3) {
    final d = Offset(an[1], an[2]);
    return (p) => p + d;
  }
  if (an[0] == patKindRotate && an.length >= 4) {
    final c = Offset(an[1], an[2]);
    final ca = math.cos(an[3]), sa = math.sin(an[3]);
    return (p) {
      final v = p - c;
      return c + Offset(v.dx * ca - v.dy * sa, v.dx * sa + v.dy * ca);
    };
  }
  return null;
}

/// Rotation angle of a rotate-kind pattern (0 for translate) — the arc sweep
/// angles of a rotated copy are the source's angles shifted by exactly this.
double patternRotation(List<double> an) =>
    an.isNotEmpty && an[0] == patKindRotate && an.length >= 4 ? an[3] : 0.0;

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

/// The POINT-binding portion of constraint inference for entity [newIdx]:
/// bind each of its points to (highest priority first) the projected center
/// point, a coinciding existing point, or the interior of an existing straight
/// edge. [bindOnlyBefore] restricts partner entities to indices below it —
/// deterministic constructions (rectangles, slots, fillets) pass their own
/// first index so their INTERNAL corner relations, which they add themselves,
/// are never duplicated, while landings on PRE-EXISTING geometry and on the
/// center point still bind exactly like Inventor.
List<Constraint> inferPointBindings(List<Geo> gs, int newIdx,
    {int? bindOnlyBefore}) {
  final out = <Constraint>[];
  final g = gs[newIdx];
  final limit = bindOnlyBefore ?? newIdx;
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
    for (var j = 0; j < limit && !done; j++) {
      for (var pj = 0; pj < ptCount(gs[j]) && !done; pj++) {
        if ((getPt(gs[j], pj) - q).distance < 1e-6) {
          out.add(Constraint(CType.coincident,
              pts: [PRef(j, pj), PRef(newIdx, p)]));
          done = true;
        }
      }
    }
    if (done) continue;
    for (var j = 0; j < limit; j++) {
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
  return out;
}

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
  if (g.type == Geo.polyline && !g.isSpline) {
    // Control-polygon segments of a spline are not real edges — never infer
    // horizontal/vertical on them (only straight polylines get this).
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
  out.addAll(inferPointBindings(gs, newIdx));
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
/// Companion of [remapAfterRemove] for PROJECTION tags (M32): the proj field
/// of a projected line is a source ENTITY INDEX, so removing entity [removed]
/// shifts every higher source down by one — and a projection whose source was
/// removed FREEZES in place ([Geo.projBroken], Inventor keeps it too).
List<Geo> remapProjectionsAfterRemove(List<Geo> gs, int removed) => [
      for (final g in gs)
        !g.isProjection || g.proj < 0
            ? g
            : g.proj == removed
                ? g.withProj(Geo.projBroken)
                : g.proj > removed
                    ? g.withProj(g.proj - 1)
                    : g
    ];

/// Remaps constraints after entity [removed] was REPLACED by pieces that
/// still cover (part of) its carrier — Trim and Split (M36). Unlike
/// [remapAfterRemove], constraints referencing the removed entity are kept
/// wherever they still make sense, exactly what Inventor does when a trim
/// leaves the constrained portion standing:
///  - point refs remap to the piece that still HAS that point (matched by
///    position); points that fell in the trimmed-away span drop their
///    constraint,
///  - entity refs (tangent, parallel, dimensions, ...) remap to the piece
///    nearest the constraint's other participants (the carrier is unchanged,
///    so the constraint stays geometrically valid on any piece),
///  - entity-level Fix (anchors describe the OLD full data) and pattern
///    memberships are dropped — their stored shape no longer exists.
/// [gsAfter] is the geometry list AFTER removal with the pieces appended at
/// [piecesStart]; indices in it are the ones the result must reference.
List<Constraint> remapAfterReplace(List<Constraint> cs, int removed,
    Geo oldGeo, List<Geo> gsAfter, int piecesStart) {
  const tol = 1e-6;
  final pieces = [
    for (var i = piecesStart; i < gsAfter.length; i++) (i, gsAfter[i])
  ];
  int shift(int e) => e > removed ? e - 1 : e;

  PRef? mapPt(PRef p) {
    if (p.ent != removed) return PRef(shift(p.ent), p.pt);
    final want = getPt(oldGeo, p.pt);
    for (final (idx, g) in pieces) {
      final n = ptCount(g);
      for (var q = 0; q < n; q++) {
        if ((getPt(g, q) - want).distance <= tol) return PRef(idx, q);
      }
    }
    return null; // the point was trimmed away
  }

  double distToPiece(Offset p, Geo g) {
    switch (g.type) {
      case Geo.line:
        final a = Offset(g.data[0], g.data[1]),
            b = Offset(g.data[2], g.data[3]);
        final ab = b - a;
        final len2 = ab.distanceSquared;
        if (len2 < 1e-18) return (p - a).distance;
        final t =
            (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
        return (p - (a + ab * t)).distance;
      case Geo.circle:
      case Geo.arc:
        return ((p - Offset(g.data[0], g.data[1])).distance - g.data[2])
            .abs();
      default:
        var best = double.infinity;
        for (var q = 0; q < ptCount(g); q++) {
          final d = (p - getPt(g, q)).distance;
          if (d < best) best = d;
        }
        return best;
    }
  }

  int mapEnt(Constraint c, int e) {
    if (e != removed) return shift(e);
    // anchor: where the constraint "happens" — the other participants
    final anchors = <Offset>[];
    for (final p in c.pts) {
      if (p.ent == kProjCenter) {
        anchors.add(Offset.zero);
      } else if (p.ent != removed) {
        anchors.add(getPt(gsAfter[shift(p.ent)], p.pt));
      }
    }
    for (final o in c.ents) {
      if (o != removed) anchors.add(getPt(gsAfter[shift(o)], 0));
    }
    if (anchors.isEmpty && c.textPos != null) anchors.add(c.textPos!);
    var bestIdx = pieces.first.$1;
    if (anchors.isNotEmpty) {
      var best = double.infinity;
      for (final (idx, g) in pieces) {
        var d = 0.0;
        for (final a in anchors) {
          d += distToPiece(a, g);
        }
        if (d < best) {
          best = d;
          bestIdx = idx;
        }
      }
    } else {
      // no context (H/V, radius dim, ...): the LARGEST piece keeps it
      var best = -1.0;
      for (final (idx, g) in pieces) {
        final size = g.type == Geo.line
            ? (Offset(g.data[0], g.data[1]) - Offset(g.data[2], g.data[3]))
                .distance
            : g.type == Geo.arc
                ? g.data[2] * (g.data[4] - g.data[3]).abs()
                : g.data.length > 2
                    ? g.data[2]
                    : 0.0;
        if (size > best) {
          best = size;
          bestIdx = idx;
        }
      }
    }
    return bestIdx;
  }

  final out = <Constraint>[];
  for (final c in cs) {
    final touches =
        c.ents.contains(removed) || c.pts.any((p) => p.ent == removed);
    if (!touches) {
      out.add(Constraint(c.type,
          pts: [for (final p in c.pts) PRef(shift(p.ent), p.pt)],
          ents: [for (final e in c.ents) shift(e)],
          value: c.value,
          dimKind: c.dimKind,
          textPos: c.textPos,
          driven: c.driven,
          anchors: c.anchors));
      continue;
    }
    if (pieces.isEmpty) continue; // everything trimmed away
    // stored-shape constraints cannot survive a reshape
    if (c.type == CType.pattern) continue;
    if (c.type == CType.fix && c.pts.isEmpty && c.ents.contains(removed)) {
      continue;
    }
    final pts = <PRef>[];
    var ok = true;
    for (final p in c.pts) {
      final m = mapPt(p);
      if (m == null) {
        ok = false;
        break;
      }
      pts.add(m);
    }
    if (!ok) continue;
    final ents = [for (final e in c.ents) mapEnt(c, e)];
    // an entity constraint must not collapse onto itself (equal/tangent/...
    // between a piece and itself after both refs land on the same piece)
    if (ents.length >= 2 && ents[0] == ents[1] && c.ents.length >= 2) {
      continue;
    }
    out.add(Constraint(c.type,
        pts: pts,
        ents: ents,
        value: c.value,
        dimKind: c.dimKind,
        textPos: c.textPos,
        driven: c.driven,
        anchors: c.anchors));
  }
  return out;
}

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
      return (refPt(gs, c.pts[0]) - refPt(gs, c.pts[1])).distance;
    case 'distx':
    case 'disty':
      if (c.pts.length < 2) return 0;
      final d = refPt(gs, c.pts[0]) - refPt(gs, c.pts[1]);
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
      final p = refPt(gs, c.pts[0]);
      final a = refPt(gs, c.pts[1]);
      final b = refPt(gs, c.pts[2]);
      final d = b - a;
      final len = d.distance;
      if (len < 1e-12) return (p - a).distance;
      return ((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / len;
    case 'ang3':
      // pts = [ray end A, VERTEX, ray end B] — Inventor's 3-point angle.
      if (c.pts.length < 3) return 0;
      final a = refPt(gs, c.pts[0]);
      final o = refPt(gs, c.pts[1]);
      final b = refPt(gs, c.pts[2]);
      final d1 = a - o, d2 = b - o;
      final s = d1.distance * d2.distance;
      if (s < 1e-12) return 0;
      final cross = (d1.dx * d2.dy - d1.dy * d2.dx) / s;
      final dot = (d1.dx * d2.dx + d1.dy * d2.dy) / s;
      return math.atan2(cross.abs(), dot) * 180 / math.pi;
    case 'ang4':
      // pts = [a1, a2, b1, b2] — angle between the rays a1->a2 and b1->b2.
      // This is the line-line angle expressed through POINTS, which is what
      // makes angles between polyline EDGES (rectangle sides) possible: an
      // edge has no line-entity ref, only its two vertices.
      if (c.pts.length < 4) return 0;
      final da = refPt(gs, c.pts[1]) - refPt(gs, c.pts[0]);
      final db = refPt(gs, c.pts[3]) - refPt(gs, c.pts[2]);
      final s4 = da.distance * db.distance;
      if (s4 < 1e-12) return 0;
      final cross4 = (da.dx * db.dy - da.dy * db.dx) / s4;
      final dot4 = (da.dx * db.dx + da.dy * db.dy) / s4;
      // folded to [0,180] exactly like 'ang' (quadrant choice at placement is
      // a known open item for both kinds)
      return math.atan2(cross4.abs(), dot4) * 180 / math.pi;
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
