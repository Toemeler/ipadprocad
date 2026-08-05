// Prototype — the sketch solver.
//
// This replaces the earlier projection sweeps with a proper numeric solver,
// which is what makes Inventor's behaviour possible at all:
//
//   * geometry is packed into a parameter vector (line = 4 params, circle =
//     3, arc = 5, polyline = 2n),
//   * every constraint contributes residual equations,
//   * a Levenberg-Marquardt loop drives the residuals to zero,
//   * the Jacobian's RANK gives the degrees of freedom (DOF = free params -
//     rank) and its NULL SPACE tells us exactly which points can still move,
//     which is how the DOF glyphs and the "fully constrained" state work,
//   * a rank test on a candidate constraint detects over-constraining before
//     it is applied — Inventor rejects redundant geometric constraints and
//     offers to keep a redundant dimension as a driven (reference) one.
import 'dart:math' as math;
import 'dart:ui';

import 'constraints.dart';
import 'diag.dart';
import 'log.dart';
import 'perf.dart';
import 'snap.dart';
import 'ffi/qcad_engine.dart';
import 'ffi/slvs_ffi.dart';

/// Result of the rank analysis of a sketch.
class SketchAnalysis {
  final int dof;
  final Set<(int, int)> freePoints; // (entity, point) still able to move

  /// (entity, segment) pairs whose CARRIER can still move. This is Inventor's
  /// per-entity colouring rule (confirmed by Autodesk for the sketch solver):
  /// a line is "fully constrained" as soon as its infinite carrier line —
  /// direction AND perpendicular position — is fixed, even while an endpoint
  /// can still slide ALONG it (free length). The endpoints are separate
  /// entities with their own state (freePoints / DOF arrows).
  ///   line / circle / arc / tagged polyline (spline, ellipse): segment 0
  ///   plain polyline: one entry per edge (a rectangle whites up edge by edge)
  /// For circles and arcs the carrier is (center, radius); free arc ENDPOINTS
  /// (sweep angles) do not keep the curve violet — again Inventor's rule.
  final Set<(int, int)> looseCarriers;

  const SketchAnalysis(this.dof, this.freePoints,
      [this.looseCarriers = const {}]);
  bool get fullyConstrained => dof == 0;

  /// White in Inventor's scheme: the carrier of [seg] of entity [ent] cannot
  /// move any more (length of a line may still be free).
  bool carrierFixed(int ent, [int seg = 0]) => !looseCarriers.contains((ent, seg));
}

/// Number of independently coloured segments of an entity: plain polylines
/// are coloured per edge (Inventor draws a rectangle as four lines), all
/// other entities — including spline/ellipse-tagged polylines, whose curve is
/// one piece — carry a single segment.
int carrierSegCount(Geo g) {
  if (g.type == Geo.polyline && !g.isSpline) {
    final n = g.data[1].toInt();
    if (n < 2) return 0;
    return g.data[0] != 0 ? n : n - 1; // closed: n edges, open: n-1
  }
  return 1;
}

// ---------------------------------------------------------------------------
// parameter packing
// ---------------------------------------------------------------------------
int _paramCount(Geo g) {
  switch (g.type) {
    case Geo.line:
      return 4;
    case Geo.circle:
      return 3;
    case Geo.arc:
      return 5;
    case Geo.polyline:
      return 2 * g.data[1].toInt();
  }
  return 0;
}

List<int> _offsets(List<Geo> gs) {
  final off = <int>[];
  var n = 0;
  for (final g in gs) {
    off.add(n);
    n += _paramCount(g);
  }
  off.add(n); // total
  return off;
}

List<double> _pack(List<Geo> gs) {
  final x = <double>[];
  for (final g in gs) {
    switch (g.type) {
      case Geo.line:
        x.addAll([g.data[0], g.data[1], g.data[2], g.data[3]]);
        break;
      case Geo.circle:
        x.addAll([g.data[0], g.data[1], g.data[2]]);
        break;
      case Geo.arc:
        x.addAll(
            [g.data[0], g.data[1], g.data[2], g.data[3], g.data[4]]);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        for (var i = 0; i < 2 * n; i++) {
          x.add(g.data[2 + i]);
        }
        break;
    }
  }
  return x;
}

void _unpack(List<Geo> gs, List<int> off, List<double> x) {
  for (var e = 0; e < gs.length; e++) {
    final g = gs[e];
    final o = off[e];
    final d = List<double>.from(g.data);
    switch (g.type) {
      case Geo.line:
        d[0] = x[o];
        d[1] = x[o + 1];
        d[2] = x[o + 2];
        d[3] = x[o + 3];
        break;
      case Geo.circle:
        d[0] = x[o];
        d[1] = x[o + 1];
        d[2] = math.max(1e-6, x[o + 2]);
        break;
      case Geo.arc:
        d[0] = x[o];
        d[1] = x[o + 1];
        d[2] = math.max(1e-6, x[o + 2]);
        d[3] = x[o + 3];
        d[4] = x[o + 4];
        break;
      case Geo.polyline:
        final n = d[1].toInt();
        for (var i = 0; i < 2 * n; i++) {
          d[2 + i] = x[o + i];
        }
        break;
    }
    gs[e] = g.withData(d); // withData KEEPS the layer
  }
}

/// Parameter indices that define the given grip point (used to pin the point
/// the finger is dragging).
List<int> paramsOfPoint(List<Geo> gs, List<int> off, int ent, int pt) {
  if (ent < 0 || ent >= gs.length) return const [];
  final g = gs[ent];
  final o = off[ent];
  switch (g.type) {
    case Geo.line:
      return pt == 0 ? [o, o + 1] : [o + 2, o + 3];
    case Geo.circle:
      return pt == 0 ? [o, o + 1] : [o + 2]; // quadrant grips drive the radius
    case Geo.arc:
      if (pt == 0) return [o, o + 1];
      return [o + 2, pt == 1 ? o + 3 : o + 4];
    case Geo.polyline:
      return [o + 2 * pt, o + 2 * pt + 1];
  }
  return const [];
}

Offset _pointAt(List<Geo> gs, List<int> off, List<double> x, PRef p) {
  if (p.ent < 0 || p.ent >= gs.length) return Offset.zero;
  final g = gs[p.ent];
  final o = off[p.ent];
  switch (g.type) {
    case Geo.line:
      return p.pt == 0
          ? Offset(x[o], x[o + 1])
          : Offset(x[o + 2], x[o + 3]);
    case Geo.circle:
      return Offset(x[o], x[o + 1]);
    case Geo.arc:
      if (p.pt == 0) return Offset(x[o], x[o + 1]);
      final a = p.pt == 1 ? x[o + 3] : x[o + 4];
      return Offset(
          x[o] + math.cos(a) * x[o + 2], x[o + 1] + math.sin(a) * x[o + 2]);
    case Geo.polyline:
      final i = o + 2 * p.pt;
      if (i + 1 >= x.length) return Offset.zero;
      return Offset(x[i], x[i + 1]);
  }
  return Offset.zero;
}

/// (a, b) of a line entity in parameter space.
(Offset, Offset)? _lineEnds(List<Geo> gs, List<int> off, List<double> x, int e) {
  if (e < 0 || e >= gs.length || gs[e].type != Geo.line) return null;
  final o = off[e];
  return (Offset(x[o], x[o + 1]), Offset(x[o + 2], x[o + 3]));
}

/// The same polyline with its vertices taken from PARAMETER space. Goes through
/// withData, so the spline/ellipse/gear tag — and the trailing gear parameter
/// block past the vertices — ride along; without them the curve would sample as
/// a raw control polygon.
Geo _polyAt(List<Geo> gs, List<int> off, List<double> x, int e) {
  final g = gs[e];
  final o = off[e];
  final d = List<double>.from(g.data);
  final n = d[1].toInt();
  for (var i = 0; i < 2 * n && o + i < x.length; i++) {
    d[2 + i] = x[o + i];
  }
  return g.withData(d);
}

/// Point chain of a polyline carrier: the CURVE for a spline/ellipse/gear, the
/// vertices for a straight polyline. Same funnel the render, snap and hit-test
/// use, so a constraint binds to the curve the user actually saw.
List<Offset> _curveSamples(Geo g) =>
    g.type == Geo.polyline ? sampleEntity(g) : const [];

/// Closest point on a sampled chain, plus the chain's unit NORMAL there.
(Offset, Offset)? _closestOnChain(List<Offset> pts, Offset q) {
  var best = double.infinity;
  Offset? at, dir;
  for (var i = 0; i + 1 < pts.length; i++) {
    final s = closestOnSegment(q, pts[i], pts[i + 1]);
    final d = (q - s).distance;
    if (d < best) {
      final seg = pts[i + 1] - pts[i];
      if (seg.distance < 1e-12) continue;
      best = d;
      at = s;
      dir = seg / seg.distance;
    }
  }
  if (at == null || dir == null) return null;
  return (at, Offset(-dir.dy, dir.dx));
}

/// M123 — the frozen local frame of a point-on-CURVE constraint.
///
/// A polyline carrier has no closed-form implicit equation the way a circle
/// does (|q-c| - r), and sampling the curve inside the residual would re-run
/// the B-spline / involute generator for every column of every numeric-Jacobian
/// step — precisely the per-frame cost M63/M67 removed. So the curve is sampled
/// ONCE per solve and reduced to the local tangent line at the closest point,
/// following the same freeze-per-solve idiom the tangency branches use.
///
/// The residual is then `n · (q - P(V))` with the curve point P linear in the
/// carrier's own vertices V:
///   * [p0]/[n]  closest point and unit normal at freeze time,
///   * [w]       d(n·P)/d(vertex param) — how the curve point answers a vertex
///               move, so a carrier that MOVES drags the bound point with it,
///   * [x0]      the vertex params the weights belong to.
///
/// The carrier is modelled as following its vertices RIGIDLY, i.e. each vertex
/// owns an equal share of the normal. That makes a rigid move of the carrier
/// exact — the property that matters, since dragging a whole spline or polygon
/// is the common case — and costs a single curve sample. Measuring the true
/// per-vertex response numerically was tried and reverted: it needs a curve
/// rebuild per vertex per freeze, which on a 60-vertex freehand spline (M87)
/// cost 28 ms per solve against 0.4 ms without the bind.
///
/// A DEFORMATION of the carrier (dragging one control vertex) is therefore only
/// approximated: the frame under-follows, and the [_lm] pass loop re-projects
/// onto the real curve until the point lands on it. Cheap where it is hot,
/// iterated where it is wrong.
///
/// The honest limit either way: this is a linearisation refreshed per pass, not
/// an exact NURBS projection. A solve that cannot converge its passes leaves the
/// point on the tangent, and [solveConstraints] then rejects the frame through
/// the usual residual gate rather than showing it.
class _OnCurve {
  final Offset p0, n;
  final int base;
  final List<double> w, x0;
  const _OnCurve(this.p0, this.n, this.base, this.w, this.x0);
}

/// Builds the frozen frame for point [q] on polyline carrier [e].
_OnCurve? _freezeOnCurve(
    List<Geo> gs, List<int> off, List<double> x, int e, Offset q) {
  final g = gs[e];
  if (g.type != Geo.polyline) return null;
  final nv = g.data[1].toInt();
  if (nv < 1) return null;
  final base = off[e];
  final hit = _closestOnChain(_curveSamples(_polyAt(gs, off, x, e)), q);
  if (hit == null) return null;
  final (p0, nrm) = hit;
  // Equal shares, so the weights sum to the normal itself: translate every
  // vertex by t and the modelled curve point translates by exactly t.
  final w = List<double>.filled(2 * nv, 0.0);
  for (var i = 0; i < nv; i++) {
    w[2 * i] = nrm.dx / nv;
    w[2 * i + 1] = nrm.dy / nv;
  }
  return _OnCurve(p0, nrm, base,
      w, [for (var k = 0; k < 2 * nv; k++) x[base + k]]);
}

/// (center, radius) of a circle/arc entity in parameter space.
(Offset, double)? _circle(List<Geo> gs, List<int> off, List<double> x, int e) {
  if (e < 0 || e >= gs.length) return null;
  final t = gs[e].type;
  if (t != Geo.circle && t != Geo.arc) return null;
  final o = off[e];
  return (Offset(x[o], x[o + 1]), x[o + 2]);
}

// ---------------------------------------------------------------------------
// residuals
// ---------------------------------------------------------------------------
/// Sign/branch decisions frozen once per solve so the residuals stay smooth
/// (inner vs outer tangency, the sign of a signed distance, ...).
class _Ctx {
  final Map<int, double> sign = {};
  final Map<int, double> mode = {};

  /// M123 — frozen local frame per point-on-CURVE constraint index.
  final Map<int, _OnCurve> onCurve = {};
}

bool _active(Constraint c) => !c.driven;

