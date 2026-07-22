// iPadProCAD — shared 3D render helpers (M57).
//
// The orthographic turntable camera math (Cam3) and the shaded-solid painter
// (paintPartSolids) were born inside widgets/viewport3d.dart. They are lifted
// here, verbatim in behaviour, so a SECOND caller can reuse them: the gallery
// needs the very same picture rendered off-screen into a thumbnail PNG
// (AppState._writePartPreview) as the live viewport draws on screen.
//
// This file deliberately depends ONLY on part_model.dart (Vec3, PartCamera,
// KernelSolid) and Flutter painting — never on app_state.dart. viewport3d
// imports app_state, so if this shared code did too the import graph would
// close a cycle. Keeping the ExtrudeSession out of paintPartSolids (the caller
// pre-selects which solids to draw and passes the live preview explicitly) is
// what keeps it app_state-free.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ffi/occt_engine.dart' show OcctMeshData;
import 'part_model.dart';

// Steel, same family as partCubeIcon — the committed-solid look.
const Color kSolidBase = Color(0xFF8C939A);
const Color kSolidEdge = Color(0xFF23272C);

/// Shared orthographic camera math (also used by the ViewCube/triad).
class Cam3 {
  final Vec3 dir, s, u; // view direction (camera at dir*D), right, up
  final double halfH, ox, oy;
  final Size size;
  Cam3(PartCamera c, this.size)
      : dir = c.dir,
        halfH = c.halfH,
        ox = c.ox,
        oy = c.oy,
        s = _basisS(c.dir),
        u = _basisU(c.dir);

  /// Explicit-basis camera (M59): the sketch-underlay looks straight down a
  /// face frame, whose u/v axes must map to screen x/y EXACTLY as the 2D
  /// editor draws them — so the basis is given, not derived from world-up.
  const Cam3.basis(
      {required this.dir,
      required this.s,
      required this.u,
      required this.halfH,
      required this.ox,
      required this.oy,
      required this.size});

  static Vec3 _fwd(Vec3 d) => d * -1;
  static Vec3 _basisS(Vec3 d) {
    final f = _fwd(d);
    var s = f.cross(const Vec3(0, 1, 0));
    if (s.length < 1e-9) s = f.cross(const Vec3(0, 0, 1));
    return s.normalized();
  }

  static Vec3 _basisU(Vec3 d) => _basisS(d).cross(_fwd(d)).normalized();

  double get aspect => size.width / size.height;

  Offset project(Vec3 w) {
    final x = (w.dot(s) - ox) / (halfH * aspect);
    final y = (w.dot(u) - oy) / halfH;
    return Offset(
        (x * 0.5 + 0.5) * size.width, (1 - (y * 0.5 + 0.5)) * size.height);
  }

  /// Signed view coordinate along the ray: NEARER the camera = LARGER value
  /// (depth = w·(-dir); the camera sits on the -dir side looking along dir).
  double depth(Vec3 w) => w.dot(_fwd(dir));

  /// LINEAR part of [project]: the screen displacement of a world VECTOR.
  /// The orthographic projection is affine, so any circle/ellipse maps to
  /// screen(t) = project(center) + projectVec(A)·cos t + projectVec(B)·sin t
  /// — which is how analytic edges are drawn without any tessellation.
  Offset projectVec(Vec3 v) => Offset(
      v.dot(s) / (halfH * aspect) * 0.5 * size.width,
      -v.dot(u) / halfH * 0.5 * size.height);

  /// World point of pixel [p] on the camera plane through the origin.
  Vec3 unprojectOnCamPlane(Offset p) {
    final wx = ((p.dx / size.width) * 2 - 1) * halfH * aspect + ox;
    final wy = ((1 - p.dy / size.height) * 2 - 1) * halfH + oy;
    return s * wx + u * wy;
  }

  /// Intersection of the pixel ray with the plane n·X = 0, or null when
  /// looking edge-on.
  Vec3? rayOnPlane(Offset p, Vec3 n) {
    final o = unprojectOnCamPlane(p);
    final rd = _fwd(dir);
    final denom = n.dot(rd);
    if (denom.abs() < 1e-9) return null;
    final t = -n.dot(o) / denom;
    return o + rd * t;
  }
}

/// Depth-sorted shaded triangles + B-Rep edges for a set of solids (the
/// painter's algorithm — no GPU dependency, so it works both on screen and in
/// an off-screen [PictureRecorder]).
///
/// The caller decides WHICH solids to draw: the live viewport passes the
/// visible committed features minus the one being edited and hands the live
/// extrude preview in [previewSolid]; the gallery thumbnail passes every
/// visible solid and no preview. Because the selection happens outside, this
/// function never needs to know about ExtrudeSession — which is what keeps it
/// free of an app_state import.
/// One front-facing mesh triangle on screen: projected corners, painter depth
/// and its flat shade (0..1). Pure output of [projectSolidTriangles] so host
/// tests can drive the real painter math with real curvature — no Canvas.
class ProjectedTri {
  final Offset a, b, c;
  final double depth, shade;
  const ProjectedTri(this.a, this.b, this.c, this.depth, this.shade);
}

