// M279 — projecting a whole FACE, not one edge at a time.
//
// "Im Moment kann ich mit dem Projizieren-Tool in einer Skizze nur einzelne
// Kanten projizieren. In Inventor kann ich auch ganze Flächen auswählen um
// jede Kante dieser Fläche zu projizieren."
//
// ---------------------------------------------------------------------------
// What Inventor's Project Geometry actually accepts
// ---------------------------------------------------------------------------
//
// Edges, vertices, work features — and FACES. Picking a face projects every
// edge of its boundary: the outer loop and every inner loop, so a plate with
// four holes comes across as the outline plus four circles in one pick. That
// is the whole of what is added here. The projected curves are the same
// associative reference geometry a single edge produces, and they update and
// freeze by the same rules (see syncSolidProjections) — a face pick is a
// shorthand for a set of edge picks, not a second kind of projection.
//
// The neighbouring commands are deliberately NOT in scope: Project Cut Edges
// (the section where the sketch plane slices the part) and Project Flat
// Pattern are separate commands in Inventor too, and either would be a
// different milestone rather than a bigger version of this one.
//
// ---------------------------------------------------------------------------
// Where "the edges of this face" comes from
// ---------------------------------------------------------------------------
//
// NOT from the kernel, and that is worth writing down because the kernel is
// where it belongs. OCCT can answer edge -> faces exactly and cheaply
// (TopExp::MapShapesAndAncestors), but the shim does not expose it, and adding
// it means a new C entry point, a shim version bump and an ABI both sides have
// to agree on. So it is derived here from the mesh the app already holds, and
// the derivation is exact rather than approximate:
//
//   * `triFaces` says which B-Rep face each display triangle belongs to, so
//     the triangles of one face are a known set.
//   * inside that set, a triangle side used by exactly ONE triangle is on the
//     face's BOUNDARY; a side shared by two is interior to the face. This is
//     the standard boundary extraction and it needs no tolerance at all —
//     triangles of one face index into the same vertex array, so the test is
//     on integer pairs.
//   * a display edge belongs to the face when every point of its polyline is
//     one of those boundary vertices. Every point, not just the ends: an edge
//     of the NEIGHBOURING face touches this one at both ends and nowhere
//     between, and endpoints alone would take it too.
//
// The one place a tolerance is needed is matching the edge polyline's points
// to the triangulation's vertices, because they arrive in two separate buffers
// (`edgePoints` and `positions`). They are the same nodes — OCCT tessellates an
// edge and the faces meeting it from one polygon — so the quantisation only has
// to survive the round trip through two Float64 arrays.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'ffi/occt_engine.dart';
import 'part_model.dart';

/// Snaps a world point to a key, so the two buffers can be compared.
///
/// The scale is derived from the model rather than fixed: a 2 mm bookmark and
/// a 2 m frame cannot share an absolute epsilon, and a key coarser than the
/// smallest real feature would weld two distinct vertices into one.
int _key(double x, double y, double z, double q) {
  int c(double v) => (v / q).round();
  // Three 21-bit fields. A model would have to span two million quanta in one
  // axis to collide, which is far past anything this kernel meshes.
  return (c(x) & 0x1FFFFF) << 42 | (c(y) & 0x1FFFFF) << 21 | (c(z) & 0x1FFFFF);
}

/// The quantum for [_key]: fine enough to separate real vertices, coarse
/// enough to absorb a Float64 round trip.
double _quantumFor(OcctMeshData m) {
  var lo = double.infinity, hi = -double.infinity;
  for (final v in m.positions) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  final span = (hi - lo).isFinite ? (hi - lo).abs() : 0.0;
  return math.max(span * 1e-9, 1e-9);
}

/// The DISPLAY-edge indices of [solid] that bound mesh face [face], as offsets
/// within this solid's own edge list.
///
/// Empty when the mesh carries no face metadata — a fake or a legacy mesh —
/// which callers must treat as "cannot answer" rather than as "no edges". See
/// [OcctMeshData.triFaces].
Set<int> faceBoundaryEdges(OcctMeshData m, int face) {
  if (m.triFaces.isEmpty || face < 0) return const {};
  // 1. the sides of this face's triangles, counted.
  final count = <int, int>{};
  final ends = <int, (int, int)>{};
  final idx = m.indices;
  for (var t = 0; t * 3 + 2 < idx.length; t++) {
    if (t >= m.triFaces.length || m.triFaces[t] != face) continue;
    final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
    for (final (p, q) in [(a, b), (b, c), (c, a)]) {
      final lo = p < q ? p : q, hi = p < q ? q : p;
      final k = lo * 0x100000000 + hi;
      count[k] = (count[k] ?? 0) + 1;
      ends[k] = (lo, hi);
    }
  }
  if (count.isEmpty) return const {};
  // 2. sides used ONCE are the boundary. Kept as SEGMENTS, not as loose
  //    vertices, and that distinction is the whole correctness of this:
  //    the diagonal that splits a square face into its two triangles has both
  //    ends on the boundary and is not on it. A vertex test takes it and
  //    projects a stray line across the middle of the outline.
  final q = _quantumFor(m);
  final onBoundary = <(int, int)>{};
  int keyOf(int v) => _key(
      m.positions[v * 3], m.positions[v * 3 + 1], m.positions[v * 3 + 2], q);
  for (final e in count.entries) {
    if (e.value != 1) continue;
    final (lo, hi) = ends[e.key]!;
    if (lo * 3 + 2 >= m.positions.length || hi * 3 + 2 >= m.positions.length) {
      continue;
    }
    final a = keyOf(lo), b = keyOf(hi);
    onBoundary.add(a < b ? (a, b) : (b, a));
  }
  // 3. a display edge every SEGMENT of which is a boundary side of this face.
  //    Every segment, not merely some: an edge of the neighbouring face runs
  //    off this one after its first point, and a partial match would take it.
  final out = <int>{};
  final starts = m.edgeStarts;
  final pts = m.edgePoints;
  for (var e = 0; e + 1 < starts.length; e++) {
    final a = starts[e], b = starts[e + 1];
    if (a < 0 || b * 3 > pts.length || b - a < 2) continue;
    var all = true;
    var prev = _key(pts[a * 3], pts[a * 3 + 1], pts[a * 3 + 2], q);
    for (var i = a + 1; i < b && all; i++) {
      final cur = _key(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2], q);
      all = onBoundary.contains(prev < cur ? (prev, cur) : (cur, prev));
      prev = cur;
    }
    if (all) out.add(e);
  }
  return out;
}

