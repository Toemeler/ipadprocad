// M371 — turning a tap into something measurable, in all three documents.
//
// measure.dart decides what a pair of picks MEANS; this file decides what one
// tap IS. They are split for the reason part_pick.dart and work_features.dart
// are split from the viewports that use them: the arithmetic wants no camera
// and the pick wants no widget tree, and both want to be runnable on a host.
//
// THREE DOCUMENTS, ONE ANSWER TYPE. A sketch, a part and an assembly hold
// completely different things — a `Geo` list, a `KernelSolid` list, and a set
// of occurrences each of which is a part sitting somewhere else — and every
// one of them has to answer the same question with the same [MeasureRef]. So
// there are three entry points and one vocabulary:
//
//   [measurePickSketch]    a 2D sketch, in the sketch plane (z = 0)
//   [measurePickPart]      a part's solids, under a Cam3
//   [measurePickAssembly]  an assembly's occurrences, under the same Cam3
//
// WHY THE SKETCH EMBEDS AT z = 0 rather than getting its own flat solver:
// every distance, angle and area in measure.dart is written in three
// dimensions and reads identically in the plane. A separate 2D path would be
// a second implementation of "the distance between two circles" that could
// disagree with the first, and the milestone that made them disagree would be
// the one nobody could reproduce.
//
// PICK ORDER, and it is the same everywhere:
//
//   1. VERTICES. The smallest target on screen, and the one Inventor makes
//      reachable through Select Other. A vertex within tolerance beats the
//      edge it sits on, because a tap that could have meant either meant the
//      harder one to hit.
//   2. EDGES. An edge lies ON a face, so a face test would win at every
//      boundary and "measure this edge" would be unreachable.
//   3. FACES, of any surface type. A cylinder is exactly what "click on a
//      cylinder" asks for, and the surface record answers it exactly.
//
// SELECTION PRIORITY. Inventor's Measure has a Component / Part / Faces and
// Edges combo box. [MeasurePriority] is the same idea with the modes this app
// actually has documents for; it is a parameter rather than a mode the picker
// remembers, so the panel owns it and the picker stays pure.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'assembly.dart';
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'measure.dart';
import 'part_model.dart';
import 'part_pick.dart';
import 'part_render.dart'
    show
        Cam3,
        kFaceCone,
        kFaceCylinder,
        kFacePlane,
        kFaceSphere,
        kFaceTorus,
        placedCam;
import 'quat.dart';
import 'snap.dart';
import 'work_features.dart' show WorkRef, WorkRefSource;

/// Screen tolerance for a VERTEX. Wider than the edge tolerance on purpose:
/// a vertex is a single point and a finger is not a mouse, and the depth
/// ordering below stops the extra width from stealing taps meant for a face.
const double kMeasureVertexPx = 12.0;

/// How much nearer a vertex counts than the edge that ends at it, in world
/// units. Without it the two report the same depth and the edge's much larger
/// hit area takes every tap — the same problem [kAsmEdgeBias] solves for an
/// edge against the face it bounds.
const double kMeasureVertexBias = 1.0;

/// How much nearer an edge counts than the face it lies on.
const double kMeasureEdgeBias = 0.6;

/// One candidate, with everything needed to choose between candidates.
class MeasurePick {
  const MeasurePick(this.ref, this.depth, this.pixels);

  final MeasureRef ref;

  /// Cam3 depth of the touched point. SMALLER IS NEARER — the convention
  /// asm_pick.dart's header establishes and every picker in this app follows.
  final double depth;

  /// Screen distance from the tap, for the tie-break between candidates at
  /// equal depth.
  final double pixels;
}

// ===========================================================================
// 2D — the sketcher
// ===========================================================================

