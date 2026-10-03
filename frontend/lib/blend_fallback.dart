// Exact rounds for the edges OCCT's blend cannot build.
//
// OCCT's BRepFilletAPI walks a rolling ball along the edge and has to close
// it off at both ends against whatever meets there. On bodies Inventor rounds
// without a second thought it gives up -- or returns a "solid" with a 28 mm
// tolerance and the wrong volume, which the shim rightly refuses. Seen on an
// imported Inventor part: a plain 90° inner corner, 35 mm long, ending flush
// on two flat faces, would not round at ANY radius down to 0.5 mm.
//
// For the commonest edges no rolling ball is needed at all. A round of
// radius r on a straight edge between two flat faces is a constant cross-
// section -- the corner of the angle between the faces minus the inscribed
// circle -- swept along the edge: a prism. On a circular edge where a flat
// face meets a cylinder square to it, the same section swept around the
// cylinder's axis: a revolve. Added to the body at an inner (concave) edge,
// cut from it at an outer (convex) one. Both sweeps are exact, so the result
// is the surface Inventor builds; where the edge ends on a flat face the
// sweep is trimmed by that face's plane, which is where Inventor stops the
// round too.
//
// What this does NOT do: the spherical patch where three rounds meet at a
// corner (here the sweeps simply overlap), or any edge on a curved face other
// than the cylinder case above. Those stay with OCCT, and if OCCT cannot
// build them they stay unbuilt -- reported, never faked.
import 'dart:math' as math;

import 'ffi/occt_engine.dart';
import 'log.dart';

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double s) => _V(x * s, y * s, z * s);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get len => math.sqrt(dot(this));
  _V get unit => this * (1 / len);
}

class _Face {
  final int type; // 0 plane, 1 cylinder (occt_capi.h per-face record)
  final _V p, n; // plane: point, OUTWARD normal; cylinder: axis point, axis
  final double radius;
  _Face(this.type, this.p, this.n, this.radius);
}

/// One swept round, ready to combine with the body.
class _Sweep {
  final OcctShape tool;
  final bool add; // concave: fuse; convex: cut
  final double volume;
  _Sweep(this.tool, this.add, this.volume);
}

/// Exact rounds for [topoIds] (with [radii]) on the body whose display mesh
/// is [m] and whose edges are [edges] (for their convexity), applied to
/// [target]. Returns the new shape and which edges it rounded, or null when
/// it could not round any of them.
(OcctShape, List<bool>)? exactRoundFallback(OcctFfi ffi, OcctShape target,
    OcctMeshData m, List<OcctEdgeInfo> edges, List<int> topoIds, List<double> radii) {
  final built = List<bool>.filled(topoIds.length, false);
  final sweeps = <_Sweep>[];
  final conv = {for (final e in edges) e.index: e.convexity};
  try {
    for (var k = 0; k < topoIds.length; k++) {
      final c = conv[topoIds[k]] ?? 0;
      if (c == 0) continue; // a smooth or unknown edge: not a corner to round
      final s = _sweepFor(ffi, m, topoIds[k], radii[k], c);
      if (s == null) continue;
      sweeps.add(s);
      built[k] = true;
    }
    if (sweeps.isEmpty) return null;
    final v0 = target.volume;
    var cur = target;
    var expected = 0.0;
    for (final add in [true, false]) {
      for (final s in sweeps.where((s) => s.add == add)) {
        final next = add ? ffi.fuse(cur, s.tool) : ffi.cut(cur, s.tool);
        if (!identical(cur, target)) cur.dispose();
        if (next == null) return null;
        cur = next;
        expected += add ? s.volume : -s.volume;
      }
    }
    // A round adds (inner corner) or removes (outer corner) exactly its
    // sweep. Rounds that meet at a corner overlap, so the change can fall
    // short of the sum -- never past it, and never the other way.
    final got = cur.volume - v0;
    final ok = cur.valid &&
        got * expected > 0 &&
        got.abs() <= expected.abs() * 1.02 + 1e-6 &&
        got.abs() >= expected.abs() * 0.6;
    if (!ok) {
      Log.i('blend', 'exact rounds refused: valid=${cur.valid} '
          'volume change $got, expected $expected');
      if (!identical(cur, target)) cur.dispose();
      return null;
    }
    final unified = ffi.unify(cur);
    if (unified != null && unified.valid) {
      if (!identical(cur, target)) cur.dispose();
      cur = unified;
    } else {
      unified?.dispose();
    }
    return (cur, built);
  } finally {
    for (final s in sweeps) {
      s.tool.dispose();
    }
  }
}

