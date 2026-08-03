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

// shim v12 (M130): revolve, edge identity, fillet/chamfer, ray casting
typedef _RevolveN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    Int32, Double, Double, Double, Double, Double);
typedef _RevolveD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    int, double, double, double, double, double);
typedef _EdgeCountN = Int32 Function(Pointer<Void>);
typedef _EdgeCountD = int Function(Pointer<Void>);
typedef _EdgeInfoN = Int32 Function(Pointer<Void>, Int32, Pointer<Double>);
typedef _EdgeInfoD = int Function(Pointer<Void>, int, Pointer<Double>);
// v16 — occt_fillet_edges / occt_chamfer_edges still exist in the shim and
// still carry every guarantee, but Dart binds the _ex forms exclusively: they
// are the same call and they also say which edges were skipped and what size
// was actually built, and there is no reason to ask for less.
typedef _FilletExN = Pointer<Void> Function(Pointer<Void>, Pointer<Int32>,
    Pointer<Double>, Pointer<Double>, Int32, Pointer<Int32>, Pointer<Double>);
typedef _FilletExD = Pointer<Void> Function(Pointer<Void>, Pointer<Int32>,
    Pointer<Double>, Pointer<Double>, int, Pointer<Int32>, Pointer<Double>);
typedef _ChamferExN = Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Pointer<Int32>,
    Pointer<Double>);
typedef _ChamferExD = Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    int,
    Pointer<Int32>,
    Pointer<Double>);
typedef _SweepN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>, Int32,
    Pointer<Double>, Pointer<Double>, Int32, Int32, Double, Double);
typedef _SweepD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>, int,
    Pointer<Double>, Pointer<Double>, int, int, double, double);
typedef _LoftN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    Pointer<Double>, Int32, Int32, Int32, Int32);
typedef _LoftD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    Pointer<Double>, int, int, int, int);
typedef _CoilN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>, Int32,
    Pointer<Double>, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Int32, Int32, Int32);
typedef _CoilD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>, int,
    Pointer<Double>, double, double, double, double, double, double, double,
    double, double, int, int, int);
typedef _RevFaceN = Int32 Function(Pointer<Void>, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double, Double,
    Pointer<Double>, Int32);
typedef _RevFaceD = int Function(Pointer<Void>, double, double, double, double,
    double, double, double, double, double, double, double, double,
    Pointer<Double>, int);
typedef _RevHitsN = Int32 Function(Pointer<Void>, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Pointer<Double>, Int32);
typedef _RevHitsD = int Function(Pointer<Void>, double, double, double, double,
    double, double, double, double, double, Pointer<Double>, int);
typedef _RayHitsN = Int32 Function(Pointer<Void>, Double, Double, Double,
    Double, Double, Double, Pointer<Double>, Int32);
typedef _RayHitsD = int Function(Pointer<Void>, double, double, double, double,
    double, double, Pointer<Double>, int);

// M110 — occt_split_solids(shape, out, max) -> count
typedef _SplitN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>, Int32);
typedef _SplitD = int Function(Pointer<Void>, Pointer<Pointer<Void>>, int);

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
/// v12 — identity record of one TOPOLOGICAL edge (see occt_capi.h).
///
/// [index] is 1-based and only meaningful for the shape it was read from:
/// OCCT re-indexes on every rebuild. The geometry — [mid], [length], [kind],
/// [radius] — is what survives, and is what a stored fillet is re-matched
/// against after a recompute. Same contract as [ProfileSel] in part_model:
/// remember the geometry, re-find the index.
class OcctEdgeInfo {
  final int index;
  final int kind; // 1 line, 2 circle, 3 ellipse, 4 other, 0 degenerate
  final double mx, my, mz; // midpoint BY ARC LENGTH
  final double tx, ty, tz; // unit tangent there
  final double length;
  final double radius; // circle radius / ellipse major, else 0
  final int faceCount; // 2 = ordinary edge; 1 = free boundary (not filletable)

  /// v13 — angle between the two adjacent faces, in degrees. 0 means
  /// tangent-continuous (a smooth edge, which is why the display list drops
  /// it); 90 is a square corner.
  final double dihedralDeg;

