// M242 — turning a tap in the assembly viewport into a CONSTRAINT SELECTION.
//
// The part viewport has _pickWorkRef for this: tap something, get back "a
// point, a line or a plane". An assembly needs the same answer and cannot
// reuse that code, for one reason that runs through this whole milestone —
// a component is a part sitting somewhere else. Every mesh in it is in the
// SOURCE PART's coordinates and only the occurrence's rigid transform says
// where that is on screen.
//
// Two consequences, and they are the whole design of this file:
//
//   * The pick runs under a PLACED CAMERA (part_render.placedCam), never
//     against a transformed mesh. project(R*l + t) == placedCam(...).project(l)
//     exactly, so a component is picked where it is drawn without a single
//     vertex being copied — the same identity the renderer runs on.
//
//   * What comes back is stored in the component's OWN coordinates. That is
//     the difference between a constraint and a snap: the moment the solver
//     moves the component, a world-space reference would still be naming
//     where the face used to be. [AsmPick.world] carries the world form
//     alongside, because the preview and the highlight need it NOW.
//
// PICK ORDER is by DEPTH, not by category. The part viewport answers origin
// geometry first and faces last; that works there because a part's origin
// planes are small. An assembly's are sized to its whole contents, so a
// category order would make a visible XY plane swallow every tap in the
// document. Everything competes on depth instead, with an EDGE BIAS so that
// a circular edge still wins over the cylindrical face it bounds — which is
// what makes Insert reachable, since Insert is created by picking two
// circular edges.
//
// Depth convention, stated once because two contradictory ones exist in this
// tree: the RENDERER's. Cam3.depth is w.(-dir), so LARGER is nearer, and a
// face is visible when its outward normal has n.dir < 0. paintPartSolids,
// buildSceneSolid and pickOccurrence all run on that rule and so does this.
// part_pick.PickBest uses the opposite (smaller = nearer), which is why the
// edge pass below hands it a NEGATED depth function.
import 'dart:math' as math;
import 'dart:ui';

import 'asm_constraints.dart';
import 'assembly.dart';
import 'part_model.dart';
import 'part_pick.dart';
import 'pick_math.dart';
import 'part_render.dart';

/// One thing the user could have meant, with everything three callers need:
/// the reference to STORE, the geometry to draw NOW, and the depth that
/// decides between candidates.
class AsmPick {
  const AsmPick(this.ref, this.world, this.depth, this.hit);

  /// What to store on the constraint — geometry in the component's own frame.
  final AsmRef ref;

  /// The same geometry in WORLD coordinates, for the highlight and the
  /// predicted offset. Recomputing it from [ref] needs the occurrence, so it
  /// travels with the pick rather than being derived twice.
  final AsmGeom world;

  /// Cam3.depth of the touched point. LARGER is nearer — see the file header.
  final double depth;

  /// The world point actually under the finger.
  final Vec3 hit;

  String get occurrence => ref.occurrence;
}

/// How much nearer an edge counts than the face it bounds, in world units.
///
/// Without it a circular edge never wins: it lies exactly ON the cylindrical
/// face and the two report the same depth, so the face's larger hit area
/// would take every tap and Insert would be unreachable by pointing at the
/// hole you want the bolt in.
const double kAsmEdgeBias = 0.6;

/// What the user pointed at, or null.
AsmPick? pickAsmRef(AssemblyModel a, Cam3 cam, Offset px) {
  AsmPick? best;
  void offer(AsmPick? p) {
    if (p == null) return;
    if (best == null || p.depth > best!.depth) best = p;
  }

  for (final o in a.occurrences) {
    if (!o.visible || !o.loaded) continue;
    offer(_pickEdgeOn(o, cam, px));
    offer(_pickFaceOn(o, cam, px));
  }
  offer(_pickOriginOf(a, cam, px));
  return best;
}

// ---------------------------------------------------------------------------
// components
// ---------------------------------------------------------------------------

