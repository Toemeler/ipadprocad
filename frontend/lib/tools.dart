// iPadProCAD — Create-tool geometry. ONE source of truth used both by the
// commit path (AppState.toolClick) and the live preview (viewport painter),
// so what you see while drawing is exactly what lands in the document.
//
// All output is expressed in the backend's four primitives (line, circle,
// arc, polyline). Splines / ellipses / equation curves are sampled to
// polylines because the QCAD core is built with splines deferred
// (R_NO_OPENNURBS, see HANDOFF); the sampling density is high enough that
// they render and export smoothly.
import 'dart:math' as math;
import 'dart:ui';

import 'app_state.dart' show Tool, arcFrom3Points;
import 'ffi/qcad_engine.dart';

/// Per-tool metadata: how many picks commit the tool. `fixed` == null means
/// a variable-length tool (splines): commit via Enter once >= `minVar`.
class ToolMeta {
  final int? fixed;
  final int minVar;
  const ToolMeta.fixedPts(int this.fixed) : minVar = 0;
  const ToolMeta.variable(this.minVar) : fixed = null;
}

const toolMeta = <Tool, ToolMeta>{
  Tool.line: ToolMeta.fixedPts(2),
  Tool.lineMid: ToolMeta.fixedPts(2),
  Tool.splineCV: ToolMeta.variable(3),
  Tool.splineInterp: ToolMeta.variable(2),
  Tool.eqCurve: ToolMeta.fixedPts(1),
  Tool.bridge: ToolMeta.fixedPts(2),
  Tool.circleCenter: ToolMeta.fixedPts(2),
  Tool.circleTangent: ToolMeta.fixedPts(3),
  Tool.ellipse: ToolMeta.fixedPts(3),
  Tool.arcThreePoint: ToolMeta.fixedPts(3),
  Tool.arcTangent: ToolMeta.fixedPts(2),
  Tool.arcCenter: ToolMeta.fixedPts(3),
  Tool.rectTwoPoint: ToolMeta.fixedPts(2),
  Tool.rect3P: ToolMeta.fixedPts(3),
  Tool.rect2PC: ToolMeta.fixedPts(2),
  Tool.rect3PC: ToolMeta.fixedPts(3),
  Tool.slotCC: ToolMeta.fixedPts(3),
  Tool.slotOverall: ToolMeta.fixedPts(3),
  Tool.slotCP: ToolMeta.fixedPts(3),
  Tool.slot3A: ToolMeta.fixedPts(4),
  Tool.slotCPA: ToolMeta.fixedPts(4),
  Tool.polygon: ToolMeta.fixedPts(2),
  Tool.fillet: ToolMeta.fixedPts(2),
  Tool.chamfer: ToolMeta.fixedPts(2),
  Tool.point: ToolMeta.fixedPts(1),
};