/// Number of equations a constraint contributes (0 = ignored).
int residualCount(List<Geo> gs, Constraint c) {
  if (!_active(c)) return 0;
  bool ent(int i) => i < c.ents.length && c.ents[i] < gs.length;
  bool pt(int i) => i < c.pts.length && c.pts[i].ent < gs.length;
  switch (c.type) {
    case CType.coincident:
      if (pt(0) && pt(1)) return 2; // point-on-point
      // point-on-line: one point pinned onto one straight edge
      if (pt(0) && ent(0) && gs[c.ents[0]].type == Geo.line) return 1;
      // point-on-circle/arc: one point pinned onto the curve (|q-c| == r)
      if (pt(0) &&
          ent(0) &&
          (gs[c.ents[0]].type == Geo.circle ||
              gs[c.ents[0]].type == Geo.arc)) {
        return 1;
      }
      // M123 point-on-CURVE: one point pinned onto a polyline carrier — a
      // polygon edge, a spline, an ellipse or a gear outline. One equation,
      // exactly like point-on-line: the point keeps one degree of freedom,
      // sliding ALONG the curve.
      //
      // Decided from the VERTEX COUNT, never by sampling: this runs once per
      // constraint per residual evaluation, i.e. on every column of every
      // numeric-Jacobian step, and generating the curve here cost ~100x the
      // whole solve on a 60-vertex freehand spline. A carrier that yields no
      // usable chain still contributes its one (zero) residual, so the count
      // and the residual list cannot disagree.
      if (pt(0) && ent(0) && gs[c.ents[0]].type == Geo.polyline) {
        return gs[c.ents[0]].data[1] >= 2 ? 1 : 0;
      }
      return 0;
    case CType.fix:
      if (c.pts.isNotEmpty) return pt(0) ? 2 : 0;
      return ent(0) ? _paramCount(gs[c.ents[0]]) : 0;
    case CType.horizontal:
    case CType.vertical:
      if (c.pts.length >= 2) return pt(0) && pt(1) ? 1 : 0;
      return ent(0) && gs[c.ents[0]].type == Geo.line ? 1 : 0;
    case CType.parallel:
    case CType.perpendicular:
      return ent(0) &&
              ent(1) &&
              gs[c.ents[0]].type == Geo.line &&
              gs[c.ents[1]].type == Geo.line
          ? 1
          : 0;
    case CType.collinear:
      return ent(0) &&
              ent(1) &&
              gs[c.ents[0]].type == Geo.line &&
              gs[c.ents[1]].type == Geo.line
          ? 2
          : 0;
    case CType.concentric:
      return ent(0) && ent(1) ? 2 : 0;
    case CType.tangent:
      if (!ent(0) || !ent(1)) return 0;
      // spline participants (open CV/fit splines) act through their END and
      // plain-polyline participants (rectangle/polygon sides) through the
      // picked EDGE's two vertices — pts layout: [spline end(s)...,
      // edge vertex pair(s)...], all resolved at click time. One direction
      // equation, exactly like Inventor's 1-DOF tangency.
      final nSpl = [c.ents[0], c.ents[1]]
          .where((e) =>
              gs[e].type == Geo.polyline &&
              (gs[e].spline == Geo.splineCv || gs[e].spline == Geo.splineFit))
          .length;
      final nPoly = [c.ents[0], c.ents[1]]
          .where((e) =>
              gs[e].type == Geo.polyline && gs[e].spline == Geo.straight)
          .length;
      if (nSpl > 0 || nPoly > 0) {
        final need = nSpl + 2 * nPoly;
        if (c.pts.length < need) return 0;
        for (var k = 0; k < need; k++) {
          if (!pt(k)) return 0;
        }
        for (var k = 0; k < nSpl; k++) {
          if (gs[c.pts[k].ent].data[1].toInt() < 2) return 0; // no direction
        }
      }
      return 1;
    case CType.smooth:
      // G2 = tangency + equal curvature (only meaningful for two arcs)
      if (!ent(0) || !ent(1)) return 0;
      final a = gs[c.ents[0]].type, b = gs[c.ents[1]].type;
      final curved = (a == Geo.arc || a == Geo.circle) &&
          (b == Geo.arc || b == Geo.circle);
      return curved ? 2 : 1;
    case CType.symmetric:
      return pt(0) && pt(1) && ent(0) && gs[c.ents[0]].type == Geo.line ? 2 : 0;
    case CType.midpoint:
      return pt(0) && ent(0) && gs[c.ents[0]].type == Geo.line ? 2 : 0;
    case CType.equal:
      return ent(0) && ent(1) ? 1 : 0;
    case CType.dimension:
      if (c.value == null) return 0;
      switch (c.dimKind) {
        case 'dist':
        case 'distx':
        case 'disty':
          return pt(0) && pt(1) ? 1 : 0;
        case 'rad':
        case 'dia':
          return ent(0) ? 1 : 0;
        case 'gap':
          // M124 radial gap between two circles/arcs: one equation.
          return ent(0) && ent(1) ? 1 : 0;
        case 'ang':
          return ent(0) && ent(1) ? 1 : 0;
        case 'pline':
        case 'ang3':
          return pt(0) && pt(1) && pt(2) ? 1 : 0;
        case 'plinetan':
          // M202 — needs the radius as well as the three points.
          return pt(0) && pt(1) && pt(2) && ent(0) ? 1 : 0;
        case 'ang4':
          return pt(0) && pt(1) && pt(2) && pt(3) ? 1 : 0;
      }
      return 0;
    case CType.pattern:
      // one equation per COPY parameter: the copy is rigidly slaved to the
      // source, so a pattern never adds net DOF and can never over-constrain
      // on its own (copy params == copy equations).
      if (!ent(0) || !ent(1)) return 0;
      final src = gs[c.ents[0]], cp = gs[c.ents[1]];
      if (src.type != cp.type) return 0;
      if (_paramCount(src) != _paramCount(cp)) return 0;
      if (patternTransform(c.anchors) == null) return 0;
      return _paramCount(cp);
  }
}

void _prepare(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx) {
  for (var i = 0; i < cs.length; i++) {
    final c = cs[i];
    if (residualCount(gs, c) == 0) continue;
    switch (c.type) {
      case CType.coincident:
        // M123 — point on a polyline CARRIER (polygon edge, spline, ellipse,
        // gear). Sample the real curve once and keep its local tangent frame;
        // the residual is then O(1) and the numeric Jacobian never re-runs the
        // curve generator.
        if (c.pts.length == 1 &&
            c.ents.length == 1 &&
            c.ents[0] < gs.length &&
            gs[c.ents[0]].type == Geo.polyline) {
          final fr = _freezeOnCurve(
              gs, off, x, c.ents[0], _pointAt(gs, off, x, c.pts[0]));
          if (fr != null) ctx.onCurve[i] = fr;
        }
        break;
      case CType.tangent:
      case CType.smooth:
        final c1 = _circle(gs, off, x, c.ents[0]);
        final c2 = _circle(gs, off, x, c.ents[1]);
        if (c1 != null && c2 != null) {
          // curve-curve: inner (0) vs outer (1) tangency. Captured ONCE and
          // persisted on the constraint — re-deriving per solve let drags walk
          // continuously onto the other branch through the degenerate point.
          if (c.tanBranch == null) {
            final d = (c2.$1 - c1.$1).distance;
            final outer = c1.$2 + c2.$2;
            final inner = (c1.$2 - c2.$2).abs();
            c.tanBranch = (d - outer).abs() <= (d - inner).abs() ? 1 : 0;
          }
          ctx.mode[i] = c.tanBranch!;
          break;
        }
        // line + circle/arc (direct or polygon-edge variant): WHICH SIDE of
        // the line the center sits on. Same persistence rule as above — the
        // naked |dist| - r has two branches and a kink at dist = 0; freezing
        // the side per SOLVE made the residual smooth but still allowed the
        // branch to migrate BETWEEN frames (the slot "teardrop"). The side is
        // captured once from the creation/load geometry and honoured forever,
        // like Inventor: a tangency cannot be flipped by dragging.
        Offset? la, lb, cCen;
        if (c.pts.length >= 2 &&
            (gs[c.ents[0]].type == Geo.polyline ||
                gs[c.ents[1]].type == Geo.polyline)) {
          final circE =
              gs[c.ents[0]].type == Geo.polyline ? c.ents[1] : c.ents[0];
          final cc = _circle(gs, off, x, circE);
          if (cc != null) {
            la = _pointAt(gs, off, x, c.pts[0]);
            lb = _pointAt(gs, off, x, c.pts[1]);
            cCen = cc.$1;
          }
        } else {
          final lineFirst = gs[c.ents[0]].type == Geo.line;
          final lineE = lineFirst ? c.ents[0] : c.ents[1];
          final circE = lineFirst ? c.ents[1] : c.ents[0];
          if (gs[lineE].type == Geo.line) {
            final l = _lineEnds(gs, off, x, lineE);
            final cc = _circle(gs, off, x, circE);
            if (l != null && cc != null) {
              la = l.$1;
              lb = l.$2;
              cCen = cc.$1;
            }
          }
        }
        if (la != null && lb != null && cCen != null) {
          if (c.tanBranch == null) {
            final d = lb - la;
            final len = d.distance;
            if (len > 1e-12) {
              final n = Offset(-d.dy, d.dx) / len;
              final dist = (cCen - la).dx * n.dx + (cCen - la).dy * n.dy;
              c.tanBranch = dist < 0 ? -1.0 : 1.0;
            }
          }
          if (c.tanBranch != null) ctx.sign[i] = c.tanBranch!;
        }
        break;
      case CType.dimension:
        if (c.dimKind == 'distx' || c.dimKind == 'disty') {
          final pa = _pointAt(gs, off, x, c.pts[0]);
          final pb = _pointAt(gs, off, x, c.pts[1]);
          final d = c.dimKind == 'distx' ? pb.dx - pa.dx : pb.dy - pa.dy;
          ctx.sign[i] = d < 0 ? -1.0 : 1.0;
        } else if (c.dimKind == 'ang') {
          final l1 = _lineEnds(gs, off, x, c.ents[0]);
          final l2 = _lineEnds(gs, off, x, c.ents[1]);
          if (l1 != null && l2 != null) {
            final d1 = l1.$2 - l1.$1, d2 = l2.$2 - l2.$1;
            final cross = d1.dx * d2.dy - d1.dy * d2.dx;
            ctx.sign[i] = cross < 0 ? -1.0 : 1.0;
          }
        } else if (c.dimKind == 'gap' && c.ents.length >= 2) {
          // M124 — freeze WHICH circle is the outer one. Without this the
          // |R2-R1| corner sits exactly at the solution, and a pair that
          // crosses during a drag would swap roles mid-solve and jump.
          final g1 = _circle(gs, off, x, c.ents[0]);
          final g2 = _circle(gs, off, x, c.ents[1]);
          if (g1 != null && g2 != null) {
            ctx.sign[i] = (g2.$2 - g1.$2) < 0 ? -1.0 : 1.0;
          }
        } else if ((c.dimKind == 'pline' || c.dimKind == 'plinetan') &&
            c.pts.length >= 3) {
          // keep the point on the side of the line it is on now — Inventor
          // never mirrors geometry through the line to satisfy a distance
          final p = _pointAt(gs, off, x, c.pts[0]);
          final a = _pointAt(gs, off, x, c.pts[1]);
          final b = _pointAt(gs, off, x, c.pts[2]);
          final d = b - a;
          final cross = (p - a).dx * d.dy - (p - a).dy * d.dx;
          ctx.sign[i] = cross < 0 ? -1.0 : 1.0;
        } else if (c.dimKind == 'ang3' && c.pts.length >= 3) {
          final a = _pointAt(gs, off, x, c.pts[0]);
          final o = _pointAt(gs, off, x, c.pts[1]);
          final b = _pointAt(gs, off, x, c.pts[2]);
          final d1 = a - o, d2 = b - o;
          final cross = d1.dx * d2.dy - d1.dy * d2.dx;
          ctx.sign[i] = cross < 0 ? -1.0 : 1.0;
        } else if (c.dimKind == 'ang4' && c.pts.length >= 4) {
          final da = _pointAt(gs, off, x, c.pts[1]) -
              _pointAt(gs, off, x, c.pts[0]);
          final db = _pointAt(gs, off, x, c.pts[3]) -
              _pointAt(gs, off, x, c.pts[2]);
          final cross = da.dx * db.dy - da.dy * db.dx;
          ctx.sign[i] = cross < 0 ? -1.0 : 1.0;
        }
        break;
      default:
        break;
    }
  }
}

