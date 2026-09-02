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

import 'cycles_assets.dart' show CyclesTextureSet, CyclesAssets;
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
///
/// M344 — AND EVERYTHING ELSE A SURFACE IS. Until now this was three numbers,
/// and they were nearly the same three for every appearance in the list: a
/// colour, a roughness that took one of two values, and a metallic that was
/// 0.15 for brass and for violet alike. That is a coloured object, not a
/// material. What is added here is what separates them — a clear coat, a
/// specular level, a texture set, a relief — and all of it is optional, so an
/// appearance that says nothing about them renders exactly as it did.
class CyclesMaterial {
  const CyclesMaterial(
    this.r,
    this.g,
    this.b, {
    this.roughness = 0.5,
    this.metallic = 0.0,
    this.specular = 0.5,
    this.coat = 0.0,
    this.coatRoughness = 0.06,
    this.anisotropy = 0.0,
    this.sheen = 0.0,
    this.textures = CyclesTextureSet.none,
    this.textureScale = kCyclesTextureScale,
    this.bumpStrength = kCyclesBumpStrength,
    this.bumpDistance = kCyclesBumpDistance,
  });

  final double r;
  final double g;
  final double b;
  final double roughness;
  final double metallic;

  /// Index-of-refraction level, 0..1, 0.5 being an ordinary dielectric.
  final double specular;

  /// Clear-coat weight — a thin smooth layer over the pigment. It is the
  /// second, sharper highlight sitting on top of the diffuse one, and it is
  /// most of what makes paint look like paint rather than like plastic.
  final double coat;
  final double coatRoughness;

  /// Directional reflection, for brushed and turned finishes. Left at zero
  /// everywhere for now: Cycles takes the tangent from the mesh, a CAD
  /// tessellation has none, and what it would fall back to is a generated
  /// radial frame that is right on a turned face and arbitrary anywhere else.
  final double anisotropy;

  /// The soft rim a bead-blasted or fabric surface has.
  final double sheen;

  /// The texture set, or [CyclesTextureSet.none].
  final CyclesTextureSet textures;

  /// How many MILLIMETRES one tile of the texture covers. See
  /// [kCyclesTextureScale].
  final double textureScale;

  /// Relief from the height map: how much of it to apply, and how far its
  /// white end stands above its black end, in millimetres.
  final double bumpStrength;
  final double bumpDistance;

  @override
  bool operator ==(Object other) =>
      other is CyclesMaterial &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.roughness == roughness &&
      other.metallic == metallic &&
      other.specular == specular &&
      other.coat == coat &&
      other.coatRoughness == coatRoughness &&
      other.anisotropy == anisotropy &&
      other.sheen == sheen &&
      other.textureScale == textureScale &&
      other.bumpStrength == bumpStrength &&
      other.bumpDistance == bumpDistance &&
      other.textures == textures;

  @override
  int get hashCode => Object.hash(r, g, b, roughness, metallic, specular, coat,
      coatRoughness, anisotropy, sheen, textureScale, bumpStrength,
      bumpDistance, textures);
}