  /// v13 — +1 CONVEX (exterior corner; rounding one is what Inventor calls a
  /// round), -1 CONCAVE (interior corner; rounding one is a fillet), 0 when
  /// unknown or tangent.
  final int convexity;

  const OcctEdgeInfo(this.index, this.kind, this.mx, this.my, this.mz, this.tx,
      this.ty, this.tz, this.length, this.radius, this.faceCount,
      [this.dihedralDeg = 0, this.convexity = 0]);

  /// An edge a fillet or chamfer can actually be applied to.
  bool get filletable => kind != 0 && length > 0 && faceCount == 2;

  /// An INTERIOR corner — what Inventor's "All Fillets" selects.
  bool get isConcave => convexity < 0;

  /// An EXTERIOR corner — what "All Rounds" selects.
  bool get isConvex => convexity > 0;

  @override
  String toString() => 'edge#$index(k$kind len${length.toStringAsFixed(3)})';
}

/// v16 — what a fillet or chamfer actually did, as opposed to what it was
/// asked for.
///
/// Two things can differ, and both used to be invisible. An edge the kernel
/// could not blend no longer takes the whole feature down with it, so the
/// caller has to be told which ones were skipped. And a size landing exactly
/// on a tangency (the 2 mm fillet on a 2 mm wall that OCCT has never been able
/// to build) is retried a hair smaller rather than refused, so the caller has
/// to be told that too. Neither is allowed to be silent.
class BlendReport {
  /// Indices into the edge list passed in, for edges that got no blend.
  final List<int> dropped = [];

  /// Relative size actually built: 1.0 when the asked-for size worked.
  double sizeScale = 1.0;

  /// True when the kernel had to step off the asked-for size to build at all.
  bool get resized => sizeScale < 1.0 - 1e-12;

  void _read(Pointer<Int32> drop, Pointer<Double> scale, int n) {
    dropped.clear();
    for (var i = 0; i < n; i++) {
      if (drop[i] != 0) dropped.add(i);
    }
    final s = scale[0];
    sizeScale = (s > 0 && s.isFinite) ? s : 1.0;
  }

  /// A line for the log, or null when the blend was built exactly as asked.
  String? note(int total, String sizeLabel) {
    final parts = <String>[];
    if (dropped.isNotEmpty) {
      parts.add('${dropped.length} of $total edge(s) could not be blended '
          'at $sizeLabel and were skipped');
    }
    if (resized) {
      // Report the deviation, not the ratio: "0.002 mm under" is actionable,
      // "scale 0.999" is not.
      final ppm = ((1.0 - sizeScale) * 1e6).round();
      parts.add('built $ppm ppm under $sizeLabel — OCCT cannot close a blend '
          'that lands exactly on a tangency');
    }
    return parts.isEmpty ? null : parts.join('; ');
  }
}

class OcctMeshData {
  /// Float32 copies of the vertex buffers, built once per mesh and reused on
  /// every scene push.
  ///
  /// The kernel hands us Float64, but the GPU only ever consumes Float32, so
  /// the conversion happened anyway — vertex by vertex, in Swift, on every
  /// push (`Payload.floats`). Doing it once here halves what crosses the
  /// platform channel (~3.4 MB for a 54k-vertex gear) AND removes that loop.
  Float32List? _pos32, _nor32, _edge32;
  Float32List get positions32 => _pos32 ??= Float32List.fromList(positions);
  Float32List get normals32 => _nor32 ??= Float32List.fromList(normals);
  Float32List get edgePoints32 => _edge32 ??= Float32List.fromList(edgePoints);

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

  /// v12 — the 1-based TOPOLOGICAL edge index behind each display edge.
  /// Display edges are a filtered subset (no degenerate, seam or
  /// tangent-continuous edges), so display index i and topological index i
  /// are different numbers the moment the model has a fillet or a cylinder
  /// in it. Fillet/chamfer address the topological one; picking produces the
  /// display one. Empty on fakes/legacy meshes — treat that as "unknown" and
  /// disable edge-based features rather than guessing an index.
  final Int32List edgeIds;