/// One B-Rep edge segment on screen (viewer-biased depth, see below).
class ProjectedEdge {
  final Offset a, b;
  final double depth;
  const ProjectedEdge(this.a, this.b, this.depth);
}

/// The headlight for shading: it comes FROM the camera (along -dir) with a
/// fixed tilt, so a face pointing at the viewer is brightest and one angled
/// away darkens smoothly. (depth/facing convention: camera looks along dir.)
Vec3 solidLight(Cam3 cam) =>
    (cam.dir * -1 + const Vec3(0.35, 0.55, 0.2)).normalized();

/// Projects the front-facing triangles of [m]: backface-culled against the
/// camera, flat-shaded against [solidLight], depth = triangle centroid along
/// the view ray (painter's algorithm sorts far-to-near on it).
List<ProjectedTri> projectSolidTriangles(OcctMeshData m, Cam3 cam) {
  final light = solidLight(cam);
  final out = <ProjectedTri>[];
  for (var t = 0; t < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (w1 - w0).cross(w2 - w0).normalized();
    if (n.dot(cam.dir) >= 0) continue; // backface (visible face has n·dir<0)
    final shade =
        (0.42 + 0.58 * math.max(0, n.dot(light))).clamp(0.0, 1.0).toDouble();
    out.add(ProjectedTri(cam.project(w0), cam.project(w1), cam.project(w2),
        (cam.depth(w0) + cam.depth(w1) + cam.depth(w2)) / 3, shade));
  }
  return out;
}

/// Projects the B-Rep edge polylines of [m] as screen segments. The depth
/// carries the 0.35 viewer bias so an edge draws over the faces it borders.
List<ProjectedEdge> projectSolidEdges(OcctMeshData m, Cam3 cam) {
  final out = <ProjectedEdge>[];
  for (var e = 0; e + 1 < m.edgeStarts.length; e++) {
    for (var k = m.edgeStarts[e]; k + 1 < m.edgeStarts[e + 1]; k++) {
      final p0 = Vec3(m.edgePoints[3 * k], m.edgePoints[3 * k + 1],
          m.edgePoints[3 * k + 2]);
      final p1 = Vec3(m.edgePoints[3 * k + 3], m.edgePoints[3 * k + 4],
          m.edgePoints[3 * k + 5]);
      out.add(ProjectedEdge(cam.project(p0), cam.project(p1),
          (cam.depth(p0) + cam.depth(p1)) / 2 - 0.35));
    }
  }
  return out;
}

// ===========================================================================
// M59 — Inventor "Shaded with Edges" pipeline.
//
// Faces: ONE depth-sorted ui.Vertices buffer with GOURAUD shading (per-vertex
// colours from the OCCT vertex normals). Adjacent triangles share exact
// vertex positions inside one drawVertices call, so the rasterizer is
// watertight by construction — no AA cracks, no per-triangle strokes, no
// facet banding, and a translucent preview shows no inner wireframe.
//
// Edges: drawn as ANALYTIC vector curves. The shim exports each edge's curve
// (line / circle / ellipse); an orthographic camera is affine, so those
// project to lines and ellipses that Flutter draws as exact béziers — smooth
// at every zoom. Unknown curve types fall back to the adaptive polyline.
// Hidden portions are suppressed (Inventor's default): every edge is sampled
// and tested against a screen-space grid of the opaque triangles.
//
// Silhouettes: the contour a curved face shows against the background
// (Inventor's "Silhouettes" display). Cylinders get exact generator lines;
// other curved surfaces fall back to the front/back-facing boundary of
// their own triangles.
// ===========================================================================

/// Inventor-like prehighlight blue for hoverable faces (M59 / Phase 2).
const Color kFaceHighlight = Color(0xFF4FA3FF);

/// Surface-type codes of the 15-double face records (see occt_capi.h).
const int kFacePlane = 0, kFaceCylinder = 1;

/// Curve-type codes of the 16-double edge records (see occt_capi.h).
const int kEdgeOther = 0, kEdgeLine = 1, kEdgeCircle = 2, kEdgeEllipse = 3;

/// One projected triangle of the scene, with everything the pipeline needs:
/// screen corners, per-corner depths and shades, its B-Rep face, and whether
/// it faces the camera (backfaces are kept for silhouette detection).
class SceneTri {
  final Offset a, b, c;
  final double da, db, dc;
  final double sa, sb, sc;
  final int faceId;
  final bool front;
  const SceneTri(this.a, this.b, this.c, this.da, this.db, this.dc, this.sa,
      this.sb, this.sc, this.faceId, this.front);
  double get depth => (da + db + dc) / 3;
}

