// Prototype — shared 3D render helpers (M57).
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
import 'materials.dart';
import 'part_model.dart';
import 'perf.dart';
import 'quat.dart';
import 'theme.dart';

// M236 — palette reads, not constants, so a solid picks up the active scheme
// wherever it is drawn: the live viewport AND the off-screen gallery
// thumbnails.
//
// GETTERS rather than top-level finals: a `final` is initialised lazily on
// first use and would freeze whichever palette happened to be active then —
// which would show up as "the thumbnails kept the old colours".

/// Steel, same family as partCubeIcon — the committed-solid look.
Color get kSolidBase => T.solid;

/// M250 — the base colour the EDIT-IN-PLACE context shades from: the steel,
/// most of the way back to the viewport ground.
///
/// A base colour rather than a wash laid over the context afterwards, and the
/// difference is the whole of a defect this milestone shipped once. A wash is
/// SCREEN SPACE: it dims every pixel the context covers, including the pixels
/// where the PART is in front of it, so the part came out veiled by the very
/// component it was standing in front of. Shading from a darker base puts the
/// dimming in the same sorted pass as everything else, where the depths that
/// were right all along can act on it. Only a rendering found this; every
/// depth test in the file was already correct.
///
/// A getter, not a const, for the reason kSolidBase is one: a final would
/// freeze whichever palette happened to be active when it was first read.
Color get kContextBase => Color.lerp(T.solid, T.viewport, 0.55) ?? T.solid;

/// M144 — accented (hovered or selected) B-Rep edge in the CPU painter. Same
/// hue as the RealityKit accent so the two renderers agree.
Color get kEdgeAccent => T.edgeAccent;

Color get kSolidEdge => T.solidEdge;

/// Shared orthographic camera math (also used by the ViewCube/triad).
///
/// WHERE THE CAMERA IS, because getting this wrong is how the assembly
/// pickers came to answer with the far side of the model (device report
/// 2026-08-26; see asm_pick.dart's header). The EYE is at `+dir * D` and looks
/// along `-dir`. Three independent witnesses:
///
///   * this class's own basis — `s.cross(u) == dir`, so `dir` comes out of the
///     screen toward the viewer;
///   * RealityKit, which draws the scene on the device, puts the eye at
///     `center + dir * dist` (RealityPartView.placeCamera);
///   * the device measurement recorded at viewport3d._pickSolidFace (build
///     2648d2e), which is also the form the ViewCube has always used.
///
/// So a VISIBLE face has `n.dir > 0` for an outward normal `n`, and [depth]
/// gets SMALLER toward the viewer. The Flutter painter below still runs the
/// opposite rule and is self-consistent with it; it is host-only (RealityKit
/// owns the device scene), and it is not the convention to copy.
class Cam3 {
  /// [dir] points from the scene TOWARD the eye — see the class note. [s] is
  /// screen right and [u] screen up.
  final Vec3 dir, s, u;
  final double halfH, ox, oy;
  final Size size;
  Cam3(PartCamera c, this.size)
      : dir = c.dir,
        halfH = c.halfH,
        ox = c.ox,
        oy = c.oy,
        s = _rolledS(c.dir, c.az, c.roll),
        u = _rolledU(c.dir, c.az, c.roll);

  /// Basis rotated about the view direction by [roll] (M80). At roll 0 these
  /// return exactly the old derived basis, so every existing camera is
  /// unaffected.
  static Vec3 _rolledS(Vec3 d, double az, double roll) {
    final s0 = PartCamera.rightFor(az), u0 = _upFrom(d, az);
    if (roll == 0) return s0;
    return (s0 * math.cos(roll) + u0 * math.sin(roll)).normalized();
  }

  static Vec3 _rolledU(Vec3 d, double az, double roll) {
    final s0 = PartCamera.rightFor(az), u0 = _upFrom(d, az);
    if (roll == 0) return u0;
    return (u0 * math.cos(roll) - s0 * math.sin(roll)).normalized();
  }

  static Vec3 _upFrom(Vec3 d, double az) =>
      PartCamera.rightFor(az).cross(_fwd(d)).normalized();

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



  double get aspect => size.width / size.height;

  Offset project(Vec3 w) {
    final x = (w.dot(s) - ox) / (halfH * aspect);
    final y = (w.dot(u) - oy) / halfH;
    return Offset(
        (x * 0.5 + 0.5) * size.width, (1 - (y * 0.5 + 0.5)) * size.height);
  }

  /// True when a surface whose OUTWARD normal is [n] faces the camera, i.e.
  /// when it is a surface the user can see.
  ///
  /// A named predicate rather than a bare `n.dot(cam.dir) > 0` at each pick
  /// site, because the bare form is one character away from selecting the far
  /// side of the model and reads as correct either way. That character is
  /// exactly what the assembly pickers had wrong. Hand it the normal in
  /// whatever space [dir] is in — for a placed component that is the piece's
  /// own, via [placedCam], which is what makes a mirrored one work.
  ///
  /// [n] need not be unit length; only its sign against [dir] is read.
  bool facesCamera(Vec3 n) => n.dot(dir) > 0;