/// What the tap at sketch point [w] measures, or null.
///
/// [tolWorld] is the pick radius in SKETCH units — the viewport passes its own
/// `px / zoom`, so the tolerance is a constant number of points on glass at
/// every zoom, which is the only way a tolerance can behave on a pinch-zoom
/// canvas.
///
/// Snap points come first and that is Inventor's rule too: hovering an
/// endpoint under Measure offers the endpoint, not the line it ends. The
/// [Snap] machinery is reused rather than reimplemented, so the points the
/// measure tool offers are exactly the points the drawing tools snap to —
/// endpoints, midpoints, centres, quadrants and the origin.
MeasureRef? measurePickSketch(List<Geo> geos, Offset w, double tolWorld) {
  final snap = computeSnap(geos, w, tolWorld);
  if (snap != null && snap.kind != 'align' && snap.kind != 'on') {
    return MeasureRef.point(_flat(snap.pos));
  }
  var best = -1;
  var bestD = tolWorld;
  for (var i = 0; i < geos.length; i++) {
    final d = distToEntity(geos[i], w);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  if (best < 0) return null;
  return measureRefOfGeo(geos[best], hitAt: _flat(w));
}

/// One sketch entity as something measurable.
///
/// Every carrier of the 2D document reaches its exact analytic form where it
/// has one — a circle is a circle and not its 32-gon — and its drawn polyline
/// where it does not, which is what makes a spline's length the length the
/// user can see rather than one only the solver knows.
MeasureRef? measureRefOfGeo(Geo g, {Vec3? hitAt, String? owner}) {
  const up = Vec3(0, 0, 1);
  switch (g.type) {
    case Geo.line:
      return MeasureRef.segment(Vec3(g.data[0], g.data[1], 0),
          Vec3(g.data[2], g.data[3], 0),
          owner: owner, hitAt: hitAt);

    case Geo.circle:
      final c = Vec3(g.data[0], g.data[1], 0);
      // M209 — a sketch POINT is a circle carrier with a tag on it. Its
      // radius is a drawing detail and measuring it would be nonsense.
      if (g.isSketchPoint) return MeasureRef.point(c, owner: owner);
      return MeasureRef.circle(c, up, g.data[2],
          owner: owner, samples: _lift(sampleEntity(g)), hitAt: hitAt);

    case Geo.arc:
      final c = Vec3(g.data[0], g.data[1], 0);
      return MeasureRef.arc(c, up, g.data[2], _arcSweep(g),
          owner: owner, samples: _lift(sampleEntity(g)), hitAt: hitAt);

    case Geo.polyline:
      final n = g.data[1].toInt();
      if (g.spline == Geo.ellipseTag && n >= 3) {
        // Stored as centre / major vertex / minor vertex — Inventor's own
        // three ellipse grips, and the two half-axes fall straight out.
        final c = Vec3(g.data[2], g.data[3], 0);
        final major = (Vec3(g.data[4], g.data[5], 0) - c).length;
        final minor = (Vec3(g.data[6], g.data[7], 0) - c).length;
        return MeasureRef.ellipse(c, up, major, minor,
            owner: owner,
            length: ellipsePerimeter(major, minor),
            samples: _lift(sampleEntity(g)),
            hitAt: hitAt);
      }
      final pts = _lift(g.isSpline || g.isGear
          ? sampleEntity(g)
          : [
              for (var i = 0; i < n; i++)
                Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
            ]);
      if (pts.length < 2) return null;
      final closed = _polylineCloses(g, pts);
      return MeasureRef.curve(closed ? _closeLoop(pts) : pts,
          owner: owner, closed: closed, planeNormal: up, hitAt: hitAt);
  }
  return null;
}

/// The angle an arc sweeps, always positive. Mirrors [sampleEntity]'s own
/// reading of the reversed flag, so the length here and the curve drawn in the
/// viewport can never disagree about which way round the arc goes.
double _arcSweep(Geo g) {
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final reversed = g.data[5] != 0;
  return reversed ? norm(g.data[3] - g.data[4]) : norm(g.data[4] - g.data[3]);
}

/// True when the entity is a closed loop — either flagged closed, or drawn
/// back onto its own start (which is how a polyline traced by hand closes).
bool _polylineCloses(Geo g, List<Vec3> pts) {
  if (g.data[0] != 0) return true;
  return pts.length > 2 && (pts.last - pts.first).length < 1e-9;
}

List<Vec3> _closeLoop(List<Vec3> pts) =>
    (pts.last - pts.first).length < 1e-12 ? pts : [...pts, pts.first];

Vec3 _flat(Offset o) => Vec3(o.dx, o.dy, 0);

List<Vec3> _lift(List<Offset> pts) => [for (final p in pts) _flat(p)];

// ===========================================================================
// existing work geometry — reuse, not a second picker
// ===========================================================================

/// A [WorkRef] as something measurable.
///
/// The part and assembly viewports already answer "did the tap land on an
/// origin plane, an origin axis, the centre point or an existing work
/// feature?" — in `_hitOrigin` and `_hitWorkFeature`. Those answers are
/// WorkRefs, and this is the one function that saves the measure tool from
/// growing a fourth copy of that hit test.
///
/// A WorkRef is a REDUCTION (see its own header) and carries no length or
/// area, which is exactly right here: an origin plane has neither, and a work
/// axis is infinite. What comes back is the pick as half of a pair, which is
/// all any of these can ever be.
MeasureRef? measureRefFromWorkRef(WorkRef r) {
  switch (r.source) {
    case WorkRefSource.sphere:
      return r.point == null ? null : MeasureRef.sphere(r.point!);
    case WorkRefSource.torus:
      return r.hasLine && r.point != null
          ? MeasureRef.torus(r.point!, r.lineDir!)
          : null;
    case WorkRefSource.circle:
      // A circular edge reduced to a WorkRef keeps its centre, axis and
      // plane but not its radius. Measured on its own it is therefore its
      // CENTRE POINT, which is the honest reading and still the thing a hole
      // pattern is dimensioned from.
      return r.point == null ? null : MeasureRef.point(r.point!);
    case WorkRefSource.revolved:
      if (!r.hasLine) return null;
      final radius = r.radius;
      return radius == null
          ? MeasureRef.axis(r.lineAt!, r.lineDir!)
          : MeasureRef.cylinder(r.lineAt!, r.lineDir!, radius,
              hitAt: r.hitAt);
    case WorkRefSource.plane:
      return r.hasPlane
          ? MeasureRef.plane(r.planeAt!, r.planeNormal!, hitAt: r.hitAt)
          : null;
    case WorkRefSource.axis:
      return r.hasLine ? MeasureRef.axis(r.lineAt!, r.lineDir!) : null;
    case WorkRefSource.edge:
    case WorkRefSource.curve:
      if (r.hasLine) return MeasureRef.axis(r.lineAt!, r.lineDir!);
      return r.point == null ? null : MeasureRef.point(r.point!);
    case WorkRefSource.vertex:
      return r.point == null ? null : MeasureRef.point(r.point!);
  }
}

// ===========================================================================
// 3D — one placed mesh
// ===========================================================================

/// The measurable thing on [m] under [px], or null.
///
/// [at] places the mesh's own coordinates into the world; it is the identity
/// for a part and the occurrence's placement for an assembly component. The
/// camera is shifted rather than the mesh transformed, which is the identity
/// `project(R·l + t) == placedCam(cam, at).project(l)` that asm_pick.dart's
/// header spells out — so a component is picked exactly where it is drawn
/// without a single vertex being copied.
///
/// [depthBase] is added to every depth so that several pieces compete in ONE
/// depth space; the caller passes `cam.depth(at.at)`.
MeasurePick? measurePickMesh(
  OcctMeshData m,
  Cam3 cam,
  Offset px, {
  Placement at = Placement.identity,
  double depthBase = 0,
  String? owner,
}) {
  final sc = placedCam(cam, at);
  double depth(Vec3 local) => sc.depth(local) + depthBase;
  Vec3 world(Vec3 local) => at.apply(local);
  Vec3 worldDir(Vec3 local) => at.applyDir(local);

  MeasurePick? best;
  void offer(MeasurePick? c) {
    if (c == null) return;
    if (best == null ||
        c.depth < best!.depth - 1e-9 ||
        ((c.depth - best!.depth).abs() <= 1e-9 && c.pixels < best!.pixels)) {
      best = c;
    }
  }

  offer(_pickVertex(m, sc, px, depth, world, owner));
  offer(_pickEdgeRef(m, sc, px, depth, world, worldDir, owner));
  offer(_pickFaceRef(m, sc, px, depth, world, worldDir, owner));
  return best;
}

/// A B-Rep VERTEX under the tap.
///
/// The mesh carries no vertex list, but it does not need one: a display
/// edge's polyline STARTS and ENDS at real B-Rep vertices, so the two ends of
/// every edge are exactly the vertex set (with duplicates, which cost a few
/// comparisons and nothing else).
MeasurePick? _pickVertex(OcctMeshData m, Cam3 sc, Offset px,
    double Function(Vec3) depth, Vec3 Function(Vec3) world, String? owner) {
  final n = m.edgeCount;
  if (n <= 0) return null;
  MeasurePick? best;
  for (var e = 0; e < n; e++) {
    final s = m.edgeStarts[e], t = m.edgeStarts[e + 1];
    if (t - s < 2) continue;
    for (final i in [s, t - 1]) {
      final v = Vec3(m.edgePoints[i * 3], m.edgePoints[i * 3 + 1],
          m.edgePoints[i * 3 + 2]);
      final d = (sc.project(v) - px).distance;
      if (d > kMeasureVertexPx) continue;
      final cand = MeasurePick(MeasureRef.point(world(v), owner: owner),
          depth(v) - kMeasureVertexBias, d);
      if (best == null ||
          cand.depth < best.depth ||
          (cand.depth == best.depth && cand.pixels < best.pixels)) {
        best = cand;
      }
    }
  }
  return best;
}

/// The B-Rep EDGE under the tap, read from its ANALYTIC record where it has
/// one — a circle picked off its polyline would give a centre that wobbles
/// with the display deflection, and a radius that changed as you zoomed.
MeasurePick? _pickEdgeRef(
    OcctMeshData m,
    Cam3 sc,
    Offset px,
    double Function(Vec3) depth,
    Vec3 Function(Vec3) world,
    Vec3 Function(Vec3) worldDir,
    String? owner) {
  final hit = pickEdge([m], sc.project, depth, px,
      // An edge being MEASURED is not an edge being filleted: one with no
      // topological id is still a perfectly good line to read the length of,
      // and requiring one would drop every edge of a mesh with no id map.
      requireTopoId: false);
  if (hit == null) return null;

  final samples = _edgeSamples(m, hit.displayEdge, world);
  final ci = hit.displayEdge * 16;
  final atHit = world(hit.point);
  final d = depth(hit.point) - kMeasureEdgeBias;

  if (ci >= 0 && ci + 16 <= m.edgeCurves.length) {
    final c = m.edgeCurves;
    switch (c[ci].round()) {
      case 1:
        final p0 = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
        final p1 = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
        if ((p1 - p0).length > 1e-9) {
          return MeasurePick(
              MeasureRef.segment(world(p0), world(p1),
                  owner: owner, hitAt: atHit),
              d,
              hit.pixels);
        }
        break;
      case 2:
        final centre = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
        final xd = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
        final yd = Vec3(c[ci + 7], c[ci + 8], c[ci + 9]);
        final axis = xd.cross(yd);
        final radius = c[ci + 10];
        if (axis.length > 1e-9 && radius > 1e-12) {
          // t0..t1 is the parameter span; a full circle sweeps 2 pi and an
          // arc less. Which of the two it is decides whether the reading
          // leads with a diameter or with an arc length.
          final sweep = (c[ci + 12] - c[ci + 11]).abs();
          final full = (sweep - 2 * math.pi).abs() < 1e-6 || sweep < 1e-12;
          final centreW = world(centre);
          final axisW = worldDir(axis).normalized();
          return MeasurePick(
              full
                  ? MeasureRef.circle(centreW, axisW, radius,
                      owner: owner, samples: samples, hitAt: atHit)
                  : MeasureRef.arc(centreW, axisW, radius, sweep,
                      owner: owner, samples: samples, hitAt: atHit),
              d,
              hit.pixels);
        }
        break;
      case 3:
        final centre = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
        final xd = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
        final yd = Vec3(c[ci + 7], c[ci + 8], c[ci + 9]);
        final axis = xd.cross(yd);
        if (axis.length > 1e-9) {
          return MeasurePick(
              MeasureRef.ellipse(world(centre), worldDir(axis).normalized(),
                  c[ci + 10], c[ci + 11],
                  owner: owner,
                  length: hit.length,
                  samples: samples,
                  hitAt: atHit),
              d,
              hit.pixels);
        }
        break;
    }
  }
  // A spline, or a mesh with no curve records: the drawn polyline is still an
  // honest length, and it is the one the user can see.
  if (samples.length >= 2) {
    return MeasurePick(
        MeasureRef.curve(samples, owner: owner, hitAt: atHit), d, hit.pixels);
  }
  return null;
}

/// One display edge as a world-space polyline.
List<Vec3> _edgeSamples(
    OcctMeshData m, int e, Vec3 Function(Vec3) world) {
  if (e < 0 || e + 1 >= m.edgeStarts.length) return const [];
  final s = m.edgeStarts[e], t = m.edgeStarts[e + 1];
  return [
    for (var i = s; i < t; i++)
      world(Vec3(m.edgePoints[i * 3], m.edgePoints[i * 3 + 1],
          m.edgePoints[i * 3 + 2]))
  ];
}

/// The FACE under the tap, as whatever its surface type makes it.
///
/// Every type answers, not only the planar one: "click on a cylinder" is in
/// the brief, and the surface record has the axis and the radius that answers
/// it exactly.
MeasurePick? _pickFaceRef(
    OcctMeshData m,
    Cam3 sc,
    Offset px,
    double Function(Vec3) depth,
    Vec3 Function(Vec3) world,
    Vec3 Function(Vec3) worldDir,
    String? owner) {
  final f = frontFaceUnder(m, sc, px, depth);
  if (f == null) return null;
  final (face, hitLocal, d) = f;
  if (15 * face + 15 > m.faceInfos.length) return null;
  final info = m.faceInfos.sublist(15 * face, 15 * face + 15);
  final type = info[0].round();
  final at = world(Vec3(info[1], info[2], info[3]));
  final dirLocal = Vec3(info[4], info[5], info[6]);
  final dir = worldDir(dirLocal);
  final radius = info[10];
  final hit = world(hitLocal);
  final area = faceArea(m, face);
  final loop = faceLoopLength(m, face);

  MeasureRef? ref;
  switch (type) {
    case kFacePlane:
      if (dir.length < 1e-9) return null;
      ref = MeasureRef.plane(at, dir,
          owner: owner,
          // A FACE's normal is the outward one, which is what lets the
          // dihedral come out as the wedge angle rather than as an unsigned
          // one. See MeasureRef.planeIsOriented.
          oriented: true,
          area: area,
          perimeter: loop,
          hitAt: hit);
      break;
    case kFaceCylinder:
      if (dir.length < 1e-9) return null;
      ref = MeasureRef.cylinder(at, dir, radius,
          owner: owner,
          // [13],[14] is the v range, which for a cylinder is measured ALONG
          // the axis — so this really is how deep the bore is.
          height: (info[14] - info[13]).abs(),
          area: area,
          perimeter: loop,
          hitAt: hit);
      break;
    case kFaceCone:
      if (dir.length < 1e-9) return null;
      ref = MeasureRef.cone(at, dir,
          owner: owner,
          radius: radius,
          area: area,
          perimeter: loop,
          hitAt: hit);
      break;
    case kFaceSphere:
      ref = MeasureRef.sphere(at,
          owner: owner,
          radius: radius,
          area: area,
          perimeter: loop,
          hitAt: hit);
      break;
    case kFaceTorus:
      if (dir.length < 1e-9) return null;
      ref = MeasureRef.torus(at, dir,
          owner: owner,
          majorRadius: radius,
          area: area,
          perimeter: loop,
          hitAt: hit);
      break;
    default:
      // A surface with no analytic record still has an AREA, and a tap on it
      // must not fall through to nothing. Reported as a plane through the hit
      // point with the triangle's own normal, which is true locally and is
      // what a distance to it means.
      final n = _triangleNormalAt(m, face, worldDir);
      if (n == null) return null;
      ref = MeasureRef.plane(hit, n,
          owner: owner,
          oriented: true,
          area: area,
          perimeter: loop,
          hitAt: hit);
  }
  return MeasurePick(ref, d, 0);
}

/// The frontmost triangle of [m] under [px], as (mesh face index, hit point in
/// the mesh's own frame, depth).
///
/// Shared by the face pick and the body pick, and written once here rather
/// than a fourth time in a viewport: viewport3d.dart already carries three
/// near-identical copies of this loop, and a measurement that disagreed with
/// the highlight about which face was under the finger would be the worst
/// possible kind of wrong.
(int, Vec3, double)? frontFaceUnder(
    OcctMeshData m, Cam3 sc, Offset px, double Function(Vec3) depth) {
  if (m.triFaces.length * 3 != m.indices.length || m.faceInfos.isEmpty) {
    return null;
  }
  (int, Vec3, double)? best;
  var bestDepth = double.infinity;
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (w1 - w0).cross(w2 - w0);
    // Front faces only: a visible face has n·dir > 0 (asm_pick.dart's header
    // records the device measurement that settled the sign).
    if (n.length < 1e-12 || !sc.facesCamera(n)) continue;
    final a = sc.project(w0), b = sc.project(w1), c = sc.project(w2);
    final den = (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
    if (den.abs() < 1e-9) continue;
    final l0 =
        ((b.dy - c.dy) * (px.dx - c.dx) + (c.dx - b.dx) * (px.dy - c.dy)) / den;
    final l1 =
        ((c.dy - a.dy) * (px.dx - c.dx) + (a.dx - c.dx) * (px.dy - c.dy)) / den;
    final l2 = 1 - l0 - l1;
    const e = -1e-6;
    if (l0 < e || l1 < e || l2 < e) continue;
    final hit = w0 * l0 + w1 * l1 + w2 * l2;
    final d = depth(hit);
    if (d >= bestDepth) continue;
    bestDepth = d;
    best = (m.triFaces[t ~/ 3], hit, d);
  }
  return best;
}

/// The outward normal of any triangle of [face], in world space. The fallback
/// for a surface with no analytic record.
Vec3? _triangleNormalAt(
    OcctMeshData m, int face, Vec3 Function(Vec3) worldDir) {
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    if (m.triFaces[t ~/ 3] != face) continue;
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (w1 - w0).cross(w2 - w0);
    if (n.length > 1e-12) return worldDir(n).normalized();
  }
  return null;
}