/// A constant-radius round of [ids] on [shape], the way the app builds every
/// fillet: OCCT's blend first; whatever it cannot round, as exact sweeps where
/// the edge allows (see the top of this file). The whole set goes the exact
/// way when every edge of it can, so neighbouring rounds are built alike and
/// meet cleanly; otherwise only what OCCT dropped, on top of what it built.
/// [report] says which edges were left unbuilt. [mesh] is [shape]'s display
/// mesh when the caller has one. Null when nothing could be rounded.
OcctShape? roundEdges(OcctFfi ffi, OcctShape shape, List<int> ids, List<double> radii,
    {List<double> radii2 = const [], BlendReport? report, OcctMeshData? mesh}) {
  final rep = report ?? BlendReport();
  final out = shape.filletEdges(ids, radii, radii2: radii2, report: rep);
  if (radii2.any((r) => r > 0) || (out != null && rep.dropped.isEmpty)) return out;
  final occtErr = ffi.lastError();
  final m = mesh ?? shape.mesh(linDeflection: 0.2, angDeflection: 0.35);
  if (m == null) return out;
  final live = shape.allEdges();
  final all = exactRoundFallback(ffi, shape, m, live, ids, radii);
  if (all != null && all.$2.every((b) => b)) {
    out?.dispose();
    rep.dropped.clear();
    Log.i('blend', 'OCCT could not round ${ids.length} edge(s) as a set; '
        'built all of them as exact sweeps');
    return all.$1;
  }
  all?.$1.dispose();
  final failed = out == null ? List<int>.generate(ids.length, (i) => i) : List<int>.of(rep.dropped);
  final some = exactRoundFallback(ffi, out ?? shape, m, live,
      [for (final i in failed) ids[i]], [for (final i in failed) radii[i]]);
  if (some == null) {
    if (out == null) Log.w('blend', 'no round built: $occtErr');
    return out;
  }
  out?.dispose();
  final still = [
    for (var k = 0; k < failed.length; k++)
      if (!some.$2[k]) failed[k]
  ];
  rep.dropped
    ..clear()
    ..addAll(still);
  Log.i('blend', '${failed.length - still.length} of ${failed.length} edge(s) '
      'OCCT could not round built as exact sweeps'
      '${still.isEmpty ? '' : '; ${still.length} still not built'}');
  return some.$1;
}

_V _vec(List<double> a, int i) => _V(a[i], a[i + 1], a[i + 2]);

_Face _face(OcctMeshData m, int f) {
  final o = 15 * f;
  final i = m.faceInfos;
  return _Face(i[o].round(), _vec(i, o + 1), _vec(i, o + 4).unit, i[o + 10]);
}

/// Mesh vertices of face [f]: (position, outward normal).
Iterable<(_V, _V)> _faceVerts(OcctMeshData m, int f) sync* {
  for (var t = 0; t < m.triFaces.length; t++) {
    if (m.triFaces[t] != f) continue;
    for (var k = 0; k < 3; k++) {
      final v = m.indices[3 * t + k] * 3;
      yield (
        _V(m.positions[v], m.positions[v + 1], m.positions[v + 2]),
        _V(m.normals[v], m.normals[v + 1], m.normals[v + 2]),
      );
    }
  }
}

/// Whether face [f] reaches at least [r] away from the edge (measured by
/// [off]): a round wider than the face it lies on is not this construction.
bool _wideEnough(OcctMeshData m, int f, double Function(_V) off, double r) {
  // corners AND centroids: a flat disc is meshed from its rim alone, so its
  // corners say nothing about how far in it reaches
  var far = 0.0;
  var k = 0;
  var sum = const _V(0, 0, 0);
  for (final (p, _) in _faceVerts(m, f)) {
    far = math.max(far, off(p).abs());
    sum = sum + p;
    if (++k == 3) {
      far = math.max(far, off(sum * (1 / 3)).abs());
      k = 0;
      sum = const _V(0, 0, 0);
    }
  }
  return far >= r * (1 - 1e-6);
}