  /// Signed view coordinate along the ray: `w·(-dir)`, so NEARER the camera is
  /// a SMALLER value — the eye is at `+dir * D` (see the class note).
  ///
  /// Every PICKER in this app resolves overlaps by keeping the smallest:
  /// viewport3d's face and body picks, part_pick.PickBest, asm_pick and
  /// pickOccurrence. This doc said the opposite until 2026-08-26, and the two
  /// assembly pickers were written to it — which is why a tap in the assembly
  /// answered with the far side of the model.
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

  /// Intersection of the pixel ray with the plane through [at] with normal
  /// [n], or null when looking edge-on.
  ///
  /// M175 — [at] used to be implicit and always the WORLD ORIGIN (the plane
  /// n·X = 0). That is right for the three origin planes and wrong for every
  /// other frame in the app: a work plane offset 10 mm from XY, and a sketch
  /// on a solid face, are both planes that do NOT pass through the origin, and
  /// they were being hit-tested against a parallel plane through it instead.
  ///
  /// Looking straight down a frame's normal the error vanishes — the ray runs
  /// along the offset, so the hit point's u/v are unchanged — which is why
  /// this survived: the app orients the camera to the face before you draw on
  /// it. Off-axis it drifts, and for a work plane it also returns the DEPTH of
  /// the wrong plane, so the face behind won the "which surface did you tap"
  /// comparison and the work plane could never be sketched on.
  Vec3? rayOnPlane(Offset p, Vec3 n, [Vec3 at = Vec3.zero]) {
    final o = unprojectOnCamPlane(p);
    final rd = _fwd(dir);
    final denom = n.dot(rd);
    if (denom.abs() < 1e-9) return null;
    final t = n.dot(at - o) / denom;
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
/// CPU projection of every triangle through the camera.
///
/// Cost scales with the TRIANGLE COUNT, not the screen, so it grows with the
/// model rather than with what is visible — 34 000 triangles is 34 000
/// iterations whether one of them is on screen or all of them.
List<ProjectedTri> projectSolidTriangles(OcctMeshData m, Cam3 cam) =>
    Perf.span('render.projectTris', () => _projectSolidTrianglesInner(m, cam));

List<ProjectedTri> _projectSolidTrianglesInner(OcctMeshData m, Cam3 cam) {
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
List<ProjectedEdge> projectSolidEdges(OcctMeshData m, Cam3 cam) =>
    Perf.span('render.projectEdges', () => _projectSolidEdgesInner(m, cam));

List<ProjectedEdge> _projectSolidEdgesInner(OcctMeshData m, Cam3 cam) {
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

/// Inventor-like prehighlight for hoverable faces (M59 / Phase 2).
Color get kFaceHighlight => T.faceHighlight;

/// Surface-type codes of the 15-double face records (see occt_capi.h).
const int kFacePlane = 0, kFaceCylinder = 1;
// M215 — the rest of the shim's surface discriminator. Cone, sphere and
// torus records carry a real centre/axis since shim v18; before that they
// were type-only, which is why nothing named them until now.
const int kFaceCone = 2, kFaceSphere = 3, kFaceTorus = 4, kFaceOther = 5;

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
/// M240 — [depthBias] is added to every projected depth.
///
/// An assembly draws each component through a SHIFTED camera, which gets the
/// projection exactly right (see [shiftedCam]) and leaves the depths measured
/// from the component's own origin. Adding the placement's own depth back puts
/// every component into ONE depth space, which is what lets a single
/// [SceneOccluders] hide one component behind another — and lets the shaded
/// triangles of the whole assembly go through one sort.
SceneSolid buildSceneSolid(KernelSolid solid, Cam3 cam,
        {bool preview = false, double depthBias = 0}) =>
    Perf.span(
        'render.buildSceneSolid',
        () => _buildSceneSolidInner(solid, cam,
            preview: preview, depthBias: depthBias));

SceneSolid _buildSceneSolidInner(KernelSolid solid, Cam3 cam,
    {bool preview = false, double depthBias = 0}) {
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
        cam.depth(w0) + depthBias,
        cam.depth(w1) + depthBias,
        cam.depth(w2) + depthBias,
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
        OcctMeshData m, SceneSolid scene, int faceId) =>
    Perf.span('render.silhouette',
        () => _meshSilhouetteSegmentsInner(m, scene, faceId));

List<(Offset, Offset, double)> _meshSilhouetteSegmentsInner(
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

void _drawShaded(Canvas canvas, List<SceneTri> tris, int alpha) =>
    _drawShadedGroups(canvas, [(tris, kSolidBase)], alpha);

/// M250 — ONE sorted pass over triangles that do not all shade from the same
/// base colour.
///
/// Edit in place is what needs it: the surrounding assembly is drawn dimmed
/// and the part is not, and the two must sort against EACH OTHER or a
/// component standing in front of the part will not hide it — which is the one
/// thing modelling in context is for. See [kContextBase] for what was tried
/// first and why it was wrong.
///
/// The groups are flattened and sorted together, so the group a triangle came
/// from decides only its colour and never its order.
void _drawShadedGroups(
    Canvas canvas, List<(List<SceneTri>, Color)> groups, int alpha) {
  // Grown rather than pre-sized from a filler element: a group can be present
  // and hold no FRONT triangles (a solid seen edge-on, or one whose faces all
  // point away), and seeding a fixed-length list from `groups.first.first`
  // throws on exactly that. The old single-group form built a copy to sort in
  // any case, so this costs nothing it did not already.
  final flat = <(SceneTri, Color)>[];
  for (final (tris, base) in groups) {
    for (final t in tris) {
      flat.add((t, base));
    }
  }
  if (flat.isEmpty) return;
  final n = flat.length;
  // near = higher depth, so draw FAR (lower depth) first (painter's algo)
  flat.sort((a, b) => a.$1.depth.compareTo(b.$1.depth));
  final pos = Float32List(n * 6);
  final col = Int32List(n * 3);
  var pi = 0, ci = 0;
  int shadeColor(Color base, double s) => Color.fromARGB(
          alpha,
          (base.r * 255 * s).round().clamp(0, 255),
          (base.g * 255 * s).round().clamp(0, 255),
          (base.b * 255 * s).round().clamp(0, 255))
      .toARGB32();
  for (final (t, base) in flat) {
    pos[pi++] = t.a.dx;
    pos[pi++] = t.a.dy;
    pos[pi++] = t.b.dx;
    pos[pi++] = t.b.dy;
    pos[pi++] = t.c.dx;
    pos[pi++] = t.c.dy;
    col[ci++] = shadeColor(base, t.sa);
    col[ci++] = shadeColor(base, t.sb);
    col[ci++] = shadeColor(base, t.sc);
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
    SceneOccluders occ, Color color,
    {Set<int> accent = const {},
    bool accentAll = false,
    Color? accentColor}) {
  final ac = accentColor ?? kEdgeAccent;
  final m = scene.solid.mesh;
  var ei = -1;
  for (final e in DisplayEdge.of(m)) {
    // DisplayEdge.of walks the display edges in order, so the counter IS the
    // display index the accent set is expressed in.
    ei++;
    // Cannot shadow the parameter, so name it for what it is.
    final edgeColor = (accentAll || accent.contains(ei)) ? ac : color;
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
      _strokeRuns(canvas, path, edgeColor);
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
    _strokeRuns(canvas, path, edgeColor);
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
/// M272 — [solids] grouped by the base colour they shade from, in a stable
/// order (steel first, then first-seen).
///
/// A LinkedHashMap by construction, so the group order is deterministic and a
/// golden-image test of a two-material part cannot flip between runs.
Map<Color, List<SceneSolid>> _byMaterial(
    List<SceneSolid> solids, Color? Function(KernelSolid)? materialOf) {
  final out = <Color, List<SceneSolid>>{};
  // Steel first and unconditionally, so the common case — nothing painted —
  // produces exactly one group holding exactly what it always held.
  out[kSolidBase] = [];
  for (final s in solids) {
    (out[materialOf?.call(s.solid) ?? kSolidBase] ??= []).add(s);
  }
  return out;
}

void paintPartSolids(
  Canvas canvas,
  Cam3 cam,
  List<KernelSolid> solids, {
  KernelSolid? previewSolid,
  KernelSolid? highlightSolid,
  int highlightFace = -1,
  Color? highlightColor,
  /// M144 — DISPLAY edge indices of [accentSolid] to draw in
  /// [accentColor], mirroring the RealityKit accent overlay so the CPU
  /// painter (non-iOS, and gallery thumbnails) shows the same selection.
  KernelSolid? accentSolid,
  Set<int> accentEdges = const {},
  Color? accentColor,

  /// M240 — accent EVERY display edge of EVERY solid drawn.
  ///
  /// [accentSolid]/[accentEdges] name one solid and the handful of edges the
  /// user picked inside it, which is right for a fillet. A SELECTED ASSEMBLY
  /// COMPONENT is "all of it", and spelling that as a set at the call site
  /// would only rebuild the edge list the painter is about to walk anyway.
  bool accentAll = false,

  /// M242 — the solids of the body SELECTED in the model browser. Their faces
  /// are washed with [selectedTint] and their edges accented, which is what
  /// RealityKit says with a tinted material (see reality_scene's
  /// `_bodyRowTint`): the two viewports must agree about what selection looks
  /// like. Compared by identity — a body is a handful of solids, so a linear
  /// scan beats building a set per frame.
  List<KernelSolid> selectedSolids = const [],
  Color? selectedTint,

  /// The solids of the body merely HOVERED in the model browser: the same wash
  /// at half the strength and no edge accent, so the prehighlight reads as the
  /// weaker statement it is. A solid that is in both sets is drawn SELECTED —
  /// two washes would compound into a third colour that means nothing.
  List<KernelSolid> hoveredSolids = const [],
  Color? hoveredTint,

  /// M250 — EDIT IN PLACE: the rest of the assembly, around the part.
  ///
  /// Each piece is a solid plus its placement IN THE PART'S OWN FRAME —
  /// assembly.inPlaceContext is where that transform is worked out, and it is
  /// the one place it happens. Empty for every ordinary part render, which is
  /// all of them except an in-place edit.
  ///
  /// It joins the SAME sorted buffer and the SAME occluder as the part, and
  /// that is the whole reason it is a parameter here rather than a separate
  /// call before this one. Drawing the context first and the part over it
  /// would put the part in front of everything, however far behind a
  /// component it actually is — and modelling a bracket against the thing it
  /// bolts to is exactly the case where you need to see which is in front.
  List<(Placement, KernelSolid)> context = const [],

  /// The base colour the context shades from, so it reads as background
  /// rather than as more of the part. Inventor dims the components you are not
  /// editing. Defaults to [kContextBase]; see there for why this is a BASE and
  /// not a wash laid over the top.
  Color? contextBase,

  /// M272 — the appearance assigned to a solid, or null for the palette's
  /// steel.
  ///
  /// A BASE, like [contextBase], and never a wash: the shading is computed
  /// from the base, so laying a colour over finished grey shading gives a
  /// flat, plastic body instead of a lit one. Solids are grouped by the colour
  /// this returns and every group goes through the SAME sort, which is what
  /// keeps a red body and a blue one interleaving correctly where they overlap.
  Color? Function(KernelSolid)? materialOf,
}) {
  final opaque = [for (final s in solids) buildSceneSolid(s, cam)];
  // The context, each piece through its own PLACED camera — the same identity
  // paintAssemblySolids runs on, and no mesh is copied. The depth bias is the
  // piece's own distance along the view axis, because buildSceneSolid measures
  // depth in the frame it is handed and every one of these has a different
  // one; without it the whole context would sort as if it sat at the part's
  // origin.
  final ctxCams = [for (final (at, _) in context) placedCam(cam, at)];
  final ctx = [
    for (var i = 0; i < context.length; i++)
      buildSceneSolid(context[i].$2, ctxCams[i],
          depthBias: cam.depth(context[i].$1.at))
  ];
  final occ = SceneOccluders([...ctx, ...opaque]);

  // 1. shaded faces (front triangles only), one watertight sorted buffer.
  //
  // M250 — TWO groups, ONE sort. The in-place context shades from a darker
  // base so it reads as background, and it sorts against the part rather than
  // sitting behind it: a component in front of the part hides it, which is the
  // whole of modelling in context.
  _drawShadedGroups(
      canvas,
      [
        if (ctx.isNotEmpty)
          (
            [
              for (final s in ctx)
                for (final t in s.tris)
                  if (t.front) t
            ],
            contextBase ?? kContextBase
          ),
        // M272 — one group per DISTINCT appearance. Grouped rather than drawn
        // solid by solid because _drawShadedGroups sorts all of its groups
        // together: one call per body would put each body in its own depth
        // buffer and a blue body poking through a red one would come out
        // whichever was drawn last.
        for (final entry in _byMaterial(opaque, materialOf).entries)
          (
            [
              for (final s in entry.value)
                for (final t in s.tris)
                  if (t.front) t
            ],
            entry.key
          ),
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
          BlendMode.srcOver, Paint()..color = (highlightColor ?? kFaceHighlight).withOpacity(0.42));
      break;
    }
  }

  // 2b. the browser's selection / hover wash, over the shading and under the
  //     edges. Same treatment paintAssemblySolids gives a selected component,
  //     because it is the same statement: the whole body is picked.
  bool isSelected(KernelSolid s) =>
      selectedSolids.any((x) => identical(x, s));
  bool isHovered(KernelSolid s) =>
      !isSelected(s) && hoveredSolids.any((x) => identical(x, s));
  for (final (pick, tint, alpha) in [
    (isSelected, selectedTint ?? kFaceHighlight, 0.42),
    (isHovered, hoveredTint ?? kFaceHighlight, 0.20),
  ]) {
    final tris = [
      for (final s in opaque)
        if (pick(s.solid))
          for (final t in s.tris)
            if (t.front) t
    ];
    if (tris.isEmpty) continue;
    final pos = Float32List(tris.length * 6);
    var pi = 0;
    for (final t in tris) {
      pos[pi++] = t.a.dx;
      pos[pi++] = t.a.dy;
      pos[pi++] = t.b.dx;
      pos[pi++] = t.b.dy;
      pos[pi++] = t.c.dx;
      pos[pi++] = t.c.dy;
    }
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos),
        BlendMode.srcOver, Paint()..color = tint.withValues(alpha: alpha));
  }

  // 3. edges + silhouettes over the shading
  //
  // M250 — the context's first, dimmed, against the shared occluder: an edge
  // of a surrounding component that runs behind the part must disappear
  // behind it, which is exactly what the shared occluder gives for free.
  for (var i = 0; i < ctx.length; i++) {
    final dim = kSolidEdge.withValues(alpha: 0.5);
    _paintSolidEdges(canvas, ctxCams[i], ctx[i], occ, dim);
    _paintSolidSilhouettes(canvas, ctxCams[i], ctx[i], occ, dim);
  }
  for (final s in opaque) {
    final on = accentAll || isSelected(s.solid);
    _paintSolidEdges(canvas, cam, s, occ, kSolidEdge,
        accent: (accentSolid != null && identical(s.solid, accentSolid))
            ? accentEdges
            : const {},
        accentAll: on,
        accentColor: accentColor);
    _paintSolidSilhouettes(
        canvas, cam, s, occ, on ? (accentColor ?? kEdgeAccent) : kSolidEdge);
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

// ---------------------------------------------------------------------------
// M240 — assemblies
//
// A placed component is the source part's geometry SHIFTED, and nothing else
// (see lib/assembly.dart for why there is no rotation yet). An orthographic
// projection is affine, so "shifted geometry" and "shifted camera" are the
// same picture:
//
//     project(w + t) = ((w + t)·s - ox) / k  =  (w·s - (ox - t·s)) / k
//
// which is exactly [shiftedCam]. That identity is what lets an assembly reuse
// [paintPartSolids] verbatim instead of copying a mesh per component per
// frame — the drag would otherwise rebuild every vertex buffer it touches.
// ---------------------------------------------------------------------------

/// One placed component: the world-placed pieces it is made of.
///
/// M246 — a LIST of transforms rather than one. A component used to be "these
/// solids, at this placement", which is true of a part and false of a
/// SUBASSEMBLY: its own components each sit somewhere inside it, so every
/// piece carries its own composed transform. A part still arrives as a list
/// of pieces all at the same placement, so nothing about the single-part case
/// changed except where the transform is written down.
class PlacedComponent {
  const PlacedComponent(this.pieces);

  /// (placement, solid), already composed into world space.
  ///
  /// M248 — a [Placement] rather than a (rotation, translation) pair, because
  /// a MIRRORED component is not a rigid transform and a quaternion cannot
  /// hold one. The painter needs nothing else: [placedCam] takes the whole
  /// value, and says there why the front-face test is unaffected.
  final List<(Placement, KernelSolid)> pieces;
}

/// [cam] as seen by geometry that has been moved by the rigid transform
/// (rot, t) — the identity the note above describes, generalised from a pure
/// translation to a full placement.
///
/// M242 gave a component an ORIENTATION, and the identity still holds, because
/// the projection is affine in the world point and the world point is affine
/// in the local one:
///
///     project(R·l + t)
///       = ((R·l + t)·s - ox) / k
///       = (l·(Rᵀ·s) - (ox - t·s)) / k
///
/// So a rotated component is the same camera with its BASIS turned the other
/// way and its pan shifted — no mesh is copied, exactly as before. The view
/// direction turns with the basis too, which is what keeps the front-face test
/// inside buildSceneSolid correct in the component's own space.
/// M248 — and the identity survives a REFLECTION unchanged, which is the one
/// piece of luck in this milestone. project uses the basis only through dot
/// products, so
///
///     project(R·S·l + t) = (l·(S·Rᵀ·s) − (ox − t·s)) / k
///
/// and [Placement.unapplyDir] is exactly S·Rᵀ. The camera comes back with a
/// LEFT-handed basis, which project, depth and projectVec are all indifferent
/// to.
///
/// AND SO IS THE FRONT-FACE TEST, which is worth writing down because it is
/// the opposite of what the milestone expected. A reflection does reverse
/// triangle winding — but only in WORLD space. Every consumer on this path
/// works in the component's OWN space (the whole point of a placed camera) and
/// there the mesh is untouched: cross(p1−p0, p2−p0) is still the outward
/// normal. The map carries an outward normal to an outward normal, because it
/// is orthogonal, so
///
///     sign((R·S·n)·dir)   ==   sign(n·(S·Rᵀ·dir))   ==   sign(n·cam.dir)
///
/// — whichever sign a caller tests for. So buildSceneSolid, pickOccurrence and
/// asm_pick._pickFaceOn all keep the test they had. Adding a sign HERE is not
/// harmless: it selects the far side of a mirrored component, which draws with
/// the right silhouette and the wrong shading — found by rendering one, not by
/// any unit test.
///
/// (Which sign each caller should test is a separate question, and this note
/// deliberately no longer answers it: see [Cam3] for where the camera is. The
/// two assembly pickers were reading a stale answer here.)
///
/// The one path where the winding trap IS real is RealityKit's, because the
/// GPU transforms the vertices before it culls. See [solidPayload].
Cam3 placedCam(Cam3 cam, Placement at) => Cam3.basis(
      dir: at.unapplyDir(cam.dir),
      s: at.unapplyDir(cam.s),
      u: at.unapplyDir(cam.u),
      halfH: cam.halfH,
      ox: cam.ox - at.at.dot(cam.s),
      oy: cam.oy - at.at.dot(cam.u),
      size: cam.size,
    );

/// [placedCam] for a component that has only been moved, not turned.
Cam3 shiftedCam(Cam3 cam, Vec3 t) =>
    placedCam(cam, Placement(Quat.identity, t));

/// Draws every component of an assembly, and hands back the occluder it built
/// so the caller can draw origin planes and axes THROUGH the model the way the
/// part viewport does. Null when there is nothing to occlude.
///
/// One pass over all components rather than one [paintPartSolids] call each:
/// that is what makes the depth right BETWEEN components as well as inside
/// one. Every component's triangles land in one sorted buffer and one
/// occluder, in a single depth space (see [buildSceneSolid]'s depthBias), so a
/// component behind another is hidden by it — including its edges. Sorting
/// components by their origin and painting them in turn, which is what this
/// did first, gets that wrong for any two components that overlap on screen.
///
/// [selected] and [hovered] are indices into [placed]. That component's faces
/// are washed with [selectedTint] / [hoveredTint] and, for the selection, its
/// edges are drawn in [accentColor].
///
/// The wash is what keeps this renderer and RealityKit saying the SAME thing:
/// on device a selected component is a tinted body (the payload carries the
/// colour, PartRenderer.applyTint puts it on the material), and a viewport
/// where selection means one thing on the iPad and another on a desktop run is
/// a viewport nobody can reason about. It is drawn as a translucent overlay
/// over the shading rather than by re-tinting it, because the shading path is
/// shared with every part render and a per-solid base colour there would be a
/// hot-loop change for one document kind. The face prehighlight above does
/// exactly the same thing for exactly the same reason.
SceneOccluders? paintAssemblySolids(
  Canvas canvas,
  Cam3 cam,
  List<PlacedComponent> placed, {
  int selected = -1,
  int hovered = -1,
  Color? accentColor,
  Color? selectedTint,
  Color? hoveredTint,

  /// M272 — the appearance assigned to component [i], or null for steel.
  ///
  /// A base colour, and grouped through the same one sorted pass the part
  /// painter uses: an assembly of differently painted components has to
  /// interleave correctly wherever two of them overlap.
  Color? Function(int i)? materialOf,
}) {
  // (component index, the piece's own placed camera, the projected solid).
  //
  // M246 — the camera is per PIECE, not per component: a subassembly's parts
  // each sit somewhere inside it, so one camera per component would draw them
  // all at the subassembly's own origin, stacked.
  final scenes = <(int, Cam3, SceneSolid)>[];
  for (var i = 0; i < placed.length; i++) {
    for (final (at, s) in placed[i].pieces) {
      final sc = placedCam(cam, at);
      scenes.add((i, sc, buildSceneSolid(s, sc, depthBias: cam.depth(at.at))));
    }
  }
  if (scenes.isEmpty) return null;
  final occ = SceneOccluders([for (final (_, _, s) in scenes) s]);

  // 1. shaded faces of the WHOLE assembly, one watertight sorted buffer
  //
  // M272 — one GROUP per distinct appearance, still one sort. Steel is seeded
  // first and unconditionally, so an assembly nobody has painted produces
  // exactly the single group it always produced.
  final byBase = <Color, List<SceneTri>>{kSolidBase: []};
  for (final (i, _, s) in scenes) {
    final base = materialOf?.call(i) ?? kSolidBase;
    final into = byBase[base] ??= [];
    for (final t in s.tris) {
      if (t.front) into.add(t);
    }
  }
  _drawShadedGroups(
      canvas, [for (final e in byBase.entries) (e.value, e.key)], 255);

  // 2. the selection / hover wash, over the shading and under the edges.
  //
  // Selection WINS on the component that is both: two washes would compound
  // into a third colour that means nothing, and "selected" is the stronger
  // statement. Same rule as assemblyTint on the RealityKit side.
  for (final (which, tint, alpha) in [
    (selected, selectedTint ?? kFaceHighlight, 0.42),
    (hovered == selected ? -1 : hovered, hoveredTint ?? kFaceHighlight, 0.20),
  ]) {
    if (which < 0) continue;
    final tris = [
      for (final (i, _, sol) in scenes)
        if (i == which)
          for (final t in sol.tris)
            if (t.front) t
    ];
    if (tris.isEmpty) continue;
    final pos = Float32List(tris.length * 6);
    var pi = 0;
    for (final t in tris) {
      pos[pi++] = t.a.dx;
      pos[pi++] = t.a.dy;
      pos[pi++] = t.b.dx;
      pos[pi++] = t.b.dy;
      pos[pi++] = t.c.dx;
      pos[pi++] = t.c.dy;
    }
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos),
        BlendMode.srcOver, Paint()..color = tint.withValues(alpha: alpha));
  }

  // 3. edges + silhouettes over the shading, against the shared occluder
  for (final (i, sc, s) in scenes) {
    final on = i == selected;
    // The EDGES are drawn through the PIECE's own placed camera, carried
    // along from the pass above: the occluder is in screen space and shared,
    // but where an edge lands is the piece's own business.
    _paintSolidEdges(canvas, sc, s, occ, kSolidEdge,
        accentAll: on, accentColor: accentColor);
    _paintSolidSilhouettes(
        canvas, sc, s, occ, on ? (accentColor ?? kEdgeAccent) : kSolidEdge);
  }
  return occ;
}

/// [fitThumbCamera] for an assembly: the same fixed top-front-right view,
/// framed to every component's PLACED geometry.
PartCamera fitAssemblyThumbCamera(List<PlacedComponent> placed, Size size) =>
    _fitThumb(size, _walkPlaced(placed));

/// Frames [placed] in [cam] WITHOUT touching its orientation — Inventor's Zoom
/// All, which is what placing a component runs.
///
/// The thumbnail's twin ([fitAssemblyThumbCamera]) chooses the view direction
/// as well, because a gallery card should look the same however the user left
/// the model turned. In the viewport the opposite is true: the user turned it
/// deliberately, and only the pan and the zoom are ours to set.
void fitAssemblyView(PartCamera cam, List<PlacedComponent> placed, Size size) {
  if (placed.isEmpty) return;
  _fitInto(cam, size, _walkPlaced(placed));
}

/// [fitAssemblyView] for a part: frames [solids] in [cam] WITHOUT touching its
/// orientation.
///
/// M283 — the ViewCube runs this on the camera it is about to swing to, so
/// that choosing a view direction also brings the whole model into frame. It
/// used to set a flat `halfH = 27` there, which is a fixed 54 mm of view
/// height: a bookmark filled it, an engine block was a speck in the middle of
/// it, and neither had anything to do with what the user had asked for, which
/// was to look at the model from the front.
void fitPartView(PartCamera cam, List<KernelSolid> solids, Size size) {
  if (solids.isEmpty) return;
  _fitInto(cam, size, _walkSolids(solids));
}

/// Every vertex of [solids], in model coordinates.
void Function(void Function(Vec3)) _walkSolids(List<KernelSolid> solids) =>
    (add) {
      for (final sol in solids) {
        final pos = sol.mesh.positions;
        for (var i = 0; i + 2 < pos.length; i += 3) {
          add(Vec3(pos[i], pos[i + 1], pos[i + 2]));
        }
      }
    };

/// Every placed vertex of [placed], in world coordinates.
void Function(void Function(Vec3)) _walkPlaced(List<PlacedComponent> placed) =>
    (add) {
      for (final c in placed) {
        for (final (at, sol) in c.pieces) {
          final pos = sol.mesh.positions;
          for (var i = 0; i + 2 < pos.length; i += 3) {
            add(at.apply(Vec3(pos[i], pos[i + 1], pos[i + 2])));
          }
        }
      }
    };

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
///
/// M250 — [context] is the in-place edit's surrounding components, each with
/// its own placement in the part's frame. They belong in this occluder for
/// the same reason they belong in the painter's: an origin plane or a sketch
/// line that runs BEHIND a component of the assembly must be hidden by it,
/// and an occluder that only knew about the part would draw the plane over
/// the top of the thing the part is being built against.
///
/// The scene solids are therefore built TWICE per frame while an in-place edit
/// is open — once here and once inside [paintPartSolids]. That duplication is
/// not new: _ScenePainter has always handed this the same list it hands the
/// painter, and the part's own solids have been built twice since M59. Ending
/// it means having [paintPartSolids] hand back the occluder it already built,
/// which is a change to the part viewport's main render path and belongs to
/// whichever milestone measures it rather than to this one.
SceneOccluders solidOccluder(List<KernelSolid> solids, Cam3 cam,
        {List<(Placement, KernelSolid)> context = const []}) =>
    SceneOccluders([
      for (final s in solids) buildSceneSolid(s, cam),
      for (final (at, s) in context)
        buildSceneSolid(s, placedCam(cam, at), depthBias: cam.depth(at.at)),
    ]);

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

// ===========================================================================
// Gallery thumbnail camera (M82 — shared by the CPU painter AND the RealityKit
// snapshot path, so both engines frame a part identically).
// ===========================================================================

/// Azimuth of the canonical thumbnail view.
///
/// The world is Y-up (see [PlaneFrame]: the XZ plane carries normal +Y), so a
/// camera sitting on +X/+Y/+Z looks at the model's TOP-FRONT-RIGHT corner —
/// the ViewCube's home corner and Inventor's default isometric.
const double kThumbAz = math.pi / 4; // between +X (right) and +Z (front)

/// Polar angle of the canonical thumbnail view: the EXACT isometric corner,
/// acos(1/sqrt(3)) ≈ 0.9553166. The old literal 0.955 was a rounded stand-in
/// and tilted the view by ~0.02°; naming the exact value means the three
/// direction components come out equal to machine precision, which is what
/// [thumbCameraDir] is tested against.
final double kThumbPol = math.acos(1 / math.sqrt(3));

/// Fraction of the frame the silhouette fills — a small honest margin.
const double kThumbFill = 0.82;

/// The fixed top-front-right view direction, all three components equal.
Vec3 get thumbCameraDir =>
    PartCamera(az: kThumbAz, pol: kThumbPol).dir;

/// A fixed top-front-right [PartCamera] framed to [solids], for gallery
/// thumbnails. Independent of the live viewport camera, so a part always looks
/// the same in the gallery no matter where the user left it rotated — and
/// identical whether the picture is produced by the CPU painter or by the
/// RealityKit snapshot, since both are handed THIS camera.
PartCamera fitThumbCamera(List<KernelSolid> solids, Size size) =>
    _fitThumb(size, _walkSolids(solids));

/// The framing itself, over whatever world points [walk] offers.
///
/// M240 — split out of [fitThumbCamera] so an assembly can be framed by the
/// same rule with its components' PLACEMENTS folded in. The camera is
/// identical for a part either way: the walk is the only difference.
PartCamera _fitThumb(Size size, void Function(void Function(Vec3)) walk) {
  final cam = PartCamera(az: kThumbAz, pol: kThumbPol);
  _fitInto(cam, size, walk);
  return cam;
}

/// Sets [cam]'s pan and zoom so the points [walk] offers fill [size] at
/// [kThumbFill]. The ORIENTATION is read, never written.
void _fitInto(
    PartCamera cam, Size size, void Function(void Function(Vec3)) walk) {
  // A provisional Cam3 gives the screen-space right/up basis (s, u) to measure
  // the silhouette against before committing pan/zoom.
  final basis = Cam3(cam, size);
  double minS = 1e30, maxS = -1e30, minU = 1e30, maxU = -1e30;
  walk((v) {
    final su = v.dot(basis.s), uv = v.dot(basis.u);
    if (!su.isFinite || !uv.isFinite) return;
    minS = math.min(minS, su);
    maxS = math.max(maxS, su);
    minU = math.min(minU, uv);
    maxU = math.max(maxU, uv);
  });
  if (minS > maxS) return; // no finite vertices — leave the camera alone
  cam.ox = (minS + maxS) / 2;
  cam.oy = (minU + maxU) / 2;
  final hx = (maxS - minS) / 2, hy = (maxU - minU) / 2;
  final aspect = size.width / size.height;
  final halfH = math.max(hy, hx / (aspect <= 0 ? 1 : aspect)) / kThumbFill;
  cam.halfH = PartCamera.clampHalfH(halfH > 1e-6 ? halfH : 27);
}

/// M272 — the appearance colour of [s] within [p], or null for steel.
///
/// Lives here rather than in materials.dart because it needs [PartModel] to
/// walk feature -> body -> material, and materials.dart is deliberately free of
/// the model. Linear over the features: a part has tens of them, this runs once
/// per solid per paint, and a cache would have to be invalidated by every
/// rebuild.
Color? materialColorOfSolid(PartModel p, KernelSolid s) {
  if (p.bodyMaterials.isEmpty) return null;
  for (final f in p.features) {
    if (!identical(f.solid, s)) continue;
    final argb = materialArgb(p.bodyMaterials[f.bodyName]);
    return argb == null ? null : Color(argb);
  }
  return null;
}