List<double> _residuals(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx) {
  final r = <double>[];
  for (var i = 0; i < cs.length; i++) {
    final c = cs[i];
    final n = residualCount(gs, c);
    if (n == 0) continue;
    switch (c.type) {
      case CType.coincident:
        if (c.pts.length >= 2) {
          final a = _pointAt(gs, off, x, c.pts[0]);
          final b = _pointAt(gs, off, x, c.pts[1]);
          r.add(a.dx - b.dx);
          r.add(a.dy - b.dy);
        } else {
          final q = _pointAt(gs, off, x, c.pts[0]);
          final tgt = gs[c.ents[0]].type;
          if (tgt == Geo.circle || tgt == Geo.arc) {
            // point-on-curve: distance to the center equals the radius.
            // Smooth and branch-free (unlike line tangency, distance-to-a-
            // POINT has no side).
            final cc = _circle(gs, off, x, c.ents[0]);
            r.add(cc == null ? 0 : (q - cc.$1).distance - cc.$2);
          } else if (tgt == Geo.polyline) {
            // M123 point-on-CURVE against the frame frozen in _prepare:
            //   n · (q - P(V)),  P(V) linear in the carrier's vertices.
            // residualCount promised one equation, so one always goes out —
            // a missing frame (degenerate carrier) contributes 0, never a
            // silently dropped row.
            final fr = ctx.onCurve[i];
            if (fr == null) {
              r.add(0);
            } else {
              var pn = fr.p0.dx * fr.n.dx + fr.p0.dy * fr.n.dy;
              for (var k = 0; k < fr.w.length; k++) {
                if (fr.w[k] == 0) continue;
                pn += fr.w[k] * (x[fr.base + k] - fr.x0[k]);
              }
              r.add(q.dx * fr.n.dx + q.dy * fr.n.dy - pn);
            }
          } else {
            // point-on-line: signed perpendicular distance to the edge == 0
            final l = _lineEnds(gs, off, x, c.ents[0]);
            if (l == null) {
              r.add(0);
            } else {
              final d = l.$2 - l.$1;
              final len = d.distance;
              if (len < 1e-12) {
                r.add(0);
              } else {
                final nrm = Offset(-d.dy, d.dx) / len;
                r.add((q - l.$1).dx * nrm.dx + (q - l.$1).dy * nrm.dy);
              }
            }
          }
        }
        break;
      case CType.fix:
        if (c.pts.isNotEmpty) {
          final p = _pointAt(gs, off, x, c.pts[0]);
          final an = c.anchors;
          r.add(p.dx - (an.length > 0 ? an[0] : p.dx));
          r.add(p.dy - (an.length > 1 ? an[1] : p.dy));
        } else {
          final e = c.ents[0];
          final o = off[e];
          for (var k = 0; k < _paramCount(gs[e]); k++) {
            r.add(x[o + k] - (k < c.anchors.length ? c.anchors[k] : x[o + k]));
          }
        }
        break;
      case CType.horizontal:
      case CType.vertical:
        final horiz = c.type == CType.horizontal;
        if (c.pts.length >= 2) {
          final a = _pointAt(gs, off, x, c.pts[0]);
          final b = _pointAt(gs, off, x, c.pts[1]);
          r.add(horiz ? a.dy - b.dy : a.dx - b.dx);
        } else {
          final l = _lineEnds(gs, off, x, c.ents[0])!;
          final d = l.$2 - l.$1;
          r.add(horiz ? d.dy : d.dx);
        }
        break;
      case CType.parallel:
      case CType.perpendicular:
        final l1 = _lineEnds(gs, off, x, c.ents[0])!;
        final l2 = _lineEnds(gs, off, x, c.ents[1])!;
        final d1 = l1.$2 - l1.$1, d2 = l2.$2 - l2.$1;
        final s = d1.distance * d2.distance;
        if (s < 1e-12) {
          r.add(0);
          break;
        }
        r.add(c.type == CType.parallel
            ? (d1.dx * d2.dy - d1.dy * d2.dx) / s
            : (d1.dx * d2.dx + d1.dy * d2.dy) / s);
        break;
      case CType.collinear:
        final l1 = _lineEnds(gs, off, x, c.ents[0])!;
        final l2 = _lineEnds(gs, off, x, c.ents[1])!;
        final d1 = l1.$2 - l1.$1;
        final len = d1.distance;
        if (len < 1e-12) {
          r..add(0)..add(0);
          break;
        }
        final n1 = Offset(-d1.dy, d1.dx) / len;
        r.add((l2.$1 - l1.$1).dx * n1.dx + (l2.$1 - l1.$1).dy * n1.dy);
        r.add((l2.$2 - l1.$1).dx * n1.dx + (l2.$2 - l1.$1).dy * n1.dy);
        break;
      case CType.concentric:
        final a = _circle(gs, off, x, c.ents[0]);
        final b = _circle(gs, off, x, c.ents[1]);
        if (a == null || b == null) {
          r..add(0)..add(0);
          break;
        }
        r.add(a.$1.dx - b.$1.dx);
        r.add(a.$1.dy - b.$1.dy);
        break;
      case CType.tangent:
      case CType.smooth:
        _tangentResiduals(gs, off, x, cs, ctx, i, c, r);
        break;
      case CType.midpoint:
        // pts[0] == midpoint of line ents[0] — LINEAR, so it never traps the
        // LM solver the way the two coupled symmetric-about-the-other-axis
        // equations did for ellipse axes.
        final ml = _lineEnds(gs, off, x, c.ents[0])!;
        final mp = _pointAt(gs, off, x, c.pts[0]);
        r.add((ml.$1.dx + ml.$2.dx) / 2 - mp.dx);
        r.add((ml.$1.dy + ml.$2.dy) / 2 - mp.dy);
        break;
      case CType.symmetric:
        final ax = _lineEnds(gs, off, x, c.ents[0])!;
        final d = ax.$2 - ax.$1;
        final len = d.distance;
        final a = _pointAt(gs, off, x, c.pts[0]);
        final b = _pointAt(gs, off, x, c.pts[1]);
        if (len < 1e-12) {
          r..add(0)..add(0);
          break;
        }
        final nAx = Offset(-d.dy, d.dx) / len;
        final mid = (a + b) / 2;
        // midpoint on the axis + AB perpendicular to the axis
        r.add((mid - ax.$1).dx * nAx.dx + (mid - ax.$1).dy * nAx.dy);
        r.add(((b - a).dx * d.dx + (b - a).dy * d.dy) / len);
        break;
      case CType.equal:
        final g1 = gs[c.ents[0]], g2 = gs[c.ents[1]];
        if (g1.type == Geo.line && g2.type == Geo.line) {
          final l1 = _lineEnds(gs, off, x, c.ents[0])!;
          final l2 = _lineEnds(gs, off, x, c.ents[1])!;
          r.add((l1.$2 - l1.$1).distance - (l2.$2 - l2.$1).distance);
        } else {
          final a = _circle(gs, off, x, c.ents[0]);
          final b = _circle(gs, off, x, c.ents[1]);
          r.add(a == null || b == null ? 0 : a.$2 - b.$2);
        }
        break;
      case CType.dimension:
        _dimResidual(gs, off, x, ctx, i, c, r);
        break;
      case CType.pattern:
        _patternResiduals(gs, off, x, c, r);
        break;
    }
  }
  return r;
}

/// Residuals of a pattern element (M35): every parameter of the COPY equals
/// the pattern-transformed parameter of the SOURCE. Point parameters go
/// through the rigid transform; a radius stays equal; arc sweep angles shift
/// by the rotation (wrapped, so the equations stay smooth across ±pi).
void _patternResiduals(
    List<Geo> gs, List<int> off, List<double> x, Constraint c, List<double> r) {
  final f = patternTransform(c.anchors)!;
  final rot = patternRotation(c.anchors);
  final src = c.ents[0], cp = c.ents[1];
  final os = off[src], oc = off[cp];
  double wrap(double a) {
    var v = a % (2 * math.pi);
    if (v > math.pi) v -= 2 * math.pi;
    if (v < -math.pi) v += 2 * math.pi;
    return v;
  }

  switch (gs[cp].type) {
    case Geo.line:
      for (var k = 0; k < 2; k++) {
        final p = f(Offset(x[os + 2 * k], x[os + 2 * k + 1]));
        r.add(x[oc + 2 * k] - p.dx);
        r.add(x[oc + 2 * k + 1] - p.dy);
      }
      break;
    case Geo.circle:
      final ce = f(Offset(x[os], x[os + 1]));
      r.add(x[oc] - ce.dx);
      r.add(x[oc + 1] - ce.dy);
      r.add(x[oc + 2] - x[os + 2]); // equal radius
      break;
    case Geo.arc:
      final ce = f(Offset(x[os], x[os + 1]));
      r.add(x[oc] - ce.dx);
      r.add(x[oc + 1] - ce.dy);
      r.add(x[oc + 2] - x[os + 2]); // equal radius
      r.add(wrap(x[oc + 3] - x[os + 3] - rot)); // start angle shifted by rot
      r.add(wrap(x[oc + 4] - x[os + 4] - rot)); // end angle shifted by rot
      break;
    case Geo.polyline:
      final n = gs[cp].data[1].toInt();
      for (var k = 0; k < n; k++) {
        final p = f(Offset(x[os + 2 * k], x[os + 2 * k + 1]));
        r.add(x[oc + 2 * k] - p.dx);
        r.add(x[oc + 2 * k + 1] - p.dy);
      }
      break;
  }
}

void _tangentResiduals(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx, int i, Constraint c, List<double> r) {
  final t1 = gs[c.ents[0]].type, t2 = gs[c.ents[1]].type;

  // ---- spline tangency (M29) --------------------------------------------
  // Endpoint tangency, Inventor's semantics: the spline's END TANGENT — which
  // for BOTH kinds runs along the two defining points at that end (Catmull-
  // Rom phantom ends; clamped B-spline endpoint property) — is made parallel
  // to the line, perpendicular to the circle/arc radius at the endpoint, or
  // parallel to the other spline's end tangent. One normalized equation.
  bool isSpl(int e) =>
      gs[e].type == Geo.polyline &&
      (gs[e].spline == Geo.splineCv || gs[e].spline == Geo.splineFit);
  bool isPoly(int e) =>
      gs[e].type == Geo.polyline && gs[e].spline == Geo.straight;
  if (isSpl(c.ents[0]) || isSpl(c.ents[1])) {
    Offset endDir(PRef pr) {
      final n = gs[pr.ent].data[1].toInt();
      final adj = pr.pt == 0 ? 1 : n - 2;
      return _pointAt(gs, off, x, PRef(pr.ent, adj)) -
          _pointAt(gs, off, x, pr);
    }

    final splRefs = c.pts;
    final dA = endDir(splRefs[0]);
    final otherE = c.ents[0] == splRefs[0].ent ? c.ents[1] : c.ents[0];
    if (isSpl(otherE) && splRefs.length >= 2) {
      // spline + spline: end tangents parallel
      final dB = endDir(splRefs[1]);
      final m = dA.distance * dB.distance;
      r.add(m < 1e-12 ? 0 : (dA.dx * dB.dy - dA.dy * dB.dx) / m);
      return;
    }
    if (isPoly(otherE)) {
      // spline + rectangle/polygon EDGE (pts = [end, edgeA, edgeB]):
      // end tangent parallel to the edge
      final ea = _pointAt(gs, off, x, c.pts[1]);
      final eb = _pointAt(gs, off, x, c.pts[2]);
      final de = eb - ea;
      final m = dA.distance * de.distance;
      r.add(m < 1e-12 ? 0 : (dA.dx * de.dy - dA.dy * de.dx) / m);
      return;
    }
    if (gs[otherE].type == Geo.line) {
      final l = _lineEnds(gs, off, x, otherE)!;
      final dl = l.$2 - l.$1;
      final m = dA.distance * dl.distance;
      r.add(m < 1e-12 ? 0 : (dA.dx * dl.dy - dA.dy * dl.dx) / m);
      return;
    }
    // circle / arc: end tangent perpendicular to the radius at the endpoint
    final cc = _circle(gs, off, x, otherE);
    if (cc == null) {
      r.add(0);
      return;
    }
    final rad = _pointAt(gs, off, x, splRefs[0]) - cc.$1;
    final m = dA.distance * rad.distance;
    r.add(m < 1e-12 ? 0 : (dA.dx * rad.dx + dA.dy * rad.dy) / m);
    return;
  }
  if (isPoly(c.ents[0]) || isPoly(c.ents[1])) {
    // circle/arc + rectangle/polygon EDGE (pts = [edgeA, edgeB]): the
    // classic line-circle tangency, but over the edge's vertex refs —
    // distance(center, infinite edge line) == radius
    final circE = isPoly(c.ents[0]) ? c.ents[1] : c.ents[0];
    final cc = _circle(gs, off, x, circE);
    final ea = _pointAt(gs, off, x, c.pts[0]);
    final eb = _pointAt(gs, off, x, c.pts[1]);
    final de = eb - ea;
    final len = de.distance;
    if (cc == null || len < 1e-12) {
      r.add(0);
      return;
    }
    final n = Offset(-de.dy, de.dx) / len;
    final dist = (cc.$1 - ea).dx * n.dx + (cc.$1 - ea).dy * n.dy;
    // signed via ctx (side frozen in _prepare); smooth, branch-stable
    r.add((ctx.sign[i] ?? (dist < 0 ? -1.0 : 1.0)) * dist - cc.$2);
    return;
  }

  final lineFirst = t1 == Geo.line;
  final curved = (t1 == Geo.arc || t1 == Geo.circle) &&
      (t2 == Geo.arc || t2 == Geo.circle);
  if (curved) {
    final a = _circle(gs, off, x, c.ents[0])!;
    final b = _circle(gs, off, x, c.ents[1])!;
    final d = (b.$1 - a.$1).distance;
    final outer = (ctx.mode[i] ?? 1) == 1;
    r.add(d - (outer ? a.$2 + b.$2 : (a.$2 - b.$2).abs()));
    if (c.type == CType.smooth) {
      r.add(a.$2 - b.$2); // G2: equal curvature
    }
    return;
  }
  // line + circle/arc: distance(center, line) == radius
  final lineE = lineFirst ? c.ents[0] : c.ents[1];
  final circE = lineFirst ? c.ents[1] : c.ents[0];
  // exactly ONE residual here (see residualCount): a line has no curvature,
  // so G2 against a line degenerates to tangency and the UI rejects it.
  final l = _lineEnds(gs, off, x, lineE);
  final cc = _circle(gs, off, x, circE);
  if (l == null || cc == null) {
    r.add(0);
    return;
  }
  final d = l.$2 - l.$1;
  final len = d.distance;
  if (len < 1e-12) {
    r.add(0);
    return;
  }
  final n = Offset(-d.dy, d.dx) / len;
  final dist = (cc.$1 - l.$1).dx * n.dx + (cc.$1 - l.$1).dy * n.dy;
  // signed via ctx (side frozen in _prepare); smooth, branch-stable
  r.add((ctx.sign[i] ?? (dist < 0 ? -1.0 : 1.0)) * dist - cc.$2);
}