/// The cusp: corner (0, 0) of the angle between u (at 2D angle 0) and v (at
/// angle th), minus the circle of radius r tangent to both, as (x, y, bulge)
/// triplets in the (u, u-perp) frame.
List<double> _cusp(double th, double r) {
  final t = r / math.tan(th / 2);
  final bulge = math.tan(-(math.pi - th) / 4);
  return [0.0, 0.0, 0.0, t, 0.0, bulge, t * math.cos(th), t * math.sin(th), 0.0];
}

List<double> _mat(_V e1, _V e2, _V e3, _V o) => [
      e1.x, e2.x, e3.x, o.x, //
      e1.y, e2.y, e3.y, o.y,
      e1.z, e2.z, e3.z, o.z,
    ];

/// Faces other than [a] and [b] on the edges that touch [p].
List<int> _capFaces(OcctMeshData m, int self, _V p, int a, int b, double tol) {
  final out = <int>{};
  for (var j = 0; j < m.edgeCount; j++) {
    if (j == self) continue;
    final c = 16 * j;
    if (c + 16 > m.edgeCurves.length) break;
    final type = m.edgeCurves[c].round();
    final ends = <_V>[];
    if (type == 1) {
      ends.addAll([_vec(m.edgeCurves, c + 1), _vec(m.edgeCurves, c + 4)]);
    } else if (type == 2 || type == 3) {
      final ctr = _vec(m.edgeCurves, c + 1), xd = _vec(m.edgeCurves, c + 4), yd = _vec(m.edgeCurves, c + 7);
      final ra = m.edgeCurves[c + 10], rb = type == 3 ? m.edgeCurves[c + 11] : ra;
      final t0 = m.edgeCurves[c + (type == 3 ? 12 : 11)], t1 = m.edgeCurves[c + (type == 3 ? 13 : 12)];
      for (final t in [t0, t1]) {
        ends.add(ctr + xd * (ra * math.cos(t)) + yd * (rb * math.sin(t)));
      }
    } else {
      // a free-form edge: its ends are the first and last polyline points
      final s = m.edgeStarts[j], e = m.edgeStarts[j + 1];
      if (e - s < 2) continue;
      ends.addAll([_vec(m.edgePoints, 3 * s), _vec(m.edgePoints, 3 * (e - 1))]);
    }
    if (!ends.any((q) => (q - p).len < tol)) continue;
    for (final f in m.facesOfEdge(j)) {
      if (f != a && f != b) out.add(f);
    }
  }
  return out.toList();
}

/// The flat faces an edge ends on at [p] (planes across the edge's direction
/// [dir] there), or null when something else meets it there -- the round
/// then ends square at [p], which is right where it runs on into a tangent
/// neighbour.
List<(_V, _V)>? _caps(OcctMeshData m, int self, _V p, _V dir, List<int> fs, double tol) {
  final cf = _capFaces(m, self, p, fs[0], fs[1], tol);
  if (cf.isEmpty) return null;
  final out = <(_V, _V)>[];
  for (final f in cf) {
    final face = _face(m, f);
    if (face.type != 0 || face.n.dot(dir).abs() < 0.1) return null;
    out.add((p, face.n));
  }
  return out;
}

/// A half-space as a big box: everything behind plane (p, n), n outward.
OcctShape? _halfSpace(OcctFfi ffi, _V p, _V n, double size) {
  final a = (n.x.abs() < 0.9 ? const _V(1, 0, 0) : const _V(0, 1, 0)).cross(n).unit;
  final b = n.cross(a);
  final box = ffi.makeBox(size, size, size);
  if (box == null) return null;
  final o = p - a * (size / 2) - b * (size / 2) - n * size;
  final placed = box.transformed(_mat(a, b, n, o));
  box.dispose();
  return placed;
}

/// [tool] trimmed by the planes it must not pass; null when that fails.
OcctShape? _trim(OcctFfi ffi, OcctShape tool, List<(_V, _V)> caps, double size) {
  var cur = tool;
  for (final (p, n) in caps) {
    final hs = _halfSpace(ffi, p, n, size);
    if (hs == null) return null;
    final next = ffi.common(cur, hs);
    hs.dispose();
    if (!identical(cur, tool)) cur.dispose();
    if (next == null) return null;
    cur = next;
  }
  return identical(cur, tool) ? null : cur;
}

