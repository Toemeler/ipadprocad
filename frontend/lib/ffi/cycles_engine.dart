// M297 — the Dart side of the Cycles shim.
//
// Same shape as OcctFfi: symbols are looked up in the PROCESS, because the
// renderer is a static library linked into the app rather than a dylib to be
// opened. On a host that has not linked it — every test runner, and any build
// before the libraries land — the lookup fails and [CyclesFfi.instance] is
// null. Nothing in the app may assume a renderer exists.
//
// M344 — AND NOW THERE ARE TWO WAYS IN.
//
//   * [render] is the one-shot: build a scene, block until the sample count is
//     reached, hand back pixels. It is what the kernel warm-up uses.
//   * [liveScene], [liveView] and [liveFrame] drive the resident session: the
//     scene is uploaded when it changes, the camera whenever it moves, and
//     frames are pulled out as they converge. It is what the viewport uses,
//     from one long-lived isolate — see cycles_live.dart.
//
// Both block, and neither belongs on the UI thread.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../cycles_view.dart' show CyclesEnv, CyclesMaterial, CyclesMesh;
import '../log.dart';
import 'native_lib.dart';

// ---- the C surface, mirrored ------------------------------------------------
// Kept structurally identical to backend/cycles/shim/cycles_shim.h. A field
// added there and not here is a silently misread struct, so the two are
// reviewed together.

/// M344 — the material TABLE's element. See cycles_shim.h for why the
/// appearance stopped travelling inside CyMesh: a copy per mesh worked while
/// an appearance was five numbers, and stops working the moment one carries
/// five file paths.
final class CyMaterialS extends Struct {
  @Array(3)
  external Array<Float> color;
  @Float()
  external double roughness;
  @Float()
  external double metallic;
  @Float()
  external double specular;
  @Float()
  external double coat;
  @Float()
  external double coatRoughness;
  @Float()
  external double anisotropy;
  @Float()
  external double sheen;
  @Array(3)
  external Array<Float> emission;
  @Float()
  external double emissionStrength;
  external Pointer<Utf8> baseMap;
  external Pointer<Utf8> roughnessMap;
  external Pointer<Utf8> metallicMap;
  external Pointer<Utf8> bumpMap;
  external Pointer<Utf8> aoMap;
  @Float()
  external double textureScale;
  @Float()
  external double bumpStrength;
  @Float()
  external double bumpDistance;
}

final class CyMeshS extends Struct {
  external Pointer<Float> verts;
  @Int32()
  external int vertCount;
  external Pointer<Float> normals;
  external Pointer<Int32> tris;
  @Int32()
  external int triCount;

  /// Index into the material table, or -1 for the renderer's own steel. A
  /// field added to cycles_shim.h and not here is not a missing feature, it is
  /// a struct read past its end: Dart sizes the array from THIS declaration,
  /// so the shim would index into the next element's memory.
  @Int32()
  external int material;
}

final class CyEnvS extends Struct {
  external Pointer<Utf8> hdri;
  @Float()
  external double hdriStrength;
  @Float()
  external double hdriRotation;
  @Int32()
  external int hdriVisible;
  @Array(3)
  external Array<Float> world;
  @Float()
  external double ambient;
  @Float()
  external double rig;
}

final class CyViewS extends Struct {
  @Array(12)
  external Array<Float> matrix;
  @Float()
  external double halfWidth;
  @Float()
  external double halfHeight;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int samples;
}

final class CyFrameS extends Struct {
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int samples;
  @Int32()
  external int target;
  @Int32()
  external int done;
  @Int32()
  external int denoised;
}

typedef _AvailN = Int32 Function();
typedef _PauseN = Int32 Function(Int32);
typedef _PauseD = int Function(int);
typedef _AvailD = int Function();
typedef _VoidN = Void Function();
typedef _VoidD = void Function();
typedef _StrN = Pointer<Utf8> Function();
typedef _StrD = Pointer<Utf8> Function();
typedef _SetPathN = Void Function(Pointer<Utf8>);
typedef _SetPathD = void Function(Pointer<Utf8>);
typedef _RenderN = Int32 Function(Pointer<CyMeshS>, Int32, Pointer<CyMaterialS>,
    Int32, Pointer<CyEnvS>, Pointer<CyViewS>, Pointer<Uint8>);