/// sRGB 0..255 to linear 0..1.
double cyclesLinear(int channel) {
  final c = (channel & 0xFF) / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// The four ids [kMaterials] calls metals.
const Set<String> kCyclesMetals = {'aluminium', 'graphite', 'brass', 'copper'};

/// The id an unpainted body's finish is looked up under. Not a material the
/// user can pick — [materialArgb] returns null for it — but a real name, so
/// steel can carry a texture set like every other appearance.
const String kCyclesSteelId = 'steel';

/// How many millimetres one tile of a PBR texture covers.
///
/// IN WORLD UNITS RATHER THAN AS A REPEAT COUNT, and that is the whole
/// difference between a triplanar projection that reads as a finish and one
/// that reads as a texture stuck on. The bodies are real objects at real
/// sizes: a brushed grain is a fixed physical scale, and a bracket and the
/// plate it bolts to have to show the same one. A repeat count would make the
/// small part's grain coarse and the big part's fine.
///
/// Forty millimetres is about a hand's width of surface per tile, which is
/// where a machining or casting texture stops being something you can count.
const double kCyclesTextureScale = 40.0;

/// How much of the height map to apply, and how far its white end stands above
/// its black end, in millimetres.
///
/// A twentieth of a millimetre is real machining relief — a fine turned finish
/// is a few microns, a coarse milled one a few hundredths — and it is far
/// below anything the tessellation could carry as geometry, which is exactly
/// why it is worth having as a bump.
const double kCyclesBumpStrength = 0.8;
const double kCyclesBumpDistance = 0.05;

/// M344 — THE TRACE OF METAL IS GONE, AND THE REASON IT EXISTED WENT WITH IT.
///
/// M332 held every appearance at metallic 0.15, metals included, and said why:
///
///   "a surface at metallic 1.0 takes essentially all of its colour from what
///    it reflects, and what this scene has to reflect is four lights and a dim
///    room. A brass part would come out dark and colourless."
///
/// That was correct, and it was an argument about the ENVIRONMENT, not about
/// the material. A part made of brass is metallic 1.0; it was held at 0.15
/// because the renderer had nothing for it to be metallic against.
///
/// It does now. With an HDRI loaded there is a room to reflect, and a metal
/// rendered as a metal is the largest single visible difference in M344 — it
/// is why the four appearances the app calls metals stop looking like grey
/// plastic in four tints.
///
/// So the number depends on whether there is an environment, and the fallback
/// is exactly the value that shipped. A build with no HDRI renders what M343
/// rendered.
const double kCyclesMetallicNoEnvironment = 0.15;

/// How bright a metal's own reflectance is allowed to be, as a maximum linear
/// channel.
///
/// WHY THE PALETTE COLOUR IS NOT USED AS-IS FOR A METAL. At metallic 1.0 the
/// base colour is F0 — the fraction of light the surface returns head-on — and
/// for a real metal that is high: polished aluminium is about 0.91 flat, brass
/// around 0.95 in red falling to 0.43 in blue. The app's palette is a set of
/// SCREEN colours chosen so a shaded solid reads well, and its brass is linear
/// 0.53/0.37/0.13. Given to a metal, that is not brass, it is brass in deep
/// shade: the part comes out tarnished and dim under a studio that is lighting
/// everything else correctly.
///
/// So a metal's colour is lifted to this level with its hue and its chroma
/// intact. The appearance the user picked still decides WHICH metal it is; the
/// renderer decides how much light a metal reflects. Below 1.0 because nothing
/// is a perfect mirror, and a part at F0 = 1 reads as chrome whatever tint it
/// carries.
const double kCyclesMetalReflectance = 0.9;

/// The material for a body painted [id] with packed [argb], or null for steel.
///
/// [environment] is whether the scene has an HDRI to reflect. It changes what
/// a metal IS, not merely how it is lit — see [kCyclesMetallicNoEnvironment].
CyclesMaterial? cyclesMaterial(String? id, int? argb,
    {bool environment = false, CyclesTextureSet? textures}) {
  if (argb == null) return null;
  return cyclesSurface(
    id,
    cyclesLinear(argb >> 16),
    cyclesLinear(argb >> 8),
    cyclesLinear(argb),
    environment: environment,
    textures: textures ?? CyclesAssets.instance.texturesFor(id),
  );
}

/// The steel an unpainted body renders as.
///
/// It has a shape here as well as in the shim because the two answer different
/// questions. The shim's is the fallback for a mesh that arrives naming no
/// material at all — the contract cycles_shim.h states — and this is the one
/// the app builds when it wants steel to carry a texture set like every other
/// appearance. They are the same colour, deliberately: 0x86898D, the palette's.
CyclesMaterial cyclesSteel(
        {bool environment = false, CyclesTextureSet? textures}) =>
    cyclesSurface(
      kCyclesSteelId,
      cyclesLinear(0x86),
      cyclesLinear(0x89),
      cyclesLinear(0x8D),
      environment: environment,
      textures: textures ?? CyclesAssets.instance.texturesFor(kCyclesSteelId),
    );

/// The finish for appearance [id] over a linear colour.
///
/// THE ONE PLACE THAT DECIDES WHAT EACH APPEARANCE IS MADE OF. Two families:
///
///   METALS reflect their environment and have no diffuse component at all.
///   Their colour becomes reflectance, lifted to [kCyclesMetalReflectance];
///   their ROUGHNESS is what separates them — a polished copper bus-bar is
///   nearly a mirror, cast graphite is nothing like one.
///
///   PIGMENTS are a coloured dielectric under a thin clear layer. The coat is
///   what makes them read as painted or anodised rather than as coloured
///   plastic: it puts a second, much sharper highlight on top of the soft
///   diffuse one, and the eye reads the pair as a finish.
///
/// Steel is a metal, and treating it as one is why an unpainted body stops
/// looking like clay. It is the roughest of them: a machined surface, not a
/// polished one.
CyclesMaterial cyclesSurface(
  String? id,
  double r,
  double g,
  double b, {
  bool environment = false,
  CyclesTextureSet textures = CyclesTextureSet.none,
}) {
  final metal = id == kCyclesSteelId || kCyclesMetals.contains(id);
  if (!metal) {
    return CyclesMaterial(
      r,
      g,
      b,
      roughness: 0.42,
      metallic: 0.0,
      specular: 0.5,
      // A clear coat, and a tight one. Automotive paint and anodising are both
      // essentially a lacquer, and 0.06 is where its highlight is sharp enough
      // to read as a separate thing from the diffuse without becoming a mirror.
      coat: 0.55,
      coatRoughness: 0.06,
      textures: textures,
    );
  }
  final roughness = switch (id) {
    'copper' => 0.20,
    'brass' => 0.24,
    'aluminium' => 0.30,
    'graphite' => 0.52,
    _ => 0.38, // steel: machined, not polished
  };
  if (!environment) {
    // No room to reflect. Exactly what M332 shipped, for exactly its reasons.
    return CyclesMaterial(
      r,
      g,
      b,
      roughness: roughness,
      metallic: kCyclesMetallicNoEnvironment,
      textures: textures,
    );
  }
  final peak = math.max(r, math.max(g, b));
  final k = peak > 1e-6 ? kCyclesMetalReflectance / peak : 1.0;
  return CyclesMaterial(
    (r * k).clamp(0.0, 1.0),
    (g * k).clamp(0.0, 1.0),
    (b * k).clamp(0.0, 1.0),
    roughness: roughness,
    metallic: 1.0,
    textures: textures,
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

/// A ceiling on the rendered image's long side that no current device reaches.
///
/// M353 — A STANDSTILL NOW RENDERS AT THE VIEWPORT'S OWN RESOLUTION.
///
/// The history is worth keeping because it is the same mistake twice. 900 was
/// a one-shot renderer's number: cost is pixels times samples, so a third of a
/// megapixel "lands in seconds rather than minutes". M347 raised it to 1440 —
/// four fifths of an iPad Pro viewport's long side — and stopped there for one
/// reason, MEMORY, with the arithmetic written down: the shim held frame,
/// albedo and normal in floats, twice over, plus nine floats a pixel of
/// denoiser scratch. About 176 bytes per pixel, which at a true 1:1 came to
/// roughly half a gigabyte.
///
/// Every term in that sum except the frame itself belonged to the denoiser,
/// and M353 removed the denoiser. What is left is the output driver's copy,
/// the store's and the reader's — three RGBA float buffers, 48 bytes a pixel,
/// plus the four bytes of the RGBA8 image that crosses to Dart. Fifty-two
/// bytes a pixel, under a third of what it was. On a ~1800-pixel viewport
/// that is about 126 MB, and dropping the two guide passes takes another six
/// floats a pixel off Cycles' own GPU render buffer at the same time.
///
/// So the cap that existed to buy back denoiser memory has nothing left to buy
/// back, and a render at anything less than 1:1 is soft at every sample count
/// with no amount of waiting able to sharpen it. A standstill renders at the
/// device pixels the viewport actually occupies.
///
/// This constant survives only as an ALLOCATION GUARD. 4096 is above the long
/// side of any iPad's full screen, so it never binds on real hardware; it is
/// here so that a nonsense size — an unlaid-out viewport, an external display
/// nobody has thought about — cannot ask for a buffer measured in gigabytes.
/// If it ever binds, that is a bug to look at rather than a limit to raise.
///
/// The orbit is not affected either way: it renders at [kCyclesMovingSide],
/// and only a standstill reaches this.
const int kCyclesMaxSide = 4096;

/// The long side to render at WHILE THE CAMERA IS MOVING.
///
/// M344 — THE ONE KNOB AN ORBIT TURNS. A path tracer that follows the camera
/// has a frame budget like any other renderer, and the honest way to meet it
/// is fewer pixels, not fewer samples: at 480 the image is a quarter of the
/// work, the first sample lands in tens of milliseconds instead of hundreds,
/// and it is scaled up over a viewport the user is dragging — where the eye is
/// tracking the SHAPE moving and cannot resolve fine detail anyway. Cutting
/// samples instead would keep the sharpness nobody can see and spend the
/// budget on noise everybody can.
///
/// Cycles has its own version of this (SessionParams.use_resolution_divider,
/// which renders early samples small and scales them up) and the shim turns it
/// off, because doing it here is strictly better: the pixels that are skipped
/// are never allocated, never crossed over the FFI boundary and never
/// denoised.
const int kCyclesMovingSide = 480;

/// How many samples a render converges to.
///
/// M344 — A TARGET, NOT A COUNT. Sampling is progressive now: the image is on
/// screen from the first sample and improves until it reaches this, at which
/// point Cycles stops and the GPU goes quiet. So the number no longer decides
/// how long you wait for a picture, only how good the one you are already
/// looking at gets — which is why it is far higher than the 48 that was the
/// whole wait before it.
///
/// M353 — 4096, WHICH IS BLENDER'S OWN FINAL-RENDER DEFAULT.
///
/// 256 was chosen as "where a studio-lit CAD body stops changing in any way
/// the eye can see", and with a denoiser smoothing what was left that was
/// true. Nothing is filtered now, so the only thing standing between the image
/// and a clean one is samples, and the target has to be high enough that the
/// path tracer is never the reason a render stopped looking better.
///
/// It is a CEILING, not a duration. Adaptive sampling ends each pixel at its
/// own error estimate, so a flat lit face is finished in tens of samples and
/// only the soft shadows and glossy reflections spend the rest; a typical CAD
/// scene stops well short of this and the badge reports where it actually got
/// to (M347). Raising the ceiling costs nothing on a scene that converges
/// early and buys everything on one that does not.
const int kCyclesSamples = 4096;

/// The sample target WHILE THE CAMERA IS MOVING.
///
/// M347 — THE OTHER HALF OF THE ORBIT BUDGET, AND THE HALF THAT WAS MISSING.
///
/// [kCyclesMovingSide] cut the pixels an orbit renders and left the sample
/// target at [kCyclesSamples], which means that during an orbit the path
/// tracer was still working towards 256 samples of every frame it would never
/// finish. It never got there and it never stopped trying: each camera move
/// restarted a render that would have taken a quarter of a second of solid GPU
/// time, so between the first frame of a drag and the last the GPU was pinned
/// at a hundred per cent — and the compositor, which needs a slice of the same
/// GPU every eight milliseconds to put a frame on the screen, had to fight it
/// for one. That is what an orbit that stutters while the model itself is
/// simple is made of.
///
/// A small target ends the fight. The tracer reaches 24 samples in a few tens
/// of milliseconds, the session goes idle, and the GPU is free until the next
/// camera push — which at 60 Hz is immediately, but IN BETWEEN, which is where
/// a frame gets composited. It is the same bargain the resolution ladder
/// makes and for the same reason: the eye tracking a moving shape cannot
/// resolve either detail or noise while it is tracking a moving shape.
///
/// M353 — THE OLD JUSTIFICATION NAMED THE FILTER, AND THE FILTER IS GONE. It
/// used to read "24 samples through the a-trous filter reads as a clean moving
/// picture". Nothing filters now, so an orbit frame is visibly grainy, and
/// that is the deliberate trade rather than an oversight: a fluid grainy orbit
/// is what Blender's viewport does and what was asked for here, and the number
/// stays where it is because fluidity was the complaint. Raising it is the
/// first thing to try if a moving frame turns out to be TOO coarse to aim
/// with — but it is paid for in exactly the stutter this constant exists to
/// prevent.
///
/// It is Blender's bargain too — `RenderScheduler` caps the samples per work
/// item while the user is navigating and drops the resolution divider — with
/// the difference that this app owns its own resolution ladder and so has to
/// own the sample cap as well.
const int kCyclesMovingSamples = 24;

/// The side of the throwaway frame the renderer is parked on during a drag.
///
/// M354 — WHILE THE CAMERA MOVES THE VIEWPORT IS REALITYKIT, AND THE PATH
/// TRACER HAS TO ACTUALLY STOP.
///
/// Not pushing a new view is not enough. If the camera is grabbed while a
/// render is still converging, Cycles goes on tracing the view it already has
/// — at full resolution, towards [kCyclesSamples] — which is exactly the
/// moment the GPU is needed for something else. The session has to be told to
/// abandon it.
///
/// Closing the session would do it and costs far too much: it drops the
/// geometry, so the next standstill re-uploads every vertex and rebuilds the
/// BVH, once per gesture. Instead the session is PARKED — pushed a view it can
/// finish immediately, one sample of a frame this size. Pushing it calls
/// Session::reset, which cancels the render in flight; the tracer then does a
/// few thousand paths, reports finished, and the session sits idle with the
/// GPU free until the camera stops.
///
/// It is one push per GESTURE, not per frame: the parked request does not
/// change while the drag continues, so the session sees the same key and does
/// nothing. Nobody ever sees this frame — the layer draws RealityKit for as
/// long as the camera is moving.
const int kCyclesParkedSide = 64;

/// Everything a moving camera changes about the request, in one place.
///
/// M347 — THE TWO HALVES OF THE BUDGET, SO THEY CANNOT DRIFT APART. Until now
/// only the size knew about navigation; the sample target was a constant, and
/// the result was an orbit that rendered a quarter of the pixels and then
/// worked on them for a quarter of a second each. Both halves are the same
/// decision — how much of the machine a frame nobody will look at for more
/// than sixteen milliseconds is allowed to take — and a caller that has to
/// remember to ask two functions the same question will eventually ask only
/// one.
({int width, int height, int samples}) cyclesFrameBudget(
    double width, double height, double dpr,
    {required bool moving}) {
  final (w, h) = cyclesImageSize(width, height, dpr, moving: moving);
  return (
    width: w,
    height: h,
    samples: moving ? kCyclesMovingSamples : kCyclesSamples,
  );
}

/// The pixel size to render [size] logical points at, and never zero.
///
/// A STANDSTILL IS 1:1 — the device pixels the viewport occupies, subject only
/// to [kCyclesMaxSide], which is an allocation guard no real viewport reaches.
/// [moving] drops it to [kCyclesMovingSide] for the frames of an orbit, which
/// is the one place fewer pixels are worth more than sharpness.
(int, int) cyclesImageSize(double width, double height, double dpr,
    {bool moving = false}) {
  final w = width * dpr, h = height * dpr;
  if (!w.isFinite || !h.isFinite || w < 1 || h < 1) return (1, 1);
  final cap = moving ? kCyclesMovingSide : kCyclesMaxSide;
  final long = math.max(w, h);
  final k = long > cap ? cap / long : 1.0;
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

/// How much of the analytic rig is left once an HDRI is doing the lighting.
///
/// NOT ZERO, and the reason is the one thing an environment map cannot do. It
/// lights beautifully and casts nothing sharp: every shadow it throws is the
/// soft average of a whole room, so a part rendered under one alone FLOATS —
/// there is no contact shadow with a direction, and a direction is the cue
/// that says "resting on the table". A fifth of the rig keeps the sun's shadow
/// and the headlight's modelling and is far too little to compete with the
/// environment for what the specular reflects.
const double kCyclesRigWithEnvironment = 0.2;

/// How bright the environment is, against the map as captured.
///
/// One, because a studio HDRI is already exposed for exactly this: it was shot
/// to light a product. A multiplier here would be a second exposure control
/// fighting the first, and the place to fix a dark map is the map.
const double kCyclesHdriStrength = 1.0;

/// How much of the visible background the surfaces see when there is no HDRI.
///
/// A FRACTION, so what it is worth depends entirely on the palette, and the
/// two schemes are nowhere near each other: Chalk's viewport is 0xFCFBF8,
/// linear 0.96, and this puts about 0.036 on a steel face — a real if modest
/// lift. The dark scheme's is 0x201D19, linear 0.012, and this puts 0.0005 on
/// the same face, which is nothing at all.
///
/// That is the right behaviour and not a gap to close. The number the camera
/// sees has to be the viewport's colour exactly, or the render does not sit on
/// the ground the app draws; and a room whose walls are that dark really does
/// bounce nothing. What keeps the model from having black faces under the dark
/// scheme is the camera-locked headlight and the floor bounce, not this.
const double kCyclesAmbient = 0.15;

/// The world a render happens in: what lights it, and what is behind it.
///
/// The two are DELIBERATELY SEPARATE, and that separation is what lets an HDRI
/// ship at all. `world` is the app's own viewport colour and is what the
/// camera sees, so a path-traced image lands on exactly the ground the rest of
/// the app is drawing rather than as a bright rectangle in the middle of a
/// charcoal viewport. The HDRI is what every OTHER ray sees, which is to say
/// it is the light. Cycles can tell the two kinds of ray apart, so both are
/// true at once.
class CyclesEnv {
  const CyclesEnv({
    this.hdri,
    this.hdriStrength = kCyclesHdriStrength,
    this.hdriRotation = 0.0,
    this.hdriVisible = false,
    this.world = const [0.8, 0.8, 0.8],
    this.ambient = kCyclesAmbient,
    this.rig = 1.0,
  });

  /// An equirectangular .hdr or .exr, or null for none.
  final String? hdri;
  final double hdriStrength;

  /// Turn the environment about the world's up axis, radians. The one control
  /// that matters on a studio map: it aims the softbox.
  final double hdriRotation;

  /// Show the environment behind the model instead of the viewport's colour.
  final bool hdriVisible;

  /// The viewport's own background, LINEAR.
  final List<double> world;
  final double ambient;

  /// 0..1 on the four analytic lights.
  final double rig;

  bool get hasHdri => hdri != null && hdri!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is CyclesEnv &&
      other.hdri == hdri &&
      other.hdriStrength == hdriStrength &&
      other.hdriRotation == hdriRotation &&
      other.hdriVisible == hdriVisible &&
      other.ambient == ambient &&
      other.rig == rig &&
      other.world.length == world.length &&
      other.world[0] == world[0] &&
      other.world[1] == world[1] &&
      other.world[2] == world[2];

  @override
  int get hashCode => Object.hash(hdri, hdriStrength, hdriRotation, hdriVisible,
      ambient, rig, world[0], world[1], world[2]);
}

/// The world for a viewport whose background is [argb], using whatever
/// environment map this build has.
CyclesEnv cyclesEnvFor(int argb, {String? hdri}) {
  final map = hdri ?? CyclesAssets.instance.hdri;
  final lit = map != null && map.isNotEmpty;
  return CyclesEnv(
    hdri: lit ? map : null,
    world: cyclesWorld(argb),
    ambient: kCyclesAmbient,
    rig: lit ? kCyclesRigWithEnvironment : 1.0,
  );
}

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

/// How far across the floor reaches, as a multiple of the model's own radius.
///
/// M277's lesson on the RealityKit side: a floor sized from the SCENE alone is
/// smaller than the frame the moment you zoom out past the part, and its edge
/// walking into view takes the shadow with it. M333 answered that by sizing it
/// from the scene OR the viewplane, whichever was bigger.
///
/// M344 — AND THE VIEWPLANE HAD TO GO. A floor whose size depends on the zoom
/// is a floor that changes whenever the camera does, and in a live renderer
/// that means re-uploading the geometry on every frame of a pinch — which is
/// exactly the cost the scene/view split exists to avoid.
///
/// So it is sized from the model alone, and generously: twelve times the
/// part's own radius is past any zoom at which the part is still recognisable,
/// and a quad costs nothing whatever size it is. The edge that M277 saw
/// walking into view is now further away than the part is interesting.
const double kCyclesFloorSpan = 12.0;

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
/// see [cyclesSceneData].
///
/// [lookingDown] is whether the camera is above the floor, which is the Y
/// component of the direction the camera LOOKS being negative — column 2 of
/// the matrix [cyclesCameraMatrix] builds. It is the ONE thing about the
/// camera the geometry depends on, and it is a single bit, so it travels in
/// the scene key: crossing the horizon rebuilds the scene, and nothing else
/// about an orbit does.
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
  required bool lookingDown,
}) {
  if (!lookingDown) return null;
  final low = cyclesMeshLowY(meshes);
  if (low == null) return null;
  final radius = cyclesMeshReach(meshes);
  final side = math.max(2.0, radius * kCyclesFloorSpan);
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