  OcctMeshData(this.positions, this.normals, this.indices, this.edgeStarts,
      this.edgePoints,
      {Int32List? triFaces,
      Float64List? faceInfos,
      Float64List? edgeCurves,
      Int32List? edgeIds})
      : triFaces = triFaces ?? Int32List(0),
        faceInfos = faceInfos ?? Float64List(0),
        edgeCurves = edgeCurves ?? Float64List(0),
        edgeIds = edgeIds ?? Int32List(0);

  /// Topological edge index of display edge [i], or -1 when unknown.
  int topoEdgeId(int i) =>
      (i >= 0 && i < edgeIds.length) ? edgeIds[i] : -1;

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

  /// v12 — number of topological edges (the index space fillet/chamfer use).
  /// NOT the number of DISPLAY edges: the mesh drops degenerate, seam and
  /// tangent-continuous edges. -1 on error.
  int get edgeCount => _ffi._shapeEdgeCount(_handle);

  /// v12 — identity record of 1-based topological edge [index], or null.
  OcctEdgeInfo? edgeInfo(int index) {
    // 12 doubles since v13; the last two are the dihedral and the convexity.
    final buf = calloc<Double>(12);
    try {
      if (_ffi._shapeEdgeInfo(_handle, index, buf) != 1) return null;
      return OcctEdgeInfo(index, buf[0].round(), buf[1], buf[2], buf[3], buf[4],
          buf[5], buf[6], buf[7], buf[8], buf[9].round(), buf[10],
          buf[11].round());
    } finally {
      calloc.free(buf);
    }
  }

  /// v12 — every topological edge in one pass (one call per edge underneath,
  /// but a single allocation). Degenerate edges come back with kind 0.
  List<OcctEdgeInfo> allEdges() {
    final n = edgeCount;
    if (n <= 0) return const [];
    final out = <OcctEdgeInfo>[];
    for (var i = 1; i <= n; i++) {
      final e = edgeInfo(i);
      if (e != null) out.add(e);
    }
    return out;
  }

  /// v12 — constant-radius edge fillet. [edgeIds] are 1-based TOPOLOGICAL
  /// indices (translate a picked display edge through
  /// [OcctMeshData.edgeIds]); [radii] is one radius per edge, so a single
  /// call can carry the several edge sets Inventor folds into one fillet
  /// feature. Result is a NEW shape; this one stays owned by the caller.
  /// Null on failure — a radius the adjacent faces cannot hold fails loudly
  /// instead of quietly shrinking to fit.
  /// v13 — [radii2], when given, makes the fillet vary linearly along each
  /// edge from [radii] at its start to [radii2] at its end. A zero entry means
  /// that edge stays constant.
  OcctShape? filletEdges(List<int> edgeIds, List<double> radii,
      {List<double> radii2 = const [], BlendReport? report}) {
    if (edgeIds.isEmpty || edgeIds.length != radii.length) return null;
    if (radii2.isNotEmpty && radii2.length != radii.length) return null;
    final n = edgeIds.length;
    final ids = calloc<Int32>(n);
    final rs = calloc<Double>(n);
    final rs2 = radii2.isEmpty ? nullptr : calloc<Double>(n);
    final drop = calloc<Int32>(n);
    final scale = calloc<Double>(1);
    try {
      for (var i = 0; i < n; i++) {
        ids[i] = edgeIds[i];
        rs[i] = radii[i];
        if (rs2 != nullptr) rs2[i] = radii2[i];
      }
      final out =
          _ffi._wrap(_ffi._filletEdgesEx(_handle, ids, rs, rs2, n, drop, scale));
      report?._read(drop, scale, n);
      return out;
    } finally {
      calloc.free(ids);
      calloc.free(rs);
      if (rs2 != nullptr) calloc.free(rs2);
      calloc.free(drop);
      calloc.free(scale);
    }
  }