/// Builds the geometry for [t] given picked points [p] (world coords).
/// Returns null while the input is insufficient/invalid. [existing] is the
/// sketch geometry (for tangent/fillet hit-testing), [params]/[expr] carry
/// dialog inputs (polygon sides, fillet radius, equation, ...).
List<Geo>? buildToolGeometry(Tool t, List<Offset> p,
    {List<Geo> existing = const [],
    Map<String, double> params = const {},
    String expr = ''}) {
  switch (t) {
    case Tool.none:
      return null;
    case Tool.line:
      if (p.length < 2) return null;
      return [_line(p[0], p[1])];
    case Tool.lineMid:
      // pick midpoint, then one endpoint -> mirror for the other endpoint
      if (p.length < 2) return null;
      final a = p[1], b = p[0] * 2 - p[1];
      return [_line(a, b)];
    case Tool.splineCV:
      if (p.length < 3) return null;
      return [_spline(p, Geo.splineCv)];
    case Tool.splineInterp:
      if (p.length < 2) return null;
      return [_spline(p, Geo.splineFit)];
    case Tool.eqCurve:
      if (p.isEmpty) return null;
      final f = ExprParser(expr).parse();
      if (f == null) return null;
      final x0 = params['x0'] ?? 0, x1 = params['x1'] ?? 10;
      if (!(x1 > x0)) return null;
      final n = 128;
      final pts = <Offset>[];
      for (var i = 0; i <= n; i++) {
        final x = x0 + (x1 - x0) * i / n;
        final y = f(x);
        if (!y.isFinite) return null;
        pts.add(p[0] + Offset(x, y));
      }
      return [_poly(pts, closed: false)];
    case Tool.bridge:
      if (p.length < 2) return null;
      final t0 = _tangentNear(existing, p[0], toward: p[1]);
      final t1 = _tangentNear(existing, p[1], toward: p[0]);
      return [_poly(_hermite(p[0], t0, p[1], t1), closed: false)];
    case Tool.circleCenter:
      if (p.length < 2) return null;
      final r = (p[1] - p[0]).distance;
      return r > 1e-9 ? [_circle(p[0], r)] : null;
    case Tool.circleTangent:
      // three picks, each selecting a LINE of the sketch; circle tangent to
      // all three (center = intersection of the click-side bisectors)
      if (p.length < 3) return null;
      final l1 = _lineNear(existing, p[0]),
          l2 = _lineNear(existing, p[1]),
          l3 = _lineNear(existing, p[2]);
      if (l1 == null || l2 == null || l3 == null) return null;
      final c = _tangentCircle3(l1, p[0], l2, p[1], l3, p[2]);
      return c == null ? null : [_circle(c.$1, c.$2)];
    case Tool.ellipse:
      // center, major-axis endpoint, minor extent — stored as a 3-vertex
      // polyline [center, major vertex, minor vertex] tagged Geo.ellipseTag,
      // the same mechanism splines use. The curve is generated Dart-side
      // (ellipseCurve); ONLY these three points are grips/snap targets —
      // Inventor's ellipse handles — instead of the old 96 sampled vertices
      // that each became a draggable, snappable, solver-free point.
      if (p.length < 3) return null;
      final u = p[1] - p[0];
      final a = u.distance;
      if (a < 1e-9) return null;
      final un = u / a;
      final vn = Offset(-un.dy, un.dx);
      final b = ((p[2] - p[0]).dx * vn.dx + (p[2] - p[0]).dy * vn.dy).abs();
      if (b < 1e-9) return null;
      return [
        _poly([p[0], p[1], p[0] + vn * b], closed: true)
            .asSpline(Geo.ellipseTag)
      ];
    case Tool.arcThreePoint:
      if (p.length < 3) return null;
      final arc = arcFrom3Points(p[0], p[1], p[2]);
      return arc == null ? null : [_arcT(arc)];
    case Tool.arcTangent:
      // first pick near an existing entity endpoint (tangent taken from it),
      // second pick = arc end
      if (p.length < 2) return null;
      final t0 = _tangentNear(existing, p[0], toward: p[1]);
      final s = _snapEndpoint(existing, p[0]) ?? p[0];
      final e = p[1];
      final d = e - s;
      final nrm = Offset(-t0.dy, t0.dx);
      final denom = 2 * (nrm.dx * d.dx + nrm.dy * d.dy);
      if (denom.abs() < 1e-9) return [_line(s, e)]; // tangent hits end: line
      final k = (d.dx * d.dx + d.dy * d.dy) / denom;
      final c = s + nrm * k;
      final r = k.abs();
      double ang(Offset q) => math.atan2(q.dy - c.dy, q.dx - c.dx);
      // sweep direction such that the tangent at s matches t0
      final ccwTan = Offset(-(s - c).dy, (s - c).dx);
      final ccw = (ccwTan.dx * t0.dx + ccwTan.dy * t0.dy) >= 0;
      return [
        Geo(Geo.arc, [c.dx, c.dy, r, ang(s), ang(e), ccw ? 0.0 : 1.0])
      ];
    case Tool.arcCenter:
      // center, start, end (CCW)
      if (p.length < 3) return null;
      final r = (p[1] - p[0]).distance;
      if (r < 1e-9) return null;
      double ang(Offset q) => math.atan2(q.dy - p[0].dy, q.dx - p[0].dx);
      return [
        Geo(Geo.arc, [p[0].dx, p[0].dy, r, ang(p[1]), ang(p[2]), 0.0])
      ];
    case Tool.rectTwoPoint:
      if (p.length < 2) return null;
      final a = p[0], b = p[1];
      return [
        _poly([a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)], closed: true)
      ];
    case Tool.rect3P:
      // corner A, corner B (first edge), extent C
      if (p.length < 3) return null;
      return _rectFromEdge(p[0], p[1], p[2]);
    case Tool.rect2PC:
      if (p.length < 2) return null;
      final d = p[1] - p[0];
      return [
        _poly([
          p[0] - d,
          p[0] + Offset(d.dx, -d.dy),
          p[0] + d,
          p[0] + Offset(-d.dx, d.dy)
        ], closed: true)
      ];
    case Tool.rect3PC:
      // center, edge-direction point, extent
      if (p.length < 3) return null;
      final u = p[1] - p[0];
      if (u.distance < 1e-9) return null;
      final un = u / u.distance;
      final vn = Offset(-un.dy, un.dx);
      final hw = u.distance;
      final hh = ((p[2] - p[0]).dx * vn.dx + (p[2] - p[0]).dy * vn.dy).abs();
      if (hh < 1e-9) return null;
      return [
        _poly([
          p[0] + un * hw + vn * hh,
          p[0] - un * hw + vn * hh,
          p[0] - un * hw - vn * hh,
          p[0] + un * hw - vn * hh
        ], closed: true)
      ];
    case Tool.slotCC:
      // arc-center 1, arc-center 2, width point
      if (p.length < 3) return null;
      final r = _distToSegment(p[2], p[0], p[1]);
      return _linearSlot(p[0], p[1], r);
    case Tool.slotOverall:
      // overall end 1, overall end 2, width point
      if (p.length < 3) return null;
      final r = _distToSegment(p[2], p[0], p[1]);
      final u = p[1] - p[0];
      final len = u.distance;
      if (r < 1e-9 || len <= 2 * r) return null;
      final un = u / len;
      return _linearSlot(p[0] + un * r, p[1] - un * r, r);
    case Tool.slotCP:
      // slot center, one arc center, width point
      if (p.length < 3) return null;
      final c2 = p[1], c1 = p[0] * 2 - p[1];
      final r = _distToSegment(p[2], c1, c2);
      return _linearSlot(c1, c2, r);
    case Tool.slot3A:
      // three points on the centre arc, then width point
      if (p.length < 4) return null;
      final arc = arcFrom3Points(p[0], p[1], p[2]);
      if (arc == null) return null;
      final r = ((p[3] - arc.$1).distance - arc.$2).abs();
      return _arcSlot(arc, r);
    case Tool.slotCPA:
      // arc center, arc start-center, arc end-center, width point
      if (p.length < 4) return null;
      final rr = (p[1] - p[0]).distance;
      if (rr < 1e-9) return null;
      double ang(Offset q) => math.atan2(q.dy - p[0].dy, q.dx - p[0].dx);
      final arc = (p[0], rr, ang(p[1]), ang(p[2]), false);
      final r = ((p[3] - p[0]).distance - rr).abs();
      return _arcSlot(arc, r);
    case Tool.polygon:
      if (p.length < 2) return null;
      final n = (params['sides'] ?? 6).round().clamp(3, 64);
      final r = (p[1] - p[0]).distance;
      if (r < 1e-9) return null;
      final a0 = math.atan2(p[1].dy - p[0].dy, p[1].dx - p[0].dx);
      final pts = List<Offset>.generate(
          n,
          (i) => p[0] +
              Offset(math.cos(a0 + 2 * math.pi * i / n),
                      math.sin(a0 + 2 * math.pi * i / n)) *
                  r);
      return [_poly(pts, closed: true)];
    case Tool.fillet:
      if (p.length < 2) return null;
      return _filletChamfer(existing, p[0], p[1],
          radius: params['radius'] ?? 5, chamfer: false);
    case Tool.chamfer:
      if (p.length < 2) return null;
      return _filletChamfer(existing, p[0], p[1],
          radius: params['dist'] ?? 5, chamfer: true);
    case Tool.point:
      if (p.isEmpty) return null;
      // sketch point: rendered/exported as a tiny circle marker
      return [_circle(p[0], 0.35)];
    default:
      return null; // modify tools have their own click pipeline
  }
}

