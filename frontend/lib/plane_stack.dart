// Depth-correct ordering for the translucent work-plane fills.
//
// THE REPORT (#53, reopened 2026-09-12 with two screenshots one small orbit
// apart): "the workplanes still have issues with displaying the handling which
// is in front and what behind something is completely off". In the first
// screenshot the blue plane's wash lies over the red one through the middle of
// the star; in the second, taken from almost the same angle, the red lies over
// the blue. Nothing in the scene changed but the camera, by a few degrees.
//
// TWO ROOT CAUSES, and the first one is why every previous attempt at this was
// doomed:
//
//  1. THE THREE ORIGIN PLANES INTERSECT EACH OTHER. A renderer that sorts
//     whole objects — which is what RealityKit does with transparent entities,
//     and what the CPU painter did by drawing them in `kPlaneKeys` order — has
//     to answer "is the XY plane in front of the YZ plane?" with ONE answer.
//     There is no such answer: half of the XY plane is in front of the YZ
//     plane and the other half is behind it. Whichever way the sort goes, half
//     the picture is wrong. No amount of better sorting fixes this, because
//     the question itself is ill-posed.
//
//  2. ALL THREE CENTROIDS SIT AT THE WORLD ORIGIN. This part is measured —
//     the test asserts it — and the rest of it is inference, stated as such:
//     a transparent sort that separates whole objects by their distance from
//     the camera is the usual arrangement, and three distances that are equal
//     to the last bit leave such a sort breaking a tie with floating-point
//     noise. That is what a few degrees of orbit changing the picture looks
//     like, and it is consistent with the "flackern" M254 blamed on mesh
//     churn. What is certain either way is (1): no order of whole planes is
//     right, so the fix below is needed whatever the sort does with ties.
//
// THE FIX, which is the textbook one and is exact rather than approximate:
// split every translucent plane by the supporting planes of all the others, so
// that no two drawn pieces intersect any more (the three origin planes become
// four quadrants each), and then draw those pieces strictly back-to-front. A
// BSP tree gives both halves at once: building it does the splitting, and
// walking it far-subtree-first from the eye yields the exact back-to-front
// order for ANY camera position. It cannot tie, so it cannot flicker.
//
// This lives in Dart, is pure, and is shared: the CPU painter walks the tree
// directly, and the RealityKit payload carries the same tree so the native
// side walks it too (the ordering has to be redone when the camera crosses a
// plane, which is why the TREE travels rather than a finished order).
import 'package:flutter/painting.dart' show Color;

import 'part_model.dart';

/// Tolerance for "on the plane", in millimetres.
///
/// A plane's own four corners must classify as coplanar with it and nothing
/// else may: the smallest gap in play is the coplanar-face bias placeCamera
/// applies, which is `halfH * 5e-4` — micrometres at any sane zoom. 1e-7 mm
/// sits far below that and far above double-precision noise on coordinates of
/// a few hundred millimetres.
const double kPlaneStackEps = 1e-7;

/// A plane equation `n·x = d`, [n] unit length.
class PlaneEq {
  final Vec3 n;
  final double d;
  const PlaneEq(this.n, this.d);

  /// The plane through [p] with normal [n]; [n] need not be unit length.
  factory PlaneEq.throughPoint(Vec3 p, Vec3 n) {
    final u = n.normalized();
    return PlaneEq(u, u.dot(p));
  }

  /// Signed distance of [p]: positive on the side [n] points to.
  double side(Vec3 p) => n.dot(p) - d;
}

/// One convex translucent polygon, ready to draw.
///
/// [key] names the plane it was cut from — the pieces of one plane keep its
/// key, so a caller can still tell which plane a piece belongs to (the hit
/// test and the hover tint both work on whole planes, not on pieces).
class PlanePiece {
  final String key;
  final List<Vec3> pts;
  final Color color;
  final PlaneEq plane;
  const PlanePiece(this.key, this.pts, this.color, this.plane);

  PlanePiece _with(List<Vec3> p) => PlanePiece(key, p, color, plane);

