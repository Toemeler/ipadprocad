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


/// A body's appearance, in the form Cycles shades with.
///
/// LINEAR colour, not sRGB. The app stores materials as sRGB hex, which is what
/// a screen wants and not what a renderer integrates; handing sRGB straight to
/// a path tracer makes everything too bright and washed out in a way that
/// reads as a lighting problem rather than a colour-space one.
class CyclesMaterial {
  const CyclesMaterial(this.r, this.g, this.b,
      {this.roughness = 0.5, this.metallic = 0.0});

  final double r;
  final double g;
  final double b;
  final double roughness;
  final double metallic;

  @override
  bool operator ==(Object other) =>
      other is CyclesMaterial &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.roughness == roughness &&
      other.metallic == metallic;

  @override
  int get hashCode => Object.hash(r, g, b, roughness, metallic);
}

/// sRGB 0..255 to linear 0..1.
double cyclesLinear(int channel) {
  final c = (channel & 0xFF) / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// The four ids [kMaterials] calls metals.
///
/// They differ from the pigments in FINISH — a tighter specular from a lower
/// roughness — and not in how metallic they are. M332 gave the renderer four
/// directional lights and a real environment, which is what a metal needs to
/// reflect, so the old reason for holding `metallic` at zero (a uniform world
/// reflects uniformly, and a fully metallic surface under one is a flat card)
/// is gone. What replaces it is PARITY, not caution: see [kCyclesMetallic].
const Set<String> kCyclesMetals = {'aluminium', 'graphite', 'brass', 'copper'};

/// A TRACE of metal on every appearance, exactly as the RealityKit rendered
/// view does it (PartScene.rendered, metallic 0.15).
///
/// The reasoning there applies here and is worth not re-deriving: a surface at
/// metallic 1.0 takes essentially all of its colour from what it reflects, and
/// what this scene has to reflect is four lights and a dim room. A brass part
/// would come out dark and colourless — the appearance the user picked would
/// have almost no say in how it looks, which is the opposite of the point.
/// 0.15 gives the highlight the body's own tint without staking the surface on
/// an environment that is not rich enough to carry it.
///
/// The same number for pigments and metals, again as RealityKit has it. The
/// four metal ids are already distinguished by roughness, and doubling up two
/// signals on one distinction only makes brass and red look like different
/// KINDS of thing rather than the same plastic-or-metal question answered
/// twice.
const double kCyclesMetallic = 0.15;

/// The material for a body painted [id] with packed [argb], or null for steel.
CyclesMaterial? cyclesMaterial(String? id, int? argb) {
  if (argb == null) return null;
  return CyclesMaterial(
    cyclesLinear(argb >> 16),
    cyclesLinear(argb >> 8),
    cyclesLinear(argb),
    roughness: kCyclesMetals.contains(id) ? 0.25 : 0.5,
    metallic: kCyclesMetallic,
  );
}

/// One mesh, in the form the shim's CyMesh takes: 32-bit positions, optional
/// 32-bit normals, 32-bit triangle indices, and the body's appearance (null
/// for the renderer's own default surface).
typedef CyclesMesh = (
  Float32List verts,
  Float32List? normals,
  Int32List tris,
  CyclesMaterial? material
);

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
CyclesMesh? cyclesMeshAt(KernelSolid solid, Placement? at,
    {CyclesMaterial? material}) {
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
  return (verts, normals, tris, material);
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
/// M333 — the RENDERED view's floor, as a mesh.
///
/// WHY IT IS A MESH AND NOT SHIM CODE. It is one quad. Building it here costs
/// nothing across the FFI boundary that a body does not already cost, it is
/// testable without a GPU, and it takes the palette's colour through exactly
/// the path every other appearance takes. A floor built in C++ would need the
/// colour, the size and the toggle pushed across as three new fields for a
/// shape the app can describe in twelve numbers.
///
/// WHY THERE IS ONE AT ALL. The RealityKit rendered view has had one since
/// M276, and a shadow with nothing to fall on is not a shadow — the sun in the
/// shim's rig casts, and without a floor the only thing it can darken is the
/// part's own undercuts. A part floating in a flat void also reads as an
/// ICON rather than as an object resting on something, which is most of what
/// makes the rendered mode feel different from the working ones.

/// M336 — a colour as the shim wants the world: three LINEAR channels.
///
/// The render's background, and through it the small ambient the surfaces
/// see. It comes from the palette rather than from a constant here for the
/// same reason RealityAppearance.setViewportColor exists: the app has two
/// schemes, and a frozen grey is right in one and wrong in the other. That is
/// exactly how the viewport background came to be charcoal under Chalk's cream
/// chrome, and how a path-traced image would come to sit as a bright grey
/// rectangle in the middle of a charcoal viewport.
List<double> cyclesWorld(int argb) => [
      cyclesLinear(argb >> 16),
      cyclesLinear(argb >> 8),
      cyclesLinear(argb),
    ];

/// The lowest Y in the scene, or null when there is nothing in it.
///
/// The world is Y-UP (see RealityPartView.commonInit — the sketch planes make
/// it look otherwise, but the camera basis, the ViewCube's top face and
/// PartCamera.dir all agree on +Y), so this is what the model is standing on.
double? cyclesMeshLowY(List<CyclesMesh> meshes) {
  double? low;
  for (final (v, _, _, _) in meshes) {
    for (var i = 1; i < v.length; i += 3) {
      final y = v[i];
      if (!y.isFinite) continue;
      if (low == null || y < low) low = y;
    }
  }
  return low;
}

/// How far across the floor reaches, as a multiple of what it has to cover.
///
/// M277's lesson on the RealityKit side: a floor sized from the SCENE alone is
/// smaller than the frame the moment you zoom out past the part, and its edge
/// walking into view takes the shadow with it. So the reach is the scene or
/// the viewplane, whichever is bigger.
const double kCyclesFloorSpan = 4.0;

/// How far below the model's lowest point the floor sits, as a fraction of the
/// scene's size.
///
/// Not a fudge. A floor exactly coplanar with a flat bottom face is a depth
/// tie, and a depth tie shimmers. A ten-thousandth of the scene is far below a
/// pixel at any zoom and is the difference between "touching" and
/// "flickering" — the same epsilon, for the same reason, as applyGround's.
const double kCyclesFloorDrop = 1e-4;

/// The floor under [meshes], or null when there is nothing to stand on or the
/// camera is not looking down at it.
///
/// [meshes] must be the MODEL's meshes only: the floor is sized from them, and
/// sizing it from a list that already contains a floor grows it without limit.
/// For the same reason the caller must compute the camera before adding this —
/// see [cyclesSceneJob].
///
/// [forwardY] is the Y component of the direction the camera LOOKS, which is
/// column 2 of the matrix [cyclesCameraMatrix] builds.
///
/// A CYCLES TRIANGLE IS DOUBLE-SIDED AND REALITYKIT'S PLANE IS NOT. Every
/// RealityKit material in this app except the outline ribbon leaves
/// `faceCulling` at its default, so orbiting under the model there shows the
/// part through a floor that is simply not drawn from beneath. Give the same
/// scene to Cycles and the floor is solid from both sides: the frame fills
/// with floor colour and the part vanishes. Which is, once again, a render
/// that comes out a flat tone for a reason that has nothing to do with the
/// model.
///
/// Culling per face is not something a mesh can ask Cycles for, and the
/// alternative — a Transparent BSDF mixed on the Backfacing output — would
/// make the floor a shader special case for a question the caller can answer
/// exactly. It looks down or it does not.
CyclesMesh? cyclesFloorMesh(
  List<CyclesMesh> meshes, {
  required int argb,
  required double halfWidth,
  required double halfHeight,
  required double forwardY,
}) {
  if (!(forwardY < 0)) return null;
  final low = cyclesMeshLowY(meshes);
  if (low == null) return null;
  final radius = cyclesMeshReach(meshes);
  final frame = math.sqrt(halfWidth * halfWidth + halfHeight * halfHeight);
  final reach = math.max(radius, frame);
  final side = math.max(2.0, reach * kCyclesFloorSpan);
  if (!side.isFinite) return null;
  final y = low - math.max(1e-4, radius * kCyclesFloorDrop);
  if (!y.isFinite) return null;
  final h = side / 2;

  /// Wound so that (v1-v0) x (v2-v0) is +Y: a floor whose normal points at the
  /// ground is lit from underneath and comes out black.
  final verts = Float32List.fromList([
    -h, y, h, //
    h, y, h, //
    h, y, -h, //
    -h, y, -h,
  ]);
  final tris = Int32List.fromList([0, 1, 2, 0, 2, 3]);
  return (
    verts,
    null,
    tris,
    CyclesMaterial(
      cyclesLinear(argb >> 16),
      cyclesLinear(argb >> 8),
      cyclesLinear(argb),
      // Fully rough and not at all metallic, exactly as
      // PartScene.groundMaterial has it: the floor is there to CATCH a shadow,
      // and anything it does beyond that competes with the model.
      roughness: 1.0,
      metallic: 0.0,
    ),
  );
}

double cyclesMeshReach(List<CyclesMesh> meshes) {
  var r2 = 0.0;
  for (final (v, _, _, _) in meshes) {
    for (var i = 0; i + 2 < v.length; i += 3) {
      final d = v[i] * v[i] + v[i + 1] * v[i + 1] + v[i + 2] * v[i + 2];
      if (d.isFinite && d > r2) r2 = d;
    }
  }
  return math.sqrt(r2);
}