/// The projected triangles of ONE solid plus its occlusion bias (how deep a
/// point may sit behind a triangle before it counts as hidden — covers the
/// tessellation sag so an edge is never occluded by its own face's chords).
class SceneSolid {
  final KernelSolid solid;
  final List<SceneTri> tris;
  final double bias;
  final bool preview;
  const SceneSolid(this.solid, this.tris, this.bias, this.preview);
}

/// Projects [solid] with per-vertex Gouraud shades. Backfacing triangles are
/// included (front = false) so silhouette detection can see both sides.
SceneSolid buildSceneSolid(KernelSolid solid, Cam3 cam,
    {bool preview = false}) {
  final m = solid.mesh;
  final light = solidLight(cam);
  final tris = <SceneTri>[];
  var maxAbs = 0.0;
  for (var i = 0; i < m.positions.length; i++) {
    final a = m.positions[i].abs();
    if (a > maxAbs) maxAbs = a;
  }
  double shadeAt(int vi) {
    final n = Vec3(m.normals[vi], m.normals[vi + 1], m.normals[vi + 2]);
    return (0.42 + 0.58 * math.max(0, n.dot(light))).clamp(0.0, 1.0);
  }

  for (var t = 0; t < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (w1 - w0).cross(w2 - w0);
    if (n.length < 1e-15) continue;
    // A face is FRONT (visible) when its outward normal opposes the view
    // direction — the camera looks along dir, so a face we see points back
    // toward it (n·dir < 0). Backfaces (n·dir > 0) are kept with front=false
    // only for silhouette detection.
    final front = n.normalized().dot(cam.dir) < 0;
    tris.add(SceneTri(
        cam.project(w0),
        cam.project(w1),
        cam.project(w2),
        cam.depth(w0),
        cam.depth(w1),
        cam.depth(w2),
        shadeAt(i0),
        shadeAt(i1),
        shadeAt(i2),
        t ~/ 3 < m.triFaces.length ? m.triFaces[t ~/ 3] : -1,
        front));
  }
  final bias =
      math.max(1.5 * solid.meshLin, 1e-3 * math.max(maxAbs, 1e-6)) + 1e-9;
  return SceneSolid(solid, tris, bias, preview);
}

/// Screen-space occlusion structure over the FRONT triangles of the opaque
/// scene. A sample point is hidden when some triangle covers it strictly
/// nearer than the sample's own depth minus the owning solid's bias.
class SceneOccluders {
  final List<SceneTri> tris;
  final List<double> triBias; // per triangle, from its solid
  final Map<int, List<int>> _cells = {};
  static const double cell = 48;

  SceneOccluders(List<SceneSolid> solids)
      : tris = [
          for (final s in solids)
            if (!s.preview)
              for (final t in s.tris)
                if (t.front) t
        ],
        triBias = [
          for (final s in solids)
            if (!s.preview)
              for (final t in s.tris)
                if (t.front) s.bias
        ] {
    for (var i = 0; i < tris.length; i++) {
      final t = tris[i];
      final minX = math.min(t.a.dx, math.min(t.b.dx, t.c.dx));
      final maxX = math.max(t.a.dx, math.max(t.b.dx, t.c.dx));
      final minY = math.min(t.a.dy, math.min(t.b.dy, t.c.dy));
      final maxY = math.max(t.a.dy, math.max(t.b.dy, t.c.dy));
      for (var cx = (minX / cell).floor(); cx <= (maxX / cell).floor(); cx++) {
        for (var cy = (minY / cell).floor();
            cy <= (maxY / cell).floor();
            cy++) {
          (_cells[cx * 100003 + cy] ??= []).add(i);
        }
      }
    }
  }

  /// True when world point (projected to [p], view depth [d]) is behind an
  /// opaque triangle. [extra] adds to the per-triangle bias: edges and
  /// overlays that are KNOWN to lie on the surface pass a generous margin so
  /// they are never sawtoothed off by their own grazing-angle tessellation
  /// (only geometry meaningfully in front of them hides them).
  bool hidden(Offset p, double d, {double extra = 0}) {
    final key = (p.dx / cell).floor() * 100003 + (p.dy / cell).floor();
    final bucket = _cells[key];
    if (bucket == null) return false;
    for (final i in bucket) {
      final t = tris[i];
      final den = (t.b.dy - t.c.dy) * (t.a.dx - t.c.dx) +
          (t.c.dx - t.b.dx) * (t.a.dy - t.c.dy);
      if (den.abs() < 1e-12) continue;
      final l0 = ((t.b.dy - t.c.dy) * (p.dx - t.c.dx) +
              (t.c.dx - t.b.dx) * (p.dy - t.c.dy)) /
          den;
      final l1 = ((t.c.dy - t.a.dy) * (p.dx - t.c.dx) +
              (t.a.dx - t.c.dx) * (p.dy - t.c.dy)) /
          den;
      final l2 = 1 - l0 - l1;
      const e = 1e-6;
      if (l0 < -e || l1 < -e || l2 < -e) continue;
      final td = l0 * t.da + l1 * t.db + l2 * t.dc;
      // Convention: depth = w·(-dir), so NEARER the camera = HIGHER depth.
      // A point is hidden when some front triangle covers it at a depth
      // meaningfully NEARER (greater) than the point's own, beyond the
      // tessellation-sag bias (plus any caller [extra] margin).
      if (td > d + triBias[i] + extra) return true;
    }
    return false;
  }