/// One face of one feature, as the projector addresses it.
class PartFaceRef {
  /// Index into the part's visible feature list — the same walk [partEdges]
  /// makes, so the two agree about which solids exist and in which order.
  final int feature;

  /// Mesh face index within that feature's solid.
  final int face;

  /// How far the hit sits along the sketch normal. Larger is nearer the
  /// viewer; see [faceUnderPoint].
  final double height;

  const PartFaceRef(this.feature, this.face, this.height);
}

/// The face of [part] under sketch-plane point [w], seen along [fr]'s normal,
/// or null when the point is over nothing.
///
/// The NEAREST one: a sketch looks down its own normal at a solid, so the
/// point is usually over two faces (the front of the part and its back) and
/// only the near one is the one being pointed at. Height is measured along
/// +n, and [PlaneFrame.n] points at the viewer — the same convention
/// Cam3.facesCamera uses, and the reason a sketch on a face is drawn over the
/// solid rather than inside it.
PartFaceRef? faceUnderPoint(PartModel part, PlaneFrame fr, Offset w) {
  PartFaceRef? best;
  var fi = -1;
  for (final f in part.features) {
    final sol = f.solid;
    if (!f.visible || sol == null || f.consumedByJoin) continue;
    fi++;
    final m = sol.mesh;
    if (m.triFaces.isEmpty) continue;
    final idx = m.indices;
    for (var t = 0; t * 3 + 2 < idx.length && t < m.triFaces.length; t++) {
      final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
      if (a * 3 + 2 >= m.positions.length ||
          b * 3 + 2 >= m.positions.length ||
          c * 3 + 2 >= m.positions.length) {
        continue;
      }
      Vec3 p(int v) =>
          Vec3(m.positions[v * 3], m.positions[v * 3 + 1], m.positions[v * 3 + 2]);
      final pa = p(a), pb = p(b), pc = p(c);
      final sa = fr.toSketch(pa), sb = fr.toSketch(pb), sc = fr.toSketch(pc);
      final bary = _barycentric(sa, sb, sc, w);
      if (bary == null) continue;
      final (ua, ub, uc) = bary;
      final h = ua * (pa - fr.origin).dot(fr.n) +
          ub * (pb - fr.origin).dot(fr.n) +
          uc * (pc - fr.origin).dot(fr.n);
      if (best == null || h > best.height) {
        best = PartFaceRef(fi, m.triFaces[t], h);
      }
    }
  }
  return best;
}

/// Barycentric weights of [p] in triangle (a, b, c), or null when outside.
///
/// Degenerate triangles are rejected rather than divided by: a face
/// triangulation routinely contains slivers, and a NaN weight here would win
/// every depth comparison it entered.
(double, double, double)? _barycentric(
    Offset a, Offset b, Offset c, Offset p) {
  final v0 = b - a, v1 = c - a, v2 = p - a;
  final den = v0.dx * v1.dy - v1.dx * v0.dy;
  if (den.abs() < 1e-15) return null;
  final u = (v2.dx * v1.dy - v1.dx * v2.dy) / den;
  final v = (v0.dx * v2.dy - v2.dx * v0.dy) / den;
  if (u < 0 || v < 0 || u + v > 1) return null;
  return (1 - u - v, u, v);
}

/// The display-edge indices [faceBoundaryEdges] answers, renumbered into the
/// part-wide index space [partEdges] hands out.
///
/// The part-wide index counts every display edge of every visible, unconsumed
/// feature in order, so the offset of a feature's block is the number of edges
/// before it — INCLUDING the ones partEdges skips as degenerate, which it
/// counts too. Recomputing that walk here rather than taking a length keeps
/// the two in step: they are the same numbering or the projection lands on the
/// wrong curve.
List<int> partEdgeIndicesForFace(PartModel part, PartFaceRef ref) {
  var fi = -1, base = 0;
  for (final f in part.features) {
    final sol = f.solid;
    if (!f.visible || sol == null || f.consumedByJoin) continue;
    fi++;
    final m = sol.mesh;
    final n = m.edgeStarts.isEmpty ? 0 : m.edgeStarts.length - 1;
    if (fi == ref.feature) {
      final local = faceBoundaryEdges(m, ref.face);
      final out = [for (final e in local) base + e]..sort();
      return out;
    }
    base += n;
  }
  return const [];
}

/// Test seam: the raw buffers a synthetic mesh needs, so a test can build a
/// two-face box without the kernel.
@visibleForTesting
OcctMeshData meshForTest({
  required Float64List positions,
  required Int32List indices,
  required Int32List triFaces,
  required Int32List edgeStarts,
  required Float64List edgePoints,
}) =>
    OcctMeshData(positions, Float64List(positions.length), indices, edgeStarts,
        edgePoints,
        triFaces: triFaces);