// ---------------------------------------------------------------------------
// areas and loop lengths
// ---------------------------------------------------------------------------

/// Area of mesh face [face], by summing its triangles.
///
/// EXACT for a planar face — a triangulation of a polygon has the polygon's
/// area, whatever the deflection — and within the display deflection for a
/// curved one, which is why every curved reading is marked approximate. The
/// analytic alternative (`r·Δu·Δv` for a cylinder) is exact only for an
/// UNTRIMMED patch and would over-report every cylinder with a hole through
/// it, so the tessellation is not a compromise here: it is the form that
/// respects trimming.
double faceArea(OcctMeshData m, int face) {
  if (m.triFaces.length * 3 != m.indices.length) return 0;
  var total = 0.0;
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    if (m.triFaces[t ~/ 3] != face) continue;
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    total += (b - a).cross(c - a).length * 0.5;
  }
  return total;
}

/// Total length of the loops bounding mesh face [face] — Inventor's "total
/// loop length".
///
/// Read off the TRIANGULATION rather than off a face-to-edge map, because the
/// mesh carries no such map. A segment of the face's triangle set that is
/// used ONCE is on the boundary; one used twice is interior.
///
/// The seam is why the count is geometric rather than by vertex index. A
/// cylinder is triangulated with the vertices along its seam DUPLICATED, so
/// the seam appears as two index-distinct segments that each look like a
/// boundary — and a full bore would have reported its two rims plus twice its
/// own height. Counting by coordinates instead puts both copies in one bucket,
/// the bucket holds two, and the seam is correctly interior.
double faceLoopLength(OcctMeshData m, int face) {
  if (m.triFaces.length * 3 != m.indices.length) return 0;
  final count = <String, int>{};
  final length = <String, double>{};
  void edge(Vec3 a, Vec3 b) {
    // Undirected: the two orientations must land in the same bucket.
    final ka = _key(a), kb = _key(b);
    final k = ka.compareTo(kb) <= 0 ? '$ka|$kb' : '$kb|$ka';
    count[k] = (count[k] ?? 0) + 1;
    length[k] = (b - a).length;
  }

  var any = false;
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    if (m.triFaces[t ~/ 3] != face) continue;
    any = true;
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    edge(a, b);
    edge(b, c);
    edge(c, a);
  }
  if (!any) return 0;
  var total = 0.0;
  count.forEach((k, n) {
    if (n == 1) total += length[k] ?? 0;
  });
  return total;
}

