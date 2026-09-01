// M297 — the Dart side of the Cycles shim.
//
// Same shape as OcctFfi: symbols are looked up in the PROCESS, because the
// renderer is a static library linked into the app rather than a dylib to be
// opened. On a host that has not linked it — every test runner, and any build
// before the libraries land — the lookup fails and [CyclesFfi.instance] is
// null. Nothing in the app may assume a renderer exists.
//
// The blocking call is deliberate and belongs off the UI thread; see
// cycles_shim.h. What runs it is [AppState], not this file.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../cycles_view.dart' show CyclesMesh;
import '../log.dart';

// ---- the C surface, mirrored ------------------------------------------------
// Kept structurally identical to backend/cycles/shim/cycles_shim.h. A field
// added there and not here is a silently misread struct, so the two are
// reviewed together.

final class CyMeshS extends Struct {
  external Pointer<Float> verts;
  @Int32()
  external int vertCount;
  external Pointer<Float> normals;
  external Pointer<Int32> tris;
  @Int32()
  external int triCount;
  // M323 — the body's appearance. A field added to cycles_shim.h and not here
  // is not a missing feature, it is a struct read past its end: Dart sizes the
  // array from THIS declaration, so the shim would index into the next
  // element's memory. The two are reviewed together for that reason.
  @Int32()
  external int hasMaterial;
  @Array(3)
  external Array<Float> color;
  @Float()
  external double roughness;
  @Float()
  external double metallic;
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
  @Array(3)
  external Array<Float> world;
}

typedef _AvailN = Int32 Function();
typedef _AvailD = int Function();
typedef _StrN = Pointer<Utf8> Function();
typedef _StrD = Pointer<Utf8> Function();
typedef _SetPathN = Void Function(Pointer<Utf8>);
typedef _SetPathD = void Function(Pointer<Utf8>);
typedef _RenderN = Int32 Function(
    Pointer<CyMeshS>, Int32, Pointer<CyViewS>, Pointer<Uint8>);
typedef _RenderD = int Function(
    Pointer<CyMeshS>, int, Pointer<CyViewS>, Pointer<Uint8>);
typedef _StatusN = Void Function(Pointer<Uint8>, Int32);
typedef _StatusD = void Function(Pointer<Uint8>, int);
typedef _ProgressN = Float Function();
typedef _ProgressD = double Function();

/// How long a status line can be. Cycles' own are one sentence.
const int _kStatusMax = 256;

/// The renderer, or null when this build has none linked.
class CyclesFfi {
  CyclesFfi._(this._available, this._deviceName, this._setPath, this._render,
      this._lastError, this._preload, this._kernelsReady, this._status,
      this._progress);

  final _AvailD _available;
  final _StrD _deviceName;
  final _SetPathD _setPath;
  final _RenderD _render;
  final _StrD _lastError;
  final _AvailD _preload;
  final _AvailD _kernelsReady;
  final _StatusD _status;
  final _ProgressD _progress;

  static CyclesFfi? _instance;
  static bool _tried = false;

  /// Null when the shim is not in this binary. Probed once.
  static CyclesFfi? get instance {
    if (_tried) return _instance;
    _tried = true;
    try {
      final lib = DynamicLibrary.process();
      _instance = CyclesFfi._(
        lib.lookupFunction<_AvailN, _AvailD>('cy_available'),
        lib.lookupFunction<_StrN, _StrD>('cy_device_name'),
        lib.lookupFunction<_SetPathN, _SetPathD>('cy_set_resource_path'),
        lib.lookupFunction<_RenderN, _RenderD>('cy_render'),
        lib.lookupFunction<_StrN, _StrD>('cy_last_error'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_preload'),
        lib.lookupFunction<_AvailN, _AvailD>('cy_kernels_ready'),
        lib.lookupFunction<_StatusN, _StatusD>('cy_status'),
        lib.lookupFunction<_ProgressN, _ProgressD>('cy_progress'),
      );
      Log.i('cycles', 'shim linked; device ${_instance!.deviceName}');
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
    List<double> world = const [0.8, 0.8, 0.8],
  }) {
    if (matrix.length != 12 || width <= 0 || height <= 0) return null;
    final arena = Arena();
    try {
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
          ..triCount = t.length ~/ 3;
        if (n != null && n.length == v.length) {
          final np = arena<Float>(n.length);
          np.asTypedList(n.length).setAll(0, n);
          meshArr[i].normals = np;
        } else {
          meshArr[i].normals = nullptr;
        }
        meshArr[i].hasMaterial = mat == null ? 0 : 1;
        meshArr[i].color[0] = mat?.r ?? 0.0;
        meshArr[i].color[1] = mat?.g ?? 0.0;
        meshArr[i].color[2] = mat?.b ?? 0.0;
        meshArr[i].roughness = mat?.roughness ?? 0.5;
        meshArr[i].metallic = mat?.metallic ?? 0.0;
      }
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
      for (var i = 0; i < 3; i++) {
        view.ref.world[i] = i < world.length ? world[i] : 0.8;
      }
      final out = arena<Uint8>(width * height * 4);
      final ok = _render(meshArr, meshes.length, view, out);
      if (ok == 0) return null;
      return Uint8List.fromList(out.asTypedList(width * height * 4));
    } finally {
      arena.releaseAll();
    }
  }
}