// ---------------------------------------------------------------------------
// primitive constructors
// ---------------------------------------------------------------------------
Geo _line(Offset a, Offset b) => Geo(Geo.line, [a.dx, a.dy, b.dx, b.dy]);
Geo _circle(Offset c, double r) => Geo(Geo.circle, [c.dx, c.dy, r]);
Geo _arcT((Offset, double, double, double, bool) a) =>
    Geo(Geo.arc, [a.$1.dx, a.$1.dy, a.$2, a.$3, a.$4, a.$5 ? 1.0 : 0.0]);
Geo _poly(List<Offset> pts, {required bool closed}) => Geo(Geo.polyline, [
      closed ? 1.0 : 0.0,
      pts.length.toDouble(),
      for (final q in pts) ...[q.dx, q.dy]
    ]);

/// Build a spline: a polyline of the control/fit points tagged [kind]
/// (Geo.splineCv or Geo.splineFit). If the user snapped the last point back
/// onto the first, close it (drop the duplicate) so the curve meets up — that
/// is how a spline ends on its own start point.
Geo _spline(List<Offset> ptsIn, int kind) {
  final pts = List<Offset>.from(ptsIn);
  var closed = false;
  if (pts.length >= 3 && (pts.first - pts.last).distance < 1e-6) {
    pts.removeLast();
    closed = true;
  }
  return _poly(pts, closed: closed).asSpline(kind);
}