/// A vertex's identity for the boundary count.
///
/// Rounded rather than exact: the seam's duplicated vertices hold the same
/// numbers today, but a kernel that recomputed one of them and left it a
/// half-ulp out would silently put the seam back in the perimeter. Six
/// decimals on a millimetre model is a nanometre — far below anything the
/// tessellation resolves, and far above float noise.
String _key(Vec3 v) =>
    '${v.x.toStringAsFixed(6)},${v.y.toStringAsFixed(6)},'
    '${v.z.toStringAsFixed(6)}';

// ===========================================================================
// bodies
// ===========================================================================

/// The whole solid [s] as something measurable, placed by [at].
///
/// The mesh travels with it because a body-to-body distance has no closed
/// form — see [nearestBetweenMeshes]. Its triangles and its display edges are
/// copied into world space ONCE here, at pick time, which is the only place
/// that copy is affordable: it happens on a tap, not on a frame.
MeasureRef measureRefOfSolid(KernelSolid s,
    {Placement at = Placement.identity,
    bool component = false,
    String? owner,
    Vec3? hitAt}) {
  final m = s.mesh;
  final tris = <Vec3>[];
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    for (final k in [t, t + 1, t + 2]) {
      final i = m.indices[k] * 3;
      tris.add(at.apply(
          Vec3(m.positions[i], m.positions[i + 1], m.positions[i + 2])));
    }
  }
  final curves = <List<Vec3>>[];
  for (var e = 0; e < m.edgeCount; e++) {
    final pts = _edgeSamples(m, e, at.apply);
    if (pts.length >= 2) curves.add(pts);
  }
  var lo = const Vec3(double.infinity, double.infinity, double.infinity);
  var hi = Vec3(-double.infinity, -double.infinity, -double.infinity);
  for (final p in tris) {
    lo = Vec3(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z));
    hi = Vec3(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z));
  }
  if (tris.isEmpty) {
    lo = hi = at.at;
  }
  var area = 0.0;
  for (var i = 0; i + 2 < tris.length; i += 3) {
    area += (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]).length * 0.5;
  }
  return MeasureRef.solid(lo, hi,
      component: component,
      owner: owner,
      // The kernel's own volume, not one integrated off the triangles: it is
      // exact, and it is already on the solid.
      volume: s.volume > 0 ? s.volume : null,
      area: area > 0 ? area : null,
      mesh: MeasureMesh(tris, curves, lo, hi),
      hitAt: hitAt);
}

