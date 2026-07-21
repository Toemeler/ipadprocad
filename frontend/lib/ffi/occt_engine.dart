// Dart FFI binding for the OCCT shim (backend/occt/shim/occt_capi.h) — M55.
//
// Same architecture as slvs_ffi.dart / qcad_engine.dart: the 14 occt_*
// symbols are statically linked into the app binary on iOS, so we resolve
// them from DynamicLibrary.process(). If they are not linked (host
// `flutter run`/`flutter test` without the native lib), [OcctFfi.instance]
// is null and callers must not pretend a 3D kernel exists — there is NO
// Dart fallback for B-Rep. This module depends only on dart:ffi /
// package:ffi so it can never drag the rest of the app into a compile error.
//
// ABI contract (mirrors the header comments — keep in sync):
//   - int-returning functions: 1 = success, 0 = failure (unless noted).
//   - const char* returns point at library-owned storage: copy immediately
//     (toDartString does), never free.
//   - occt_shape* is an opaque handle; every shape returned by a
//     constructor must go through occt_free_shape exactly once.
//   - Not thread-safe; call only from the UI thread like qcad/slvs.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ---- native signatures (14 functions, order of occt_capi.h) -------------

typedef _VersionN = Pointer<Utf8> Function();
typedef _VersionD = Pointer<Utf8> Function();
typedef _ShimVerN = Int32 Function();
typedef _ShimVerD = int Function();
typedef _LastErrN = Pointer<Utf8> Function();
typedef _LastErrD = Pointer<Utf8> Function();

typedef _MakeBoxN = Pointer<Void> Function(Double, Double, Double);
typedef _MakeBoxD = Pointer<Void> Function(double, double, double);
typedef _MakeCylN = Pointer<Void> Function(
    Double, Double, Double, Double, Double);
typedef _MakeCylD = Pointer<Void> Function(
    double, double, double, double, double);
typedef _ExtrudeN = Pointer<Void> Function(Pointer<Double>, Int32, Double);
typedef _ExtrudeD = Pointer<Void> Function(Pointer<Double>, int, double);
typedef _FuseN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _FuseD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);

typedef _CountsN = Int32 Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _CountsD = int Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _ValidN = Int32 Function(Pointer<Void>);
typedef _ValidD = int Function(Pointer<Void>);
typedef _VolumeN = Double Function(Pointer<Void>);
typedef _VolumeD = double Function(Pointer<Void>);
typedef _BboxN = Int32 Function(Pointer<Void>, Pointer<Double>);
typedef _BboxD = int Function(Pointer<Void>, Pointer<Double>);

typedef _ExportN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _ExportD = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _ImportN = Pointer<Void> Function(Pointer<Utf8>);
typedef _ImportD = Pointer<Void> Function(Pointer<Utf8>);

typedef _FreeN = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

/// Topology counts of a shape, as reported by occt_shape_counts().
class OcctCounts {
  final int faces, edges, vertices;
  const OcctCounts(this.faces, this.edges, this.vertices);
  @override
  String toString() => 'F$faces/E$edges/V$vertices';
}

/// An owned B-Rep shape. Call [dispose] exactly once; using a disposed
/// shape throws [StateError] Dart-side (the shim cannot detect it).
class OcctShape {
  OcctShape._(this._ffi, this._ptr);
  final OcctFfi _ffi;
  Pointer<Void> _ptr;

  bool get disposed => _ptr == nullptr;

  Pointer<Void> get _handle {
    if (_ptr == nullptr) throw StateError('OcctShape used after dispose');
    return _ptr;
  }

  /// Faces/edges/vertices, or null on shim failure.
  OcctCounts? counts() {
    final f = calloc<Int32>(), e = calloc<Int32>(), v = calloc<Int32>();
    try {
      if (_ffi._counts(_handle, f, e, v) != 1) return null;
      return OcctCounts(f.value, e.value, v.value);
    } finally {
      calloc.free(f);
      calloc.free(e);
      calloc.free(v);
    }
  }

  /// BRepCheck_Analyzer verdict.
  bool get valid => _ffi._valid(_handle) == 1;

  /// Enclosed volume (mm^3 by convention); negative on failure — mirrors
  /// the shim contract 1:1 instead of masking failure as 0.
  double get volume => _ffi._volume(_handle);

  /// {xmin,ymin,zmin,xmax,ymax,zmax}, or null on failure.
  List<double>? bbox() {
    final out = calloc<Double>(6);
    try {
      if (_ffi._bbox(_handle, out) != 1) return null;
      return List<double>.generate(6, (i) => out[i]);
    } finally {
      calloc.free(out);
    }
  }

  /// Write to STEP (AP214). Returns success.
  bool exportStep(String path) {
    final p = path.toNativeUtf8();
    try {
      return _ffi._exportStep(_handle, p) == 1;
    } finally {
      calloc.free(p);
    }
  }

  void dispose() {
    if (_ptr == nullptr) return; // idempotent, like Engine.dispose
    _ffi._free(_ptr);
    _ptr = nullptr;
  }
}

/// Probe-once singleton over the 14-symbol OCCT shim surface.
class OcctFfi {
  OcctFfi._(
      this.version,
      this.shimVersion,
      this._lastError,
      this._makeBox,
      this._makeCylinder,
      this._extrude,
      this._fuse,
      this._counts,
      this._valid,
      this._volume,
      this._bbox,
      this._exportStep,
      this._importStep,
      this._free);

  /// occt_version() marker string, e.g.
  /// "iPadProCAD OCCT shim v1 (OCCT 7.9.3)".
  final String version;

  /// occt_shim_version() of the linked binary (>= 1). Gate new surface on
  /// this, exactly like SlvsFfi.version.
  final int shimVersion;