  /// v13 — crossing angles of the circular path against ONE face: the face of
  /// this solid nearest ([fx], [fy], [fz]). What a revolve's "To <face>"
  /// needs, as distinct from the first material the sweep meets.
  List<double> revolveHitsFace(
      double axPx, double axPy, double axPz,
      double axDx, double axDy, double axDz,
      double px, double py, double pz,
      double fx, double fy, double fz,
      {int maxHits = 32}) {
    final buf = calloc<Double>(maxHits);
    try {
      final n = _ffi._revolveHitsFace(_handle, axPx, axPy, axPz, axDx, axDy,
          axDz, px, py, pz, fx, fy, fz, buf, maxHits);
      if (n <= 0) return const [];
      return List<double>.generate(n, (i) => buf[i], growable: false);
    } finally {
      calloc.free(buf);
    }
  }

  /// v12 — edge chamfer with Inventor's three methods. [modes] per edge:
  /// 0 equal distance ([d1] only), 1 two distances ([d1] on the reference
  /// face, [d2] on the other), 2 distance and angle ([d1] plus [angleDeg],
  /// which must be in (0, 90)). [d2] / [angleDeg] may be empty when no edge
  /// uses that mode. Result is a NEW shape; null on failure.
  OcctShape? chamferEdges(List<int> edgeIds, List<int> modes, List<double> d1,
      {List<double> d2 = const [],
      List<double> angleDeg = const [],
      BlendReport? report}) {
    final n = edgeIds.length;
    if (n == 0 || modes.length != n || d1.length != n) return null;
    if (d2.isNotEmpty && d2.length != n) return null;
    if (angleDeg.isNotEmpty && angleDeg.length != n) return null;
    final ids = calloc<Int32>(n);
    final md = calloc<Int32>(n);
    final p1 = calloc<Double>(n);
    final p2 = d2.isEmpty ? nullptr : calloc<Double>(n);
    final pa = angleDeg.isEmpty ? nullptr : calloc<Double>(n);
    final drop = calloc<Int32>(n);
    final scale = calloc<Double>(1);
    try {
      for (var i = 0; i < n; i++) {
        ids[i] = edgeIds[i];
        md[i] = modes[i];
        p1[i] = d1[i];
        if (p2 != nullptr) p2[i] = d2[i];
        if (pa != nullptr) pa[i] = angleDeg[i];
      }
      final out = _ffi._wrap(
          _ffi._chamferEdgesEx(_handle, ids, md, p1, p2, pa, n, drop, scale));
      report?._read(drop, scale, n);
      return out;
    } finally {
      calloc.free(ids);
      calloc.free(md);
      calloc.free(p1);
      if (p2 != nullptr) calloc.free(p2);
      if (pa != nullptr) calloc.free(pa);
      calloc.free(drop);
      calloc.free(scale);
    }
  }

  /// v13 — sorted, de-duplicated ANGLES in degrees at which the circular path
  /// of ([px], [py], [pz]) about the axis through ([axPx], [axPy], [axPz])
  /// along ([axDx], [axDy], [axDz]) crosses a face of this solid, measured
  /// from that point. Empty when it never crosses, or when the point lies on
  /// the axis and therefore has no path.
  List<double> revolveHits(double axPx, double axPy, double axPz, double axDx,
      double axDy, double axDz, double px, double py, double pz,
      {int maxHits = 32}) {
    final buf = calloc<Double>(maxHits);
    try {
      final n = _ffi._revolveHits(
          _handle, axPx, axPy, axPz, axDx, axDy, axDz, px, py, pz, buf,
          maxHits);
      if (n <= 0) return const [];
      return List<double>.generate(n, (i) => buf[i], growable: false);
    } finally {
      calloc.free(buf);
    }
  }