  /// A generous depth margin for occluding EDGES/overlays that lie on the
  /// surface: several times the largest face bias, so a grazing-angle barrel
  /// triangle can never sawtooth an edge off, while geometry a real
  /// millimetre in front still hides it.
  double get edgeMargin {
    var m = 0.0;
    for (final b in triBias) {
      if (b > m) m = b;
    }
    return m * 6;
  }
}

/// Groups a boolean visibility sampling into inclusive index runs of
/// consecutive `true`s: [(first, last), ...]. Pure; host-tested.
List<(int, int)> visibleRuns(List<bool> vis) {
  final out = <(int, int)>[];
  int? start;
  for (var i = 0; i < vis.length; i++) {
    if (vis[i]) {
      start ??= i;
    } else if (start != null) {
      out.add((start, i - 1));
      start = null;
    }
  }
  if (start != null) out.add((start, vis.length - 1));
  return out;
}

/// Control points of cubic béziers tracing the generalized arc
/// p(t) = C + A·cos t + B·sin t for t in [t0, t1] (any affine image of a
/// circle/ellipse — the projected form of every round edge). Returns
/// [p0, c1, c2, p1, c1, c2, p2, ...]; each span covers <= pi/2.
/// Standard tangent-matching construction: k = 4/3 · tan(dt/4).
List<Offset> genArcCubics(
    Offset c, Offset ax, Offset ay, double t0, double t1) {
  final pts = <Offset>[];
  final total = t1 - t0;
  if (total.abs() < 1e-12) return pts;
  // <= 30 deg per span: with the classic k = 4/3 tan(dt/4) tangent
  // construction this holds the cubic within ~3e-4 * radius of the true
  // arc — sub-pixel until absurd zoom, and the segment count stays tiny.
  final nSeg = math.max(1, (total.abs() / (math.pi / 6)).ceil());
  final dt = total / nSeg;
  final k = 4 / 3 * math.tan(dt / 4);
  Offset p(double t) => c + ax * math.cos(t) + ay * math.sin(t);
  Offset dp(double t) => ax * -math.sin(t) + ay * math.cos(t);
  pts.add(p(t0));
  for (var i = 0; i < nSeg; i++) {
    final a = t0 + dt * i, b = a + dt;
    pts.add(p(a) + dp(a) * k);
    pts.add(p(b) - dp(b) * k);
    pts.add(p(b));
  }
  return pts;
}

/// One display edge of a mesh in renderable form.
class DisplayEdge {
  final int type; // kEdge*
  // analytic (world space):
  final Vec3 c, ax, ay; // circle/ellipse frame (ax/ay scaled by radii)
  final Vec3 p0, p1; // line endpoints
  final double t0, t1;
  // fallback:
  final int polyStart, polyEnd; // index range into mesh.edgePoints (points)
  const DisplayEdge(this.type, this.c, this.ax, this.ay, this.p0, this.p1,
      this.t0, this.t1, this.polyStart, this.polyEnd);

  /// Parses the v4 records of [m]; when records are missing every edge is a
  /// type-0 polyline (fake meshes, legacy binaries).
  static List<DisplayEdge> of(OcctMeshData m) {
    final out = <DisplayEdge>[];
    final ne = m.edgeCount;
    for (var e = 0; e < ne; e++) {
      final ps = m.edgeStarts[e], pe = m.edgeStarts[e + 1];
      if (m.edgeCurves.length >= 16 * (e + 1)) {
        final r = m.edgeCurves.sublist(16 * e, 16 * e + 16);
        final type = r[0].round();
        if (type == kEdgeLine) {
          out.add(DisplayEdge(kEdgeLine, Vec3.zero, Vec3.zero, Vec3.zero,
              Vec3(r[1], r[2], r[3]), Vec3(r[4], r[5], r[6]), 0, 1, ps, pe));
          continue;
        }
        if (type == kEdgeCircle) {
          final rad = r[10];
          out.add(DisplayEdge(
              kEdgeCircle,
              Vec3(r[1], r[2], r[3]),
              Vec3(r[4], r[5], r[6]) * rad,
              Vec3(r[7], r[8], r[9]) * rad,
              Vec3.zero,
              Vec3.zero,
              r[11],
              r[12],
              ps,
              pe));
          continue;
        }
        if (type == kEdgeEllipse) {
          out.add(DisplayEdge(
              kEdgeEllipse,
              Vec3(r[1], r[2], r[3]),
              Vec3(r[4], r[5], r[6]) * r[10],
              Vec3(r[7], r[8], r[9]) * r[11],
              Vec3.zero,
              Vec3.zero,
              r[12],
              r[13],
              ps,
              pe));
          continue;
        }
      }
      out.add(DisplayEdge(kEdgeOther, Vec3.zero, Vec3.zero, Vec3.zero,
          Vec3.zero, Vec3.zero, 0, 0, ps, pe));
    }
    return out;
  }

