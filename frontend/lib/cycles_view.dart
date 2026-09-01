// M297 — the numbers a Cycles render needs, worked out where they can be
// tested.
//
// The renderer itself is C++ that first compiles in CI and first runs on a
// device. The arithmetic in front of it is not: a camera matrix is twelve
// doubles and a convention, and getting the convention wrong is the single
// most likely way for the first render to come back looking like nothing.
// So it lives here, in Dart, with tests.
//
// ---------------------------------------------------------------------------
// THE TWO CONVENTIONS, WRITTEN DOWN
// ---------------------------------------------------------------------------
//
// This app's camera ([Cam3]) is orthographic and projects
//
//     x = (w·s - ox) / (halfH * aspect)      in [-1, 1]
//     y = (w·u - oy) / halfH                 in [-1, 1]
//
// with the eye at `+dir * D` — see Cam3's own note, and `facesCamera`, which
// is `n·dir > 0`.
//
// Cycles' camera matrix is CAMERA-TO-WORLD, and its third column is the
// FORWARD direction — the way the camera looks. Not the backward vector.
//
//     X = s        (screen right)
//     Y = u        (screen up)
//     Z = -dir     (FORWARD along the view: Cam3's dir points at the eye)
//
// This is worth being explicit about, because "a Blender camera looks down its
// own -Z" is true of the Blender OBJECT and not of what Cycles is handed.
// Blender flips it on the way in:
//
//     /* Note the blender camera points along the negative z-axis. */
//     result = tfm * transform_scale(1.0f, 1.0f, -1.0f);
//                                — intern/cycles/blender/camera.cpp
//
// and the kernel then shoots orthographic rays along +Z of that matrix:
//
//     float3 D = make_float3(0.0f, 0.0f, 1.0f);
//                                — intern/cycles/kernel/camera/camera.h
//
// with projection_orthographic() containing no flip of its own. So the third
// column must be where the camera is pointing. Getting it backwards does NOT
// render the model from behind — it renders no model at all, because every ray
// leaves the eye travelling away from the scene and hits the world. A full
// frame of flat background is the signature, and it is the one this got wrong
// for its first four builds on device.
//
// The basis is therefore LEFT-handed, by construction, exactly as Blender's
// own multiplication by scale(1,1,-1) makes it. That is not a bug to fix.
//
// The half-extents follow from the same two lines: half-height is halfH and
// half-width is halfH * aspect, which is exactly what `project` divides by.
import 'dart:math' as math;
import 'dart:typed_data';

import 'part_model.dart' show KernelSolid, Vec3;
import 'part_render.dart' show Cam3;
import 'quat.dart' show Placement;

/// How far behind the model the eye is put, as a multiple of the scene's own
/// reach.
///
/// An orthographic camera's position does not change what is in frame — only
/// the viewplane does — but it does decide what is BEHIND the camera, and
/// Cycles clips that. Three times the reach clears any model of that reach
/// whatever direction it is viewed from, and costs nothing.
const double kCyclesEyePullback = 3.0;

/// The camera-to-world matrix for [cam], row-major 3x4, in the order
/// [Transform] takes it (see util/transform.h: `t.x` is the first ROW).
///
/// [reach] is how far the scene extends from the origin; the eye is pulled
/// back past it so nothing is behind the camera.
List<double> cyclesCameraMatrix(Cam3 cam, double reach) {
  final d = _norm(cam.dir);
  final s = _norm(cam.s);
  final u = _norm(cam.u);
  // The world point at the centre of the view. Its s and u coordinates are the
  // camera's pan; its dir coordinate is free, so the eye is placed along dir
  // from there.
  final back = (reach.isFinite && reach > 0 ? reach : 1.0) * kCyclesEyePullback;
  final eye = s * cam.ox + u * cam.oy + d * back;
  return [
    s.x, u.x, -d.x, eye.x, //
    s.y, u.y, -d.y, eye.y, //
    s.z, u.z, -d.z, eye.z, //
  ];
}

