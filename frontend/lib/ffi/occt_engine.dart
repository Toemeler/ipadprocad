// Dart FFI binding for the OCCT shim (backend/occt/shim/occt_capi.h) —
// M55, grown to the shim v2 surface in M56 (extrude with holes + taper,
// tessellation for display).
//
// Same architecture as slvs_ffi.dart / qcad_engine.dart: the 23 occt_*
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
import 'dart:typed_data';

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
typedef _Shape1N = Pointer<Void> Function(Pointer<Void>); // v4 unify
typedef _Shape1D = Pointer<Void> Function(Pointer<Void>);

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

// ---- shim v2 (M56): extrude with holes + taper, tessellation ------------

typedef _ExtrudeProfN = Pointer<Void> Function(
    Pointer<Double>, Pointer<Int32>, Int32, Double, Double);
typedef _ExtrudeProfD = Pointer<Void> Function(
    Pointer<Double>, Pointer<Int32>, int, double, double);
typedef _TransformN = Pointer<Void> Function(Pointer<Void>, Pointer<Double>);
typedef _TransformD = Pointer<Void> Function(Pointer<Void>, Pointer<Double>);

typedef _MeshCreateN = Pointer<Void> Function(Pointer<Void>, Double, Double);
typedef _MeshCreateD = Pointer<Void> Function(Pointer<Void>, double, double);
typedef _MeshCountsN = Int32 Function(Pointer<Void>, Pointer<Int32>,
    Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _MeshCountsD = int Function(Pointer<Void>, Pointer<Int32>,
    Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _MeshDblOutN = Int32 Function(Pointer<Void>, Pointer<Double>);
typedef _MeshDblOutD = int Function(Pointer<Void>, Pointer<Double>);
typedef _MeshIntOutN = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _MeshIntOutD = int Function(Pointer<Void>, Pointer<Int32>);
typedef _MeshFaceCountN = Int32 Function(Pointer<Void>);
typedef _MeshFaceCountD = int Function(Pointer<Void>);
typedef _MeshEdgesN = Int32 Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Double>);
typedef _MeshEdgesD = int Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Double>);

/// Topology counts of a shape, as reported by occt_shape_counts().
class OcctCounts {
  final int faces, edges, vertices;
  const OcctCounts(this.faces, this.edges, this.vertices);
  @override
  String toString() => 'F$faces/E$edges/V$vertices';
}

/// A display triangulation copied out of the shim (see occt_capi.h v2).
/// Pure Dart data — the native mesh handle is freed before this returns, so
/// an [OcctMeshData] can outlive its shape and travel across isolates.
///
///  * [positions] / [normals]: 3 doubles per vertex; normals unit, outward.
///  * [indices]: 3 per triangle, wound counter-clockwise seen from outside.
///  * [edgeStarts]/[edgePoints]: B-Rep edge polylines for edge display —
///    edge i spans points `[edgeStarts[i], edgeStarts[i+1])` of
///    [edgePoints] (3 doubles per point).
class OcctMeshData {
  final Float64List positions;
  final Float64List normals;
  final Int32List indices;
  final Int32List edgeStarts;
  final Float64List edgePoints;

  /// v4 display metadata (empty on fakes / legacy meshes; renderers must
  /// treat "empty" as "unknown" and fall back gracefully).
  final Int32List triFaces; // 1 face index per triangle
  final Float64List faceInfos; // 15 doubles per face (see occt_capi.h)
  final Float64List edgeCurves; // 16 doubles per edge (see occt_capi.h)

  OcctMeshData(this.positions, this.normals, this.indices, this.edgeStarts,
      this.edgePoints,
      {Int32List? triFaces, Float64List? faceInfos, Float64List? edgeCurves})
      : triFaces = triFaces ?? Int32List(0),
        faceInfos = faceInfos ?? Float64List(0),
        edgeCurves = edgeCurves ?? Float64List(0);

  int get faceCount => faceInfos.length ~/ 15;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  int get edgeCount => edgeStarts.length - 1;

  @override
  String toString() => 'mesh(v$vertexCount/t$triangleCount/e$edgeCount)';
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

  /// Rigid placement (shim v2): returns a NEW shape moved by the row-major
  /// 3x4 matrix [mat34] = {r00 r01 r02 tx, r10 r11 r12 ty, r20 r21 r22 tz}.
  /// The 3x3 part must be a pure rotation — the shim refuses scale, shear
  /// and mirror, so a wrong frame can never silently resize a solid.
  /// Null on failure (see [OcctFfi.lastError]).
  OcctShape? transformed(List<double> mat34) {
    if (mat34.length != 12) return null;
    final p = calloc<Double>(12);
    try {
      for (var i = 0; i < 12; i++) {
        p[i] = mat34[i];
      }
      return _ffi._wrap(_ffi._transform(_handle, p));
    } finally {
      calloc.free(p);
    }
  }