  Vec3 pointAt(double t) => type == kEdgeLine
      ? p0 + (p1 - p0) * t
      : c + ax * math.cos(t) + ay * math.sin(t);
}

/// Exact silhouette generator lines of a cylindrical face for camera [cam]:
/// the two axis-parallel lines where the surface normal is perpendicular to
/// the view. Returns world segments (may be 0 for partial barrels that do
/// not span the tangency angle). Record layout: see occt_capi.h.
List<(Vec3, Vec3)> cylinderSilhouettes(List<double> rec, Cam3 cam) {
  final o = Vec3(rec[1], rec[2], rec[3]);
  final a = Vec3(rec[4], rec[5], rec[6]).normalized();
  final xd = Vec3(rec[7], rec[8], rec[9]).normalized();
  final r = rec[10];
  final u0 = rec[11], u1 = rec[12], v0 = rec[13], v1 = rec[14];
  if (!(r > 0) || !v0.isFinite || !v1.isFinite) return const [];
  final yd = a.cross(xd).normalized();
  final dx = cam.dir.dot(xd), dy = cam.dir.dot(yd);
  if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return const []; // axis view
  final th0 = math.atan2(-dx, dy);
  final full = (u1 - u0) >= 2 * math.pi - 1e-6;
  bool inRange(double th) {
    if (full) return true;
    var t = th - u0;
    t -= (t / (2 * math.pi)).floor() * 2 * math.pi;
    return t <= (u1 - u0) + 1e-9;
  }

  final out = <(Vec3, Vec3)>[];
  for (final th in [th0, th0 + math.pi]) {
    if (!inRange(th)) continue;
    final w = xd * math.cos(th) + yd * math.sin(th);
    out.add((o + a * v0 + w * r, o + a * v1 + w * r));
  }
  return out;
}