/// Half-extents of the orthographic viewplane, in world units: the same two
/// numbers [Cam3.project] divides by.
(double, double) cyclesViewplane(Cam3 cam) =>
    (cam.halfH * cam.aspect, cam.halfH);

/// Where a world point lands in the image, in the same normalised [-1, 1]
/// coordinates [Cam3.project] produces — computed THROUGH the matrix rather
/// than from the camera, so a test can check that the two agree.
///
/// This is the whole verification: if the matrix and the viewplane say the
/// same thing about a point as the app's own projection does, the render will
/// frame what the viewport frames.
(double, double) cyclesProject(List<double> m, double halfW, double halfH,
    Vec3 w) {
  // World -> camera is the inverse of a rigid camera-to-world, which for an
  // orthonormal basis is the transpose applied to (w - eye).
  final ex = m[3], ey = m[7], ez = m[11];
  final rel = Vec3(w.x - ex, w.y - ey, w.z - ez);
  final cx = rel.x * m[0] + rel.y * m[4] + rel.z * m[8];
  final cy = rel.x * m[1] + rel.y * m[5] + rel.z * m[9];
  return (cx / halfW, cy / halfH);
}

/// How far the model reaches from the origin, for [cyclesCameraMatrix].
double cyclesReach(Iterable<Vec3> points) {
  var r = 0.0;
  for (final p in points) {
    final d = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
    if (d.isFinite && d > r) r = d;
  }
  return r;
}

Vec3 _norm(Vec3 v) {
  final n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (!n.isFinite || n < 1e-12) return const Vec3(0, 0, 1);
  return Vec3(v.x / n, v.y / n, v.z / n);
}


/// One mesh, in the form the shim's CyMesh takes: 32-bit positions, optional
/// 32-bit normals, 32-bit triangle indices.
typedef CyclesMesh = (Float32List verts, Float32List? normals, Int32List tris);

/// [solids] as Cycles meshes.
///
/// The app keeps 64-bit positions because the kernel does; Cycles is 32-bit
/// throughout (packed_float3), so the narrowing happens once, here, rather
/// than being discovered at the FFI boundary. On a model of any size a CAD
/// program can hold, single precision is nowhere near the limit — the meshes
/// are already a tessellation.
///
/// Normals travel only when the solid has them for every vertex. A partial
/// normal array is worse than none: Cycles would smooth-shade some triangles
/// and not others, and the seam reads as a modelling error.
List<CyclesMesh> cyclesMeshes(Iterable<KernelSolid> solids) {
  final out = <CyclesMesh>[];
  for (final s in solids) {
    final m = cyclesMeshAt(s, null);
    if (m != null) out.add(m);
  }
  return out;
}