// ---------------------------------------------------------------------------
// curves
// ---------------------------------------------------------------------------
List<Offset> _hermite(Offset p0, Offset t0, Offset p1, Offset t1,
    {int n = 48}) {
  final scale = (p1 - p0).distance;
  final m0 = t0 * scale, m1 = t1 * scale;
  return [
    for (var i = 0; i <= n; i++) _hermitePt(p0, m0, p1, m1, i / n)
  ];
}

Offset _hermitePt(Offset p0, Offset m0, Offset p1, Offset m1, double t) {
  final t2 = t * t, t3 = t2 * t;
  return p0 * (2 * t3 - 3 * t2 + 1) +
      m0 * (t3 - 2 * t2 + t) +
      p1 * (-2 * t3 + 3 * t2) +
      m1 * (t3 - t2);
}

// ---------------------------------------------------------------------------
// hit-testing against existing geometry
// ---------------------------------------------------------------------------
const _snap = 8.0; // world units — generous, sketches are unit-scale for now

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (p - a).distance;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Nearest LINE entity to [p] (as endpoint pair), or null.
(Offset, Offset)? _lineNear(List<Geo> geos, Offset p) {
  (Offset, Offset)? best;
  var bd = double.infinity;
  for (final g in geos) {
    if (g.type != Geo.line) continue;
    final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
    final d = _distToSegment(p, a, b);
    if (d < bd) {
      bd = d;
      best = (a, b);
    }
  }
  return bd <= _snap * 4 ? best : null; // lines may be picked from afar
}