  /// Average of the corners. Not used for ordering — it is exactly the number
  /// whose ties caused the bug — but it is how a test names a piece.
  Vec3 get centroid {
    var s = Vec3.zero;
    for (final p in pts) {
      s = s + p;
    }
    return s * (1 / pts.length);
  }
}

/// A translucent quad as the scene knows it, before any splitting.
PlanePiece planePieceFromQuad(String key, List<Vec3> corners, Color color) {
  assert(corners.length == 4);
  final n = (corners[1] - corners[0]).cross(corners[3] - corners[0]);
  return PlanePiece(key, corners, color, PlaneEq.throughPoint(corners[0], n));
}

/// Cut [poly] by [pl] into (front, back). Either may be null; both are null
/// when the polygon lies IN the plane.
///
/// Sutherland–Hodgman, run once for each side so a straddling polygon yields
/// two pieces that share the cut edge exactly (the intersection point is
/// computed once and handed to both, so no crack can open between them).
(List<Vec3>?, List<Vec3>?) splitPolygonByPlane(List<Vec3> poly, PlaneEq pl) {
  final ds = [for (final p in poly) pl.side(p)];
  var anyFront = false, anyBack = false;
  for (final d in ds) {
    if (d > kPlaneStackEps) anyFront = true;
    if (d < -kPlaneStackEps) anyBack = true;
  }
  if (!anyFront && !anyBack) return (null, null); // coplanar
  if (!anyBack) return (poly, null);
  if (!anyFront) return (null, poly);

  final front = <Vec3>[], back = <Vec3>[];
  for (var i = 0; i < poly.length; i++) {
    final j = (i + 1) % poly.length;
    final pi = poly[i], pj = poly[j];
    final di = ds[i], dj = ds[j];
    if (di >= -kPlaneStackEps) front.add(pi);
    if (di <= kPlaneStackEps) back.add(pi);
    final crosses = (di > kPlaneStackEps && dj < -kPlaneStackEps) ||
        (di < -kPlaneStackEps && dj > kPlaneStackEps);
    if (crosses) {
      final t = di / (di - dj);
      final x = pi + (pj - pi) * t;
      front.add(x);
      back.add(x);
    }
  }
  return (front.length >= 3 ? front : null, back.length >= 3 ? back : null);
}

/// A node of the plane BSP: the pieces lying IN [plane], and the two subtrees.
class PlaneBspNode {
  final PlaneEq plane;
  final List<PlanePiece> coplanar;
  final PlaneBspNode? front;
  final PlaneBspNode? back;
  const PlaneBspNode(this.plane, this.coplanar, this.front, this.back);
}

/// Are [a] and [b] the same plane, either way up?
bool samePlane(PlaneEq a, PlaneEq b) {
  final c = a.n.dot(b.n);
  if (c.abs() < 1 - 1e-9) return false;
  return (a.d - (c > 0 ? b.d : -b.d)).abs() < 1e-7;
}

/// Every piece cut by every OTHER plane in the set, so that no two pieces
/// intersect at all.
///
/// A BSP does not need this — splitting by the pivot alone already makes each
/// PAIR orderable, which is all the painter's algorithm asks. It is done
/// anyway because of where these pieces are going: the native renderer may
/// fall back to sorting them by distance, and the whole reason the two
/// screenshots disagree is that an unsplit plane's centroid sits on the world
/// origin, where the other two also sit. Fully split, the pieces are 12 small
/// quadrants with 12 distinct centroids, and even the crude sort gets it right.
/// Twelve quads is nothing to draw; a scene that can be ordered correctly by
/// any renderer that touches it is worth more.
/// Ceilings for [splitPiecesApart]. Cutting by N planes can in principle
/// double the piece count N times, and a part with a dozen work planes up must
/// not turn a viewport frame into a geometry session. Neither ceiling costs
/// correctness: the BSP below is exact with or without this pass, which is
/// only here so a renderer that falls back to a distance sort also gets it
/// right. A scene busy enough to hit one of these keeps the exact order and
/// loses only that insurance.
const int kMaxSplitPlanes = 8;
const int kMaxSplitPieces = 256;

