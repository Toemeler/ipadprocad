// iPadProCAD — the sketch solver.
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
import 'ffi/qcad_engine.dart';

/// Result of the rank analysis of a sketch.
class SketchAnalysis {
  final int dof;
  final Set<(int, int)> freePoints; // (entity, point) still able to move
  const SketchAnalysis(this.dof, this.freePoints);
  bool get fullyConstrained => dof == 0;
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
    gs[e] = Geo(g.type, d);
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
}

bool _active(Constraint c) => !c.driven;

/// Number of equations a constraint contributes (0 = ignored).
int residualCount(List<Geo> gs, Constraint c) {
  if (!_active(c)) return 0;
  bool ent(int i) => i < c.ents.length && c.ents[i] < gs.length;
  bool pt(int i) => i < c.pts.length && c.pts[i].ent < gs.length;
  switch (c.type) {
    case CType.coincident:
      return pt(0) && pt(1) ? 2 : 0;
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
      return ent(0) && ent(1) ? 1 : 0;
    case CType.smooth:
      // G2 = tangency + equal curvature (only meaningful for two arcs)
      if (!ent(0) || !ent(1)) return 0;
      final a = gs[c.ents[0]].type, b = gs[c.ents[1]].type;
      final curved = (a == Geo.arc || a == Geo.circle) &&
          (b == Geo.arc || b == Geo.circle);
      return curved ? 2 : 1;
    case CType.symmetric:
      return pt(0) && pt(1) && ent(0) && gs[c.ents[0]].type == Geo.line ? 2 : 0;
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
        case 'ang':
          return ent(0) && ent(1) ? 1 : 0;
      }
      return 0;
  }
}

void _prepare(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx) {
  for (var i = 0; i < cs.length; i++) {
    final c = cs[i];
    if (residualCount(gs, c) == 0) continue;
    switch (c.type) {
      case CType.tangent:
      case CType.smooth:
        final c1 = _circle(gs, off, x, c.ents[0]);
        final c2 = _circle(gs, off, x, c.ents[1]);
        if (c1 != null && c2 != null) {
          final d = (c2.$1 - c1.$1).distance;
          final outer = c1.$2 + c2.$2;
          final inner = (c1.$2 - c2.$2).abs();
          ctx.mode[i] = (d - outer).abs() <= (d - inner).abs() ? 1 : 0;
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
        final a = _pointAt(gs, off, x, c.pts[0]);
        final b = _pointAt(gs, off, x, c.pts[1]);
        r.add(a.dx - b.dx);
        r.add(a.dy - b.dy);
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
    }
  }
  return r;
}

void _tangentResiduals(List<Geo> gs, List<int> off, List<double> x,
    List<Constraint> cs, _Ctx ctx, int i, Constraint c, List<double> r) {
  final t1 = gs[c.ents[0]].type, t2 = gs[c.ents[1]].type;
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
  r.add(dist.abs() - cc.$2);
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
  }
}

// ---------------------------------------------------------------------------
// linear algebra (dense, small systems)
// ---------------------------------------------------------------------------
/// Rank of [m] (rows x cols) by Gaussian elimination with partial pivoting.
/// Also returns the pivot columns.
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
/// Drives all constraints to zero. [pinned] holds (entity, point) pairs whose
/// parameters must not move (the point under the finger while dragging).
void solveConstraints(List<Geo> gs, List<Constraint> cs,
    {Set<(int, int)> pinned = const {}, int iterations = 25}) {
  if (cs.isEmpty || gs.isEmpty) return;
  final off = _offsets(gs);
  final total = off.last;
  if (total == 0) return;

  final x = _pack(gs);
  final frozen = List<bool>.filled(total, false);
  for (final (e, p) in pinned) {
    for (final i in paramsOfPoint(gs, off, e, p)) {
      if (i < total) frozen[i] = true;
    }
  }
  final free = <int>[];
  for (var i = 0; i < total; i++) {
    if (!frozen[i]) free.add(i);
  }
  if (free.isEmpty) return;

  final ctx = _Ctx();
  _prepare(gs, off, x, cs, ctx);

  var r = _residuals(gs, off, x, cs, ctx);
  if (r.isEmpty) return;
  var lambda = 1e-3;
  var err = _norm(r);

  for (var it = 0; it < iterations && err > 1e-9; it++) {
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
  _unpack(gs, off, x);
}

/// Rank analysis: degrees of freedom + which points can still move.
SketchAnalysis analyzeSketch(List<Geo> gs, List<Constraint> cs) {
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

  if (r.isEmpty) return SketchAnalysis(total, allPoints());

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
  if (dof <= 0) return const SketchAnalysis(0, {});

  // null space: every non-pivot column spawns a basis vector; a parameter is
  // still movable if it appears in one of them.
  final pivotSet = pivots.toSet();
  final movable = List<bool>.filled(total, false);
  for (var freeCol = 0; freeCol < total; freeCol++) {
    if (pivotSet.contains(freeCol)) continue;
    movable[freeCol] = true;
    for (var row = 0; row < pivots.length; row++) {
      if (j[row][freeCol].abs() > 1e-6) movable[pivots[row]] = true;
    }
  }
  final pts = <(int, int)>{};
  for (var e = 0; e < gs.length; e++) {
    for (var p = 0; p < ptCount(gs[e]); p++) {
      if (paramsOfPoint(gs, off, e, p).any((i) => movable[i])) {
        pts.add((e, p));
      }
    }
  }
  return SketchAnalysis(dof, pts);
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