void _dimResidual(List<Geo> gs, List<int> off, List<double> x, _Ctx ctx,
    int i, Constraint c, List<double> r) {
  final v = c.value!;
  switch (c.dimKind) {
    case 'dist':
      final a = _pointAt(gs, off, x, c.pts[0]);
      final b = _pointAt(gs, off, x, c.pts[1]);
      r.add((b - a).distance - v);
      break;
    case 'distx':
    case 'disty':
      final a = _pointAt(gs, off, x, c.pts[0]);
      final b = _pointAt(gs, off, x, c.pts[1]);
      final d = c.dimKind == 'distx' ? b.dx - a.dx : b.dy - a.dy;
      r.add((ctx.sign[i] ?? 1.0) * d - v);
      break;
    case 'rad':
    case 'dia':
      final cc = _circle(gs, off, x, c.ents[0]);
      final f = c.dimKind == 'rad' ? 1.0 : 2.0;
      r.add(cc == null ? 0 : f * cc.$2 - v);
      break;
    case 'gap':
      // M124 — |R2 - R1| == v. The absolute value is resolved ONCE per solve
      // into a frozen sign (_prepare), the same trick the distx/disty and
      // pline dimensions use: an abs() has a corner exactly at the solution
      // and would stall LM, and re-deciding which circle is the outer one per
      // ITERATION would let the pair flip inside a single drag.
      final g1 = _circle(gs, off, x, c.ents[0]);
      final g2 = _circle(gs, off, x, c.ents[1]);
      if (g1 == null || g2 == null) {
        r.add(0);
      } else {
        r.add((ctx.sign[i] ?? 1.0) * (g2.$2 - g1.$2) - v);
      }
      break;
    case 'ang':
      final l1 = _lineEnds(gs, off, x, c.ents[0])!;
      final l2 = _lineEnds(gs, off, x, c.ents[1])!;
      final d1 = l1.$2 - l1.$1, d2 = l2.$2 - l2.$1;
      final s = d1.distance * d2.distance;
      if (s < 1e-12) {
        r.add(0);
        break;
      }
      final cross = (d1.dx * d2.dy - d1.dy * d2.dx) / s;
      final dot = (d1.dx * d2.dx + d1.dy * d2.dy) / s;
      final ang = math.atan2(cross, dot);
      final target = (ctx.sign[i] ?? 1.0) * v * math.pi / 180;
      r.add(ang - target);
      break;
    case 'pline':
      // signed perpendicular distance of pts[0] to the infinite line through
      // pts[1],pts[2]; the sign captured in _prepare keeps the point on its
      // current side (matches the shim's SLVS_C_PT_LINE_DISTANCE signing)
      final p = _pointAt(gs, off, x, c.pts[0]);
      final la = _pointAt(gs, off, x, c.pts[1]);
      final lb = _pointAt(gs, off, x, c.pts[2]);
      final dl = lb - la;
      final len = dl.distance;
      if (len < 1e-12) {
        r.add((p - la).distance - v);
        break;
      }
      final cross2 = ((p - la).dx * dl.dy - (p - la).dy * dl.dx) / len;
      r.add(cross2 - (ctx.sign[i] ?? 1.0) * v);
      break;
    case 'plinetan':
      // M202 — Inventor's tangent dimension: the gap between the line and the
      // NEAREST point of the circle, i.e. the centre distance less the radius.
      // Same frozen sign as 'pline', for the same reason: a distance must not
      // be satisfied by mirroring the circle through the line.
      if (c.ents.isEmpty || c.ents[0] >= gs.length) {
        r.add(0);
        break;
      }
      final tp = _pointAt(gs, off, x, c.pts[0]);
      final ta = _pointAt(gs, off, x, c.pts[1]);
      final tb = _pointAt(gs, off, x, c.pts[2]);
      final rad = x[off[c.ents[0]] + 2];
      final tdl = tb - ta;
      final tlen = tdl.distance;
      if (tlen < 1e-12) {
        r.add((tp - ta).distance - rad - v);
        break;
      }
      final tcross = ((tp - ta).dx * tdl.dy - (tp - ta).dy * tdl.dx) / tlen;
      final sgn = ctx.sign[i] ?? 1.0;
      r.add(sgn * tcross - rad - v);
      break;
    case 'ang3':
      final pa = _pointAt(gs, off, x, c.pts[0]);
      final po = _pointAt(gs, off, x, c.pts[1]);
      final pb = _pointAt(gs, off, x, c.pts[2]);
      final e1 = pa - po, e2 = pb - po;
      final s3 = e1.distance * e2.distance;
      if (s3 < 1e-12) {
        r.add(0);
        break;
      }
      final cr = (e1.dx * e2.dy - e1.dy * e2.dx) / s3;
      final dt = (e1.dx * e2.dx + e1.dy * e2.dy) / s3;
      r.add(math.atan2(cr, dt) - (ctx.sign[i] ?? 1.0) * v * math.pi / 180);
      break;
    case 'ang4':
      // pts = [a1, a2, b1, b2]: angle between the rays a1->a2 and b1->b2 —
      // the line-line angle over POINTS (works for polyline edges). Sign is
      // captured in _prepare like 'ang' so LM drives towards the current
      // winding instead of flipping the sketch.
      final qa = _pointAt(gs, off, x, c.pts[1]) -
          _pointAt(gs, off, x, c.pts[0]);
      final qb = _pointAt(gs, off, x, c.pts[3]) -
          _pointAt(gs, off, x, c.pts[2]);
      final s4 = qa.distance * qb.distance;
      if (s4 < 1e-12) {
        r.add(0);
        break;
      }
      final cr4 = (qa.dx * qb.dy - qa.dy * qb.dx) / s4;
      final dt4 = (qa.dx * qb.dx + qa.dy * qb.dy) / s4;
      r.add(math.atan2(cr4, dt4) - (ctx.sign[i] ?? 1.0) * v * math.pi / 180);
      break;
  }
}

// ---------------------------------------------------------------------------
// linear algebra (dense, small systems)
// ---------------------------------------------------------------------------
/// Rank of [m] (rows x cols) by Gaussian elimination with partial pivoting.
/// Also returns the pivot columns.
/// (rank, equations, params) of the ACTIVE constraint system at the current
/// geometry — the ground truth for redundancy checks in tests and diagnostics:
/// `equations - rank` is the number of redundant rows (must be 0 for every
/// deterministic construction, or the LM normal equations go singular and the
/// native solver flags the sketch inconsistent).
(int, int, int) debugRank(List<Geo> gs, List<Constraint> cs) {
  final off = _offsets(gs);
  final total = off.last;
  final x = _pack(gs);
  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);
  final r = _residuals(gs, off, x, cs, ctx);
  if (r.isEmpty || total == 0) return (0, r.length, total);
  final j = List.generate(r.length, (_) => List<double>.filled(total, 0.0));
  for (var k = 0; k < total; k++) {
    final h = 1e-6 * (1 + x[k].abs());
    final save = x[k];
    x[k] = save + h;
    final r2 = _residuals(gs, off, x, cs, ctx);
    x[k] = save;
    for (var i = 0; i < r.length; i++) {
      j[i][k] = (r2[i] - r[i]) / h;
    }
  }
  return (_rankAndPivots(j, r.length, total).$1, r.length, total);
}

(int, List<int>) _rankAndPivots(List<List<double>> m, int rows, int cols) {
  var row = 0;
  final pivots = <int>[];
  for (var col = 0; col < cols && row < rows; col++) {
    var best = row;
    for (var i = row + 1; i < rows; i++) {
      if (m[i][col].abs() > m[best][col].abs()) best = i;
    }
    if (m[best][col].abs() < 1e-7) continue;
    final t = m[row];
    m[row] = m[best];
    m[best] = t;
    final piv = m[row][col];
    for (var j = col; j < cols; j++) {
      m[row][j] /= piv;
    }
    for (var i = 0; i < rows; i++) {
      if (i == row) continue;
      final f = m[i][col];
      if (f == 0) continue;
      for (var j = col; j < cols; j++) {
        m[i][j] -= f * m[row][j];
      }
    }
    pivots.add(col);
    row++;
  }
  return (row, pivots);
}