/// Nearest entity ENDPOINT to [p], or null.
Offset? _snapEndpoint(List<Geo> geos, Offset p) {
  Offset? best;
  var bd = _snap;
  void check(Offset q) {
    final d = (p - q).distance;
    if (d < bd) {
      bd = d;
      best = q;
    }
  }

  for (final g in geos) {
    switch (g.type) {
      case Geo.line:
        check(Offset(g.data[0], g.data[1]));
        check(Offset(g.data[2], g.data[3]));
        break;
      case Geo.arc:
        final c = Offset(g.data[0], g.data[1]);
        check(c + Offset(math.cos(g.data[3]), math.sin(g.data[3])) * g.data[2]);
        check(c + Offset(math.cos(g.data[4]), math.sin(g.data[4])) * g.data[2]);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        if (n > 0) {
          check(Offset(g.data[2], g.data[3]));
          check(Offset(g.data[2 + 2 * (n - 1)], g.data[3 + 2 * (n - 1)]));
        }
        break;
    }
  }
  return best;
}

/// Unit tangent at the entity endpoint nearest [p], oriented toward
/// [toward]; falls back to the straight direction if nothing snaps.
Offset _tangentNear(List<Geo> geos, Offset p, {required Offset toward}) {
  Offset fallback() {
    final d = toward - p;
    return d.distance < 1e-9 ? const Offset(1, 0) : d / d.distance;
  }

  Offset? bestT;
  var bd = _snap;
  void consider(Offset end, Offset tan) {
    final d = (p - end).distance;
    if (d < bd) {
      bd = d;
      bestT = tan / tan.distance;
    }
  }

  for (final g in geos) {
    switch (g.type) {
      case Geo.line:
        final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
        consider(a, b - a);
        consider(b, b - a);
        break;
      case Geo.arc:
        final c = Offset(g.data[0], g.data[1]);
        for (final ang in [g.data[3], g.data[4]]) {
          final end = c + Offset(math.cos(ang), math.sin(ang)) * g.data[2];
          consider(end, Offset(-math.sin(ang), math.cos(ang)));
        }
        break;
    }
  }
  if (bestT == null) return fallback();
  // orient the tangent so the curve leaves toward the other pick
  final f = fallback();
  return (bestT!.dx * f.dx + bestT!.dy * f.dy) >= 0 ? bestT! : -bestT!;
}

// ---------------------------------------------------------------------------
// constructions
// ---------------------------------------------------------------------------
List<Geo>? _rectFromEdge(Offset a, Offset b, Offset c) {
  final u = b - a;
  if (u.distance < 1e-9) return null;
  final un = u / u.distance;
  final vn = Offset(-un.dy, un.dx);
  final h = (c - a).dx * vn.dx + (c - a).dy * vn.dy;
  if (h.abs() < 1e-9) return null;
  final off = vn * h;
  return [
    _poly([a, b, b + off, a + off], closed: true)
  ];
}

List<Geo>? _linearSlot(Offset c1, Offset c2, double r) {
  final u = c2 - c1;
  final len = u.distance;
  if (r < 1e-9 || len < 1e-9) return null;
  final un = u / len;
  final vn = Offset(-un.dy, un.dx);
  final cap1 = arcFrom3Points(c1 + vn * r, c1 - un * r, c1 - vn * r);
  final cap2 = arcFrom3Points(c2 - vn * r, c2 + un * r, c2 + vn * r);
  if (cap1 == null || cap2 == null) return null;
  return [
    _line(c1 + vn * r, c2 + vn * r),
    _line(c2 - vn * r, c1 - vn * r),
    _arcT(cap1),
    _arcT(cap2),
  ];
}