/// Several solids as ONE measurable thing — a component made of more than one
/// body, or a part measured whole.
MeasureRef? measureRefOfSolids(List<(Placement, KernelSolid)> pieces,
    {required bool component, String? owner, Vec3? hitAt}) {
  if (pieces.isEmpty) return null;
  if (pieces.length == 1) {
    return measureRefOfSolid(pieces.first.$2,
        at: pieces.first.$1,
        component: component,
        owner: owner,
        hitAt: hitAt);
  }
  final tris = <Vec3>[];
  final curves = <List<Vec3>>[];
  var volume = 0.0;
  for (final (at, s) in pieces) {
    final one = measureRefOfSolid(s, at: at, component: component);
    final mesh = one.mesh;
    if (mesh != null) {
      tris.addAll(mesh.triangles);
      curves.addAll(mesh.curves);
    }
    volume += s.volume > 0 ? s.volume : 0;
  }
  var lo = const Vec3(double.infinity, double.infinity, double.infinity);
  var hi = Vec3(-double.infinity, -double.infinity, -double.infinity);
  for (final p in tris) {
    lo = Vec3(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z));
    hi = Vec3(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z));
  }
  if (tris.isEmpty) return null;
  var area = 0.0;
  for (var i = 0; i + 2 < tris.length; i += 3) {
    area += (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]).length * 0.5;
  }
  return MeasureRef.solid(lo, hi,
      component: component,
      owner: owner,
      volume: volume > 0 ? volume : null,
      area: area > 0 ? area : null,
      mesh: MeasureMesh(tris, curves, lo, hi),
      hitAt: hitAt);
}