/// Solves A x = b in place (A is n x n, symmetric positive semi-definite).
List<double>? _solveDense(List<List<double>> a, List<double> b, int n) {
  for (var i = 0; i < n; i++) {
    var best = i;
    for (var k = i + 1; k < n; k++) {
      if (a[k][i].abs() > a[best][i].abs()) best = k;
    }
    if (a[best][i].abs() < 1e-14) return null;
    final t = a[i];
    a[i] = a[best];
    a[best] = t;
    final tb = b[i];
    b[i] = b[best];
    b[best] = tb;
    for (var k = i + 1; k < n; k++) {
      final f = a[k][i] / a[i][i];
      if (f == 0) continue;
      for (var j = i; j < n; j++) {
        a[k][j] -= f * a[i][j];
      }
      b[k] -= f * b[i];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = b[i];
    for (var j = i + 1; j < n; j++) {
      s -= a[i][j] * x[j];
    }
    x[i] = s / a[i][i];
  }
  return x;
}

double _norm(List<double> v) {
  var s = 0.0;
  for (final e in v) {
    s += e * e;
  }
  return math.sqrt(s);
}

// ---------------------------------------------------------------------------
// solve
// ---------------------------------------------------------------------------
/// Drives all constraints to zero. [dragged] holds the (entity, point) under
/// the finger. It is a WISH, never a command: the constraints are hard, and the
/// dragged point keeps only as much of the cursor position as its remaining
/// freedom allows. Hard-pinning it instead (the old behaviour) let the drag
/// outvote the constraints — a "vertical" line went slanted and a grounded
/// point drifted off its anchor.
// ---------------------------------------------------------------------------
// libslvs (SolveSpace) path — real geometric constraint solver via FFI.
//
// The sketch is decomposed to points + point-indexed entities (a polyline
// becomes n points + n segments), handed to the native solver, and the
// solved coordinates written back. The result is then VERIFIED against the
// Dart residuals; if it doesn't check out (or the symbol isn't linked, or the
// sketch uses a feature the shim doesn't model), we return false and the
// caller falls back to the Dart Levenberg-Marquardt loop. This makes enabling
// libslvs strictly safe: the app can never end up worse than the Dart solver.
// ---------------------------------------------------------------------------
int _pkey(int e, int p) => e * 100000 + p;

/// For a tangent constraint between two entities of which at least one is an
/// arc (and none is a circle/spline): determines at WHICH end each arc meets
/// its partner, by comparing endpoint coordinates. Returns a bitfield for the
/// shim (bit 0: ents[0]'s arc joins at its END; bit 1: ents[1]'s arc likewise;
/// a line contributes 0), or null when an arc participant shares NO endpoint
/// with its partner — such a tangency has no anchor in libslvs and must stay
/// on the Dart solver.
int? _tangentSeamFlags(List<Geo> gs, Constraint c) {
  const tol = 1e-6;
  final e1 = c.ents[0], e2 = c.ents[1];
  List<Offset> ends(int e) {
    final g = gs[e];
    if (g.type == Geo.line) {
      return [getPt(g, 0), getPt(g, 1)];
    }
    return [getPt(g, 1), getPt(g, 2)]; // arc: start, end
  }

  final a = ends(e1), b = ends(e2);
  int? endOf(int e, List<Offset> own, List<Offset> other) {
    if (gs[e].type != Geo.arc) return 0; // lines carry no flag
    for (var i = 0; i < 2; i++) {
      for (final q in other) {
        if ((own[i] - q).distance <= tol) return i; // 0 = start, 1 = end
      }
    }
    return null; // no shared endpoint
  }

  final f1 = endOf(e1, a, b);
  final f2 = endOf(e2, b, a);
  if (f1 == null || f2 == null) return null;
  return f1 | (f2 << 1);
}

bool _trySolveWithSlvs(
    List<Geo> gs, List<Constraint> cs, Set<(int, int)> dragged) {
  final ffi = SlvsFfi.instance();
  if (ffi == null) {
    if (Log.every('slvs-unavail', 5000)) {
      Log.w('slvs', 'libslvs NOT linked — running on the Dart fallback solver');
    }
    return false;
  }
  // Bail on anything the shim doesn't model, so we never silently drop a
  // constraint: fall back to the Dart solver instead.
  for (final c in cs) {
    if (c.type == CType.smooth) {
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: CType.smooth is not modelled by the shim');
      }
      return false;
    }
    if (c.type == CType.pattern) {
      // sketch pattern elements (M35): the shim has no transform constraint,
      // so the whole sketch goes to the verified Dart LM solver.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: CType.pattern is LM-only');
      }
      return false;
    }
    if (c.type == CType.tangent &&
        c.ents.any((e) => e < gs.length && gs[e].type == Geo.polyline)) {
      // spline endpoint tangency (M29): the shim has no spline entity, so the
      // sketch goes to the verified Dart LM solver.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: tangent with spline is LM-only');
      }
      return false;
    }
    if (c.type == CType.tangent && c.ents.length >= 2) {
      // SolveSpace's tangencies are endpoint-anchored (ARC_LINE_TANGENT /
      // CURVE_CURVE_TANGENT). Anything they cannot express goes to the Dart
      // LM solver instead of being packed WRONG:
      //  * circles have no endpoints — libslvs has no free-radius line/circle
      //    tangency, and CURVE_CURVE_TANGENT ssasserts on a circle entity;
      //  * an arc tangency with NO shared endpoint has no anchor to pick.
      if (c.ents.any((e) => e < gs.length && gs[e].type == Geo.circle)) {
        if (Log.every('slvs-bail', 2000)) {
          Log.d('slvs', 'bail: circle tangency is LM-only (no endpoint '
              'anchor in libslvs)');
        }
        return false;
      }
      if (_tangentSeamFlags(gs, c) == null) {
        if (Log.every('slvs-bail', 2000)) {
          Log.d('slvs', 'bail: tangent without a shared endpoint is LM-only');
        }
        return false;
      }
    }
    if (c.type == CType.tangent && ffi.version < 3) {
      // Shim v3 introduced the seam-end flag. An older binary anchors every
      // tangency at the arc START — a wrong equation for end-side seams — so
      // do not feed it tangencies at all.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: tangent needs shim>=3, have ${ffi.version}');
      }
      return false;
    }
    if (c.type == CType.coincident &&
        c.pts.isNotEmpty &&
        c.ents.isNotEmpty &&
        c.ents[0] < gs.length &&
        gs[c.ents[0]].type == Geo.polyline) {
      // M123 — point on a polyline CARRIER (polygon edge, spline, ellipse,
      // gear). The shim has no such constraint, and a polyline is not an slvs
      // entity at all, so packing it as SH_PT_ON_LINE would hand the shim a
      // garbage entity id. Send the whole sketch to the verified Dart LM path
      // instead, exactly like the pattern constraint does — the bind is never
      // silently dropped.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: point-on-curve on a polyline is Dart-LM only');
      }
      return false;
    }
    if (c.type == CType.coincident &&
        c.pts.isNotEmpty &&
        c.ents.isNotEmpty &&
        c.ents[0] < gs.length &&
        (gs[c.ents[0]].type == Geo.circle || gs[c.ents[0]].type == Geo.arc) &&
        ffi.version < 4) {
      // point-on-curve packs to SLVS_C_PT_ON_CIRCLE, shim v4+
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: point-on-curve needs shim>=4, have ${ffi.version}');
      }
      return false;
    }
    if (c.type == CType.dimension &&
        !const ['dist', 'distx', 'disty', 'rad', 'dia', 'ang', 'pline']
            .contains(c.dimKind)) {
      // 'ang3' (3-point angle) and 'ang4' (edge/edge angle over four points)
      // land here on purpose: the shim has no point-based angle, so the
      // sketch goes to the verified Dart LM solver instead of
      // silently dropping the dimension.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: unsupported dimKind=${c.dimKind}');
      }
      return false;
    }
    if (c.type == CType.dimension &&
        c.dimKind == 'pline' &&
        ffi.version < 2) {
      // SH_PT_LINE_DIST needs shim v2; an older linked binary would treat the
      // record as an unknown code and DROP it — the residual verify would then
      // reject every solve. Bail up front instead.
      if (Log.every('slvs-bail', 2000)) {
        Log.d('slvs', 'bail: pline needs shim>=2, have ${ffi.version}');
      }
      return false;
    }
  }

  final s = SlvsSketch();
  final ptIndex = <int, int>{}; // (ent,pt) packed -> shim point index
  final entRef = <int, int>{}; //  dart entity index -> Sh.ent(kind, idx)

  for (var e = 0; e < gs.length; e++) {
    final g = gs[e];
    final ids = <int>[];
    for (var p = 0; p < ptCount(g); p++) {
      final q = getPt(g, p);
      // NB: a dragged point is NOT fixed. Hard-fixing it lets the drag override
      // the constraints (that is what bent "vertical" lines and pushed grounded
      // points off their anchor). It gets a SOFT SH_DRAGGED wish below instead.
      final gi = s.addPoint(q.dx, q.dy);
      ptIndex[_pkey(e, p)] = gi;
      ids.add(gi);
    }
    switch (g.type) {
      case Geo.line:
        entRef[e] = Sh.ent(1, s.addLine(ids[0], ids[1]));
        break;
      case Geo.circle:
        entRef[e] = Sh.ent(2, s.addCircle(ids[0], g.data[2]));
        break;
      case Geo.arc:
        entRef[e] = Sh.ent(3, s.addArc(ids[0], ids[1], ids[2], g.data[2]));
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        final closed = g.data[0] != 0;
        final segs = closed ? n : n - 1;
        for (var k = 0; k < segs; k++) {
          s.addLine(ids[k], ids[(k + 1) % n]);
        }
        break;
    }
  }

  // The projected center point (kProjCenter) has no slot in gs, so give libslvs
  // a real point at the origin, marked FIXED. Added lazily: sketches that never
  // touch the origin get exactly the system they got before. Without this the
  // coincidence would be dropped, the solved result would fail the Dart verify,
  // and every origin-snapped sketch would silently fall back to the Dart solver.
  int? originPt;
  int? pOf(PRef r) => r.ent < 0
      ? (originPt ??= s.addPoint(0, 0, fix: true))
      : ptIndex[_pkey(r.ent, r.pt)];
  int eOf(int dartEnt) => entRef[dartEnt] ?? 0;

  // The grip drag is a WISH, never a command: SolveSpace's WHERE_DRAGGED keeps
  // the point where the cursor put it only as far as the hard constraints allow.
  // A point with no freedom left simply does not move; one on a line slides
  // along it.
  for (final (e, p) in dragged) {
    final gi = ptIndex[_pkey(e, p)];
    if (gi != null) s.addCon(Sh.dragged, a: gi);
  }

  for (final c in cs) {
    if (c.driven) continue; // reference dimensions measure but don't drive
    switch (c.type) {
      case CType.coincident:
        if (c.pts.length >= 2) {
          final a = pOf(c.pts[0]), b = pOf(c.pts[1]);
          if (a != null && b != null) s.addCon(Sh.coincident, a: a, b: b);
        } else if (c.pts.isNotEmpty && c.ents.isNotEmpty) {
          final a = pOf(c.pts[0]);
          if (a != null) {
            final tgt = gs[c.ents[0]].type;
            if (tgt == Geo.circle || tgt == Geo.arc) {
              // shim v4: SLVS_C_PT_ON_CIRCLE (works for circles AND arcs)
              s.addCon(Sh.pointOnCircle, a: a, e1: eOf(c.ents[0]));
            } else if (tgt == Geo.line) {
              s.addCon(Sh.pointOnLine, a: a, e1: eOf(c.ents[0]));
            }
            // Anything else (a polyline carrier, M123) never reaches here —
            // _trySolveWithSlvs bailed on it above. Guarded rather than
            // defaulted: packing an unsupported carrier as a LINE would give
            // the shim a wrong equation instead of no solution.
          }
        }
        break;
      case CType.horizontal:
      case CType.vertical:
        final code = c.type == CType.horizontal ? Sh.horizontal : Sh.vertical;
        if (c.pts.length >= 2) {
          final a = pOf(c.pts[0]), b = pOf(c.pts[1]);
          if (a != null && b != null) s.addCon(code, a: a, b: b);
        } else if (c.ents.isNotEmpty) {
          s.addCon(code, e1: eOf(c.ents[0]));
        }
        break;
      case CType.parallel:
        if (c.ents.length >= 2) {
          s.addCon(Sh.parallel, e1: eOf(c.ents[0]), e2: eOf(c.ents[1]));
        }
        break;
      case CType.perpendicular:
        if (c.ents.length >= 2) {
          s.addCon(Sh.perpendicular, e1: eOf(c.ents[0]), e2: eOf(c.ents[1]));
        }
        break;
      case CType.collinear:
        if (c.ents.length >= 2) {
          s.addCon(Sh.collinear, e1: eOf(c.ents[0]), e2: eOf(c.ents[1]));
        }
        break;
      case CType.concentric:
        if (c.ents.length >= 2) {
          s.addCon(Sh.concentric, e1: eOf(c.ents[0]), e2: eOf(c.ents[1]));
        }
        break;
      case CType.equal:
        if (c.ents.length >= 2) {
          s.addCon(Sh.equal, e1: eOf(c.ents[0]), e2: eOf(c.ents[1]));
        }
        break;
      case CType.tangent:
        if (c.ents.length >= 2) {
          // seam flags precomputed; the bail block above guarantees non-null
          final flags = _tangentSeamFlags(gs, c) ?? 0;
          s.addCon(Sh.tangent,
              e1: eOf(c.ents[0]), e2: eOf(c.ents[1]), val: flags.toDouble());
        }
        break;
      case CType.midpoint:
        if (c.pts.isNotEmpty && c.ents.isNotEmpty) {
          final a = pOf(c.pts[0]);
          if (a != null) {
            s.addCon(Sh.midpoint, a: a, e1: eOf(c.ents[0]));
          }
        }
        break;
      case CType.symmetric:
        if (c.pts.length >= 2 && c.ents.isNotEmpty) {
          final a = pOf(c.pts[0]), b = pOf(c.pts[1]);
          if (a != null && b != null) {
            s.addCon(Sh.symmetric, a: a, b: b, e1: eOf(c.ents[0]));
          }
        }
        break;
      case CType.fix:
        for (final r in c.pts) {
          final gi = pOf(r);
          if (gi != null) s.fixed[gi] = 1;
        }
        for (final en in c.ents) {
          if (en < 0 || en >= gs.length) continue;
          for (var p = 0; p < ptCount(gs[en]); p++) {
            final gi = ptIndex[_pkey(en, p)];
            if (gi != null) s.fixed[gi] = 1;
          }
        }
        break;
      case CType.dimension:
        final v = c.value;
        if (v == null) break;
        switch (c.dimKind) {
          case 'dist':
          case 'distx':
          case 'disty':
            if (c.pts.length >= 2) {
              final a = pOf(c.pts[0]), b = pOf(c.pts[1]);
              if (a != null && b != null) {
                final code = c.dimKind == 'distx'
                    ? Sh.distX
                    : c.dimKind == 'disty'
                        ? Sh.distY
                        : Sh.distance;
                s.addCon(code, a: a, b: b, val: v);
              }
            }
            break;
          case 'rad':
            if (c.ents.isNotEmpty) {
              s.addCon(Sh.radius, e1: eOf(c.ents[0]), val: v);
            }
            break;
          case 'dia':
            if (c.ents.isNotEmpty) {
              s.addCon(Sh.diameter, e1: eOf(c.ents[0]), val: v);
            }
            break;
          case 'ang':
            if (c.ents.length >= 2) {
              s.addCon(Sh.angle,
                  e1: eOf(c.ents[0]), e2: eOf(c.ents[1]), val: v);
            }
            break;
          case 'pline':
            // pts = [point, line A, line B]; e1/e2 carry the RAW shim point
            // indices of A and B (the shim builds an ad-hoc line entity over
            // them, so this also works for polyline segments that never got
            // an SH_ENT line ref on the Dart side).
            if (c.pts.length >= 3) {
              final p = pOf(c.pts[0]);
              final a = pOf(c.pts[1]);
              final b = pOf(c.pts[2]);
              if (p != null && a != null && b != null) {
                s.addCon(Sh.ptLineDist, a: p, e1: a, e2: b, val: v);
              }
            }
            break;
        }
        break;
      case CType.smooth:
      case CType.pattern:
        return false; // already filtered, but keep the switch exhaustive
    }
  }

  final res = ffi.solve(s);
  // OKAY, or INCONSISTENT-meaning-redundant: libslvs collapses REDUNDANT_OKAY
  // (a converged solve) into INCONSISTENT. The residual verification further
  // down is the real gate, so a truly contradictory result still gets rejected.
  if (!res.usable) {
    Log.w('slvs',
        'solve unusable: result=${res.result} dof=${res.dof} '
        'failed=${res.failed} — falling back to the Dart solver');
    return false;
  }
  if (Log.every('slvs-ok', 200)) {
    Log.d('slvs', 'result=${res.result} dof=${res.dof} '
        'pts=${s.px.length} cons=${s.ct.length}');
  }

  // Rebuild geometry into a copy so we can verify before committing.
  final newGs = List<Geo>.from(gs);
  for (var e = 0; e < gs.length; e++) {
    final g = gs[e];
    Offset gp(int p) {
      final gi = ptIndex[_pkey(e, p)]!;
      return Offset(s.px[gi], s.py[gi]);
    }

    switch (g.type) {
      case Geo.line:
        final a = gp(0), b = gp(1);
        newGs[e] = g.withData([a.dx, a.dy, b.dx, b.dy]);
        break;
      case Geo.circle:
        final c = gp(0);
        final ci = entRef[e]! % 100000000;
        newGs[e] = g.withData([c.dx, c.dy, s.circR[ci]]);
        break;
      case Geo.arc:
        final c = gp(0), st = gp(1), en = gp(2);
        final rad = (st - c).distance;
        final a0 = math.atan2(st.dy - c.dy, st.dx - c.dx);
        final a1 = math.atan2(en.dy - c.dy, en.dx - c.dx);
        // Keep the 6th element (the reversed/CW flag). An arc is
        // [cx, cy, r, startAngle, endAngle, reversed]; the SolveSpace points go
        // in and come back in the same order (center, start, end), so the
        // winding is unchanged — but dropping data[5] here produced a 5-element
        // arc that paintGeo (which reads data[5]) threw on, blanking the canvas
        // mid-drag. That was the "circles/curves go invisible when dragging" bug.
        newGs[e] = g.withData(
            [c.dx, c.dy, rad, a0, a1, g.data.length > 5 ? g.data[5] : 0.0]);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        final d = <double>[g.data[0], g.data[1]];
        for (var p = 0; p < n; p++) {
          final q = gp(p);
          d.add(q.dx);
          d.add(q.dy);
        }
        // Keep everything AFTER the point block — same lesson as the arc case
        // above, one field further along. A gear is stored compactly as a
        // [closed, count, centre, handle] polyline FOLLOWED BY its parameter
        // block (module, teeth, angles...). Rebuilding the list from scratch
        // silently dropped that block, so gearParams() returned null and
        // gearCurve() fell back to its two-point line: the tooth contour
        // vanished the instant the solver ran. That is exactly why the gear
        // PREVIEW looked right (drawn before the solve) while the placed gear
        // showed nothing but its construction lines. The Newton path never had
        // the bug — it copies g.data and edits the points in place.
        if (g.data.length > 2 + 2 * n) {
          d.addAll(g.data.sublist(2 + 2 * n));
        }
        newGs[e] = g.withData(d);
        break;
    }
  }

  // Verify with the Dart residuals (driven dims contribute nothing, matching
  // the mapping). If the native result doesn't satisfy the constraints, bail.
  final off = _offsets(newGs);
  final x = _pack(newGs);
  final ctx = _Ctx();
  _prepare(newGs, off, x, cs, ctx);
  final r = _residuals(newGs, off, x, cs, ctx);
  final resid = r.isEmpty ? 0.0 : _norm(r);
  if (r.isNotEmpty && resid > 1e-4) {
    Log.w('slvs',
        'VERIFY FAILED residual=${resid.toStringAsExponential(2)} '
        '(> 1e-4) — discarding native result, falling back');
    Log.block('slvs', 'rejected native result', sketchDump(newGs, cs));
    return false;
  }
  // Never let a native result poison the sketch either.
  if (!allFinite(newGs)) {
    Log.e('slvs', 'native result is NON-FINITE — discarding');
    Log.block('slvs', 'rejected native result', sketchDump(newGs, cs));
    return false;
  }
  if (Log.every('slvs-verify', 500)) {
    Log.d('slvs', 'verify ok residual=${resid.toStringAsExponential(2)}');
  }

  for (var e = 0; e < gs.length; e++) {
    gs[e] = newGs[e];
  }
  return true;
}