/// Mesh-based silhouette for curved faces without an analytic rule: the
/// shared edges between a front- and a back-facing triangle of the SAME
/// face. Fine adaptive tessellation keeps this visually smooth.
List<(Offset, Offset, double)> meshSilhouetteSegments(
    OcctMeshData m, SceneSolid scene, int faceId) {
  // pass 1: remember the FIRST triangle using each undirected vertex pair
  final byEdge = <int, (int, bool)>{}; // packed pair -> (tri, front)
  final out = <(Offset, Offset, double)>[];
  for (var t = 0; t < scene.tris.length; t++) {
    if (scene.tris[t].faceId != faceId) continue;
    final i0 = m.indices[3 * t],
        i1 = m.indices[3 * t + 1],
        i2 = m.indices[3 * t + 2];
    final front = scene.tris[t].front;
    for (final (a, b) in [(i0, i1), (i1, i2), (i2, i0)]) {
      final key = a < b ? a * 1000003 + b : b * 1000003 + a;
      byEdge.putIfAbsent(key, () => (t, front));
    }
  }
  // pass 2: a pair whose two triangles face opposite ways is a silhouette
  final seen = <int, bool>{};
  for (var t = 0; t < scene.tris.length; t++) {
    if (scene.tris[t].faceId != faceId) continue;
    final front = scene.tris[t].front;
    final idx = [m.indices[3 * t], m.indices[3 * t + 1], m.indices[3 * t + 2]];
    for (var k = 0; k < 3; k++) {
      final a = idx[k], b = idx[(k + 1) % 3];
      final key = a < b ? a * 1000003 + b : b * 1000003 + a;
      final other = byEdge[key];
      if (other == null || other.$1 == t) continue;
      if (scene.tris[other.$1].front == front) continue;
      if (seen.containsKey(key)) continue;
      seen[key] = true;
      Offset proj(int vi) {
        // reuse the already-projected corner from either triangle
        final tri = scene.tris[t];
        if (m.indices[3 * t] == vi) return tri.a;
        if (m.indices[3 * t + 1] == vi) return tri.b;
        return tri.c;
      }

      double depthOf(int vi) {
        final tri = scene.tris[t];
        if (m.indices[3 * t] == vi) return tri.da;
        if (m.indices[3 * t + 1] == vi) return tri.db;
        return tri.dc;
      }

      out.add((proj(a), proj(b), (depthOf(a) + depthOf(b)) / 2));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// The painter
// ---------------------------------------------------------------------------

void _drawShaded(Canvas canvas, List<SceneTri> tris, int alpha) {
  if (tris.isEmpty) return;
  final sorted = [for (final t in tris) t]
    // near = higher depth, so draw FAR (lower depth) first (painter's algo)
    ..sort((a, b) => a.depth.compareTo(b.depth));
  final pos = Float32List(sorted.length * 6);
  final col = Int32List(sorted.length * 3);
  var pi = 0, ci = 0;
  int shadeColor(double s) => Color.fromARGB(
          alpha,
          (kSolidBase.red * s).round(),
          (kSolidBase.green * s).round(),
          (kSolidBase.blue * s).round())
      .value;
  for (final t in sorted) {
    pos[pi++] = t.a.dx;
    pos[pi++] = t.a.dy;
    pos[pi++] = t.b.dx;
    pos[pi++] = t.b.dy;
    pos[pi++] = t.c.dx;
    pos[pi++] = t.c.dy;
    col[ci++] = shadeColor(t.sa);
    col[ci++] = shadeColor(t.sb);
    col[ci++] = shadeColor(t.sc);
  }
  final verts = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col);
  canvas.drawVertices(verts, BlendMode.dst, Paint());
}

void _strokeRuns(Canvas canvas, Path path, Color color) {
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color);
}

void _paintSolidEdges(Canvas canvas, Cam3 cam, SceneSolid scene,
    SceneOccluders occ, Color color) {
  final m = scene.solid.mesh;
  for (final e in DisplayEdge.of(m)) {
    if (e.type == kEdgeOther) {
      // adaptive polyline fallback with per-point visibility
      final n = e.polyEnd - e.polyStart;
      if (n < 2) continue;
      final pts = <Offset>[];
      final vis = <bool>[];
      for (var k = e.polyStart; k < e.polyEnd; k++) {
        final w = Vec3(m.edgePoints[3 * k], m.edgePoints[3 * k + 1],
            m.edgePoints[3 * k + 2]);
        final p = cam.project(w);
        pts.add(p);
        vis.add(!occ.hidden(p, cam.depth(w), extra: occ.edgeMargin));
      }
      final path = Path();
      for (final (a, b) in visibleRuns(vis)) {
        if (b == a) continue;
        path.moveTo(pts[a].dx, pts[a].dy);
        for (var k = a + 1; k <= b; k++) {
          path.lineTo(pts[k].dx, pts[k].dy);
        }
      }
      _strokeRuns(canvas, path, color);
      continue;
    }
    // analytic: sample for visibility, DRAW as exact vector geometry
    final sc = cam.project(e.type == kEdgeLine ? e.p0 : e.c);
    final sax = e.type == kEdgeLine ? Offset.zero : cam.projectVec(e.ax);
    final say = e.type == kEdgeLine ? Offset.zero : cam.projectVec(e.ay);
    final approxLen = e.type == kEdgeLine
        ? (cam.project(e.p1) - cam.project(e.p0)).distance
        : (sax.distance + say.distance) * (e.t1 - e.t0).abs();
    final k = approxLen.isFinite ? (approxLen / 7).round().clamp(12, 128) : 32;
    final ts = [for (var i = 0; i <= k; i++) e.t0 + (e.t1 - e.t0) * i / k];
    final vis = <bool>[];
    for (final t in ts) {
      final w = e.pointAt(t); // line t0/t1 are 0/1, so t is already normalized
      vis.add(!occ.hidden(cam.project(w), cam.depth(w), extra: occ.edgeMargin));
    }
    final path = Path();
    for (final (a, b) in visibleRuns(vis)) {
      if (b == a) continue;
      final ta = ts[a];
      final tb = ts[b];
      if (e.type == kEdgeLine) {
        final pa = cam.project(e.pointAt(ta));
        final pb = cam.project(e.pointAt(tb));
        path.moveTo(pa.dx, pa.dy);
        path.lineTo(pb.dx, pb.dy);
      } else {
        final cps = genArcCubics(sc, sax, say, ta, tb);
        if (cps.isEmpty) continue;
        path.moveTo(cps[0].dx, cps[0].dy);
        for (var i = 1; i + 2 < cps.length; i += 3) {
          path.cubicTo(cps[i].dx, cps[i].dy, cps[i + 1].dx, cps[i + 1].dy,
              cps[i + 2].dx, cps[i + 2].dy);
        }
      }
    }
    _strokeRuns(canvas, path, color);
  }
}

void _paintSolidSilhouettes(Canvas canvas, Cam3 cam, SceneSolid scene,
    SceneOccluders occ, Color color) {
  final m = scene.solid.mesh;
  final nf = m.faceCount;
  for (var f = 0; f < nf; f++) {
    final rec = m.faceInfos.sublist(15 * f, 15 * f + 15);
    final type = rec[0].round();
    if (type == kFacePlane) continue;
    if (type == kFaceCylinder) {
      for (final (w0, w1) in cylinderSilhouettes(rec, cam)) {
        final k = ((cam.project(w1) - cam.project(w0)).distance / 10)
            .round()
            .clamp(6, 48);
        final vis = <bool>[];
        final pts = <Offset>[];
        for (var i = 0; i <= k; i++) {
          final w = w0 + (w1 - w0) * (i / k);
          final p = cam.project(w);
          pts.add(p);
          vis.add(!occ.hidden(p, cam.depth(w), extra: occ.edgeMargin));
        }
        final path = Path();
        for (final (a, b) in visibleRuns(vis)) {
          if (b == a) continue;
          path.moveTo(pts[a].dx, pts[a].dy);
          path.lineTo(pts[b].dx, pts[b].dy);
        }
        _strokeRuns(canvas, path, color);
      }
      continue;
    }
    // cone/sphere/torus/other: mesh-boundary fallback
    final path = Path();
    for (final (a, b, d) in meshSilhouetteSegments(m, scene, f)) {
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      if (occ.hidden(mid, d, extra: occ.edgeMargin)) continue;
      path.moveTo(a.dx, a.dy);
      path.lineTo(b.dx, b.dy);
    }
    _strokeRuns(canvas, path, color);
  }
}

/// Draws [solids] (committed, opaque) and the optional translucent
/// [previewSolid] in Inventor's Shaded-with-Edges style. [highlightSolid]
/// + [highlightFace] tint one face for hover prehighlight (Phase 2).
void paintPartSolids(
  Canvas canvas,
  Cam3 cam,
  List<KernelSolid> solids, {
  KernelSolid? previewSolid,
  KernelSolid? highlightSolid,
  int highlightFace = -1,
  Color highlightColor = kFaceHighlight,
}) {
  final opaque = [for (final s in solids) buildSceneSolid(s, cam)];
  final occ = SceneOccluders(opaque);

  // 1. shaded faces (front triangles only), one watertight sorted buffer
  _drawShaded(
      canvas,
      [
        for (final s in opaque)
          for (final t in s.tris)
            if (t.front) t
      ],
      255);

  // 2. hover prehighlight: tint the face under the cursor (Inventor blue)
  if (highlightSolid != null && highlightFace >= 0) {
    for (final s in opaque) {
      if (!identical(s.solid, highlightSolid)) continue;
      final hl = [
        for (final t in s.tris)
          if (t.front && t.faceId == highlightFace) t
      ];
      if (hl.isEmpty) break;
      final pos = Float32List(hl.length * 6);
      var pi = 0;
      for (final t in hl) {
        pos[pi++] = t.a.dx;
        pos[pi++] = t.a.dy;
        pos[pi++] = t.b.dx;
        pos[pi++] = t.b.dy;
        pos[pi++] = t.c.dx;
        pos[pi++] = t.c.dy;
      }
      canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos),
          BlendMode.srcOver, Paint()..color = highlightColor.withOpacity(0.42));
      break;
    }
  }

  // 3. edges + silhouettes over the shading
  for (final s in opaque) {
    _paintSolidEdges(canvas, cam, s, occ, kSolidEdge);
    _paintSolidSilhouettes(canvas, cam, s, occ, kSolidEdge);
  }

  // 4. translucent live preview on top (its own sort; edges dimmed and only
  //    occluded by the committed geometry, like Inventor's feature preview)
  if (previewSolid != null) {
    final pv = buildSceneSolid(previewSolid, cam, preview: true);
    _drawShaded(
        canvas,
        [
          for (final t in pv.tris)
            if (t.front) t
        ],
        165);
    final dim = kSolidEdge.withOpacity(0.6);
    _paintSolidEdges(canvas, cam, pv, occ, dim);
    _paintSolidSilhouettes(canvas, cam, pv, occ, dim);
  }
}