// ===========================================================================
// 3D — a part
// ===========================================================================

/// What the tap at [px] measures in a part, or null.
///
/// [solids] is the part's VISIBLE solids, in the order the viewport draws
/// them; [names] labels them for the panel and may be shorter (or empty),
/// which is what a part with one unnamed body is.
MeasureRef? measurePickPart(
  List<KernelSolid> solids,
  Cam3 cam,
  Offset px, {
  MeasurePriority priority = MeasurePriority.entity,
  List<String?> names = const [],
}) {
  String? nameOf(int i) => i < names.length ? names[i] : null;

  if (priority != MeasurePriority.entity) {
    // The BODY under the finger. Found by the same frontmost-triangle test
    // the face pick uses, so the body measured is the body highlighted.
    var bestDepth = double.infinity;
    var best = -1;
    Vec3? hit;
    for (var i = 0; i < solids.length; i++) {
      final f = frontFaceUnder(solids[i].mesh, cam, px, cam.depth);
      if (f == null || f.$3 >= bestDepth) continue;
      bestDepth = f.$3;
      best = i;
      hit = f.$2;
    }
    if (best < 0) return null;
    return measureRefOfSolid(solids[best],
        owner: nameOf(best), hitAt: hit);
  }

  MeasurePick? best;
  for (var i = 0; i < solids.length; i++) {
    final p = measurePickMesh(solids[i].mesh, cam, px, owner: nameOf(i));
    if (p == null) continue;
    if (best == null ||
        p.depth < best.depth - 1e-9 ||
        ((p.depth - best.depth).abs() <= 1e-9 && p.pixels < best.pixels)) {
      best = p;
    }
  }
  return best?.ref;
}

