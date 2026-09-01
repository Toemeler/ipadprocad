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
// Cycles' camera is Blender's: it looks down its own -Z, with +Y up and +X
// right, and `Camera::matrix` is CAMERA-TO-WORLD. So the basis columns are
//
//     X = s        (screen right)
//     Y = u        (screen up)
//     Z = dir      (BACKWARDS along the view, because the view is -Z)
//
// and the translation is the eye. Getting Z as -dir instead is the classic
// error and renders the model from behind — which on a symmetric part is a
// picture that looks almost right.
//
// The half-extents follow from the same two lines: half-height is halfH and
// half-width is halfH * aspect, which is exactly what `project` divides by.
import 'dart:math' as math;
import 'dart:typed_data';

import 'part_model.dart' show KernelSolid, Vec3;
import 'part_render.dart' show Cam3;

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
    s.x, u.x, d.x, eye.x, //
    s.y, u.y, d.y, eye.y, //
    s.z, u.z, d.z, eye.z, //
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
    final m = s.mesh;
    final pos = m.positions;
    final idx = m.indices;
    if (pos.isEmpty || idx.isEmpty || pos.length % 3 != 0 || idx.length % 3 != 0) {
      continue;
    }
    final verts = Float32List(pos.length);
    for (var i = 0; i < pos.length; i++) {
      verts[i] = pos[i].toDouble();
    }
    Float32List? normals;
    final nor = m.normals;
    if (nor.length == pos.length) {
      normals = Float32List(nor.length);
      for (var i = 0; i < nor.length; i++) {
        normals[i] = nor[i].toDouble();
      }
    }
    final tris = Int32List(idx.length);
    for (var i = 0; i < idx.length; i++) {
      tris[i] = idx[i];
    }
    out.add((verts, normals, tris));
  }
  return out;
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