/// [solid] as a Cycles mesh with [at] applied, or null when it has nothing to
/// draw.
///
/// An assembly's solids are in their own part's coordinates and the occurrence
/// places them, so the placement is baked into the vertices here. Cycles could
/// carry it on the Object transform instead, and that is what the RealityKit
/// path does — but that path re-places entities on every drag frame and this
/// one renders once from a standstill, so there is nothing to save and one
/// fewer convention to get wrong. Pass null for a part's own solids, which are
/// already in world coordinates.
///
/// A MIRRORED placement reverses triangle winding. Cycles' shading is
/// two-sided so it would still draw, but the geometric normal it derives from
/// the winding would face into the solid — which is what decides shadow
/// terminator and which side a ray considers front, so it is not cosmetic.
CyclesMesh? cyclesMeshAt(KernelSolid solid, Placement? at) {
  final m = solid.mesh;
  final pos = m.positions;
  final idx = m.indices;
  if (pos.isEmpty || idx.isEmpty || pos.length % 3 != 0 || idx.length % 3 != 0) {
    return null;
  }
  final verts = Float32List(pos.length);
  if (at == null) {
    for (var i = 0; i < pos.length; i++) {
      verts[i] = pos[i].toDouble();
    }
  } else {
    for (var i = 0; i + 2 < pos.length; i += 3) {
      final w = at.apply(Vec3(
          pos[i].toDouble(), pos[i + 1].toDouble(), pos[i + 2].toDouble()));
      verts[i] = w.x;
      verts[i + 1] = w.y;
      verts[i + 2] = w.z;
    }
  }
  Float32List? normals;
  final nor = m.normals;
  if (nor.length == pos.length) {
    normals = Float32List(nor.length);
    if (at == null) {
      for (var i = 0; i < nor.length; i++) {
        normals[i] = nor[i].toDouble();
      }
    } else {
      for (var i = 0; i + 2 < nor.length; i += 3) {
        final w = at.applyDir(Vec3(
            nor[i].toDouble(), nor[i + 1].toDouble(), nor[i + 2].toDouble()));
        normals[i] = w.x;
        normals[i + 1] = w.y;
        normals[i + 2] = w.z;
      }
    }
  }
  final tris = Int32List(idx.length);
  final flip = at != null && at.mirrored;
  for (var i = 0; i + 2 < idx.length; i += 3) {
    tris[i] = idx[i];
    tris[i + 1] = flip ? idx[i + 2] : idx[i + 1];
    tris[i + 2] = flip ? idx[i + 1] : idx[i + 2];
  }
  return (verts, normals, tris);
}

/// Everything about a camera that changes the picture, as a string for the
/// render key.
///
/// The six numbers Cam3 is built from, and the size it was built for. Not the
/// matrix: it is derived from these, and a signature computed from a derived
/// value is one more place for the two to disagree.
String cyclesCameraKey(Cam3 cam) {
  String f(double v) => v.toStringAsFixed(6);
  return '${f(cam.dir.x)},${f(cam.dir.y)},${f(cam.dir.z)};'
      '${f(cam.s.x)},${f(cam.s.y)},${f(cam.s.z)};'
      '${f(cam.halfH)},${f(cam.ox)},${f(cam.oy)}';
}

/// The largest image a Cycles render will produce, on its long side.
///
/// A path tracer is not a rasteriser: cost is pixels times samples, and the
/// viewport at native iPad resolution is 5.6 megapixels. At any sample count
/// worth having, that is a minute of work for a picture the user asked for by
/// switching a display mode. 900 on the long side is a third of a megapixel,
/// it fills the viewport well enough on a Retina panel once scaled, and it
/// lands in seconds rather than minutes.
const int kCyclesMaxSide = 900;

/// How many samples one render takes.
///
/// One number, not a range: a preview that is sometimes 16 samples and
/// sometimes 512 is two different pictures of the same model, and the user
/// has no way to tell which one they are looking at. 48 is past the point
/// where a studio-lit CAD body with no caustics still looks noisy.
const int kCyclesSamples = 48;

/// The pixel size to render [size] logical points at, capped at
/// [kCyclesMaxSide] and never zero.
(int, int) cyclesImageSize(double width, double height, double dpr) {
  final w = width * dpr, h = height * dpr;
  if (!w.isFinite || !h.isFinite || w < 1 || h < 1) return (1, 1);
  final long = math.max(w, h);
  final k = long > kCyclesMaxSide ? kCyclesMaxSide / long : 1.0;
  return (math.max(1, (w * k).round()), math.max(1, (h * k).round()));
}

/// The furthest any vertex of [meshes] is from the origin.
///
/// Taken from the CONVERTED meshes rather than the solids, so an assembly's
/// placements are already baked in — the reach of a part sitting a metre off
/// the assembly origin is a metre, not the size of the part.
double cyclesMeshReach(List<CyclesMesh> meshes) {
  var r2 = 0.0;
  for (final (v, _, _) in meshes) {
    for (var i = 0; i + 2 < v.length; i += 3) {
      final d = v[i] * v[i] + v[i + 1] * v[i + 1] + v[i + 2] * v[i + 2];
      if (d.isFinite && d > r2) r2 = d;
    }
  }
  return math.sqrt(r2);
}