typedef _RenderD = int Function(Pointer<CyMeshS>, int, Pointer<CyMaterialS>, int,
    Pointer<CyEnvS>, Pointer<CyViewS>, Pointer<Uint8>);
typedef _SceneN = Int32 Function(
    Pointer<CyMeshS>, Int32, Pointer<CyMaterialS>, Int32, Pointer<CyEnvS>);
typedef _SceneD = int Function(
    Pointer<CyMeshS>, int, Pointer<CyMaterialS>, int, Pointer<CyEnvS>);
typedef _ViewN = Int32 Function(Pointer<CyViewS>);
typedef _ViewD = int Function(Pointer<CyViewS>);
typedef _FrameN = Int32 Function(Pointer<Uint8>, Int32, Pointer<CyFrameS>);
typedef _FrameD = int Function(Pointer<Uint8>, int, Pointer<CyFrameS>);
typedef _StatusN = Void Function(Pointer<Uint8>, Int32);
typedef _StatusD = void Function(Pointer<Uint8>, int);
typedef _ProgressN = Float Function();
typedef _ProgressD = double Function();

/// How long a status line can be. Cycles' own are one sentence.
const int _kStatusMax = 256;

/// One frame out of the live session: the pixels, and how far along it is.
class CyclesFrame {
  const CyclesFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.samples,
    required this.target,
    required this.done,
    required this.denoised,
  });

  final Uint8List rgba;
  final int width;
  final int height;

  /// How many samples this frame averages, and the count it is heading for.
  final int samples;
  final int target;

  /// Sampling has finished; this picture will not improve.
  final bool done;

  /// The a-trous filter was applied to it. False once it has converged.
  final bool denoised;
}

/// The renderer, or null when this build has none linked.
class CyclesFfi {
  CyclesFfi._(
    this._available,
    this._deviceName,
    this._denoiserName,
    this._setPath,
    this._render,
    this._lastError,
    this._preload,
    this._kernelsReady,
    this._status,
    this._progress,
    this._liveOpen,
    this._liveClose,
    this._liveIsOpen,
    this._liveScene,
    this._liveView,
    this._liveFrame,
    this._livePause,
  );

  final _AvailD _available;
  final _StrD _deviceName;
  final _StrD _denoiserName;
  final _SetPathD _setPath;
  final _RenderD _render;
  final _StrD _lastError;
  final _AvailD _preload;
  final _AvailD _kernelsReady;
  final _StatusD _status;
  final _ProgressD _progress;
  final _AvailD _liveOpen;
  final _VoidD _liveClose;
  final _AvailD _liveIsOpen;
  final _SceneD _liveScene;
  final _ViewD _liveView;
  final _FrameD _liveFrame;
  final _PauseD _livePause;

  static CyclesFfi? _instance;
  static bool _tried = false;