/// Residual norm below which the constraints count as FULLY satisfied
/// (converged to machine precision, world units).
const _satisfied = 1e-6;

/// Residual norm below which a solve is "good enough to show / keep": the
/// geometry is visually correct even if the last LM step left sub-pixel
/// residuals. Above this the solver FAILED to hold the constraints for this
/// configuration (a diverged frame, a broken operation) and the result must
/// never reach the renderer or a commit. Good frames sit at ~1e-12; a
/// divergence is orders of magnitude larger, so this cleanly separates them.
const _renderable = 1e-2;

/// M123 — how many times one LM run may re-project its point-on-curve tangent
/// frames onto the real curve. Each pass costs a handful of curve samples and
/// normally two or three suffice (the perpendicular correction converges
/// quadratically); the cap only exists so a point that can never reach its
/// carrier terminates instead of alternating frame and step forever.
const _maxReprojections = 12;

/// LM iterations granted to each follow-up pass after a re-projection. The
/// correction is a short perpendicular hop, so it needs far fewer steps than
/// the first pass — and it keeps the worst case bounded.
const _reprojectIterations = 12;

/// Wraps every arc's start/end angle into (-2π, 2π] IN PLACE. Endpoints are
/// invariant (angles enter only through cos/sin), so this never moves
/// geometry — it only keeps the parameters canonical. Drag paths can leave
/// angles far outside one revolution (the device log showed -8.0..4.6 rad on a
/// slot cap), which stresses every later angle computation.
void normalizeArcAngles(List<Geo> gs) {
  double wrap(double a) {
    var v = a % (2 * math.pi);
    // keep the representative closest to zero for stable diffs
    if (v > math.pi) v -= 2 * math.pi;
    if (v < -math.pi) v += 2 * math.pi;
    return v;
  }

  for (var i = 0; i < gs.length; i++) {
    final g = gs[i];
    if (g.type != Geo.arc || g.data.length < 5) continue;
    final a0 = wrap(g.data[3]), a1 = wrap(g.data[4]);
    if (a0 == g.data[3] && a1 == g.data[4]) continue;
    final d = List<double>.from(g.data);
    d[3] = a0;
    d[4] = a1;
    gs[i] = g.withData(d);
  }
}

/// The residual norm of the ACTIVE (driving) constraints at the current packed
/// state. Driven/reference dimensions contribute nothing (residualCount == 0),
/// exactly like both solve paths, so this measures only what the solver must
/// actually hold.
double constraintResidualNorm(List<Geo> gs, List<Constraint> cs) {
  if (gs.isEmpty || cs.isEmpty) return 0;
  final off = _offsets(gs);
  final x = _pack(gs);
  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);
  final r = _residuals(gs, off, x, cs, ctx);
  return r.isEmpty ? 0 : _norm(r);
}

/// The residual norm of EACH constraint separately, in constraint order.
///
/// [constraintResidualNorm] answers "did the solve hold?" — a single number
/// that says a sketch is broken without saying WHERE. When a solve fails, the
/// only question that matters is which constraint it could not satisfy, and
/// that is this: walk the residual vector in the same order [_residuals]
/// builds it and take the norm of each constraint's own slice.
///
/// Driven/reference dimensions contribute no residuals and report 0, exactly
/// as they contribute nothing to the solve.
List<double> constraintResidualsPer(List<Geo> gs, List<Constraint> cs) {
  final out = List<double>.filled(cs.length, 0);
  if (gs.isEmpty || cs.isEmpty) return out;
  final off = _offsets(gs);
  final x = _pack(gs);
  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);
  final r = _residuals(gs, off, x, cs, ctx);
  var k = 0;
  for (var i = 0; i < cs.length; i++) {
    final n = residualCount(gs, cs[i]);
    if (n == 0) continue;
    var s = 0.0;
    for (var j = 0; j < n && k + j < r.length; j++) {
      s += r[k + j] * r[k + j];
    }
    out[i] = math.sqrt(s);
    k += n;
  }
  return out;
}

/// True when [gs] contains a DEGENERATE entity that Skia would drop silently
/// (blanking it) or draw as garbage: a zero-length line, a zero-sweep or
/// non-positive-radius arc, a non-positive-radius circle. This is the last line
/// of defence so a numeric mishap can never masquerade as "geometry vanished"
/// or "geometry drawn across everything". The real fix for any given case is
/// upstream (don't produce it); this only stops it from reaching the screen.
bool hasDegenerateGeometry(List<Geo> gs) => gs.any(isDegenerateGeo);