/// The frontmost B-Rep edge of [o] under [px], as the axis / point it stands
/// for.
///
/// A CIRCULAR edge answers with its centre and its axis, which is the pair
/// Insert and Mate both want; a straight edge answers with its line; anything
/// else (a spline) answers with its arc-length midpoint, which is still an
/// honest thing to constrain to.
AsmPick? _pickEdgeOn(AssemblyOccurrence o, Cam3 cam, Offset px) {
  final solids = o.solids.toList();
  if (solids.isEmpty) return null;
  final sc = placedCam(cam, o.rot, o.offset);
  final base = cam.depth(o.offset);
  final hit = pickEdge(
    [for (final s in solids) s.mesh],
    sc.project,
    // NEGATED: PickBest keeps the SMALLEST depth, and this file's convention
    // is that the largest is nearest. sc.depth is measured from the
    // component's own origin, so the placement's own depth is added back to
    // put every component into one depth space (the rule buildSceneSolid's
    // depthBias states).
    (w) => -(sc.depth(w) + base),
    px,
    // A component's edges are for pointing at, not for filleting: an edge
    // with no topological id is still a perfectly good circle to insert a
    // bolt into, and requiring one would drop every edge of a mesh that
    // carries no id map at all.
    requireTopoId: false,
  );
  if (hit == null) return null;
  final m = solids[hit.meshIndex].mesh;
  final world = o.toWorld(hit.point);
  final depth = cam.depth(world) + kAsmEdgeBias;
  final ci = hit.displayEdge * 16;
  if (ci >= 0 && ci + 16 <= m.edgeCurves.length) {
    final c = m.edgeCurves;
    final type = c[ci].round();
    if (type == 1) {
      final p0 = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
      final p1 = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
      final d = p1 - p0;
      if (d.length > 1e-9) {
        return _local(o, AsmGeom.axis(p0, d.normalized()), 'Edge', depth,
            world);
      }
    } else if (type == 2 || type == 3) {
      final centre = Vec3(c[ci + 1], c[ci + 2], c[ci + 3]);
      final xd = Vec3(c[ci + 4], c[ci + 5], c[ci + 6]);
      final yd = Vec3(c[ci + 7], c[ci + 8], c[ci + 9]);
      final axis = xd.cross(yd);
      if (axis.length > 1e-9) {
        return _local(
            o,
            // The RADIUS travels with it: a circular edge is what Tangent and
            // Insert are usually reached through, and dropping the radius
            // here is what would make Tangent refuse a perfectly round pick.
            AsmGeom.axis(centre, axis.normalized(),
                radius: type == 2 ? c[ci + 10] : 0),
            type == 2 ? 'Circular Edge' : 'Elliptical Edge',
            depth,
            world);
      }
    }
  }
  // No analytic record: the arc-length midpoint is still a real Inventor
  // input, and it is exactly what a Mate between two vertices needs.
  return _local(o, AsmGeom.point(hit.mid), 'Edge Midpoint', depth, world);
}