/// M59 Phase 3: the part's solids rendered UNDER the 2D sketch editor, seen
/// straight down the sketch frame with the editor's own pan/zoom mapping —
/// Inventor keeps the model visible while sketching on a face. Draw a veil
/// over it (caller) so the sketch stays the crisp foreground.
void paintPartUnderlay(Canvas canvas, Size size, List<KernelSolid> solids,
    PlaneFrame frame, Offset pan, double zoom) {
  if (solids.isEmpty || zoom <= 0) return;
  final cam = Cam3.basis(
    dir: frame.n,
    s: frame.u,
    u: frame.v,
    halfH: size.height / (2 * zoom),
    ox: frame.origin.dot(frame.u) + pan.dx,
    oy: frame.origin.dot(frame.v) + pan.dy,
    size: size,
  );
  paintPartSolids(canvas, cam, solids);
}

// ---------------------------------------------------------------------------
// M59 fix — 3D compositing for the 2D overlays (planes + sketches).
//
// The scene painter draws origin planes and child sketches with a fixed
// order, which cannot express depth: a sketch behind the model bled through,
// and one in front could not cover it. These helpers let the painter test
// overlay pixels against the solid's front faces (the same watertight
// occluder the edge renderer uses), so planes/sketches occlude and are
// occluded exactly as if they lived in 3D.