_Sweep? _sweepFor(OcctFfi ffi, OcctMeshData m, int topoId, double r, int convexity) {
  if (!(r > 0) || m.faceInfos.isEmpty || m.normals.length != m.positions.length) return null;
  var i = -1;
  for (var k = 0; k < m.edgeIds.length; k++) {
    if (m.edgeIds[k] == topoId) {
      i = k;
      break;
    }
  }
  if (i < 0 || 16 * i + 16 > m.edgeCurves.length) return null;
  final fs = m.facesOfEdge(i);
  if (fs.length != 2 || fs[0] == fs[1]) return null;
  final type = m.edgeCurves[16 * i].round();
  if (type == 1) return _lineSweep(ffi, m, i, fs, r, convexity);
  if (type == 2) return _arcSweep(ffi, m, i, fs, r, convexity);
  return null;
}

/// A straight edge between two flat faces: a prism.
_Sweep? _lineSweep(OcctFfi ffi, OcctMeshData m, int i, List<int> fs, double r, int c) {
  final fa = _face(m, fs[0]), fb = _face(m, fs[1]);
  if (fa.type != 0 || fb.type != 0) return null;
  final e = 16 * i;
  final p0 = _vec(m.edgeCurves, e + 1), p1 = _vec(m.edgeCurves, e + 4);
  final len = (p1 - p0).len;
  if (len < 1e-6) return null;
  final t = (p1 - p0).unit;
  // Which way each face runs away from the edge, from the faces themselves:
  // at an outer corner each face runs AGAINST the other's outward normal, at
  // an inner corner WITH it.
  var u = t.cross(fa.n).unit, v = t.cross(fb.n).unit;
  if (u.dot(fb.n) * c > 0) u = u * -1;
  if (v.dot(fa.n) * c > 0) v = v * -1;
  final th = math.acos(u.dot(v).clamp(-1.0, 1.0));
  if (th < 0.05 || th > math.pi - 0.05) return null; // flat or knife edge
  final reach = r / math.tan(th / 2);
  if (!_wideEnough(m, fs[0], (p) => (p - p0).dot(u), reach) ||
      !_wideEnough(m, fs[1], (p) => (p - p0).dot(v), reach)) {
    return null;
  }
  final loop = _cusp(th, r);
  final e2 = (v - u * u.dot(v)).unit;
  final n2 = u.cross(e2);
  final tol = 1e-4 * math.max(1.0, len);
  final caps0 = _caps(m, i, p0, t, fs, tol), caps1 = _caps(m, i, p1, t, fs, tol);
  final margin = 3 * (reach + r);
  final m0 = caps0 == null ? 0.0 : margin, m1 = caps1 == null ? 0.0 : margin;
  // the section's normal n2 is +t or -t; extrude along it from the right end
  final start = n2.dot(t) > 0 ? p0 - t * m0 : p1 + t * m1;
  final h = len + m0 + m1;
  final raw = ffi.extrudeProfileArcs([loop], h);
  if (raw == null) return null;
  final placed = raw.transformed(_mat(u, e2, n2, start));
  raw.dispose();
  if (placed == null) return null;
  final caps = [...?caps0, ...?caps1];
  var tool = placed;
  if (caps.isNotEmpty) {
    final trimmed = _trim(ffi, placed, caps, 4 * (h + 10 * r));
    placed.dispose();
    if (trimmed == null) return null;
    tool = trimmed;
  }
  return _Sweep(tool, c < 0, tool.volume);
}