List<Geo>? _arcSlot((Offset, double, double, double, bool) arc, double r) {
  final (c, rr, a1, a2, rev) = arc;
  if (r < 1e-9 || rr - r < 1e-9) return null;
  Offset onArc(double a, double rad) =>
      c + Offset(math.cos(a), math.sin(a)) * rad;
  // outward tangent direction at each end (away from the other end)
  final revF = rev ? 1.0 : -1.0;
  Offset tangent(double a, double sign) =>
      Offset(-math.sin(a), math.cos(a)) * sign * revF;
  final capA = arcFrom3Points(
      onArc(a1, rr + r), onArc(a1, rr) + tangent(a1, 1) * r, onArc(a1, rr - r));
  final capB = arcFrom3Points(
      onArc(a2, rr - r), onArc(a2, rr) + tangent(a2, -1) * r, onArc(a2, rr + r));
  if (capA == null || capB == null) return null;
  return [
    Geo(Geo.arc, [c.dx, c.dy, rr + r, a1, a2, rev ? 1.0 : 0.0]),
    Geo(Geo.arc, [c.dx, c.dy, rr - r, a1, a2, rev ? 1.0 : 0.0]),
    _arcT(capA),
    _arcT(capB),
  ];
}

/// Circle tangent to three picked lines; the pick points choose the side of
/// each line the circle lies on.
(Offset, double)? _tangentCircle3((Offset, Offset) l1, Offset h1,
    (Offset, Offset) l2, Offset h2, (Offset, Offset) l3, Offset h3) {
  // signed distance of q to infinite line (a,b), positive on hint side
  (Offset, double, double)? norm((Offset, Offset) l, Offset hint) {
    final d = l.$2 - l.$1;
    if (d.distance < 1e-9) return null;
    var n = Offset(-d.dy, d.dx) / d.distance;
    var c0 = n.dx * l.$1.dx + n.dy * l.$1.dy;
    if (n.dx * hint.dx + n.dy * hint.dy - c0 < 0) {
      n = -n;
      c0 = -c0;
    }
    return (n, c0, 0.0);
  }

  final a = norm(l1, h1), b = norm(l2, h2), c = norm(l3, h3);
  if (a == null || b == null || c == null) return null;
  // solve: n_i . p - r = c_i  (equal positive distance r on hint side)
  // 3 eqs, unknowns (px, py, r)
  final m = [
    [a.$1.dx, a.$1.dy, -1.0, a.$2],
    [b.$1.dx, b.$1.dy, -1.0, b.$2],
    [c.$1.dx, c.$1.dy, -1.0, c.$2],
  ];
  // gaussian elimination
  for (var i = 0; i < 3; i++) {
    var piv = i;
    for (var j = i + 1; j < 3; j++) {
      if (m[j][i].abs() > m[piv][i].abs()) piv = j;
    }
    if (m[piv][i].abs() < 1e-12) return null;
    final tmp = m[i];
    m[i] = m[piv];
    m[piv] = tmp;
    for (var j = i + 1; j < 3; j++) {
      final f = m[j][i] / m[i][i];
      for (var k2 = i; k2 < 4; k2++) {
        m[j][k2] -= f * m[i][k2];
      }
    }
  }
  final x = List<double>.filled(3, 0);
  for (var i = 2; i >= 0; i--) {
    var s = m[i][3];
    for (var j = i + 1; j < 3; j++) {
      s -= m[i][j] * x[j];
    }
    x[i] = s / m[i][i];
  }
  return x[2] > 1e-9 ? (Offset(x[0], x[1]), x[2]) : null;
}

/// Nearest LINE entity INDEX (fillet/chamfer must edit the originals).
int? _lineNearIdx(List<Geo> geos, Offset p) {
  var best = -1;
  var bd = _snap * 4;
  for (var i = 0; i < geos.length; i++) {
    if (geos[i].type != Geo.line) continue;
    final d = _distToSegment(p, Offset(geos[i].data[0], geos[i].data[1]),
        Offset(geos[i].data[2], geos[i].data[3]));
    if (d < bd) {
      bd = d;
      best = i;
    }
  }
  return best < 0 ? null : best;
}