/// Builds the front-face occluder for [solids] under [cam]. Empty solids give
/// an occluder that hides nothing.
SceneOccluders solidOccluder(List<KernelSolid> solids, Cam3 cam) =>
    SceneOccluders([for (final s in solids) buildSceneSolid(s, cam)]);

/// Strokes the world polyline [worldPts] projected through [cam], but only the
/// portions NOT hidden behind [occ] (a nearer solid front face). Used for
/// origin planes and sketch geometry so they read as truly 3D. When [occ] is
/// null every segment is drawn (no solids present).
void drawOccludedPolyline(
  Canvas canvas,
  Cam3 cam,
  List<Vec3> worldPts,
  Paint paint, {
  SceneOccluders? occ,
  bool close = false,
  double extra = 0,
}) {
  if (worldPts.length < 2) return;
  final pts = <Offset>[];
  final vis = <bool>[];
  final loop = close ? [...worldPts, worldPts.first] : worldPts;
  for (final w in loop) {
    pts.add(cam.project(w));
    vis.add(occ == null
        ? true
        : !occ.hidden(cam.project(w), cam.depth(w), extra: extra));
  }
  // A segment is drawn when BOTH endpoints are visible; finer occlusion of a
  // long segment is handled by sampling its midpoints too.
  final path = Path();
  for (var i = 0; i + 1 < pts.length; i++) {
    if (!vis[i] || !vis[i + 1]) {
      // sample the interior: draw the visible sub-spans
      const steps = 6;
      Offset? runStart;
      Offset prev = pts[i];
      for (var k = 0; k <= steps; k++) {
        final t = k / steps;
        final w = loop[i] + (loop[i + 1] - loop[i]) * t;
        final sp = cam.project(w);
        final shown =
            occ == null ? true : !occ.hidden(sp, cam.depth(w), extra: extra);
        if (shown) {
          runStart ??= sp;
          prev = sp;
        } else if (runStart != null) {
          path.moveTo(runStart.dx, runStart.dy);
          path.lineTo(prev.dx, prev.dy);
          runStart = null;
        }
      }
      if (runStart != null) {
        path.moveTo(runStart.dx, runStart.dy);
        path.lineTo(prev.dx, prev.dy);
      }
      continue;
    }
    path.moveTo(pts[i].dx, pts[i].dy);
    path.lineTo(pts[i + 1].dx, pts[i + 1].dy);
  }
  canvas.drawPath(path, paint);
}

/// Fills the world quad [a,b,c,d] (a planar face, e.g. an origin plane)
/// as a semi-transparent surface that is CORRECTLY occluded by the solids:
/// the quad is tessellated into an NxN grid and each cell is kept only where
/// its centre is not hidden behind a nearer solid front face. This is what
/// lets a construction plane pass THROUGH the model instead of floating on
/// top of it. [occ] null -> the whole quad is filled.
void drawOccludedQuadFill(
  Canvas canvas,
  Cam3 cam,
  Vec3 a,
  Vec3 b,
  Vec3 c,
  Vec3 d,
  Color color, {
  SceneOccluders? occ,
  int grid = 24,
}) {
  // bilinear corners: P(s,t) = lerp(lerp(a,b,s), lerp(d,c,s), t)
  Vec3 at(double s, double t) {
    final top = a + (b - a) * s;
    final bot = d + (c - d) * s;
    return top + (bot - top) * t;
  }

  final pos = <double>[];
  void tri(Vec3 p0, Vec3 p1, Vec3 p2) {
    final s0 = cam.project(p0), s1 = cam.project(p1), s2 = cam.project(p2);
    pos
      ..add(s0.dx)
      ..add(s0.dy)
      ..add(s1.dx)
      ..add(s1.dy)
      ..add(s2.dx)
      ..add(s2.dy);
  }

  for (var i = 0; i < grid; i++) {
    for (var j = 0; j < grid; j++) {
      final s0 = i / grid, s1 = (i + 1) / grid;
      final t0 = j / grid, t1 = (j + 1) / grid;
      // keep the cell if its centre is visible (not behind the solid)
      final cW = at((s0 + s1) / 2, (t0 + t1) / 2);
      if (occ != null && occ.hidden(cam.project(cW), cam.depth(cW))) continue;
      final p00 = at(s0, t0), p10 = at(s1, t0);
      final p11 = at(s1, t1), p01 = at(s0, t1);
      tri(p00, p10, p11);
      tri(p00, p11, p01);
    }
  }
  if (pos.isEmpty) return;
  canvas.drawVertices(
      ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos)),
      BlendMode.srcOver,
      Paint()..color = color);
}