/// A circular edge where a flat face meets a cylinder square to it: the same
/// section revolved about the cylinder's axis.
_Sweep? _arcSweep(OcctFfi ffi, OcctMeshData m, int i, List<int> fs, double r, int c) {
  final f0 = _face(m, fs[0]), f1 = _face(m, fs[1]);
  if (!((f0.type == 0 && f1.type == 1) || (f0.type == 1 && f1.type == 0))) return null;
  final pl = f0.type == 0 ? f0 : f1, cy = f0.type == 1 ? f0 : f1;
  final mPl = f0.type == 0 ? fs[0] : fs[1], mCy = f0.type == 1 ? fs[0] : fs[1];
  final e = 16 * i;
  final ctr = _vec(m.edgeCurves, e + 1), xd = _vec(m.edgeCurves, e + 4).unit, yd = _vec(m.edgeCurves, e + 7).unit;
  final bigR = m.edgeCurves[e + 10];
  final t0 = m.edgeCurves[e + 11];
  var t1 = m.edgeCurves[e + 12];
  final ax = xd.cross(yd).unit; // the circle's normal; t runs counter-clockwise about it
  final scale = math.max(1.0, bigR);
  if (ax.cross(cy.n).len > 1e-6 || ax.cross(pl.n).len > 1e-6) return null;
  if ((bigR - cy.radius).abs() > 1e-6 * scale) return null;
  final off = ctr - cy.p;
  if ((off - cy.n * off.dot(cy.n)).len > 1e-6 * scale) return null;
  if (t1 < t0) t1 += 2 * math.pi;
  final sweep = t1 - t0;
  if (sweep < 1e-6) return null;
  double radial(_V p) => ((p - ctr) - ax * (p - ctr).dot(ax)).len - bigR;
  double axial(_V p) => (p - ctr).dot(ax);
  // the cylinder's outward side: +1 when it faces away from the axis
  var eps = 0.0;
  var best = double.infinity;
  for (final (p, n) in _faceVerts(m, mCy)) {
    final d = radial(p).abs() + axial(p).abs() * 1e-3;
    final rv = (p - ctr) - ax * (p - ctr).dot(ax);
    if (rv.len < 1e-9 || d >= best) continue;
    best = d;
    eps = n.dot(rv.unit).sign;
  }
  if (eps == 0) return null;
  // In the section (x radial, y along the axis, corner at (R, 0)) the flat
  // face runs radially and the cylinder axially; the same rule as for a
  // straight edge picks which way each runs from the corner.
  final sCy = -(pl.n.dot(ax) * c).sign; // against / with the plane's normal
  final sPl = -(eps * c).sign; // against / with the cylinder's normal
  if (sCy == 0 || sPl == 0) return null;
  if (!_wideEnough(m, mPl, radial, r) || !_wideEnough(m, mCy, axial, r)) return null;
  if (sPl < 0 && bigR - r < 1e-6) return null; // the round would cross the axis
  // corner P, A along the flat face, B along the cylinder, arc A -> B
  final ccw = sPl * sCy > 0; // B lies counter-clockwise of A, seen from P
  final b = math.tan(math.pi / 8) * (ccw ? -1 : 1);
  final sec = [bigR, 0.0, 0.0, bigR + sPl * r, 0.0, b, bigR, sCy * r, 0.0];
  final tol = 1e-4 * scale;
  final ends = [for (final t in [t0, t1]) ctr + xd * (bigR * math.cos(t)) + yd * (bigR * math.sin(t))];
  final caps0 = _caps(m, i, ends[0], ax.cross((ends[0] - ctr).unit), fs, tol);
  final caps1 = _caps(m, i, ends[1], ax.cross((ends[1] - ctr).unit), fs, tol);
  final margin = math.min(0.5, 6 * r / bigR);
  final m0 = caps0 == null ? 0.0 : margin, m1 = caps1 == null ? 0.0 : margin;
  final a0 = t0 - m0, total = math.min(sweep + m0 + m1, 2 * math.pi);
  final x0 = (xd * math.cos(a0) + yd * math.sin(a0)).unit;
  final raw = ffi.revolveProfile([sec], total * 180 / math.pi, axPx: 0, axPy: 0, axDx: 0, axDy: 1);
  if (raw == null) return null;
  // local X radial at the start angle, Y the axis, Z = X x Y: a positive turn
  // about Y carries X towards Y x X, which is the arc's own direction
  final placed = raw.transformed(_mat(x0, ax, x0.cross(ax), ctr));
  raw.dispose();
  if (placed == null) return null;
  final caps = [...?caps0, ...?caps1];
  var tool = placed;
  if (caps.isNotEmpty) {
    final trimmed = _trim(ffi, placed, caps, 8 * (bigR + 10 * r));
    placed.dispose();
    if (trimmed == null) return null;
    tool = trimmed;
  }
  return _Sweep(tool, c < 0, tool.volume);
}