/// Fillet/chamfer INCLUDING Inventor's automatic trim: the two picked lines
/// are shortened back to the tangent points. Returns the geometry to add and
/// the replacements for the picked lines (by entity index).
(List<Geo>, Map<int, Geo>)? filletChamferFull(
    List<Geo> geos, Offset h1, Offset h2,
    {required double radius, required bool chamfer}) {
  final i1 = _lineNearIdx(geos, h1), i2 = _lineNearIdx(geos, h2);
  if (i1 == null || i2 == null || i1 == i2) return null;
  final made = _filletChamfer(geos, h1, h2, radius: radius, chamfer: chamfer);
  if (made == null || made.isEmpty) return null;
  // the ends of the new arc/chamfer line ARE the tangent points
  final g0 = made.first;
  late final Offset t1, t2;
  if (g0.type == Geo.line) {
    t1 = Offset(g0.data[0], g0.data[1]);
    t2 = Offset(g0.data[2], g0.data[3]);
  } else {
    final c = Offset(g0.data[0], g0.data[1]);
    t1 = c + Offset(math.cos(g0.data[3]), math.sin(g0.data[3])) * g0.data[2];
    t2 = c + Offset(math.cos(g0.data[4]), math.sin(g0.data[4])) * g0.data[2];
  }
  Geo trim(int idx, Offset tp) {
    final g = geos[idx];
    final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
    // the endpoint nearer the tangent point is the one inside the corner.
    // withData keeps the picked line on ITS layer — a fillet must not move it.
    return (a - tp).distance <= (b - tp).distance
        ? g.withData([tp.dx, tp.dy, b.dx, b.dy])
        : g.withData([a.dx, a.dy, tp.dx, tp.dy]);
  }

  // match each tangent point to the line it belongs to
  final g1 = geos[i1];
  final d1a = _distToSegment(t1, Offset(g1.data[0], g1.data[1]),
      Offset(g1.data[2], g1.data[3]));
  final d1b = _distToSegment(t2, Offset(g1.data[0], g1.data[1]),
      Offset(g1.data[2], g1.data[3]));
  final tp1 = d1a <= d1b ? t1 : t2;
  final tp2 = d1a <= d1b ? t2 : t1;
  // the new arc/chamfer inherits the layer of the lines it joins
  final onLayer = [for (final g in made) g.onLayer(g1.layer)];
  return (onLayer, {i1: trim(i1, tp1), i2: trim(i2, tp2)});
}

/// Fillet arc / chamfer line between the two picked lines.
List<Geo>? _filletChamfer(List<Geo> geos, Offset h1, Offset h2,
    {required double radius, required bool chamfer}) {
  final l1 = _lineNear(geos, h1), l2 = _lineNear(geos, h2);
  if (l1 == null || l2 == null || radius < 1e-9) return null;
  // intersection of the infinite lines
  final p = l1.$1, r = l1.$2 - l1.$1, q = l2.$1, s2 = l2.$2 - l2.$1;
  final den = r.dx * s2.dy - r.dy * s2.dx;
  if (den.abs() < 1e-12) return null; // parallel
  final t = ((q - p).dx * s2.dy - (q - p).dy * s2.dx) / den;
  final ix = p + r * t;
  // unit directions from the corner toward the pick side of each line
  Offset dirTo(Offset hint, Offset d) {
    final dn = d / d.distance;
    return ((hint - ix).dx * dn.dx + (hint - ix).dy * dn.dy) >= 0 ? dn : -dn;
  }

  final d1 = dirTo(h1, r), d2 = dirTo(h2, s2);
  final cosA = (d1.dx * d2.dx + d1.dy * d2.dy).clamp(-1.0, 1.0);
  final ang = math.acos(cosA);
  if (ang < 1e-6 || (math.pi - ang) < 1e-6) return null;
  if (chamfer) {
    return [_line(ix + d1 * radius, ix + d2 * radius)];
  }
  final setback = radius / math.tan(ang / 2);
  final p1 = ix + d1 * setback, p2 = ix + d2 * setback;
  final bis = (d1 + d2) / (d1 + d2).distance;
  final center = ix + bis * (radius / math.sin(ang / 2));
  final mid = center - bis * radius;
  final arc = arcFrom3Points(p1, mid, p2);
  return arc == null ? null : [_arcT(arc)];
}