/// M203 — the same test, for ONE entity.
///
/// Split out because "is the whole sketch degenerate" turned out to be the
/// wrong question. See [newlyDegenerate].
bool isDegenerateGeo(Geo g) {
  double norm2pi(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  switch (g.type) {
    case Geo.line:
      final dx = g.data[2] - g.data[0], dy = g.data[3] - g.data[1];
      if (dx * dx + dy * dy < 1e-12) return true;
      break;
    case Geo.circle:
      if (!(g.data[2] > 1e-9)) return true;
      break;
    case Geo.arc:
      if (!(g.data[2] > 1e-9)) return true;
      final rev = g.data.length > 5 && g.data[5] != 0;
      final sweep =
          rev ? norm2pi(g.data[3] - g.data[4]) : norm2pi(g.data[4] - g.data[3]);
      // a true full circle is stored as a circle, so a ~0 or ~2π sweep on an
      // arc means the solve collapsed it
      if (sweep < 1e-6 || sweep > 2 * math.pi - 1e-6) return true;
      break;
    case Geo.polyline:
      break; // a collapsed segment is caught when it is used as a line
  }
  return false;
}

/// M203 — entities the SOLVE made degenerate: fine before, collapsed now.
///
/// "i cant drag around any point. it seems stuck somehow and buggy." The
/// device sketch held a rectangle with two ZERO-LENGTH sides, made by a 20 ms
/// tap bounce. Every drag frame after that logged "frame solve unsatisfied —
/// holding last good geometry" with a residual of 3.66e-9: the constraints
/// were satisfied to nine decimals and the solve was refused anyway, because
/// the gate asked whether the WHOLE sketch contained a degenerate entity. The
/// same gate rejected every new constraint as "cannot be satisfied".
///
/// So one bad shape froze the document, and nothing the user could do inside
/// it would thaw it — every repair is itself a solve.
///
/// The question is not "is anything degenerate" but "did this solve BREAK
/// something", which is the same continuity rule the branch-flip guard uses:
/// compare with the state the solve started from. M203 also stops such a shape
/// from being committed in the first place; this is what makes the sketches
/// that already contain one workable again.
List<int> newlyDegenerate(List<Geo> before, List<Geo> after) {
  final out = <int>[];
  for (var i = 0; i < after.length; i++) {
    if (!isDegenerateGeo(after[i])) continue;
    // Beyond the snapshot (an entity that was ADDED), or already broken before
    // the solve started: either way this solve is not what broke it.
    if (i >= before.length) continue;
    if (isDegenerateGeo(before[i])) continue;
    out.add(i);
  }
  return out;
}

/// The single number a COLLAPSE destroys: a line's length, an arc's or a
/// circle's radius. null for shapes with no such measure — a spline does not
/// collapse, it just gets smaller.
double? collapsibleSize(Geo g) {
  switch (g.type) {
    case Geo.line:
      if (g.data.length < 4) return null;
      final dx = g.data[2] - g.data[0], dy = g.data[3] - g.data[1];
      return math.sqrt(dx * dx + dy * dy);
    case Geo.arc:
    case Geo.circle:
      return g.data.length < 3 ? null : g.data[2].abs();
    default:
      return null;
  }
}

/// A gesture may not shrink an entity below this fraction of the size it had
/// when the gesture STARTED. Three orders of magnitude: no edit anyone means
/// crosses it, and a slot cap that has lost 99.9% of its radius is a line on
/// any screen at any zoom.
const double kGestureShrinkFloor = 1e-3;

/// M208 — entities THIS GESTURE destroyed: sound when the drag began, gone
/// now. "A slot shouldn't be able to become a line like this."
///
/// [newlyDegenerate] asks the same question of ONE solve, and that is what let
/// the slot through. A drag frame warm-starts from the previous frame, so once
/// a cap had reached radius zero every later frame compared against a
/// configuration that was already collapsed, found nothing newly broken, and
/// said yes — the shape stayed a line for the rest of the drag and the commit
/// wrote it to the document. Judging against the state the gesture started
/// from closes that: the collapse is measured against the sketch the user was
/// looking at when they put their finger down.
///
/// It keeps M203's promise for the same reason. That snapshot IS the committed
/// sketch, so an entity that was already collapsed before the drag began is
/// not blamed on the drag, and a document containing one stays editable.
///
/// The floor is relative and per-gesture ([kGestureShrinkFloor]), never
/// absolute: this refuses to destroy a shape in one drag, it never forbids a
/// size. Dragging something small is fine; dragging it to nothing is not.
List<int> collapsedSince(List<Geo> start, List<Geo> now) {
  final out = <int>[];
  for (var i = 0; i < now.length && i < start.length; i++) {
    if (start[i].type != now[i].type) continue; // not the same entity anymore
    if (isDegenerateGeo(start[i])) continue; // already broken; not this drag
    if (isDegenerateGeo(now[i])) {
      out.add(i);
      continue;
    }
    final s0 = collapsibleSize(start[i]), s1 = collapsibleSize(now[i]);
    if (s0 == null || s1 == null || !(s0 > 0)) continue;
    if (s1 < s0 * kGestureShrinkFloor) out.add(i);
  }
  return out;
}


/// Signed angular sweep of an arc: positive counter-clockwise, negative
/// clockwise, in (−2π, 2π). This — not the raw `reversed` flag — is what a
/// human means by "the shape of that arc".
double arcSweep(Geo g) {
  if (g.type != Geo.arc || g.data.length < 5) return 0;
  double norm2pi(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final rev = g.data.length > 5 && g.data[5] != 0;
  return rev ? -norm2pi(g.data[3] - g.data[4]) : norm2pi(g.data[4] - g.data[3]);
}

/// Two directions counted as PARALLEL: |sin| below this. 1e-2 is about 0.57°,
/// tight enough that a real corner never reads as parallel and loose enough
/// that a slot's rails still do while a drag frame is a few digits off exact.
const double _kParallelSin = 1e-2;

/// Arcs that ROUND A CORNER: tangent to two or more straight lines that
/// actually MEET at an angle. This is exactly the 2D fillet/chamfer family
/// (M36).
///
/// M208 — the "meet at an angle" half is not decoration, it is the whole
/// difference between a fillet and a SLOT CAP. A slot's cap is tangent to both
/// rails too, so counting tangent lines alone called every slot cap a corner
/// fillet and handed it to [flippedCornerFillets], which then rejected 565 of
/// 625 drag frames on the device ("it jumps around or doesnt move at all") and
/// refused a concentric the solver had already satisfied to 9.8e-10 ("it says
/// this constraint is not possible").
///
/// The rails of a slot are PARALLEL — implied by both caps being tangent to
/// both of them — and an arc tangent to two parallel lines has its centre on
/// their midline with the two tangent points diametrically opposite. Its sweep
/// is a half turn whichever way it is drawn, so there is no second branch to
/// walk onto and nothing for the guard to decide. Only lines that meet at a
/// corner give the tangency the two solutions (π − θ and π + θ) M196 is about.
Set<int> cornerFilletArcs(List<Geo> gs, List<Constraint> cs) {
  final tangentLines = <int, Set<int>>{};
  for (final c in cs) {
    if (c.type != CType.tangent || c.ents.length < 2) continue;
    for (var k = 0; k < 2; k++) {
      final arc = c.ents[k], other = c.ents[1 - k];
      if (arc < 0 || arc >= gs.length || other < 0 || other >= gs.length) {
        continue;
      }
      if (gs[arc].type == Geo.arc && gs[other].type == Geo.line) {
        tangentLines.putIfAbsent(arc, () => <int>{}).add(other);
      }
    }
  }
  return {
    for (final e in tangentLines.entries)
      if (_meetAtAnAngle(gs, e.value)) e.key
  };
}

/// Do at least two of these lines cross at a real angle (rather than all
/// running the same way, as a slot's two rails do)?
bool _meetAtAnAngle(List<Geo> gs, Set<int> lines) {
  if (lines.length < 2) return false;
  final dirs = <(double, double)>[];
  for (final i in lines) {
    final g = gs[i];
    if (g.data.length < 4) continue;
    final dx = g.data[2] - g.data[0], dy = g.data[3] - g.data[1];
    final len = math.sqrt(dx * dx + dy * dy);
    if (!(len > 1e-12)) continue; // collapsed line: no direction to compare
    dirs.add((dx / len, dy / len));
  }
  for (var i = 0; i < dirs.length; i++) {
    for (var j = i + 1; j < dirs.length; j++) {
      final cross = dirs[i].$1 * dirs[j].$2 - dirs[i].$2 * dirs[j].$1;
      if (cross.abs() > _kParallelSin) return true;
    }
  }
  return false;
}

/// M196 — corner fillets whose sweep crossed the HALF TURN during one solve.
///
/// The device report: a drag on a filleted rectangle produced "a shape which
/// should not be possible" — two R5 corners had become 270° lobes hanging off
/// the outline. The solver was not confused; it logged `verify ok
/// residual=2.51e-15`. Every coincidence, every tangency and both radius
/// dimensions held exactly. The configuration was simply the OTHER solution:
/// with the tangent point moved to the far side of the circle, the same
/// constraints describe an arc that goes the long way round.
///
/// That is the M188 lesson in a new place. A tangency has two branches, and a
/// drag walks continuously from one to the other through a degenerate pose; no
/// residual can see it, because both branches are exact. The only thing that
/// separates them is CONTINUITY — the arc you had a frame ago.
///
/// So this compares, and it is deliberately conservative: only an arc that was
/// a minor arc BEFORE and is a major arc AFTER counts as flipped. An arc that
/// is already major stays workable (some corners genuinely are), and no
/// absolute rule is imposed on shapes this does not understand.
///
/// M208 — and it must be CLEARLY minor before and CLEARLY major after. The
/// original margin was 1e-6 rad, which is fine for the 90° → 270° jump this
/// was written for and useless for an arc that lives ON the half turn: there,
/// the last digit of the solve decides whether the frame is a flip, so the
/// same drag was accepted and rejected at random. [kHalfTurnSlack] is the
/// width of the band in which "minor" and "major" stop being different shapes.
///
/// How far from a half turn an arc's sweep must be before calling it "minor"
/// or "major" means anything: ~2.9°. The flip this guards against is a quarter
/// turn or more, so nothing real is lost by ignoring the band.
const double kHalfTurnSlack = 0.05;

List<int> flippedCornerFillets(
    List<Geo> before, List<Geo> after, List<Constraint> cs) {
  if (before.length != after.length) return const [];
  final out = <int>[];
  for (final i in cornerFilletArcs(after, cs)) {
    if (i >= before.length || before[i].type != Geo.arc) continue;
    final s0 = arcSweep(before[i]).abs();
    final s1 = arcSweep(after[i]).abs();
    if (s0 < math.pi - kHalfTurnSlack && s1 > math.pi + kHalfTurnSlack) {
      out.add(i);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// projected geometry (M32 — Inventor's Project Geometry)
// ---------------------------------------------------------------------------
/// Span of a projected sketch AXIS line (long enough to act as an infinite
/// construction line at any sensible zoom, short enough not to break math).
const double kProjAxisSpan = 10000;

/// Rewrites every projection in [gs] from its CURRENT source: a projected
/// line mirrors the source line's endpoints, a projected axis is the fixed
/// long line through the projected center point. A broken projection (source
/// deleted) freezes where it is. Mutates [gs] in place, returns it.
List<Geo> syncProjections(List<Geo> gs) =>
    Perf.span('sketch.syncProjections', () => _syncProjections(gs));

List<Geo> _syncProjections(List<Geo> gs) {
  for (var i = 0; i < gs.length; i++) {
    final g = gs[i];
    if (!g.isProjection) continue;
    switch (g.proj) {
      case Geo.projAxisX:
        gs[i] = g.withData([-kProjAxisSpan, 0, kProjAxisSpan, 0]);
        break;
      case Geo.projAxisY:
        gs[i] = g.withData([0, -kProjAxisSpan, 0, kProjAxisSpan]);
        break;
      case Geo.projBroken:
        break; // frozen in place
      case Geo.projSolid:
        // Owned by syncSolidProjections(): the source is a 3D model edge and
        // re-projecting it needs the PartModel and the sketch plane, neither
        // of which the solver sees. It is still PINNED like every other
        // projection by _withProjectionPins below.
        break;
      default:
        final src = g.proj;
        if (src < 0 || src >= gs.length) break;
        if (g.projSeg >= 0 &&
            g.type == Geo.line &&
            gs[src].type == Geo.polyline) {
          // single projected EDGE of a polyline (a rectangle/polygon side,
          // M34): the projection is a LINE mirroring that segment's vertices
          final sg = gs[src];
          final n = sg.data[1].toInt();
          if (n >= 2 && g.projSeg < n) {
            final a = g.projSeg, b = (g.projSeg + 1) % n;
            gs[i] = g.withData([
              sg.data[2 + 2 * a],
              sg.data[3 + 2 * a],
              sg.data[2 + 2 * b],
              sg.data[3 + 2 * b],
            ]);
          }
        } else if (gs[src].type == g.type) {
          // whole-entity projection (M33): same-type copy, the data vector
          // transfers 1:1 (a spline/ellipse projection also carries the
          // source's spline TAG, applied at creation)
          gs[i] = g.withData(List.of(gs[src].data));
        }
    }
  }
  return gs;
}

/// The implicit constraints that PIN every projection where its source is:
/// Inventor's projected geometry is reference geometry — the solver must
/// never move it in the layer it was projected INTO (a dimension against it
/// drives the OTHER geometry instead). One fix per endpoint at the current
/// (synced) coordinates.
List<Constraint> _withProjectionPins(List<Geo> gs, List<Constraint> cs) {
  final out = List<Constraint>.of(cs);
  for (var i = 0; i < gs.length; i++) {
    final g = gs[i];
    if (!g.isProjection) continue;
    // fixing every point pins all params: line both ends; arc center + both
    // endpoints (which determine r and the sweep angles); polyline — plain,
    // spline or ellipse — every defining vertex. The circle's radius is the
    // one param no point-fix covers, so it gets a rad dimension on top.
    for (var p = 0; p < ptCount(g); p++) {
      final q = refPt(gs, PRef(i, p));
      out.add(Constraint(CType.fix, pts: [PRef(i, p)], anchors: [q.dx, q.dy]));
    }
    if (g.type == Geo.circle) {
      out.add(Constraint(CType.dimension,
          ents: [i], dimKind: 'rad', value: g.data[2]));
    }
  }
  return out;
}

/// Solves [gs] in place under [cs]. Returns true iff the result actually holds
/// the driving constraints (residual within [_renderable]), is finite, and did
/// not COLLAPSE anything that was intact when the solve started ([newlyDegenerate])
/// — i.e. iff it is safe to SHOW or COMMIT. M203: the last test is deliberately
/// about what this solve changed, not about the sketch's absolute state; a
/// document that already contains a collapsed entity must stay workable, or
/// nothing the user does inside it can ever repair it.
/// A false return means the caller is looking at a failed/diverged solve and
/// must fall back to its last-good state (the drag keeps the committed sketch;
/// a commit rolls the operation back). On non-finite/throw the pre-solve
/// snapshot is restored and false is returned.
bool solveConstraints(List<Geo> gs, List<Constraint> cs,
    {Set<(int, int)> dragged = const {}, int iterations = 80}) {
  final ok = _solveConstraintsInner(gs, cs,
      dragged: dragged, iterations: iterations);
  // ...and sync AGAIN afterwards: the pins hold each projection at its
  // source's PRE-solve position, so when the solve itself moves the source
  // (a dimension edit on the source layer) the projection would lag one
  // solve behind — snap it to where the source actually ended up.
  syncProjections(gs);
  return ok;
}

bool _solveConstraintsInner(List<Geo> gs, List<Constraint> cs,
    // 25 iterations left visibly unconverged residuals (~0.3% of the entity
    // size) on systems the slvs shim bails on — e.g. an ellipse whose axes
    // hang on symmetric constraints. 80 costs little (small dense systems,
    // and the loop exits early once err <= _satisfied) and converges those.
    {Set<(int, int)> dragged = const {}, int iterations = 80}) {
  if (gs.isEmpty) return true;
  // projections first: sync to their sources, then pin them there — every
  // call site (drags, dimension edits, redundancy checks) gets this for free
  syncProjections(gs);
  cs = _withProjectionPins(gs, cs);
  if (cs.isEmpty) return true;

  // The drag solves at ~60 Hz, so the routine lines are throttled. Anomalies
  // are never throttled.
  final chatty = Log.every('solve', 200);
  final snapshot = List<Geo>.from(gs);
  if (chatty) {
    Log.d(
        'solve',
        'start geo=${gs.length} cons=${cs.length} iters=$iterations '
        'slvs=${SlvsFfi.available} '
        'dragged={${dragged.map((d) => 'e${d.$1}.p${d.$2}').join(',')}}');
  }

  var path = '?';
  try {
    // Prefer the native SolveSpace solver; it self-verifies and returns false
    // (falling through to the Dart loop below) whenever it can't be trusted.
    if (_trySolveWithSlvs(gs, cs, dragged)) {
      path = 'slvs';
    } else if (dragged.isNotEmpty) {
      // Dart fallback. A drag is a WISH, never a command. Freezing the dragged
      // point turns an unreachable cursor position into a least-squares
      // compromise that bends the CONSTRAINTS instead of the drag. So: first
      // try to honour the cursor exactly; only if the constraints cannot hold
      // that way, drop the freeze and let the solver pull the sketch back onto
      // the constraint manifold — the point then slides along its real freedom.
      final before = List<Geo>.from(gs);
      if (_lm(gs, cs, dragged, iterations)) {
        path = 'lm-frozen';
      } else {
        for (var i = 0; i < gs.length; i++) {
          gs[i] = before[i];
        }
        _lm(gs, cs, const {}, iterations);
        path = 'lm-relaxed';
      }
    } else {
      _lm(gs, cs, const {}, iterations);
      path = 'lm';
    }
  } catch (err, st) {
    Log.e('solve', 'SOLVER THREW (path=$path)', err, st);
    Log.block('solve', 'sketch at throw', sketchDump(snapshot, cs));
    for (var i = 0; i < gs.length; i++) {
      gs[i] = snapshot[i];
    }
    return false;
  }

  // A solve must NEVER hand back garbage. NaN/Inf coordinates (or a
  // non-positive radius) make Skia drop the path silently, so the geometry just
  // vanishes from the screen while the app keeps running — which looks like a
  // rendering bug and is really a solver bug. Refuse the result, keep the last
  // good geometry, and dump everything needed to reproduce it.
  if (!allFinite(gs)) {
    Log.e('solve', 'NON-FINITE result via $path — REJECTED, keeping last good');
    Log.block('solve', 'input', sketchDump(snapshot, cs));
    Log.block('solve', 'rejected output', sketchDump(gs, cs));
    for (var i = 0; i < gs.length; i++) {
      gs[i] = snapshot[i];
    }
    return false;
  }
  // M196 — a finite, fully-satisfied result can still be the WRONG SOLUTION.
  // A corner fillet that turned into a 270° lobe holds every constraint it has
  // (the device log said residual=2.5e-15 while the shape was absurd), so
  // neither the residual below nor the finiteness check above can see it. Only
  // the previous frame can: an arc that rounded a corner a moment ago and now
  // goes the long way round has been walked onto the other branch of its
  // tangency. Refuse it and keep the last good geometry, exactly as for a
  // non-finite result — a drag that stops at the boundary is what "safe"
  // means here, and it is the only thing that stops the shape turning itself
  // inside out under the finger.
  final flipped = flippedCornerFillets(snapshot, gs, cs);
  if (flipped.isNotEmpty) {
    Log.w(
        'solve',
        'BRANCH FLIP via $path on arc(s) ${flipped.join(",")} — '
        'corner fillet went the long way round; REJECTED, keeping last good');
    Log.block('solve', 'rejected branch flip', sketchDump(gs, cs));
    for (var i = 0; i < gs.length; i++) {
      gs[i] = snapshot[i];
    }
    return false;
  }
  // Even a finite result can be WRONG: a rank-deficient or contradictory system
  // lets LM (or a rejected native result's fallback) settle far from the
  // constraint manifold — a 2.2×-radius arc, a zero-sweep cap. Those are finite,
  // so the check above passes, and they used to be rendered/committed as-is
  // (the "slot flickers, chamfer scrambles the sketch" bug). Report whether the
  // solve actually holds the constraints and is non-degenerate; the caller
  // decides whether to keep it. The geometry is left at the solver's best
  // effort so a caller that wants best-effort can still use it.
  final resid = constraintResidualNorm(gs, cs);
  // M203 — only degeneracy this solve CAUSED counts. A sketch that already
  // contains a collapsed entity must stay draggable and constrainable, or one
  // bad shape freezes the document for good.
  final broke = newlyDegenerate(snapshot, gs);
  final ok = resid <= _renderable && broke.isEmpty;
  if (broke.isNotEmpty && chatty) {
    Log.d('solve', 'collapsed by this solve: ${broke.join(",")}');
  }
  if (chatty) {
    Log.d(
        'solve',
        'done via $path maxAbs=${maxAbs(gs).toStringAsFixed(3)} '
        'resid=${resid.toStringAsExponential(2)} ok=$ok');
  }
  return ok;
}

/// M123 — re-projects ONLY the point-on-curve frames onto the curve at the
/// current parameters, leaving every other frozen decision alone.
///
/// The frame is a tangent-line linearisation, so a solve that moves the carrier
/// far leaves the bound point on the tangent instead of on the curve (off by
/// roughly d²/2R for a tangential slide d). Re-projecting inside the LM loop is
/// the standard cure: each window is smooth, and the sequence converges to the
/// real curve. This must NOT go through [_prepare] — the tangency branch there
/// is deliberately frozen once per SOLVE (re-deriving it per frame is what let
/// drags walk onto the other branch, M36/M37), and per-iteration would be
/// strictly worse.
///
/// Only the closest point and its tangent are re-measured — ONE curve sample.
/// The response weights are kept and re-normalised onto the new normal: they
/// describe how the curve answers a vertex move, which barely changes over the
/// short perpendicular hop a re-projection makes, and re-measuring them here
/// would put a dozen curve rebuilds on a path that runs several times per solve.
/// Returns true when something moved, i.e. the residuals must be recomputed.
bool _refreezeCurves(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx) {
  if (ctx.onCurve.isEmpty) return false;
  var moved = false;
  for (final i in ctx.onCurve.keys.toList()) {
    final c = cs[i];
    final old = ctx.onCurve[i]!;
    final q = _pointAt(gs, off, x, c.pts[0]);
    final hit =
        _closestOnChain(_curveSamples(_polyAt(gs, off, x, c.ents[0])), q);
    if (hit == null) continue;
    final (p0, nrm) = hit;
    // Re-normalise the kept weights onto the new normal, so a rigid carrier
    // move stays exact (they must sum to the normal itself).
    final w = List<double>.from(old.w);
    for (var axis = 0; axis < 2; axis++) {
      var sum = 0.0;
      for (var k = axis; k < w.length; k += 2) {
        sum += w[k];
      }
      final want = axis == 0 ? nrm.dx : nrm.dy;
      if (sum.abs() > 1e-9) {
        final f = want / sum;
        for (var k = axis; k < w.length; k += 2) {
          w[k] *= f;
        }
      }
    }
    ctx.onCurve[i] = _OnCurve(p0, nrm, old.base, w,
        [for (var k = 0; k < w.length; k++) x[old.base + k]]);
    moved = true;
  }
  return moved;
}

/// One Levenberg-Marquardt run; [frozen] points keep their parameters. Returns
/// true only when the constraints are actually SATISFIED at the end — a false
/// return means the caller must not keep this configuration.
bool _lm(List<Geo> gs, List<Constraint> cs, Set<(int, int)> frozen,
    int iterations) {
  final off = _offsets(gs);
  final total = off.last;
  if (total == 0) return true;

  final x = _pack(gs);
  final locked = List<bool>.filled(total, false);
  for (final (e, p) in frozen) {
    for (final i in paramsOfPoint(gs, off, e, p)) {
      if (i < total) locked[i] = true;
    }
  }
  final free = <int>[];
  for (var i = 0; i < total; i++) {
    if (!locked[i]) free.add(i);
  }
  if (free.isEmpty) return false;

  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);

  var r = _residuals(gs, off, x, cs, ctx);
  if (r.isEmpty) return true;
  var lambda = 1e-3;
  var err = _norm(r);
  // M123 — the inner LM loop minimises against the point-on-curve TANGENT
  // frames, which is not the same as landing on the curve: a carrier that moved
  // far leaves the bound point on the tangent, off the real curve by about
  // d^2/2R for a tangential slide d. So the whole loop runs in PASSES: converge,
  // re-project the frames onto the curve, converge again. The error a fresh
  // frame reports is the TRUE one and may be larger than what was just
  // minimised; the perpendicular correction converges quadratically, so two or
  // three passes are the norm.
  //
  // A sketch with no point-on-curve constraint runs exactly one pass —
  // _refreezeCurves returns false immediately — so nothing else changes.
  var budget = iterations;
  for (var pass = 0;; pass++) {
    for (var it = 0; it < budget && err > 1e-9; it++) {
      // numeric Jacobian
      final m = r.length, n = free.length;
      final j = List.generate(m, (_) => List<double>.filled(n, 0.0));
      for (var k = 0; k < n; k++) {
        final idx = free[k];
        final h = 1e-6 * (1 + x[idx].abs());
        final save = x[idx];
        x[idx] = save + h;
        final r2 = _residuals(gs, off, x, cs, ctx);
        x[idx] = save;
        for (var i = 0; i < m; i++) {
          j[i][k] = (r2[i] - r[i]) / h;
        }
      }
      // normal equations (JtJ + lambda*I) dx = -Jt r
      final jtj = List.generate(n, (_) => List<double>.filled(n, 0.0));
      final jtr = List<double>.filled(n, 0.0);
      for (var a = 0; a < n; a++) {
        for (var b = a; b < n; b++) {
          var s = 0.0;
          for (var i = 0; i < m; i++) {
            s += j[i][a] * j[i][b];
          }
          jtj[a][b] = s;
          jtj[b][a] = s;
        }
        var s = 0.0;
        for (var i = 0; i < m; i++) {
          s += j[i][a] * r[i];
        }
        jtr[a] = -s;
      }
      for (var a = 0; a < n; a++) {
        jtj[a][a] += lambda * (1 + jtj[a][a].abs());
      }
      final dx = _solveDense(jtj, jtr, n);
      if (dx == null) break;

      final saved = List<double>.from(x);
      for (var k = 0; k < n; k++) {
        x[free[k]] += dx[k];
      }
      final r2 = _residuals(gs, off, x, cs, ctx);
      final e2 = _norm(r2);
      if (e2 < err) {
        r = r2;
        err = e2;
        lambda = math.max(1e-9, lambda * 0.4);
      } else {
        for (var i = 0; i < total; i++) {
          x[i] = saved[i];
        }
        lambda *= 6;
        if (lambda > 1e9) break;
      }
    }
    // ---- end of one LM pass: re-project the curve frames and go again ----
    if (pass >= _maxReprojections) break;
    if (!_refreezeCurves(gs, off, x, cs, ctx)) break;
    r = _residuals(gs, off, x, cs, ctx);
    err = _norm(r);
    if (err <= _satisfied) break;
    // Let LM move again on the refreshed problem. Each follow-up pass gets a
    // small budget of its own — the first already had the full [iterations].
    lambda = 1e-3;
    budget = _reprojectIterations;
  }
  _unpack(gs, off, x);
  final ok = err <= _satisfied;
  if (Log.every(ok ? 'lm-ok' : 'lm-fail', 300)) {
    Log.d(
        'lm',
        'frozen={${frozen.map((f) => 'e${f.$1}.p${f.$2}').join(',')}} '
        'params=$total free=${free.length} eqs=${r.length} '
        'maxIters=$iterations err=${err.toStringAsExponential(2)} '
        'satisfied=$ok');
  }
  return ok;
}

/// Rank analysis: degrees of freedom + which points can still move.
SketchAnalysis analyzeSketch(List<Geo> gs, List<Constraint> cs) {
  // projected geometry is pinned reference geometry: the same implicit fixes
  // the solver uses, so projections count as fully defined (white/yellow,
  // never draggable — the drag block runs on freePoints from this analysis)
  cs = _withProjectionPins(gs, cs);
  final off = _offsets(gs);
  final total = off.last;
  if (total == 0) return const SketchAnalysis(0, {});
  final x = _pack(gs);
  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);
  final r = _residuals(gs, off, x, cs, ctx);

  Set<(int, int)> allPoints() {
    final s = <(int, int)>{};
    for (var e = 0; e < gs.length; e++) {
      for (var p = 0; p < ptCount(gs[e]); p++) {
        s.add((e, p));
      }
    }
    return s;
  }

  Set<(int, int)> allCarriers() {
    final s = <(int, int)>{};
    for (var e = 0; e < gs.length; e++) {
      for (var seg = 0; seg < carrierSegCount(gs[e]); seg++) {
        s.add((e, seg));
      }
    }
    return s;
  }

  if (r.isEmpty) return SketchAnalysis(total, allPoints(), allCarriers());

  final m = r.length;
  final j = List.generate(m, (_) => List<double>.filled(total, 0.0));
  for (var k = 0; k < total; k++) {
    final h = 1e-6 * (1 + x[k].abs());
    final save = x[k];
    x[k] = save + h;
    final r2 = _residuals(gs, off, x, cs, ctx);
    x[k] = save;
    for (var i = 0; i < m; i++) {
      j[i][k] = (r2[i] - r[i]) / h;
    }
  }
  final (rank, pivots) = _rankAndPivots(j, m, total); // j is now RREF
  final dof = total - rank;
  if (dof <= 0) return const SketchAnalysis(0, {}, {});

  // null space: every non-pivot column spawns a basis vector; a parameter is
  // still movable if it appears in one of them. The basis vectors themselves
  // are kept (not just the booleans): the carrier test below needs the
  // DIRECTION a point can move in, not merely that it can move — a movable
  // endpoint that only slides ALONG its own line is a free length, and
  // Inventor still paints that line fully constrained.
  final pivotSet = pivots.toSet();
  final movable = List<bool>.filled(total, false);
  final basis = <List<double>>[];
  for (var freeCol = 0; freeCol < total; freeCol++) {
    if (pivotSet.contains(freeCol)) continue;
    movable[freeCol] = true;
    // RREF row: x_pivot + sum(j[row][c] * x_c) = 0 over the free columns c,
    // so the basis vector for freeCol carries -j[row][freeCol] at each pivot.
    final v = List<double>.filled(total, 0.0);
    v[freeCol] = 1.0;
    for (var row = 0; row < pivots.length; row++) {
      final coeff = j[row][freeCol];
      if (coeff.abs() > 1e-9) {
        v[pivots[row]] = -coeff;
        if (coeff.abs() > 1e-6) movable[pivots[row]] = true;
      }
    }
    basis.add(v);
  }
  final pts = <(int, int)>{};
  for (var e = 0; e < gs.length; e++) {
    for (var p = 0; p < ptCount(gs[e]); p++) {
      if (paramsOfPoint(gs, off, e, p).any((i) => movable[i])) {
        pts.add((e, p));
      }
    }
  }

  // ---- carrier analysis (Inventor's entity colouring) --------------------
  // Every null-space vector is one first-order motion the sketch can still
  // make. A carrier is loose iff SOME motion changes it:
  //   line/edge a->b : loose iff an endpoint moves PERPENDICULAR to the edge
  //                    (that changes direction and/or offset; motion purely
  //                    along the edge is a free length and stays white),
  //   circle/arc     : loose iff center or radius moves (free arc sweep
  //                    angles are the arc's endpoints, separate entities),
  //   spline/ellipse : loose iff any defining point moves (the curve IS its
  //                    control/fit points).
  const tol = 1e-5;
  bool edgeMoves(List<double> v, double vmax, int oa, int ob) {
    final ax = x[oa], ay = x[oa + 1], bx = x[ob], by = x[ob + 1];
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    final t = tol * vmax;
    if (len < 1e-9) {
      // degenerate edge: any motion of either endpoint counts
      return v[oa].abs() > t || v[oa + 1].abs() > t ||
          v[ob].abs() > t || v[ob + 1].abs() > t;
    }
    final pa = (dx * v[oa + 1] - dy * v[oa]) / len; // perp displacement of a
    final pb = (dx * v[ob + 1] - dy * v[ob]) / len; // perp displacement of b
    return pa.abs() > t || pb.abs() > t;
  }

  final loose = <(int, int)>{};
  for (final v in basis) {
    var vmax = 0.0;
    for (final c in v) {
      if (c.abs() > vmax) vmax = c.abs();
    }
    if (vmax < 1e-12) continue;
    for (var e = 0; e < gs.length; e++) {
      final g = gs[e];
      final o = off[e];
      switch (g.type) {
        case Geo.line:
          if (!loose.contains((e, 0)) && edgeMoves(v, vmax, o, o + 2)) {
            loose.add((e, 0));
          }
          break;
        case Geo.circle:
        case Geo.arc: // carrier = (cx, cy, r); params o..o+2
          if (!loose.contains((e, 0)) &&
              (v[o].abs() > tol * vmax ||
                  v[o + 1].abs() > tol * vmax ||
                  v[o + 2].abs() > tol * vmax)) {
            loose.add((e, 0));
          }
          break;
        case Geo.polyline:
          final n = g.data[1].toInt();
          if (n < 2) break;
          if (g.isSpline) {
            if (loose.contains((e, 0))) break;
            for (var i = 0; i < 2 * n; i++) {
              if (v[o + i].abs() > tol * vmax) {
                loose.add((e, 0));
                break;
              }
            }
            break;
          }
          final edges = g.data[0] != 0 ? n : n - 1;
          for (var seg = 0; seg < edges; seg++) {
            if (loose.contains((e, seg))) continue;
            final oa = o + 2 * seg;
            final ob = o + 2 * ((seg + 1) % n);
            if (edgeMoves(v, vmax, oa, ob)) loose.add((e, seg));
          }
          break;
      }
    }
  }
  return SketchAnalysis(dof, pts, loose);
}

/// True if [candidate] adds no new independent equation — Inventor rejects
/// such a geometric constraint and offers a driven dimension instead.
bool wouldOverconstrain(
    List<Geo> gs, List<Constraint> cs, Constraint candidate) {
  final added = residualCount(gs, candidate);
  if (added == 0) return false;
  int rankOf(List<Constraint> list) {
    final off = _offsets(gs);
    final total = off.last;
    final x = _pack(gs);
    final ctx = _Ctx();
    _prepare(gs, off, x, list, ctx);
    final r = _residuals(gs, off, x, list, ctx);
    if (r.isEmpty || total == 0) return 0;
    final j = List.generate(r.length, (_) => List<double>.filled(total, 0.0));
    for (var k = 0; k < total; k++) {
      final h = 1e-6 * (1 + x[k].abs());
      final save = x[k];
      x[k] = save + h;
      final r2 = _residuals(gs, off, x, list, ctx);
      x[k] = save;
      for (var i = 0; i < r.length; i++) {
        j[i][k] = (r2[i] - r[i]) / h;
      }
    }
    return _rankAndPivots(j, r.length, total).$1;
  }

  final before = rankOf(cs);
  final after = rankOf([...cs, candidate]);
  return after - before < added;
}