  /// Triangulate for display. [linDeflection] is the max sag in model units
  /// (mm), [angDeflection] in radians. The buffers are copied to Dart and
  /// the native mesh is freed before returning. Null on shim failure (see
  /// [OcctFfi.lastError]).
  OcctMeshData? mesh(
      {double linDeflection = 0.2, double angDeflection = 0.35}) {
    final f = _ffi;
    final mp = f._meshCreate(_handle, linDeflection, angDeflection);
    if (mp == nullptr) return null;
    try {
      final nv = calloc<Int32>(),
          nt = calloc<Int32>(),
          ne = calloc<Int32>(),
          nep = calloc<Int32>();
      try {
        if (f._meshCounts(mp, nv, nt, ne, nep) != 1) return null;
        final vN = nv.value, tN = nt.value, eN = ne.value, epN = nep.value;
        if (vN <= 0 || tN <= 0) return null;
        final vBuf = calloc<Double>(3 * vN);
        final nBuf = calloc<Double>(3 * vN);
        final tBuf = calloc<Int32>(3 * tN);
        final sBuf = calloc<Int32>(eN + 1);
        final eBuf = calloc<Double>(3 * (epN > 0 ? epN : 1));
        try {
          if (f._meshVertices(mp, vBuf) != 1 ||
              f._meshNormals(mp, nBuf) != 1 ||
              f._meshTriangles(mp, tBuf) != 1 ||
              f._meshEdges(mp, sBuf, eBuf) != 1) {
            return null;
          }
          // v4 display metadata (face identity + analytic edge curves)
          final fN = f._meshFaceCount(mp);
          final tfBuf = calloc<Int32>(tN);
          final fiBuf = calloc<Double>(15 * (fN > 0 ? fN : 1));
          final ecBuf = calloc<Double>(16 * (eN > 0 ? eN : 1));
          try {
            final v4ok = fN >= 0 &&
                f._meshTriangleFaces(mp, tfBuf) == 1 &&
                f._meshFaceInfos(mp, fiBuf) == 1 &&
                f._meshEdgeCurves(mp, ecBuf) == 1;
            return OcctMeshData(
              Float64List.fromList(vBuf.asTypedList(3 * vN)),
              Float64List.fromList(nBuf.asTypedList(3 * vN)),
              Int32List.fromList(tBuf.asTypedList(3 * tN)),
              Int32List.fromList(sBuf.asTypedList(eN + 1)),
              Float64List.fromList(eBuf.asTypedList(3 * epN)),
              triFaces: v4ok ? Int32List.fromList(tfBuf.asTypedList(tN)) : null,
              faceInfos: v4ok
                  ? Float64List.fromList(fiBuf.asTypedList(15 * fN))
                  : null,
              edgeCurves: v4ok
                  ? Float64List.fromList(ecBuf.asTypedList(16 * eN))
                  : null,
            );
          } finally {
            calloc.free(tfBuf);
            calloc.free(fiBuf);
            calloc.free(ecBuf);
          }
        } finally {
          calloc.free(vBuf);
          calloc.free(nBuf);
          calloc.free(tBuf);
          calloc.free(sBuf);
          calloc.free(eBuf);
        }
      } finally {
        calloc.free(nv);
        calloc.free(nt);
        calloc.free(ne);
        calloc.free(nep);
      }
    } finally {
      f._freeMesh(mp);
    }
  }

  void dispose() {
    if (_ptr == nullptr) return; // idempotent, like Engine.dispose
    _ffi._free(_ptr);
    _ptr = nullptr;
  }
}