  /// Null when the shim is not in this binary. Probed once.
  static CyclesFfi? get instance {
    if (_tried) return _instance;
    _tried = true;
    try {
      final lib = NativeLib.open(NativeLib.cycles, optional: true);
      if (lib == null) throw StateError('no Cycles library');
      _instance = CyclesFfi._(
        lib.lookupFunction<_AvailN, _AvailD>('cy_available'),
        lib.lookupFunction<_StrN, _StrD>('cy_device_name'),
        lib.lookupFunction<_StrN, _StrD>('cy_denoiser_name'),
        lib.lookupFunction<_SetPathN, _SetPathD>('cy_set_resource_path'),
        lib.lookupFunction<_RenderN, _RenderD>('cy_render'),
        lib.lookupFunction<_StrN, _StrD>('cy_last_error'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_preload'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_kernels_ready'),
        lib.lookupFunction<_StatusN, _StatusD>('cy_status'),
        lib.lookupFunction<_ProgressN, _ProgressD>('cy_progress'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_live_open'),
        lib.lookupFunction<_VoidN, _VoidD>('cy_live_close'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_live_is_open'),
        lib.lookupFunction<_SceneN, _SceneD>('cy_live_scene'),
        lib.lookupFunction<_ViewN, _ViewD>('cy_live_view'),
        lib.lookupFunction<_FrameN, _FrameD>('cy_live_frame'),
        lib.lookupFunction<_PauseN, _PauseD>('cy_live_pause'),
      );
      Log.i(
          'cycles',
          'shim linked; device ${_instance!.deviceName}, '
          'denoiser ${_instance!.denoiserName}');
    } catch (e) {
      // Expected off-device and in every host test. Not a warning.
      Log.d('cycles', 'no Cycles shim in this binary: $e');
      _instance = null;
    }
    return _instance;
  }

  /// Forgets the probe. For tests, which must not inherit another case's
  /// answer about whether the renderer is linked.
  static void resetForTest() {
    _tried = false;
    _instance = null;
  }

  bool get available => _available() != 0;

  /// True once the Metal kernels are compiled and a render would start at once.
  bool get kernelsReady => _kernelsReady() != 0;

  /// Compiles the Metal kernels. BLOCKING, for minutes on a cold install —
  /// runs on its own isolate. Returns false when the device cannot render.
  bool preload() => _preload() != 0;

  /// What Cycles is doing right now, or '' when nothing is running.
  ///
  /// Safe to call from the UI isolate while a render runs on another: the shim
  /// copies the string out under a mutex rather than handing back a pointer
  /// into one another thread is rewriting.
  String get status {
    final buf = calloc<Uint8>(_kStatusMax);
    try {
      _status(buf, _kStatusMax);
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  /// How far along, 0..1, or negative when nothing is running.
  double get progress => _progress();
  String get deviceName => _deviceName().toDartString();

  /// M367 — which denoiser finishes a render in this build.
  ///
  /// "OpenImageDenoise" when Cycles' own is linked — the denoiser Blender uses
  /// — and "a-trous" when it is not and the shim's own filter runs instead.
  /// A compile-time fact, so it is safe to read before anything has rendered;
  /// see cy_denoiser_name in cycles_shim.h for why it cannot usefully be asked
  /// of the session.
  ///
  /// Logged beside the device name at startup, for the same reason: a render
  /// that looks different on two machines should not need a build inspection.
  String get denoiserName => _denoiserName().toDartString();
  String get lastError => _lastError().toDartString();

  /// Points Cycles at its kernel source tree. Must be called before the first
  /// render or the Metal device has nothing to compile — see cycles_shim.h.
  void setResourcePath(String path) {
    final p = path.toNativeUtf8();
    try {
      _setPath(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Renders [meshes] and returns RGBA8, or null with [lastError] set.
  ///
  /// BLOCKING, for as long as the sample count takes. The caller runs it off
  /// the UI thread.
  Uint8List? render({
    required List<CyclesMesh> meshes,
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
    CyclesEnv env = const CyclesEnv(),
  }) {
    if (matrix.length != 12 || width <= 0 || height <= 0) return null;
    final arena = Arena();
    try {
      final (meshArr, matArr, matCount) = _packScene(arena, meshes);
      final envPtr = _packEnv(arena, env);
      final view = _packView(
          arena, matrix, halfWidth, halfHeight, width, height, samples);
      final out = arena<Uint8>(width * height * 4);
      final ok = _render(
          meshArr, meshes.length, matArr, matCount, envPtr, view, out);
      if (ok == 0) return null;
      return Uint8List.fromList(out.asTypedList(width * height * 4));
    } finally {
      arena.releaseAll();
    }
  }

  // ---- the live session -----------------------------------------------------

  /// Brings up the resident session. Idempotent.
  bool liveOpen() => _liveOpen() != 0;

  /// Tears it down and gives the GPU memory back.
  void liveClose() => _liveClose();

  bool get liveIsOpen => _liveIsOpen() != 0;

  /// Replaces the geometry, the materials and the world. Expensive; sampling
  /// restarts.
  bool liveScene(List<CyclesMesh> meshes, CyclesEnv env) {
    final arena = Arena();
    try {
      final (meshArr, matArr, matCount) = _packScene(arena, meshes);
      return _liveScene(
              meshArr, meshes.length, matArr, matCount, _packEnv(arena, env)) !=
          0;
    } finally {
      arena.releaseAll();
    }
  }

  /// Points the camera somewhere else. Cheap; sampling restarts.
  bool liveView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  }) {
    if (matrix.length != 12 || width <= 0 || height <= 0) return false;
    final arena = Arena();
    try {
      return _liveView(_packView(
              arena, matrix, halfWidth, halfHeight, width, height, samples)) !=
          0;
    } finally {
      arena.releaseAll();
    }
  }

  /// The buffer [liveFrame] reads into, and the struct it reads back.
  ///
  /// M347 — KEPT, NOT ALLOCATED PER CALL. [liveFrame] is polled every
  /// `kCyclesPoll` — seventy times a second — and it used to take an Arena and
  /// ask it for width*height*4 bytes before finding out whether there was a
  /// frame at all. At the settled size that is a seven-megabyte malloc and free
  /// seventy times a second, almost all of it for polls that return "nothing
  /// new". The allocator is process-wide: that churn is contended with every
  /// allocation the UI isolate makes to build a frame, which is the shape of a
  /// stutter that no single expensive thing explains.
  ///
  /// Grown to the largest image ever asked for and then left alone. Not freed:
  /// the renderer's own buffers for the same image are an order of magnitude
  /// larger, and a session that has rendered once will render again.
  Pointer<Uint8> _frameBuf = nullptr;
  int _frameCap = 0;
  Pointer<CyFrameS> _frameInfo = nullptr;

  /// Suspend or resume sampling without losing what has been sampled.
  ///
  /// M355 — the only way to take the GPU back from a converging render and
  /// give it to the compositor. A view push would do it too and would reset
  /// the image to noise; this comes back to the same picture.
  void livePause(bool paused) => _livePause(paused ? 1 : 0);

  /// The most recent frame, or null when there is nothing newer than the last
  /// one this returned.
  ///
  /// [width] and [height] size the buffer offered to the shim; they are what
  /// the last [liveView] asked for. A frame larger than that is refused rather
  /// than truncated.
  CyclesFrame? liveFrame(int width, int height) {
    if (width <= 0 || height <= 0) return null;
    final n = width * height * 4;
    if (_frameCap < n) {
      if (_frameBuf != nullptr) calloc.free(_frameBuf);
      _frameBuf = calloc<Uint8>(n);
      _frameCap = n;
    }
    if (_frameInfo == nullptr) _frameInfo = calloc<CyFrameS>();
    final out = _frameBuf;
    final info = _frameInfo;
    final r = _liveFrame(out, n, info);
    if (r != 1) return null;
    final f = info.ref;
    final px = f.width * f.height * 4;
    if (px <= 0 || px > n) return null;
    return CyclesFrame(
      // COPIED, and it has to be: the buffer above is reused by the next poll,
      // and what leaves here crosses an isolate boundary and is drawn from.
      rgba: Uint8List.fromList(out.asTypedList(px)),
      width: f.width,
      height: f.height,
      samples: f.samples,
      target: f.target,
      done: f.done != 0,
      denoised: f.denoised != 0,
    );
  }

  // ---- packing --------------------------------------------------------------

  /// The meshes and their material table, deduplicated.
  ///
  /// ONE TABLE ENTRY PER DISTINCT APPEARANCE, which is what the index in
  /// CyMesh is for. An assembly is routinely hundreds of pieces drawn from a
  /// handful of appearances, and a table with one row per piece would make the
  /// shim build one Shader — and one ImageHandle per texture file — for each
  /// of them.
  (Pointer<CyMeshS>, Pointer<CyMaterialS>, int) _packScene(
      Arena arena, List<CyclesMesh> meshes) {
    final table = <CyclesMaterial, int>{};
    for (final (_, _, _, mat) in meshes) {
      if (mat != null) table.putIfAbsent(mat, () => table.length);
    }
    final meshArr = arena<CyMeshS>(meshes.isEmpty ? 1 : meshes.length);
    for (var i = 0; i < meshes.length; i++) {
      final (v, n, t, mat) = meshes[i];
      final vp = arena<Float>(v.length);
      vp.asTypedList(v.length).setAll(0, v);
      final tp = arena<Int32>(t.length);
      tp.asTypedList(t.length).setAll(0, t);
      meshArr[i]
        ..verts = vp
        ..vertCount = v.length ~/ 3
        ..tris = tp
        ..triCount = t.length ~/ 3
        ..material = mat == null ? -1 : table[mat]!;
      if (n != null && n.length == v.length) {
        final np = arena<Float>(n.length);
        np.asTypedList(n.length).setAll(0, n);
        meshArr[i].normals = np;
      } else {
        meshArr[i].normals = nullptr;
      }
    }
    final matArr = arena<CyMaterialS>(table.isEmpty ? 1 : table.length);
    table.forEach((mat, i) {
      matArr[i]
        ..roughness = mat.roughness
        ..metallic = mat.metallic
        ..specular = mat.specular
        ..coat = mat.coat
        ..coatRoughness = mat.coatRoughness
        ..anisotropy = mat.anisotropy
        ..sheen = mat.sheen
        ..emissionStrength = 0.0
        ..textureScale = mat.textureScale
        ..bumpStrength = mat.bumpStrength
        ..bumpDistance = mat.bumpDistance
        ..baseMap = _str(arena, mat.textures.base)
        ..roughnessMap = _str(arena, mat.textures.roughness)
        ..metallicMap = _str(arena, mat.textures.metallic)
        ..bumpMap = _str(arena, mat.textures.height)
        ..aoMap = _str(arena, mat.textures.occlusion);
      matArr[i].color[0] = mat.r;
      matArr[i].color[1] = mat.g;
      matArr[i].color[2] = mat.b;
      matArr[i].emission[0] = 0.0;
      matArr[i].emission[1] = 0.0;
      matArr[i].emission[2] = 0.0;
    });
    return (meshArr, matArr, table.length);
  }

  Pointer<CyEnvS> _packEnv(Arena arena, CyclesEnv env) {
    final p = arena<CyEnvS>();
    p.ref
      ..hdri = _str(arena, env.hdri)
      ..hdriStrength = env.hdriStrength
      ..hdriRotation = env.hdriRotation
      ..hdriVisible = env.hdriVisible ? 1 : 0
      ..ambient = env.ambient
      ..rig = env.rig;
    for (var i = 0; i < 3; i++) {
      p.ref.world[i] = i < env.world.length ? env.world[i] : 0.8;
    }
    return p;
  }

  Pointer<CyViewS> _packView(Arena arena, List<double> matrix, double halfWidth,
      double halfHeight, int width, int height, int samples) {
    final view = arena<CyViewS>();
    for (var i = 0; i < 12; i++) {
      view.ref.matrix[i] = matrix[i];
    }
    view.ref
      ..halfWidth = halfWidth
      ..halfHeight = halfHeight
      ..width = width
      ..height = height
      ..samples = samples;
    return view;
  }

  /// A NUL-terminated copy of [s] in [arena], or null.
  ///
  /// Allocated in the arena rather than with `toNativeUtf8()` on its own so
  /// the lifetime is the CALL's, not the caller's memory to remember. The shim
  /// copies what it needs — a ustring on the node — before returning.
  Pointer<Utf8> _str(Arena arena, String? s) {
    if (s == null || s.isEmpty) return nullptr;
    return s.toNativeUtf8(allocator: arena);
  }
}