/// The frontmost face of [o] under [px], as the plane / axis / point it
/// stands for. Null when the tap missed, or when the surface offers nothing
/// a constraint can act on.
AsmPick? _pickFaceOn(AssemblyOccurrence o, Cam3 cam, Offset px) {
  final sc = placedCam(cam, o.rot, o.offset);
  final base = cam.depth(o.offset);
  List<double>? bestInfo;
  var bestDepth = double.negativeInfinity;
  var bestHit = Vec3.zero;
  for (final s in o.solids) {
    final m = s.mesh;
    if (m.triFaces.length * 3 != m.indices.length || m.faceInfos.isEmpty) {
      continue; // no face identity on this mesh: nothing to report
    }
    for (var t = 0; t < m.indices.length; t += 3) {
      final i0 = m.indices[t] * 3,
          i1 = m.indices[t + 1] * 3,
          i2 = m.indices[t + 2] * 3;
      if (i0 + 2 >= m.positions.length ||
          i1 + 2 >= m.positions.length ||
          i2 + 2 >= m.positions.length) {
        continue;
      }
      final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
      final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
      final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
      final n = (w1 - w0).cross(w2 - w0);
      // Camera-facing only, the renderer's rule — see the file header.
      if (n.length < 1e-12 || n.normalized().dot(sc.dir) >= 0) continue;
      final a = sc.project(w0), b = sc.project(w1), c = sc.project(w2);
      final den = (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
      if (den.abs() < 1e-9) continue;
      final l0 =
          ((b.dy - c.dy) * (px.dx - c.dx) + (c.dx - b.dx) * (px.dy - c.dy)) /
              den;
      final l1 =
          ((c.dy - a.dy) * (px.dx - c.dx) + (a.dx - c.dx) * (px.dy - c.dy)) /
              den;
      final l2 = 1 - l0 - l1;
      const e = -1e-6;
      if (l0 < e || l1 < e || l2 < e) continue;
      final local = w0 * l0 + w1 * l1 + w2 * l2;
      final d = sc.depth(local) + base;
      if (d <= bestDepth) continue;
      final fid = m.triFaces[t ~/ 3];
      if (fid < 0 || 15 * fid + 15 > m.faceInfos.length) continue;
      bestDepth = d;
      bestInfo = m.faceInfos.sublist(15 * fid, 15 * fid + 15);
      bestHit = local;
    }
  }
  final info = bestInfo;
  if (info == null) return null;
  final type = info[0].round();
  final at = Vec3(info[1], info[2], info[3]);
  final dir = Vec3(info[4], info[5], info[6]);
  final world = o.toWorld(bestHit);
  if (dir.length < 1e-9 && type != kFacePlane) return null;
  return switch (type) {
    kFacePlane => _local(o, AsmGeom.plane(at, dir), 'Face', bestDepth, world),
    kFaceCylinder => _local(
        o,
        AsmGeom.axis(at, dir, radius: info[10]),
        'Cylindrical Face',
        bestDepth,
        world),
    // A cone has an axis and no single radius, so it constrains like an axis
    // and refuses Tangent — which is what Inventor does with one too.
    kFaceCone =>
      _local(o, AsmGeom.axis(at, dir), 'Conical Face', bestDepth, world),
    kFaceSphere =>
      _local(o, AsmGeom.point(at), 'Spherical Face', bestDepth, world),
    kFaceTorus =>
      _local(o, AsmGeom.axis(at, dir), 'Toroidal Face', bestDepth, world),
    // A surface with no axis and no centre offers nothing to constrain to.
    _ => null,
  };
}

/// Wraps geometry already in [o]'s LOCAL frame into a pick, computing the
/// world form once.
AsmPick _local(AssemblyOccurrence o, AsmGeom localGeom, String label,
    double depth, Vec3 hit) {
  final world = AsmGeom(
    localGeom.kind,
    o.toWorld(localGeom.at),
    localGeom.dir.length < 1e-12 ? Vec3.zero : o.dirToWorld(localGeom.dir),
    radius: localGeom.radius,
  );
  return AsmPick(AsmRef(o.id, localGeom, label), world, depth, hit);
}

// ---------------------------------------------------------------------------
// the assembly's own origin
// ---------------------------------------------------------------------------

/// How near, in pixels, a tap must be to an origin AXIS or the centre point.
const double kAsmOriginTolerancePx = 12.0;

/// The assembly's origin plane / axis / centre point under [px].
///
/// Only what is actually DRAWN answers: an invisible origin plane is not on
/// screen, so picking one would be picking something the user cannot see.
/// This is the same rule the part viewport's _hitOrigin follows, and it is
/// what keeps the default assembly — every origin entity switched off —
/// picking exactly as it did before this milestone.
///
/// The geometry is stored in WORLD coordinates under [kAssemblyOrigin]: the
/// assembly's own origin does not move, so there is no frame to reduce it to.
AsmPick? _pickOriginOf(AssemblyModel a, Cam3 cam, Offset px) {
  AsmPick? best;
  void offer(AsmPick? p) {
    if (p == null) return;
    if (best == null || p.depth > best!.depth) best = p;
  }

  for (final key in kPlaneKeys) {
    if (a.vis[key] != true) continue;
    final f = planeFrame(key);
    final (uMin, uMax, vMin, vMax) = assemblyPlaneRect(a, key);
    final hit = cam.rayOnPlane(px, f.n);
    if (hit == null) continue;
    final uv = f.toSketch(hit);
    if (uv.dx < uMin || uv.dx > uMax || uv.dy < vMin || uv.dy > vMax) continue;
    offer(AsmPick(
        AsmRef(kAssemblyOrigin, AsmGeom.plane(Vec3.zero, f.n),
            '${key.toUpperCase()} Plane'),
        AsmGeom.plane(Vec3.zero, f.n),
        cam.depth(hit),
        hit));
  }
  for (final (key, dir) in const [
    ('x', Vec3(1, 0, 0)),
    ('y', Vec3(0, 1, 0)),
    ('z', Vec3(0, 0, 1)),
  ]) {
    if (a.vis[key] != true) continue;
    final (lo, hi) = assemblyAxisSpan(a, dir);
    final p0 = cam.project(dir * lo), p1 = cam.project(dir * hi);
    final (d2, t) = segDistSq(px, p0, p1);
    if (d2 > kAsmOriginTolerancePx * kAsmOriginTolerancePx) continue;
    final hit = dir * (lo + (hi - lo) * t);
    offer(AsmPick(
        AsmRef(kAssemblyOrigin, AsmGeom.axis(Vec3.zero, dir),
            '${key.toUpperCase()} Axis'),
        AsmGeom.axis(Vec3.zero, dir),
        // Nearer than a plane through it, so an axis lying in a visible
        // origin plane can still be taken.
        cam.depth(hit) + kAsmEdgeBias,
        hit));
  }
  if (a.vis['cp'] == true &&
      (cam.project(Vec3.zero) - px).distance <= kAsmOriginTolerancePx) {
    offer(AsmPick(
        const AsmRef(kAssemblyOrigin, AsmGeom.point(Vec3.zero), 'Center Point'),
        const AsmGeom.point(Vec3.zero),
        cam.depth(Vec3.zero) + 2 * kAsmEdgeBias,
        Vec3.zero));
  }
  return best;
}

// ---------------------------------------------------------------------------
// what a picked pair currently measures
// ---------------------------------------------------------------------------

/// The offset or angle the two selections ALREADY have, in the units
/// [valueKindOf] gives the kind — millimetres or degrees.
///
/// This is Inventor's "Predict Offset and Orientation": with it on, the
/// dialog opens the field at whatever the parts currently measure, so
/// applying the constraint holds them where they are instead of snapping them
/// together. With it off the field stays at zero and the parts close up.
///
/// Returns null when the pair measures nothing meaningful for that kind —
/// two collinear axes have no offset worth naming, and the field is left as
/// it is rather than being filled with a fiction.
double? predictedValue(
    AsmKind kind, AsmSolution solution, AsmGeom a, AsmGeom b) {
  switch (valueKindOf(kind)) {
    case AsmValueKind.angle:
      final deg = angleBetweenDeg(a.dir, b.dir);
      if (solution == AsmSolution.undirectedAngle) return deg;
      // A directed angle is signed about the reference the constraint will
      // capture, which is a.dir x b.dir — and about THAT axis the signed
      // angle is the unsigned one by construction.
      return deg;
    case AsmValueKind.offset:
      return _separation(kind, solution, a, b);
    case AsmValueKind.ratio:
    case AsmValueKind.distancePerTurn:
    case AsmValueKind.none:
      return null;
  }
}

double? _separation(
    AsmKind kind, AsmSolution solution, AsmGeom a, AsmGeom b) {
  if (kind == AsmKind.tangent) {
    final (cyl, pl) = a.isCylinder && b.isPlane
        ? (a, b)
        : (b.isCylinder && a.isPlane ? (b, a) : (null, null));
    if (cyl != null && pl != null) {
      final n = pl.dir.normalized();
      final gap = (cyl.at - pl.at).dot(n);
      final s = solution == AsmSolution.outside ? 1.0 : -1.0;
      return gap / s - cyl.radius;
    }
    if (a.isCylinder && b.isCylinder) {
      final perp = b.at - a.at - a.dir.normalized() * (b.at - a.at).dot(a.dir.normalized());
      return perp.length -
          (solution == AsmSolution.outside
              ? a.radius + b.radius
              : (a.radius - b.radius).abs());
    }
    return null;
  }
  if (kind == AsmKind.insert) {
    if (!a.isAxis || !b.isAxis) return null;
    return (b.at - a.at).dot(a.dir.normalized());
  }
  // Mate / Flush.
  if (a.isPlane && (b.isPlane || b.isPoint || b.isAxis)) {
    return (b.at - a.at).dot(a.dir.normalized());
  }
  if (b.isPlane && (a.isPoint || a.isAxis)) {
    return (a.at - b.at).dot(b.dir.normalized());
  }
  if (a.isPoint && b.isPoint) return (b.at - a.at).length;
  return null; // two axes: see AsmSolver._mate, an offset names nothing there
}

/// The world segment or outline to DRAW for a picked reference, so the user
/// can see what they selected. Screen-space decoration; the viewport paints
/// it and RealityKit is told nothing about it.
///
/// [size] is how big to draw something that has no size of its own — an
/// infinite plane, an axis — and comes from the assembly's extent so the
/// marker is legible on a 5 mm part and on a 500 mm one.
List<Vec3> refMarker(AsmGeom g, double size) {
  switch (g.kind) {
    case AsmGeomKind.plane:
      final n = g.dir.normalized();
      if (n.length < 0.5) return [g.at];
      final u = _anyPerp(n), v = n.cross(u).normalized();
      final r = size;
      return [
        g.at + u * r + v * r,
        g.at - u * r + v * r,
        g.at - u * r - v * r,
        g.at + u * r - v * r,
      ];
    case AsmGeomKind.axis:
      final d = g.dir.normalized();
      if (d.length < 0.5) return [g.at];
      if (g.radius > 1e-9) {
        // A CIRCLE, drawn as a polygon: a cylindrical face or a circular edge
        // reads as a ring, and a bare line through the middle of a hole does
        // not say which hole.
        final u = _anyPerp(d) * g.radius, v = d.cross(_anyPerp(d)).normalized() * g.radius;
        return [
          for (var i = 0; i <= 32; i++)
            g.at +
                u * math.cos(i * math.pi / 16) +
                v * math.sin(i * math.pi / 16)
        ];
      }
      return [g.at - d * size, g.at + d * size];
    case AsmGeomKind.point:
      return [g.at];
  }
}

Vec3 _anyPerp(Vec3 v) {
  final ax = v.x.abs(), ay = v.y.abs(), az = v.z.abs();
  final other = (ax <= ay && ax <= az)
      ? const Vec3(1, 0, 0)
      : (ay <= az ? const Vec3(0, 1, 0) : const Vec3(0, 0, 1));
  return v.cross(other).normalized();
}