// ===========================================================================
// 3D — an assembly
// ===========================================================================

/// What the tap at [px] measures in an assembly, or null.
///
/// One pass per PIECE rather than one per component, exactly as
/// [pickAsmRef] does and for the same reason: a subassembly's parts each sit
/// somewhere inside it, so a single camera for the whole component would
/// hit-test them all at the subassembly's own origin.
///
/// What comes back is in WORLD coordinates, which is the difference between
/// this and asm_pick.dart. A constraint stores a reference in the component's
/// own frame so that it survives the solver moving the component; a
/// measurement is a reading of where things are RIGHT NOW, and the moment the
/// solver moves something the reading is stale by definition — the session
/// clears it rather than pretending otherwise.
MeasureRef? measurePickAssembly(
  AssemblyModel a,
  Cam3 cam,
  Offset px, {
  MeasurePriority priority = MeasurePriority.entity,
}) {
  if (priority == MeasurePriority.component ||
      priority == MeasurePriority.body) {
    return _measureWholeComponent(a, cam, px, whole: priority);
  }
  MeasurePick? best;
  for (final o in a.occurrences) {
    if (!o.visible || !o.loaded) continue;
    for (final (_, at, solid) in o.worldSolids) {
      final p = measurePickMesh(solid.mesh, cam, px,
          at: at, depthBase: cam.depth(at.at), owner: o.id);
      if (p == null) continue;
      if (best == null ||
          p.depth < best.depth - 1e-9 ||
          ((p.depth - best.depth).abs() <= 1e-9 && p.pixels < best.pixels)) {
        best = p;
      }
    }
  }
  return best?.ref;
}