  final _LastErrD _lastError;
  final _MakeBoxD _makeBox;
  final _MakeCylD _makeCylinder;
  final _ExtrudeD _extrude;
  final _FuseD _fuse;
  final _CountsD _counts;
  final _ValidD _valid;
  final _VolumeD _volume;
  final _BboxD _bbox;
  final _ExportD _exportStep;
  final _ImportD _importStep;
  final _FreeD _free;

  static OcctFfi? _cached;
  static bool _probed = false;

  /// The binding if all 14 occt_* symbols are linked, else null. Probed
  /// once and cached (create() is cheap after that). No Dart fallback:
  /// null means "no 3D kernel", period — report it, don't fake it.
  static OcctFfi? instance() {
    if (_probed) return _cached;
    _probed = true;
    try {
      final lib = DynamicLibrary.process();
      final ver = lib.lookupFunction<_ShimVerN, _ShimVerD>(
          'occt_shim_version')();
      if (ver <= 0) return null;
      final versionStr = lib
          .lookupFunction<_VersionN, _VersionD>('occt_version')()
          .toDartString();
      _cached = OcctFfi._(
        versionStr,
        ver,
        lib.lookupFunction<_LastErrN, _LastErrD>('occt_last_error'),
        lib.lookupFunction<_MakeBoxN, _MakeBoxD>('occt_make_box'),
        lib.lookupFunction<_MakeCylN, _MakeCylD>('occt_make_cylinder'),
        lib.lookupFunction<_ExtrudeN, _ExtrudeD>('occt_extrude_polygon'),
        lib.lookupFunction<_FuseN, _FuseD>('occt_fuse'),
        lib.lookupFunction<_CountsN, _CountsD>('occt_shape_counts'),
        lib.lookupFunction<_ValidN, _ValidD>('occt_shape_valid'),
        lib.lookupFunction<_VolumeN, _VolumeD>('occt_shape_volume'),
        lib.lookupFunction<_BboxN, _BboxD>('occt_bbox'),
        lib.lookupFunction<_ExportN, _ExportD>('occt_export_step'),
        lib.lookupFunction<_ImportN, _ImportD>('occt_import_step'),
        lib.lookupFunction<_FreeN, _FreeD>('occt_free_shape'),
      );
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }

  static bool get available => instance() != null;

  /// Test-only: reset the probe so a test can exercise the miss path twice.
  static void resetForTest() {
    _probed = false;
    _cached = null;
  }

  /// Message of the most recent shim failure ("" if none).
  String lastError() => _lastError().toDartString();

  OcctShape? _wrap(Pointer<Void> p) =>
      p == nullptr ? null : OcctShape._(this, p);

  /// Axis-aligned box with one corner at the origin. Null on failure
  /// (see [lastError]).
  OcctShape? makeBox(double dx, double dy, double dz) =>
      _wrap(_makeBox(dx, dy, dz));

  /// Solid cylinder: base centre (cx,cy,cz), axis +Z, radius r, height h.
  OcctShape? makeCylinder(
          double cx, double cy, double cz, double r, double h) =>
      _wrap(_makeCylinder(cx, cy, cz, r, h));

  /// Extrude a closed simple polygon in z=0 along +Z. [xy] is (x,y) pairs
  /// WITHOUT repeating the first point; needs >= 3 points, even length.
  OcctShape? extrudePolygon(List<double> xy, double height) {
    if (xy.length < 6 || xy.length.isOdd) return null;
    final p = calloc<Double>(xy.length);
    try {
      for (var i = 0; i < xy.length; i++) {
        p[i] = xy[i];
      }
      return _wrap(_extrude(p, xy.length ~/ 2, height));
    } finally {
      calloc.free(p);
    }
  }

  /// Boolean union. Inputs remain owned/valid; result is a NEW shape.
  OcctShape? fuse(OcctShape a, OcctShape b) =>
      _wrap(_fuse(a._handle, b._handle));

  /// Read a STEP file (all roots, compound if several). Null on failure.
  OcctShape? importStep(String path) {
    final p = path.toNativeUtf8();
    try {
      return _wrap(_importStep(p));
    } finally {
      calloc.free(p);
    }
  }
}

/// The honest boot-time smoke over the real linked kernel — the "backend=
/// occt-ffi" analogue of the qcad DART SMOKE. Returns the exact line to log
/// (caller logs it, so this file stays free of app imports and is host-
/// testable). Numbers mirror backend/occt/tests/smoke_occt.c: a 10x20x30
/// box has 6 faces / 12 edges / 8 vertices and volume 6000.
String occtSmokeLine() {
  final ffi = OcctFfi.instance();
  if (ffi == null) {
    return 'DART SMOKE: SKIP (backend=occt-none, occt_* symbols not linked)';
  }
  OcctShape? box;
  try {
    box = ffi.makeBox(10, 20, 30);
    if (box == null) {
      return 'DART SMOKE: FAIL (backend=occt-ffi, make_box -> NULL: '
          '${ffi.lastError()})';
    }
    final c = box.counts();
    final vol = box.volume;
    final ok = c != null &&
        c.faces == 6 &&
        c.edges == 12 &&
        c.vertices == 8 &&
        box.valid &&
        (vol - 6000.0).abs() < 1e-6;
    return ok
        ? 'DART SMOKE: PASS (backend=occt-ffi, shim v${ffi.shimVersion}, '
            '${ffi.version}, box $c vol ${vol.toStringAsFixed(6)})'
        : 'DART SMOKE: FAIL (backend=occt-ffi, box counts=$c '
            'valid=${box.valid} vol=$vol, expected F6/E12/V8 vol 6000)';
  } finally {
    box?.dispose();
  }
}