List<PlanePiece> splitPiecesApart(List<PlanePiece> pieces) {
  final planes = <PlaneEq>[];
  for (final p in pieces) {
    if (!planes.any((q) => samePlane(q, p.plane))) planes.add(p.plane);
    if (planes.length >= kMaxSplitPlanes) break;
  }
  var cur = pieces;
  for (final pl in planes) {
    if (cur.length >= kMaxSplitPieces) break;
    final next = <PlanePiece>[];
    for (final p in cur) {
      final (f, b) = splitPolygonByPlane(p.pts, pl);
      if (f == null && b == null) {
        next.add(p); // lies in this plane — nothing to cut
        continue;
      }
      if (f != null) next.add(p._with(f));
      if (b != null) next.add(p._with(b));
    }
    cur = next;
  }
  return cur;
}

/// Build the BSP over [pieces]. Returns null for an empty scene.
///
/// The pieces are cut apart first ([splitPiecesApart]) and the tree is then
/// built over the result, pivoting on the first remaining piece's own plane.
/// For the three origin planes that is the three coordinate planes, with one
/// quadrant of one plane at each of the 12 leaves.
PlaneBspNode? buildPlaneBsp(List<PlanePiece> pieces) => _bsp(splitPiecesApart(
    // A zero-area quad has no normal to build a plane from, and one that got
    // this far would make every side() zero — i.e. would make the whole scene
    // coplanar with it. Dropped rather than defended against downstream.
    [for (final p in pieces) if (p.plane.n.length > 0.5) p]));

/// How deep the tree may go. One level per distinct plane is the honest
/// bound; this is well past it, and it stops a pathological set from
/// recursing without end. At the floor the remaining pieces are hung on the
/// node as coplanar, which orders them as the old code did — for a scene no
/// part has ever had.
const int kMaxBspDepth = 32;

PlaneBspNode? _bsp(List<PlanePiece> pieces, [int depth = 0]) {
  if (pieces.isEmpty) return null;
  final pivot = pieces.first.plane;
  if (depth >= kMaxBspDepth) return PlaneBspNode(pivot, pieces, null, null);
  final coplanar = <PlanePiece>[];
  final front = <PlanePiece>[], back = <PlanePiece>[];
  for (final p in pieces) {
    final (f, b) = splitPolygonByPlane(p.pts, pivot);
    if (f == null && b == null) {
      coplanar.add(p);
      continue;
    }
    if (f != null) front.add(p._with(f));
    if (b != null) back.add(p._with(b));
  }
  return PlaneBspNode(
      pivot, coplanar, _bsp(front, depth + 1), _bsp(back, depth + 1));
}

/// The pieces of [root] in back-to-front order as seen from [eye].
///
/// Far subtree, then this node's own coplanar pieces, then the near subtree —
/// the standard BSP painter's walk. Exact: after [buildPlaneBsp] no piece
/// intersects another, and every piece lies wholly on one side of every node
/// plane above it, so "farther" is decided by a sign, never by a distance that
/// could tie.
List<PlanePiece> planesBackToFront(PlaneBspNode? root, Vec3 eye) {
  final out = <PlanePiece>[];
  void walk(PlaneBspNode? n) {
    if (n == null) return;
    if (n.plane.side(eye) >= 0) {
      walk(n.back);
      out.addAll(n.coplanar);
      walk(n.front);
    } else {
      walk(n.front);
      out.addAll(n.coplanar);
      walk(n.back);
    }
  }

  walk(root);
  return out;
}

/// How far out to put the eye when the camera is ORTHOGRAPHIC.
///
/// An ortho eye is at infinity along the view direction, and the walk only
/// reads the SIGN of `n·eye - d`. Any point far enough along [dir] that `d`
/// cannot change that sign will do; parts are millimetres and this is ten
/// kilometres of them.
const double kOrthoEyeReach = 1e7;

/// The eye point to hand [planesBackToFront] for an orthographic camera whose
/// view direction (scene toward eye, as `Cam3.dir` is) is [dir].
Vec3 orthoEye(Vec3 dir) => dir * kOrthoEyeReach;