// ---------------------------------------------------------------------------
// tiny expression parser for the Equation Curve: numbers, x, + - * / ^,
// parentheses, sin cos tan asin acos atan sqrt abs exp ln log, pi, e.
// ---------------------------------------------------------------------------
class ExprParser {
  final String src;
  int _i = 0;
  ExprParser(this.src);

  double Function(double x)? parse() {
    try {
      final f = _expr();
      _ws();
      if (_i != src.length) return null;
      f(1.0); // probe
      return f;
    } catch (_) {
      return null;
    }
  }

  void _ws() {
    while (_i < src.length && src[_i] == ' ') {
      _i++;
    }
  }

  bool _eat(String s) {
    _ws();
    if (src.startsWith(s, _i)) {
      _i += s.length;
      return true;
    }
    return false;
  }

  double Function(double) _expr() {
    var f = _term();
    while (true) {
      if (_eat('+')) {
        final g = _term();
        final h = f;
        f = (x) => h(x) + g(x);
      } else if (_eat('-')) {
        final g = _term();
        final h = f;
        f = (x) => h(x) - g(x);
      } else {
        return f;
      }
    }
  }

  double Function(double) _term() {
    var f = _pow();
    while (true) {
      if (_eat('*')) {
        final g = _pow();
        final h = f;
        f = (x) => h(x) * g(x);
      } else if (_eat('/')) {
        final g = _pow();
        final h = f;
        f = (x) => h(x) / g(x);
      } else {
        return f;
      }
    }
  }

  double Function(double) _pow() {
    final f = _unary();
    if (_eat('^')) {
      final g = _pow(); // right assoc
      return (x) => math.pow(f(x), g(x)).toDouble();
    }
    return f;
  }

  double Function(double) _unary() {
    if (_eat('-')) {
      final f = _unary();
      return (x) => -f(x);
    }
    _eat('+');
    return _atom();
  }

  static const _fns = <String, double Function(double)>{
    'asin': _asin, 'acos': _acos, 'atan': _atan,
    'sin': math.sin, 'cos': math.cos, 'tan': math.tan,
    'sqrt': math.sqrt, 'abs': _abs, 'exp': _exp, 'ln': math.log, 'log': _log10,
  };
  static double _asin(double v) => math.asin(v);
  static double _acos(double v) => math.acos(v);
  static double _atan(double v) => math.atan(v);
  static double _abs(double v) => v.abs();
  static double _exp(double v) => math.exp(v);
  static double _log10(double v) => math.log(v) / math.ln10;

  double Function(double) _atom() {
    _ws();
    if (_eat('(')) {
      final f = _expr();
      if (!_eat(')')) throw const FormatException();
      return f;
    }
    for (final e in _fns.entries) {
      final save = _i;
      if (_eat(e.key)) {
        if (_eat('(')) {
          final f = _expr();
          if (!_eat(')')) throw const FormatException();
          return (x) => e.value(f(x));
        }
        _i = save;
      }
    }
    if (_eat('pi')) return (_) => math.pi;
    final saveE = _i;
    if (_eat('e')) {
      if (_i >= src.length || !RegExp(r'[a-zA-Z0-9.]').hasMatch(src[_i])) {
        return (_) => math.e;
      }
      _i = saveE;
    }
    if (_eat('x')) return (x) => x;
    final m = RegExp(r'\d+(\.\d+)?').matchAsPrefix(src, _i);
    if (m == null) throw const FormatException();
    _i = m.end;
    final v = double.parse(m[0]!);
    return (_) => v;
  }
}