/// Probe-once singleton over the 29-symbol OCCT shim v4 surface.
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
      this._free,
      this._extrudeProfile,
      this._extrudeProfileArcs,
      this._transform,
      this._meshCreate,
      this._meshCounts,
      this._meshVertices,
      this._meshNormals,
      this._meshTriangles,
      this._meshEdges,
      this._meshFaceCount,
      this._meshTriangleFaces,
      this._meshFaceInfos,
      this._meshEdgeCurves,
      this._unify,
      this._freeMesh);

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
  // shim v2 (M56)
  final _ExtrudeProfD _extrudeProfile;
  final _ExtrudeProfD _extrudeProfileArcs; // v3: xyb triplets (x, y, bulge)
  final _TransformD _transform;
  final _MeshCreateD _meshCreate;
  final _MeshCountsD _meshCounts;
  final _MeshDblOutD _meshVertices;
  final _MeshDblOutD _meshNormals;
  final _MeshIntOutD _meshTriangles;
  final _MeshEdgesD _meshEdges;
  final _MeshFaceCountD _meshFaceCount; // v4
  final _MeshIntOutD _meshTriangleFaces; // v4
  final _MeshDblOutD _meshFaceInfos; // v4
  final _MeshDblOutD _meshEdgeCurves; // v4
  final _Shape1D _unify; // v4
  final _FreeD _freeMesh;

  static OcctFfi? _cached;
  static bool _probed = false;

  /// The binding if all 23 occt_* symbols (shim v2) are linked, else null.
  /// Probed once and cached (create() is cheap after that). No Dart
  /// fallback: null means "no 3D kernel", period — report it, don't fake
  /// it. A v1 binary (14 symbols, no mesh surface) also probes to null:
  /// shim and app ship in the same IPA, so a partial surface can only mean
  /// a stale build, and refusing it loudly beats crashing in lookup later.
  static OcctFfi? instance() {
    if (_probed) return _cached;
    _probed = true;
    try {
      final lib = DynamicLibrary.process();
      final ver =
          lib.lookupFunction<_ShimVerN, _ShimVerD>('occt_shim_version')();
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
        lib.lookupFunction<_ExtrudeProfN, _ExtrudeProfD>(
            'occt_extrude_profile'),
        lib.lookupFunction<_ExtrudeProfN, _ExtrudeProfD>(
            'occt_extrude_profile_arcs'),
        lib.lookupFunction<_TransformN, _TransformD>('occt_transform'),
        lib.lookupFunction<_MeshCreateN, _MeshCreateD>('occt_mesh_create'),
        lib.lookupFunction<_MeshCountsN, _MeshCountsD>('occt_mesh_counts'),
        lib.lookupFunction<_MeshDblOutN, _MeshDblOutD>('occt_mesh_vertices'),
        lib.lookupFunction<_MeshDblOutN, _MeshDblOutD>('occt_mesh_normals'),
        lib.lookupFunction<_MeshIntOutN, _MeshIntOutD>('occt_mesh_triangles'),
        lib.lookupFunction<_MeshEdgesN, _MeshEdgesD>('occt_mesh_edges'),
        lib.lookupFunction<_MeshFaceCountN, _MeshFaceCountD>(
            'occt_mesh_face_count'),
        lib.lookupFunction<_MeshIntOutN, _MeshIntOutD>(
            'occt_mesh_triangle_faces'),
        lib.lookupFunction<_MeshDblOutN, _MeshDblOutD>('occt_mesh_face_infos'),
        lib.lookupFunction<_MeshDblOutN, _MeshDblOutD>('occt_mesh_edge_curves'),
        lib.lookupFunction<_Shape1N, _Shape1D>('occt_unify'),
        lib.lookupFunction<_FreeN, _FreeD>('occt_free_mesh'),
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

  /// Shim v2 — extrude a MULTI-LOOP profile (Inventor semantics, see
  /// occt_capi.h): [loops] holds the (x,y) point list of each loop in the
  /// z=0 plane WITHOUT repeating the first point; loop 0 is the outer
  /// boundary, the rest are holes strictly inside it. Winding order is
  /// irrelevant (the shim normalises). Extrudes +Z by [height] (> 0) with
  /// [taperDeg] draft — positive flares OUTWARD, Inventor's sign. Null on
  /// failure (see [lastError]).
  OcctShape? extrudeProfile(List<List<double>> loops, double height,
      {double taperDeg = 0}) {
    if (loops.isEmpty) return null;
    var total = 0;
    for (final l in loops) {
      if (l.length < 6 || l.length.isOdd) return null;
      total += l.length;
    }
    final xy = calloc<Double>(total);
    final counts = calloc<Int32>(loops.length);
    try {
      var k = 0;
      for (var i = 0; i < loops.length; i++) {
        counts[i] = loops[i].length ~/ 2;
        for (final v in loops[i]) {
          xy[k++] = v;
        }
      }
      return _wrap(_extrudeProfile(xy, counts, loops.length, height, taperDeg));
    } finally {
      calloc.free(xy);
      calloc.free(counts);
    }
  }

  /// v3: extrude a profile whose loops may contain TRUE ARCS. Each loop is a
  /// flat list of vertex triplets (x, y, bulge-of-outgoing-edge; bulge 0 =
  /// straight line, tan(sweep/4) otherwise, positive = CCW). A circle enters
  /// OCCT as an exact cylindrical face — no facet edges at any zoom.
  OcctShape? extrudeProfileArcs(List<List<double>> loops, double height,
      {double taperDeg = 0}) {
    if (loops.isEmpty) return null;
    var total = 0;
    for (final l in loops) {
      if (l.length < 6 || l.length % 3 != 0) return null;
      total += l.length;
    }
    final xyb = calloc<Double>(total);
    final counts = calloc<Int32>(loops.length);
    try {
      var k = 0;
      for (var i = 0; i < loops.length; i++) {
        counts[i] = loops[i].length ~/ 3;
        for (final v in loops[i]) {
          xyb[k++] = v;
        }
      }
      return _wrap(
          _extrudeProfileArcs(xyb, counts, loops.length, height, taperDeg));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
    }
  }

  /// Boolean union. Inputs remain owned/valid; result is a NEW shape.
  OcctShape? fuse(OcctShape a, OcctShape b) =>
      _wrap(_fuse(a._handle, b._handle));

  /// v4: merge same-domain faces/edges (cleans boolean results so no
  /// spurious split lines render). Input stays owned; result is NEW.
  OcctShape? unify(OcctShape a) => _wrap(_unify(a._handle));

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
