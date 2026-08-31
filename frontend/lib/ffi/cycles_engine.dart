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

/// The renderer, or null when this build has none linked.
class CyclesFfi {
  CyclesFfi._(this._available, this._deviceName, this._setPath, this._render,
      this._lastError);

  final _AvailD _available;
  final _StrD _deviceName;
  final _SetPathD _setPath;
  final _RenderD _render;
  final _StrD _lastError;

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
    required List<(Float32List verts, Float32List? normals, Int32List tris)>
        meshes,
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
        final (v, n, t) = meshes[i];
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
