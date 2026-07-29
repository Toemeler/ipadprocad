// Prototype — M133: picking B-Rep EDGES in the 3D viewport.
//
// Kept OUT of viewport3d.dart on purpose. The viewport needs a live Cam3, a
// Flutter tree and a device to exercise; this file needs neither, so the
// maths that decides WHICH edge you hit is host-testable. The widget supplies
// two closures (project a world point to the screen, and its depth) and gets
// back a decision.
//
// Why edges are their own problem, and not a variant of face picking: a face
// is an area, so a barycentric test answers "inside or not". An edge is a
// curve of zero width, so there is no "inside" — the answer is always "the
// nearest one, if it is near enough", which needs a pixel tolerance and a
// tie-break. Getting that tie-break wrong is what makes a CAD app feel like
// it is fighting you.
import 'dart:math' as math;
import 'dart:ui';

import 'ffi/occt_engine.dart';
import 'pick_math.dart';
import 'part_model.dart' show EdgeSel, Vec3;

typedef ProjectFn = Offset Function(Vec3);
typedef DepthFn = double Function(Vec3);

/// Screen-space tolerance for an edge hit. Generous, because a finger is not
/// a mouse and an edge is one pixel wide.
const double kEdgePickTolerancePx = 14.0;

/// One edge under the pointer.
class EdgePick {
  /// Index into the mesh list handed to [pickEdge] — the caller maps it back
  /// to whichever solid that was.
  final int meshIndex;

  /// Index in the mesh's DISPLAY edge list ([OcctMeshData.edgeStarts] space).
  final int displayEdge;

  /// 1-based TOPOLOGICAL edge index, or -1 when the mesh does not carry the
  /// map. Fillet and chamfer address this one; the display index is useless
  /// to them (see OcctMeshData.edgeIds).
  final int topoEdge;

  /// Closest point on the edge, in world coordinates — where the user
  /// actually pointed. Good for drawing a highlight; NOT the fingerprint.
  final Vec3 point;

  /// Arc-length midpoint of the edge, in world coordinates.
  ///
  /// This, not [point], is what a stored selection remembers. `EdgeSel` is
  /// re-matched against `occt_shape_edge_info`, whose anchor is the
  /// arc-length midpoint; fingerprinting the tap location instead would
  /// compare a point near one END of a long edge against that edge's middle
  /// and conclude it had disappeared.
  final Vec3 mid;

  /// Polyline length of the edge. Exact for a line, and within the display
  /// deflection for a curve — which is far tighter than EdgeSel's tolerance.
  final double length;

  /// 1 line, 2 circle, 3 ellipse, 0 unknown (see occt_capi.h edge_curves).
  final int kind;

  /// Radius for a circle, major radius for an ellipse, else 0.
  final double radius;

  final double depth;

  /// Screen distance from the tap to the edge, in pixels.
  final double pixels;

  const EdgePick(this.meshIndex, this.displayEdge, this.topoEdge, this.point,
      this.mid, this.length, this.kind, this.radius, this.depth, this.pixels);

  /// An edge that cannot be filleted or chamfered should never be offered.
  bool get usable => topoEdge > 0;

  /// The re-attachable fingerprint to store on a fillet or chamfer feature.
  EdgeSel toSel() =>
      EdgeSel(mid.x, mid.y, mid.z, length, kind, radius);

  @override
  String toString() =>
      'EdgePick(mesh $meshIndex, display $displayEdge, topo $topoEdge, '
      '${pixels.toStringAsFixed(1)}px, depth ${depth.toStringAsFixed(2)})';
}

/// Arc-length midpoint, total length, curve type and radius of display edge
/// [e]. The midpoint is walked along the polyline rather than taken at the
/// middle INDEX: the discretiser puts points where the curvature needs them,
/// so on an arc the middle index sits nowhere near the middle of the curve.
(Vec3, double, int, double) edgeFingerprint(OcctMeshData m, int e) {
  final start = m.edgeStarts[e], end = m.edgeStarts[e + 1];
  Vec3 at(int i) => Vec3(m.edgePoints[i * 3], m.edgePoints[i * 3 + 1],
      m.edgePoints[i * 3 + 2]);
  var total = 0.0;
  for (var i = start; i + 1 < end; i++) {
    total += (at(i + 1) - at(i)).length;
  }
  var mid = at(start);
  if (total > 0) {
    var walked = 0.0;
    for (var i = start; i + 1 < end; i++) {
      final seg = (at(i + 1) - at(i)).length;
      if (walked + seg >= total / 2) {
        final t = seg < 1e-15 ? 0.0 : (total / 2 - walked) / seg;
        mid = at(i) + (at(i + 1) - at(i)) * t;
        break;
      }
      walked += seg;
    }
  }
  var kind = 0;
  var radius = 0.0;
  if (m.edgeCurves.length >= 16 * (e + 1)) {
    kind = m.edgeCurves[16 * e].round();
    if (kind == 2 || kind == 3) radius = m.edgeCurves[16 * e + 10];
  }
  return (mid, total, kind, radius);
}

/// The edge under [px], or null.
///
/// Among every edge within [tolPx], the NEAREST TO THE CAMERA wins — not the
/// closest in pixels. On any real model the silhouette of a near face and an
/// edge on the far side of the same body project within a few pixels of each
/// other constantly; picking by pixel distance would hand back the edge you
/// cannot see roughly half the time. Face picking already resolves overlaps
/// by depth for the same reason.
///
/// Pixel distance is only the tie-break, for edges at genuinely equal depth
/// (two edges meeting at a corner, where you meant the one you pointed at).
EdgePick? pickEdge(
  List<OcctMeshData> meshes,
  ProjectFn project,
  DepthFn depth,
  Offset px, {
  double tolPx = kEdgePickTolerancePx,
  bool requireTopoId = true,
}) {
  final tol2 = tolPx * tolPx;
  final best = PickBest<EdgePick>();
  for (var mi = 0; mi < meshes.length; mi++) {
    final m = meshes[mi];
    final n = m.edgeCount;
    if (n <= 0) continue;
    for (var e = 0; e < n; e++) {
      final topo = m.topoEdgeId(e);
      if (requireTopoId && topo <= 0) continue;
      final start = m.edgeStarts[e], end = m.edgeStarts[e + 1];
      if (end - start < 2) continue;
      // Walk the polyline once, projecting each point a single time.
      var prevW = Vec3(m.edgePoints[start * 3], m.edgePoints[start * 3 + 1],
          m.edgePoints[start * 3 + 2]);
      var prevP = project(prevW);
      for (var i = start + 1; i < end; i++) {
        final w = Vec3(m.edgePoints[i * 3], m.edgePoints[i * 3 + 1],
            m.edgePoints[i * 3 + 2]);
        final p = project(w);
        final (d2, t) = segDistSq(px, prevP, p);
        if (d2 <= tol2) {
          final hit = prevW + (w - prevW) * t;
          final dep = depth(hit);
          final pix = math.sqrt(d2);
          // Build the (allocating) fingerprint only for a candidate that
          // actually wins, not for every segment within tolerance.
          if (best.wouldTake(dep, pix)) {
            final (mid, len, kind, radius) = edgeFingerprint(m, e);
            best.offer(
                EdgePick(mi, e, topo, hit, mid, len, kind, radius, dep, pix),
                dep,
                pix);
          }
        }
        prevW = w;
        prevP = p;
      }
    }
  }
  return best.value;
}