  /// v12 — sorted, de-duplicated distances along the unit ray
  /// (origin + t * dir) at which it crosses a face of this solid. Empty on a
  /// miss. This is what "To Next" measures: extrude from the sketch plane and
  /// stop at the first hit strictly beyond the start.
  List<double> rayHits(double ox, double oy, double oz, double dx, double dy,
      double dz,
      {int maxHits = 32}) {
    final buf = calloc<Double>(maxHits);
    try {
      final n = _ffi._rayHits(_handle, ox, oy, oz, dx, dy, dz, buf, maxHits);
      if (n <= 0) return const [];
      return List<double>.generate(n, (i) => buf[i], growable: false);
    } finally {
      calloc.free(buf);
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
          final eiBuf = calloc<Int32>(eN > 0 ? eN : 1);
          try {
            final v4ok = fN >= 0 &&
                f._meshTriangleFaces(mp, tfBuf) == 1 &&
                f._meshFaceInfos(mp, fiBuf) == 1 &&
                f._meshEdgeCurves(mp, ecBuf) == 1;
            // v12: the display-edge -> topological-edge map. Read separately
            // from the v4 block so a failure here costs edge-based features
            // (fillet/chamfer picking) and nothing else.
            final v12ok = eN > 0 && f._meshEdgeIds(mp, eiBuf) == 1;
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
              edgeIds:
                  v12ok ? Int32List.fromList(eiBuf.asTypedList(eN)) : null,
            );
          } finally {
            calloc.free(tfBuf);
            calloc.free(fiBuf);
            calloc.free(eiBuf);
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

/// Probe-once singleton over the 31-symbol OCCT shim v5 surface (v4 + the two
/// booleans occt_cut / occt_common).
class OcctFfi {
  OcctFfi._(
      this.version,
      this.shimVersion,
      this._lastError,
      this._makeBox,
      this._makeCylinder,
      this._extrude,
      this._fuse,
      this._cut,
      this._common,
      this._counts,
      this._valid,
      this._volume,
      this._bbox,
      this._exportStep,
      this._importStep,
      this._splitSolids,
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
      this._freeMesh,
      this._revolveProfile,
      this._shapeEdgeCount,
      this._shapeEdgeInfo,
      this._meshEdgeIds,
      this._filletEdgesEx,
      this._chamferEdgesEx,
      this._rayHits,
      this._revolveHits,
      this._revolveHitsFace,
      this._sweepProfile,
      this._loftSections,
      this._coilProfile);

  /// occt_version() marker string, e.g.
  /// "Prototype OCCT shim v1 (OCCT 7.9.3)".
  final String version;

  /// occt_shim_version() of the linked binary (>= 1). Gate new surface on
  /// this, exactly like SlvsFfi.version.
  final int shimVersion;

  final _LastErrD _lastError;
  final _MakeBoxD _makeBox;
  final _MakeCylD _makeCylinder;
  final _ExtrudeD _extrude;
  final _FuseD _fuse;
  final _FuseD _cut; // v5 (occt_cut: a \ b) — same ABI as fuse
  final _FuseD _common; // v5 (occt_common: a ∩ b)
  final _CountsD _counts;
  final _ValidD _valid;
  final _VolumeD _volume;
  final _BboxD _bbox;
  final _ExportD _exportStep;
  final _ImportD _importStep;
  final _SplitD _splitSolids;
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
  // shim v12 (M130)
  final _RevolveD _revolveProfile;
  final _EdgeCountD _shapeEdgeCount;
  final _EdgeInfoD _shapeEdgeInfo;
  final _MeshIntOutD _meshEdgeIds;
  final _FilletExD _filletEdgesEx;
  final _ChamferExD _chamferEdgesEx;
  final _RayHitsD _rayHits;
  final _RevHitsD _revolveHits; // v13
  final _RevFaceD _revolveHitsFace; // v13
  final _SweepD _sweepProfile; // v15
  final _LoftD _loftSections; // v15
  final _CoilD _coilProfile; // v15

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
        lib.lookupFunction<_FuseN, _FuseD>('occt_cut'),
        lib.lookupFunction<_FuseN, _FuseD>('occt_common'),
        lib.lookupFunction<_CountsN, _CountsD>('occt_shape_counts'),
        lib.lookupFunction<_ValidN, _ValidD>('occt_shape_valid'),
        lib.lookupFunction<_VolumeN, _VolumeD>('occt_shape_volume'),
        lib.lookupFunction<_BboxN, _BboxD>('occt_bbox'),
        lib.lookupFunction<_ExportN, _ExportD>('occt_export_step'),
        lib.lookupFunction<_ImportN, _ImportD>('occt_import_step'),
        lib.lookupFunction<_SplitN, _SplitD>('occt_split_solids'),
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
        // v12 — looked up EAGERLY like everything else. A v11 binary makes
        // instance() null, i.e. "no 3D kernel", which is the documented
        // policy above: shim and app ship in one IPA, so a partial surface
        // can only be a stale build, and refusing it loudly beats a dlsym
        // crash the first time somebody taps Fillet.
        lib.lookupFunction<_RevolveN, _RevolveD>('occt_revolve_profile'),
        lib.lookupFunction<_EdgeCountN, _EdgeCountD>('occt_shape_edge_count'),
        lib.lookupFunction<_EdgeInfoN, _EdgeInfoD>('occt_shape_edge_info'),
        lib.lookupFunction<_MeshIntOutN, _MeshIntOutD>('occt_mesh_edge_ids'),
        lib.lookupFunction<_FilletExN, _FilletExD>('occt_fillet_edges_ex'),
        lib.lookupFunction<_ChamferExN, _ChamferExD>('occt_chamfer_edges_ex'),
        lib.lookupFunction<_RayHitsN, _RayHitsD>('occt_ray_hits'),
        lib.lookupFunction<_RevHitsN, _RevHitsD>('occt_revolve_hits'),
        lib.lookupFunction<_RevFaceN, _RevFaceD>('occt_revolve_hits_face'),
        lib.lookupFunction<_SweepN, _SweepD>('occt_sweep_profile'),
        lib.lookupFunction<_LoftN, _LoftD>('occt_loft_sections'),
        lib.lookupFunction<_CoilN, _CoilD>('occt_coil_profile'),
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

  /// v15 — Sweep a profile along a world-space path polyline. [loops] uses the
  /// same (x, y, bulge) encoding as [extrudeProfileArcs]; [mat34] places the
  /// profile's sketch frame. [orientation]: 0 follow path, 1 fixed, 2 follow
  /// path and guide. [twistDeg] must be 0 — the shim refuses a non-zero twist
  /// rather than silently producing an untwisted solid.
  OcctShape? sweepProfile(List<List<double>> loops, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0, double taperDeg = 0, double twistDeg = 0}) {
    if (loops.isEmpty || mat34.length != 12 || pathPts.length < 6) return null;
    var total = 0;
    for (final l in loops) {
      if (l.length < 6 || l.length % 3 != 0) return null;
      total += l.length;
    }
    final xyb = calloc<Double>(total);
    final counts = calloc<Int32>(loops.length);
    final m = calloc<Double>(12);
    final pp = calloc<Double>(pathPts.length);
    try {
      var k = 0;
      for (var i = 0; i < loops.length; i++) {
        counts[i] = loops[i].length ~/ 3;
        for (final v in loops[i]) {
          xyb[k++] = v;
        }
      }
      for (var i = 0; i < 12; i++) {
        m[i] = mat34[i];
      }
      for (var i = 0; i < pathPts.length; i++) {
        pp[i] = pathPts[i];
      }
      return _wrap(_sweepProfile(xyb, counts, loops.length, m, pp,
          pathPts.length ~/ 3, orientation, taperDeg, twistDeg));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
      calloc.free(m);
      calloc.free(pp);
    }
  }

  /// v15 — Loft through [sections], one closed loop each, with [mats] holding
  /// 12 doubles per section placing its sketch frame.
  OcctShape? loftSections(List<List<double>> sections, List<List<double>> mats,
      {bool solid = true, bool ruled = false, bool closed = false}) {
    if (sections.length < 2 || mats.length != sections.length) return null;
    var total = 0;
    for (final sec in sections) {
      if (sec.length < 6 || sec.length % 3 != 0) return null;
      total += sec.length;
    }
    for (final m in mats) {
      if (m.length != 12) return null;
    }
    final xyb = calloc<Double>(total);
    final counts = calloc<Int32>(sections.length);
    final mm = calloc<Double>(12 * sections.length);
    try {
      var k = 0;
      for (var i = 0; i < sections.length; i++) {
        counts[i] = sections[i].length ~/ 3;
        for (final v in sections[i]) {
          xyb[k++] = v;
        }
        for (var j = 0; j < 12; j++) {
          mm[12 * i + j] = mats[i][j];
        }
      }
      return _wrap(_loftSections(xyb, counts, mm, sections.length,
          solid ? 1 : 0, ruled ? 1 : 0, closed ? 1 : 0));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
      calloc.free(mm);
    }
  }

  /// v15 — Helical sweep. The axis is world-space; [revolutions] and [height]
  /// are the resolved pair (the panel's other methods convert to this).
  /// [closeStart]/[closeEnd] must be false — the shim refuses them.
  OcctShape? coilProfile(List<List<double>> loops, List<double> mat34,
      List<double> axP, List<double> axD,
      {required double revolutions,
      required double height,
      double taperDeg = 0,
      bool clockwise = false,
      bool closeStart = false,
      bool closeEnd = false}) {
    if (loops.isEmpty || mat34.length != 12) return null;
    if (axP.length != 3 || axD.length != 3) return null;
    var total = 0;
    for (final l in loops) {
      if (l.length < 6 || l.length % 3 != 0) return null;
      total += l.length;
    }
    final xyb = calloc<Double>(total);
    final counts = calloc<Int32>(loops.length);
    final m = calloc<Double>(12);
    try {
      var k = 0;
      for (var i = 0; i < loops.length; i++) {
        counts[i] = loops[i].length ~/ 3;
        for (final v in loops[i]) {
          xyb[k++] = v;
        }
      }
      for (var i = 0; i < 12; i++) {
        m[i] = mat34[i];
      }
      return _wrap(_coilProfile(
          xyb,
          counts,
          loops.length,
          m,
          axP[0],
          axP[1],
          axP[2],
          axD[0],
          axD[1],
          axD[2],
          revolutions,
          height,
          taperDeg,
          clockwise ? 1 : 0,
          closeStart ? 1 : 0,
          closeEnd ? 1 : 0));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
      calloc.free(m);
    }
  }

  /// v12 — Revolve a multi-loop arc profile about an axis lying IN the
  /// sketch plane. [loops] uses the same (x, y, bulge) triplet encoding as
  /// [extrudeProfileArcs]: loop 0 is the outer boundary, the rest are holes.
  /// The axis is the 2D line through ([axPx], [axPy]) along ([axDx], [axDy]);
  /// [angleDeg] is in (0, 360]. Null on failure (see [lastError]) — notably
  /// when the profile crosses the axis, which the shim refuses outright
  /// rather than sweeping the profile through itself.
  OcctShape? revolveProfile(List<List<double>> loops, double angleDeg,
      {required double axPx,
      required double axPy,
      required double axDx,
      required double axDy}) {
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
      return _wrap(_revolveProfile(
          xyb, counts, loops.length, axPx, axPy, axDx, axDy, angleDeg));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
    }
  }

  /// Boolean union. Inputs remain owned/valid; result is a NEW shape.
  OcctShape? fuse(OcctShape a, OcctShape b) =>
      _wrap(_fuse(a._handle, b._handle));

  /// v5 boolean cut (a \ b, Inventor's Cut). Inputs remain owned/valid;
  /// result is a NEW shape. Null on failure incl. an empty result.
  OcctShape? cut(OcctShape a, OcctShape b) =>
      _wrap(_cut(a._handle, b._handle));

  /// v5 boolean common (a ∩ b, Inventor's Intersect). Inputs remain
  /// owned/valid; result is a NEW shape. Null on failure incl. an empty result.
  OcctShape? common(OcctShape a, OcctShape b) =>
      _wrap(_common(a._handle, b._handle));

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

  /// M110 — a STEP file as one shape PER SOLID.
  ///
  /// [importStep] hands back OneShape(), which for a multi-part file is a
  /// compound. The browser's unit is a BODY, so an assembly should arrive as
  /// several bodies you can hide, rename and boolean against — not one opaque
  /// lump. Returns an empty list for a file with no solids (a surface or
  /// wireframe export), which the caller should report rather than turning
  /// into an empty body.
  List<OcctShape> importStepSolids(String path, {int max = 512}) {
    final whole = importStep(path);
    if (whole == null) return const [];
    final out = calloc<Pointer<Void>>(max);
    try {
      final n = _splitSolids(whole._handle, out, max);
      return [
        for (var i = 0; i < n; i++)
          if (out[i] != nullptr) OcctShape._(this, out[i])
      ];
    } finally {
      calloc.free(out);
      whole.dispose();
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