/// The whole COMPONENT (or the single BODY) under the tap.
MeasureRef? _measureWholeComponent(AssemblyModel a, Cam3 cam, Offset px,
    {required MeasurePriority whole}) {
  AssemblyOccurrence? bestOcc;
  var bestDepth = double.infinity;
  Placement? bestAt;
  KernelSolid? bestSolid;
  Vec3? bestHit;
  for (final o in a.occurrences) {
    if (!o.visible || !o.loaded) continue;
    for (final (_, at, solid) in o.worldSolids) {
      final sc = placedCam(cam, at);
      final base = cam.depth(at.at);
      final f = frontFaceUnder(
          solid.mesh, sc, px, (v) => sc.depth(v) + base);
      if (f == null || f.$3 >= bestDepth) continue;
      bestDepth = f.$3;
      bestOcc = o;
      bestAt = at;
      bestSolid = solid;
      bestHit = at.apply(f.$2);
    }
  }
  if (bestOcc == null) return null;
  if (whole == MeasurePriority.body) {
    return measureRefOfSolid(bestSolid!,
        at: bestAt!, owner: bestOcc.id, hitAt: bestHit);
  }
  return measureRefOfSolids(
      [for (final (_, at, s) in bestOcc.worldSolids) (at, s)],
      component: true,
      owner: bestOcc.id,
      hitAt: bestHit);
}

// ===========================================================================
// sketch curves in 3D
// ===========================================================================

/// A sketch curve drawn in the 3D viewport, as something measurable.
///
/// The 2D reading, lifted onto the sketch's plane by [frame]. One
/// implementation of "how long is this spline" for both viewports, which is
/// what stops the 2D and 3D answers from ever disagreeing.
MeasureRef? measureRefOfSketchCurve(Geo g, PlaneFrame frame, {Vec3? hitAt}) {
  final flat = measureRefOfGeo(g);
  if (flat == null) return null;
  Vec3 up(Vec3 v) => frame.origin + frame.u * v.x + frame.v * v.y;
  Vec3 upDir(Vec3 v) => frame.u * v.x + frame.v * v.y + frame.n * v.z;
  switch (flat.kind) {
    case MeasureRefKind.point:
      return MeasureRef.point(up(flat.point!));
    case MeasureRefKind.line:
      return MeasureRef.segment(up(flat.a!), up(flat.b!), hitAt: hitAt);
    case MeasureRefKind.circle:
      return MeasureRef.circle(up(flat.point!), frame.n, flat.radius!,
          samples: [for (final p in flat.samples) up(p)], hitAt: hitAt);
    case MeasureRefKind.arc:
      return MeasureRef.arc(
          up(flat.point!), frame.n, flat.radius!, flat.sweep ?? 0,
          samples: [for (final p in flat.samples) up(p)], hitAt: hitAt);
    case MeasureRefKind.ellipse:
      return MeasureRef.ellipse(up(flat.point!), frame.n, flat.radius!,
          flat.minorRadius ?? 0,
          length: flat.length,
          samples: [for (final p in flat.samples) up(p)],
          hitAt: hitAt);
    case MeasureRefKind.curve:
      return MeasureRef.curve([for (final p in flat.samples) up(p)],
          closed: flat.closed, planeNormal: upDir(const Vec3(0, 0, 1)),
          hitAt: hitAt);
    default:
      return null;
  }
}
