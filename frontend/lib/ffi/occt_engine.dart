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
// (perf_hook.dart is the one further import, and it is deliberately empty of
// imports itself — see the note there. Timing goes through those hooks rather
// than through perf.dart precisely so this invariant survives.)
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

import 'perf_hook.dart';

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
// shim v17 (M214): many bodies -> many NAMED products in one STEP file.
typedef _ExportNamedN = Int32 Function(Pointer<Pointer<Void>>,
    Pointer<Pointer<Utf8>>, Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef _ExportNamedD = int Function(Pointer<Pointer<Void>>,
    Pointer<Pointer<Utf8>>, int, Pointer<Utf8>, Pointer<Utf8>);

// shim v12 (M130): revolve, edge identity, fillet/chamfer, ray casting
typedef _RevolveN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    Int32, Double, Double, Double, Double, Double);
typedef _RevolveD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    int, double, double, double, double, double);
typedef _EdgeCountN = Int32 Function(Pointer<Void>);
typedef _EdgeCountD = int Function(Pointer<Void>);
typedef _EdgeInfoN = Int32 Function(Pointer<Void>, Int32, Pointer<Double>);
typedef _EdgeInfoD = int Function(Pointer<Void>, int, Pointer<Double>);
// v21 — occt_shape_edges_info: every edge's twelve doubles in ONE call, and
// therefore ONE whole-shape traversal in the shim instead of one per edge.
// Returns the number of records written, or -1; the third argument is the
// buffer's capacity IN RECORDS, not in doubles.
typedef _EdgesInfoN = Int32 Function(Pointer<Void>, Pointer<Double>, Int32);
typedef _EdgesInfoD = int Function(Pointer<Void>, Pointer<Double>, int);
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
/// v24 — what the points of a sweep path MEAN, which only the caller knows.
///
/// The path always reaches the kernel as a polyline, because `sketchCurve`
/// flattens arcs, circles and splines before the shim is called. But a
/// polyline sampled from an arc and a polyline somebody drew want opposite
/// treatment at every joint: the first wants a spine that is a curve, and the
/// second wants its corners mitered exactly where they are. Getting it wrong
/// costs either a rounded-off corner or — measured, see
/// `perf/findings/S14-sweep.md` — a sweep that is cubic in the profile size
/// and fails outright past about a thousand segments.
abstract final class SweepPathMode {
  /// Let the shim infer it from the joint angles. Right for a flattened
  /// spline, whose joints are mostly sampling but can include a real cusp —
  /// a gear outline has one at every tooth.
  static const int auto = 0;

  /// Every joint is a vertex somebody placed. Miter all of them.
  static const int polyline = 1;

  /// Every joint is a sampling artefact. Sweep along one interpolated curve.
  static const int smooth = 2;
}

// v24 — occt_sweep_profile_ex. The v15 entry point occt_sweep_profile is no
// longer bound: it is exactly this call with pathMode = auto, the shim
// delegates one to the other, and a second binding would be an unused field.
// See SweepPathMode.
typedef _SweepExN = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>,
    Int32, Pointer<Double>, Pointer<Double>, Int32, Int32, Double, Double,
    Int32);
typedef _SweepExD = Pointer<Void> Function(Pointer<Double>, Pointer<Int32>, int,
    Pointer<Double>, Pointer<Double>, int, int, double, double, int);
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

// shim v21 (M232): mesh -> B-Rep. A triangle soup in, a real solid out.
typedef _BrepFromMeshN = Pointer<Void> Function(Pointer<Double>, Int32,
    Pointer<Int32>, Int32, Int32, Double, Double, Int32, Pointer<Int32>,
    Pointer<Double>);
typedef _BrepFromMeshD = Pointer<Void> Function(Pointer<Double>, int,
    Pointer<Int32>, int, int, double, double, int, Pointer<Int32>,
    Pointer<Double>);

// shim v20 (M217): face identity + Delete Face + Direct Edit.
typedef _FaceOpN = Pointer<Void> Function(
    Pointer<Void>, Pointer<Int32>, Int32, Int32);
typedef _FaceOpD = Pointer<Void> Function(
    Pointer<Void>, Pointer<Int32>, int, int);
typedef _MoveFacesN = Pointer<Void> Function(
    Pointer<Void>, Pointer<Int32>, Int32, Double, Double, Double);
typedef _MoveFacesD = Pointer<Void> Function(
    Pointer<Void>, Pointer<Int32>, int, double, double, double);
typedef _ScaleN = Pointer<Void> Function(
    Pointer<Void>, Double, Double, Double, Double);
typedef _ScaleD = Pointer<Void> Function(
    Pointer<Void>, double, double, double, double);

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
  ///
  /// v22 — the shim decides this locally now, from the two into-face
  /// directions, rather than by stepping off the edge and asking a solid
  /// classifier where it landed. Which edges get a nonzero sign is unchanged;
  /// the sign itself changes on shapes carrying a feature thinner than
  /// `‖bbox diagonal‖ / 1414`, where the old probe stepped clean through the
  /// material and answered about the far side. On a 200 × 0.1 × 20 box —
  /// a convex solid — the old path called eight of the twelve edges concave.
  /// A shim older than v22 still does.
  final int convexity;

  const OcctEdgeInfo(this.index, this.kind, this.mx, this.my, this.mz, this.tx,
      this.ty, this.tz, this.length, this.radius, this.faceCount,
      [this.dihedralDeg = 0, this.convexity = 0]);

  /// Decode one twelve-double record of the shim's edge layout.
  ///
  /// The single-edge (`occt_shape_edge_info`) and bulk
  /// (`occt_shape_edges_info`) entry points write the SAME twelve fields in
  /// the same order — the shim computes them with literally the same code —
  /// so exactly one decoder serves both. [rec] is the whole buffer and [at]
  /// the record's first index in it, so the bulk path decodes straight out of
  /// a Float64List view with no copy and no per-record allocation.
  ///
  /// Null means "this edge could not be read": the bulk path marks such a
  /// record with a negative type, which is outside the documented 0..4 range
  /// and is how it reports a per-edge failure without abandoning the rest of
  /// the enumeration. A caller drops it, which is precisely what a loop over
  /// the single-edge call did with a null return. Type 0 is NOT that case —
  /// it is a degenerate edge, a legitimate record, and it is kept.
  static OcctEdgeInfo? decodeRecord(int index, List<double> rec, [int at = 0]) {
    if (at < 0 || at + 12 > rec.length) return null;
    if (rec[at] < 0) return null;
    return OcctEdgeInfo(
        index,
        rec[at].round(),
        rec[at + 1],
        rec[at + 2],
        rec[at + 3],
        rec[at + 4],
        rec[at + 5],
        rec[at + 6],
        rec[at + 7],
        rec[at + 8],
        rec[at + 9].round(),
        rec[at + 10],
        rec[at + 11].round());
  }

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

  /// v20 — the 1-based TOPOLOGICAL face index behind each MESH face. Same
  /// distinction [edgeIds] draws for edges and for the same reason: a face the
  /// kernel could not triangulate is absent from the mesh but still counts in
  /// the topological order, so the two indices diverge. Delete Face and Direct
  /// Edit address the topological one. Empty = unknown; callers must then
  /// disable those commands rather than guess an index.
  final Int32List faceIds;

  OcctMeshData(this.positions, this.normals, this.indices, this.edgeStarts,
      this.edgePoints,
      {Int32List? triFaces,
      Float64List? faceInfos,
      Float64List? edgeCurves,
      Int32List? edgeIds,
      Int32List? faceIds})
      : triFaces = triFaces ?? Int32List(0),
        faceInfos = faceInfos ?? Float64List(0),
        edgeCurves = edgeCurves ?? Float64List(0),
        edgeIds = edgeIds ?? Int32List(0),
        faceIds = faceIds ?? Int32List(0);

  /// Topological edge index of display edge [i], or -1 when unknown.
  int topoEdgeId(int i) =>
      (i >= 0 && i < edgeIds.length) ? edgeIds[i] : -1;

  /// Topological face index of MESH face [i], or -1 when unknown.
  int topoFaceId(int i) => (i >= 0 && i < faceIds.length) ? faceIds[i] : -1;

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

  /// Write this ONE shape to STEP (AP214IS, millimetres). Returns success.
  ///
  /// M214 — a PART export does not come through here: it has bodies, and each
  /// one should reach the file as its own named product. See
  /// [OcctFfi.exportStepNamed].
  bool exportStep(String path) {
    final p = path.toNativeUtf8();
    try {
      return ffiSpan('ffi.occt.exportStep',
              () => _ffi._exportStep(_handle, p)) ==
          1;
    } finally {
      calloc.free(p);
    }
  }

  /// v12 — number of topological edges (the index space fillet/chamfer use).
  /// NOT the number of DISPLAY edges: the mesh drops degenerate, seam and
  /// tangent-continuous edges. -1 on error.
  int get edgeCount => _ffi._shapeEdgeCount(_handle);

  /// v12 — identity record of 1-based topological edge [index], or null.
  ///
  /// This is the SINGLE-edge door and it stays exactly as expensive as it has
  /// always been: the shim rebuilds its whole-shape context per call. Do not
  /// call it in a loop — that loop is the Θ(n²) that
  /// `PERFORMANCE_PROFILE.md` §6.5 measures at ten seconds for one solid. Use
  /// [allEdges].
  OcctEdgeInfo? edgeInfo(int index) {
    // 12 doubles since v13; the last two are the dihedral and the convexity.
    final buf = calloc<Double>(12);
    try {
      ffiCount('ffi.occt.edgeInfo.calls', 1);
      if (_ffi._shapeEdgeInfo(_handle, index, buf) != 1) return null;
      return OcctEdgeInfo.decodeRecord(index, buf.asTypedList(12));
    } finally {
      calloc.free(buf);
    }
  }

  /// v21 — every topological edge, in ONE shim call and ONE traversal of the
  /// shape. Degenerate edges come back with kind 0; an edge the kernel cannot
  /// read is dropped, exactly as it was when this was a Dart-side loop.
  ///
  /// It used to be that loop — one `occt_shape_edge_info` per edge, each a
  /// separate FFI crossing with its own calloc/free — and the measurement said
  /// the crossings were never the problem. Each of those calls rebuilt the
  /// shape's edge map, its edge→face ancestor map, its bounding box and a
  /// solid classifier, and threw all four away: n calls × Θ(n) work.
  /// `PERFORMANCE_PROFILE.md` §6.5 measures the composite at **k = 2.012**
  /// [1.910, 2.113], R² = 1.0000, against a control doing strictly more work
  /// at k = 1.063 — 200.3× at 1440 edges, 10 017 ms for one enumeration, and
  /// an extrapolated 56.4 s on the part that failed in the field.
  ///
  /// v21 removed the per-call rebuilds and Lane C measured a 20.7× drop with
  /// the exponent unmoved at k = 1.909 — the quadratic outlived the fix. What
  /// was left was `BRepClass3d_SolidClassifier::Perform`, one call per edge
  /// and Θ(shape) inside, at **98.6 %** of the whole enumeration. v22 answers
  /// the same question locally and the ladder fits **k = 0.996**
  /// [0.971, 1.020]: linear at last. See `perf/findings/S6-shim2.md`.
  ///
  /// The fix is in the shim, where the quadratic is; see
  /// `occt_shape_edges_info`. What is left here is one crossing and one
  /// buffer, decoded through the same [OcctEdgeInfo.decodeRecord] the
  /// single-edge path uses.
  ///
  /// TWO COUNTERS, deliberately. `ffi.occt.edgesInfo.calls` counts crossings
  /// and `ffi.occt.edgesInfo.edges` counts edges enumerated, because the
  /// regression gate keys on counters (§15.4) and collapsing n crossings into
  /// one must not also make the amount of WORK invisible. `edgesInfo.edges`
  /// is the quantity the retired `ffi.occt.edgeInfo.calls` was really
  /// recording — it was emitted only from here, once per call with by = n, so
  /// it counted edges and never counted a single-edge call at all. That name
  /// now counts what it says.
  List<OcctEdgeInfo> allEdges() => ffiSpan('ffi.occt.allEdges', () {
        final n = edgeCount;
        if (n <= 0) return const <OcctEdgeInfo>[];
        ffiCount('ffi.occt.edgesInfo.calls', 1);
        ffiCount('ffi.occt.edgesInfo.edges', n);
        final buf = calloc<Double>(12 * n);
        try {
          final got = _ffi._shapeEdgesInfo(_handle, buf, n);
          if (got <= 0) return const <OcctEdgeInfo>[];
          final rec = buf.asTypedList(12 * got);
          final out = <OcctEdgeInfo>[];
          for (var i = 0; i < got; i++) {
            final e = OcctEdgeInfo.decodeRecord(i + 1, rec, 12 * i);
            if (e != null) out.add(e);
          }
          return out;
        } finally {
          calloc.free(buf);
        }
      });

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
      final out = ffiSpan(
          'ffi.occt.filletEdges',
          () => _ffi._wrap(
              _ffi._filletEdgesEx(_handle, ids, rs, rs2, n, drop, scale)));
      ffiCount('ffi.occt.filletEdges.edges', n);
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
      final n = ffiSpan(
          'ffi.occt.revolveHitsFace',
          () => _ffi._revolveHitsFace(_handle, axPx, axPy, axPz, axDx, axDy,
              axDz, px, py, pz, fx, fy, fz, buf, maxHits));
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
      final out = ffiSpan(
          'ffi.occt.chamferEdges',
          () => _ffi._wrap(_ffi._chamferEdgesEx(
              _handle, ids, md, p1, p2, pa, n, drop, scale)));
      ffiCount('ffi.occt.chamferEdges.edges', n);
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
      final n = ffiSpan(
          'ffi.occt.revolveHits',
          () => _ffi._revolveHits(_handle, axPx, axPy, axPz, axDx, axDy, axDz,
              px, py, pz, buf, maxHits));
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
      final n = ffiSpan('ffi.occt.rayHits',
          () => _ffi._rayHits(_handle, ox, oy, oz, dx, dy, dz, buf, maxHits));
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
      return ffiSpan(
          'ffi.occt.transform', () => _ffi._wrap(_ffi._transform(_handle, p)));
    } finally {
      calloc.free(p);
    }
  }

  /// M212 — MIRROR about the plane through [px],[py],[pz] with normal
  /// [nx],[ny],[nz] (shim v17). A NEW shape; this one is unchanged.
  ///
  /// Its own call rather than a matrix through [transformed] because a
  /// reflection has determinant -1, which the shim refuses there on purpose
  /// (see occt_capi.h): a non-rigid matrix arriving at a placement is a
  /// caller bug far more often than an intended mirror. The result is
  /// orientation-corrected by the shim, so it can go straight into a
  /// boolean. Null on failure (see [OcctFfi.lastError]).
  OcctShape? mirrored(double px, double py, double pz, double nx, double ny,
      double nz) {
    final p = calloc<Double>(6);
    try {
      p[0] = px;
      p[1] = py;
      p[2] = pz;
      p[3] = nx;
      p[4] = ny;
      p[5] = nz;
      return ffiSpan(
          'ffi.occt.mirror', () => _ffi._wrap(_ffi._mirror(_handle, p)));
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
    // Two spans, deliberately: `meshCreate` is OCCT tessellating (native,
    // scales with the B-Rep), `meshCopyOut` is Dart copying the result across
    // the FFI boundary (scales with triangle count — nine typed-list copies
    // of up to several hundred thousand doubles). They grow for different
    // reasons and are fixed in different places, so one number covering both
    // would point at the wrong layer. That is the M75 mistake in miniature.
    final mp = ffiSpan('ffi.occt.meshCreate',
        () => f._meshCreate(_handle, linDeflection, angDeflection));
    if (mp == nullptr) return null;
    ffiCount('ffi.occt.meshCreate.calls', 1);
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
          final fidBuf = calloc<Int32>(fN > 0 ? fN : 1);
          try {
            final v4ok = fN >= 0 &&
                f._meshTriangleFaces(mp, tfBuf) == 1 &&
                f._meshFaceInfos(mp, fiBuf) == 1 &&
                f._meshEdgeCurves(mp, ecBuf) == 1;
            // v12: the display-edge -> topological-edge map. Read separately
            // from the v4 block so a failure here costs edge-based features
            // (fillet/chamfer picking) and nothing else.
            final v12ok = eN > 0 && f._meshEdgeIds(mp, eiBuf) == 1;
            // v20: the mesh-face -> topological-face map. Read separately for
            // the same reason: losing it must cost Delete Face and Direct Edit
            // and nothing else.
            final v20ok = fN > 0 && f._meshFaceIds(mp, fidBuf) == 1;
            ffiCount('ffi.occt.meshCopyOut.tris', tN);
            ffiCount('ffi.occt.meshCopyOut.verts', vN);
            return ffiSpan(
                'ffi.occt.meshCopyOut',
                () => OcctMeshData(
                      Float64List.fromList(vBuf.asTypedList(3 * vN)),
                      Float64List.fromList(nBuf.asTypedList(3 * vN)),
                      Int32List.fromList(tBuf.asTypedList(3 * tN)),
                      Int32List.fromList(sBuf.asTypedList(eN + 1)),
                      Float64List.fromList(eBuf.asTypedList(3 * epN)),
                      triFaces: v4ok
                          ? Int32List.fromList(tfBuf.asTypedList(tN))
                          : null,
                      faceInfos: v4ok
                          ? Float64List.fromList(fiBuf.asTypedList(15 * fN))
                          : null,
                      edgeCurves: v4ok
                          ? Float64List.fromList(ecBuf.asTypedList(16 * eN))
                          : null,
                      edgeIds: v12ok
                          ? Int32List.fromList(eiBuf.asTypedList(eN))
                          : null,
                      faceIds: v20ok
                          ? Int32List.fromList(fidBuf.asTypedList(fN))
                          : null,
                    ));
          } finally {
            calloc.free(tfBuf);
            calloc.free(fiBuf);
            calloc.free(eiBuf);
            calloc.free(fidBuf);
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

/// Field counts of the v21 mesh report — must match OCCT_MESH_REPORT_* in
/// backend/occt/shim/occt_capi.h.
const int _kMeshReportInts = 22;
const int _kMeshReportReals = 2;

/// What the mesh converter did, in numbers. Mirrors the OCCT_MR_* indices in
/// occt_capi.h; keep the two in step.
class MeshToBrepReport {
  const MeshToBrepReport._(this._ints, this._reals);

  /// All zeros — for a kernel that has no converter, and for a failure so
  /// early that nothing was measured.
  const MeshToBrepReport.empty()
      : _ints = null,
        _reals = null;

  final Int32List? _ints;
  final Float64List? _reals;

  int _i(int k) {
    final a = _ints;
    return (a == null || k >= a.length) ? 0 : a[k];
  }

  double _d(int k) {
    final a = _reals;
    return (a == null || k >= a.length) ? 0 : a[k];
  }

  int get trianglesIn => _i(0);
  int get verticesIn => _i(1);
  int get trianglesUsed => _i(2);
  int get verticesWelded => _i(3);
  int get nonManifoldEdges => _i(4);

  /// Edges with only one triangle — holes in the mesh. A mesh with any of
  /// these cannot close into a solid, and saying so is more useful than
  /// silently handing back a surface body.
  int get boundaryEdges => _i(5);
  int get flippedTriangles => _i(6);
  int get patches => _i(7);
  int get planes => _i(8);
  int get cylinders => _i(9);
  int get cones => _i(10);
  int get spheres => _i(11);
  int get tori => _i(12);
  int get freeform => _i(13);

  /// Patches that had to stay as loose triangles. The honest measure of how
  /// well the conversion went.
  int get facetedPatches => _i(14);
  int get facesBuilt => _i(15);
  int get facesFailed => _i(16);

  /// Edges that are exact surface-intersection curves — a real circle at a
  /// hole's rim rather than a spline through the mesh points.
  int get analyticEdges => _i(17);
  int get approximatedEdges => _i(18);
  int get shells => _i(19);
  int get solids => _i(20);
  bool get closed => _i(21) == 1;

  /// Area-weighted RMS distance from the mesh to the fitted surfaces, in mm.
  double get fitRms => _d(0);
  double get diagonal => _d(1);

  /// Surfaces the converter actually recognised.
  int get analyticFaces => planes + cylinders + cones + spheres + tori;

  /// One line for the log, and the basis of what the user is told.
  String describe() => 'mesh $trianglesIn tri / $verticesIn vtx -> '
      '$patches patch(es): $planes plane, $cylinders cylinder, $cones cone, '
      '$spheres sphere, $tori torus, $facetedPatches faceted; '
      '$facesBuilt face(s) built ($facesFailed failed), '
      '$analyticEdges exact edge(s), rms ${fitRms.toStringAsFixed(4)}, '
      'closed=$closed';
}

/// The outcome of [OcctFfi.brepFromMesh]: a body, or a reason there is none.
class MeshToBrepResult {
  const MeshToBrepResult._(this.shape, this.report, this.error);

  /// Null when the conversion failed; then [error] says why.
  final OcctShape? shape;
  final MeshToBrepReport report;
  final String? error;

  bool get ok => shape != null;
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
      this._sweepProfileEx,
      this._loftSections,
      this._coilProfile,
      this._mirror,
      this._exportStepNamed,
      this._meshFaceIds,
      this._deleteFaces,
      this._moveFaces,
      this._scaleShape,
      this._shapeEdgesInfo,
      this._brepFromMesh);

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
  final _ExportNamedD _exportStepNamed; // v17
  final _MeshIntOutD _meshFaceIds; // v20
  final _FaceOpD _deleteFaces; // v20
  final _MoveFacesD _moveFaces; // v20
  final _ScaleD _scaleShape; // v20
  final _EdgesInfoD _shapeEdgesInfo; // v21 (bulk edge enumeration)
  final _BrepFromMeshD _brepFromMesh; // v21 on main's lineage — see v23
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
  final _SweepExD _sweepProfileEx; // v24
  final _LoftD _loftSections; // v15
  final _CoilD _coilProfile; // v15
  final _TransformD _mirror; // v17 (occt_mirror: point + normal, 6 doubles)

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
        lib.lookupFunction<_SweepExN, _SweepExD>('occt_sweep_profile_ex'),
        lib.lookupFunction<_LoftN, _LoftD>('occt_loft_sections'),
        lib.lookupFunction<_CoilN, _CoilD>('occt_coil_profile'),
        // v17 — the mirror placement (M212's pattern/mirror features).
        lib.lookupFunction<_TransformN, _TransformD>('occt_mirror'),
        // v17 (M214) — named multi-body STEP export. Both branches added a
        // trailing positional argument; the ORDER here is the contract with
        // the constructor above, so the two must stay in lockstep.
        lib.lookupFunction<_ExportNamedN, _ExportNamedD>(
            'occt_export_step_named'),
        // v20 (M217) — face identity, Delete Face, Direct Edit.
        lib.lookupFunction<_MeshIntOutN, _MeshIntOutD>('occt_mesh_face_ids'),
        lib.lookupFunction<_FaceOpN, _FaceOpD>('occt_delete_faces'),
        lib.lookupFunction<_MoveFacesN, _MoveFacesD>('occt_move_faces'),
        lib.lookupFunction<_ScaleN, _ScaleD>('occt_scale_shape'),
        // v21 — the bulk edge enumeration. Eager, like everything else: a v20
        // binary probes to null, i.e. "no 3D kernel", which is the documented
        // policy above.
        lib.lookupFunction<_EdgesInfoN, _EdgesInfoD>('occt_shape_edges_info'),
        // Also "v21", on the other lineage — see occt_shim_version's v23 note.
        // Both are present from v23 on; an older binary missing either fails
        // this lookup and probes to null, which is the same policy.
        lib.lookupFunction<_BrepFromMeshN, _BrepFromMeshD>(
            'occt_brep_from_mesh'),
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
  OcctShape? makeBox(double dx, double dy, double dz) => ffiSpan(
      'ffi.occt.makeBox', () => _wrap(_makeBox(dx, dy, dz)));

  /// Solid cylinder: base centre (cx,cy,cz), axis +Z, radius r, height h.
  OcctShape? makeCylinder(
          double cx, double cy, double cz, double r, double h) =>
      ffiSpan('ffi.occt.makeCylinder',
          () => _wrap(_makeCylinder(cx, cy, cz, r, h)));

  /// Extrude a closed simple polygon in z=0 along +Z. [xy] is (x,y) pairs
  /// WITHOUT repeating the first point; needs >= 3 points, even length.
  OcctShape? extrudePolygon(List<double> xy, double height) {
    if (xy.length < 6 || xy.length.isOdd) return null;
    final p = calloc<Double>(xy.length);
    try {
      for (var i = 0; i < xy.length; i++) {
        p[i] = xy[i];
      }
      return ffiSpan('ffi.occt.extrudePolygon',
          () => _wrap(_extrude(p, xy.length ~/ 2, height)));
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
      return ffiSpan(
          'ffi.occt.extrudeProfile',
          () => _wrap(
              _extrudeProfile(xy, counts, loops.length, height, taperDeg)));
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
      return ffiSpan(
          'ffi.occt.extrudeProfileArcs',
          () => _wrap(_extrudeProfileArcs(
              xyb, counts, loops.length, height, taperDeg)));
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
  ///
  /// v24 — [pathMode] says what the points MEAN, because only the caller
  /// knows. The path always arrives as a polyline, but a polyline sampled from
  /// an arc and a polyline somebody drew want opposite treatment at every
  /// joint, and getting it wrong costs either a rounded-off corner or a sweep
  /// that is cubic in the profile size. [SweepPathMode.auto] leaves the shim
  /// to infer it from the joint angles, which is what it did before this
  /// existed and is still right for a flattened spline.
  OcctShape? sweepProfile(List<List<double>> loops, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0,
      double taperDeg = 0,
      double twistDeg = 0,
      int pathMode = SweepPathMode.auto}) {
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
      return ffiSpan(
          'ffi.occt.sweepProfile',
          () => _wrap(_sweepProfileEx(xyb, counts, loops.length, m, pp,
              pathPts.length ~/ 3, orientation, taperDeg, twistDeg, pathMode)));
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
      return ffiSpan(
          'ffi.occt.loftSections',
          () => _wrap(_loftSections(xyb, counts, mm, sections.length,
              solid ? 1 : 0, ruled ? 1 : 0, closed ? 1 : 0)));
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
      return ffiSpan(
          'ffi.occt.coilProfile',
          () => _wrap(_coilProfile(
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
              closeEnd ? 1 : 0)));
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
      return ffiSpan(
          'ffi.occt.revolveProfile',
          () => _wrap(_revolveProfile(
              xyb, counts, loops.length, axPx, axPy, axDx, axDy, angleDeg)));
    } finally {
      calloc.free(xyb);
      calloc.free(counts);
    }
  }

  /// Boolean union. Inputs remain owned/valid; result is a NEW shape.
  OcctShape? fuse(OcctShape a, OcctShape b) => ffiSpan(
      'ffi.occt.fuse', () => _wrap(_fuse(a._handle, b._handle)));

  /// v5 boolean cut (a \ b, Inventor's Cut). Inputs remain owned/valid;
  /// result is a NEW shape. Null on failure incl. an empty result.
  OcctShape? cut(OcctShape a, OcctShape b) => ffiSpan(
      'ffi.occt.cut', () => _wrap(_cut(a._handle, b._handle)));

  /// v5 boolean common (a ∩ b, Inventor's Intersect). Inputs remain
  /// owned/valid; result is a NEW shape. Null on failure incl. an empty result.
  OcctShape? common(OcctShape a, OcctShape b) => ffiSpan(
      'ffi.occt.common', () => _wrap(_common(a._handle, b._handle)));

  /// v4: merge same-domain faces/edges (cleans boolean results so no
  /// spurious split lines render). Input stays owned; result is NEW.
  OcctShape? unify(OcctShape a) =>
      ffiSpan('ffi.occt.unify', () => _wrap(_unify(a._handle)));

  /// M214 — writes [shapes] to one STEP file as one NAMED product each.
  ///
  /// [names] must be the same length as [shapes] (an empty or blank entry
  /// falls back to [product]). [product] names the document in the file
  /// header. Returns false on failure — see [lastError], which names the body
  /// that could not be written.
  ///
  /// This is deliberately NOT "fuse everything and write one shape". Two
  /// bodies are two bodies; a union to make them one is slow, lossy, and can
  /// fail, and a failed convenience union used to mean no export at all.
  bool exportStepNamed(List<OcctShape> shapes, List<String> names, String path,
      String product) {
    if (shapes.isEmpty) return false;
    final arr = calloc<Pointer<Void>>(shapes.length);
    final nameArr = calloc<Pointer<Utf8>>(shapes.length);
    final owned = <Pointer<Utf8>>[];
    final p = path.toNativeUtf8();
    final prod = product.toNativeUtf8();
    try {
      for (var i = 0; i < shapes.length; i++) {
        arr[i] = shapes[i]._handle;
        final n = i < names.length ? names[i] : '';
        final np = n.toNativeUtf8();
        owned.add(np);
        nameArr[i] = np;
      }
      ffiCount('ffi.occt.exportStepNamed.shapes', shapes.length);
      return ffiSpan(
              'ffi.occt.exportStepNamed',
              () => _exportStepNamed(
                  arr, nameArr, shapes.length, p, prod)) ==
          1;
    } finally {
      for (final np in owned) {
        calloc.free(np);
      }
      calloc.free(nameArr);
      calloc.free(arr);
      calloc.free(prod);
      calloc.free(p);
    }
  }

  /// M217 — Inventor's Delete Face (Heal on). [faceIds] are 1-based
  /// TOPOLOGICAL indices ([OcctMeshData.topoFaceId] maps a pick to one).
  /// Null on failure; see [lastError].
  OcctShape? deleteFaces(OcctShape s, List<int> faceIds) {
    if (faceIds.isEmpty) return null;
    final ids = calloc<Int32>(faceIds.length);
    try {
      for (var i = 0; i < faceIds.length; i++) {
        ids[i] = faceIds[i];
      }
      ffiCount('ffi.occt.deleteFaces.faces', faceIds.length);
      return ffiSpan('ffi.occt.deleteFaces',
          () => _wrap(_deleteFaces(s._handle, ids, faceIds.length, 1)));
    } finally {
      calloc.free(ids);
    }
  }

  /// M217 — Inventor's Direct > Move/Size: slide [faceIds] by (dx,dy,dz).
  OcctShape? moveFaces(
      OcctShape s, List<int> faceIds, double dx, double dy, double dz) {
    if (faceIds.isEmpty) return null;
    final ids = calloc<Int32>(faceIds.length);
    try {
      for (var i = 0; i < faceIds.length; i++) {
        ids[i] = faceIds[i];
      }
      ffiCount('ffi.occt.moveFaces.faces', faceIds.length);
      return ffiSpan(
          'ffi.occt.moveFaces',
          () => _wrap(
              _moveFaces(s._handle, ids, faceIds.length, dx, dy, dz)));
    } finally {
      calloc.free(ids);
    }
  }

  /// M217 — Inventor's Direct > Scale: uniform scale about a centre.
  ///
  /// Three doubles rather than a Vec3 on purpose: this file imports nothing
  /// from the app (see the header note), so that it can never drag the rest of
  /// the tree into a compile error.
  OcctShape? scaleShape(
          OcctShape s, double cx, double cy, double cz, double factor) =>
      ffiSpan('ffi.occt.scaleShape',
          () => _wrap(_scaleShape(s._handle, cx, cy, cz, factor)));

  /// M232 — turn a triangle mesh into a real B-Rep body.
  ///
  /// The kernel half of opening an STL, OBJ or 3MF: the file is parsed in
  /// `mesh_io.dart` and arrives here as a plain indexed mesh in millimetres.
  /// Winding, welding and orientation are the shim's problem, not the
  /// caller's, because a downloaded mesh is reliably wrong about all three.
  ///
  /// [mode] 1 fits real surfaces (a hole comes back a cylinder with a circular
  /// rim, so it can be filleted afterwards); [mode] 0 makes one flat face per
  /// triangle, which is exact and nearly useless downstream. Pass 0 for the
  /// tuning values to take the shim's defaults, which is almost always right.
  ///
  /// Never throws and never returns null without a reason: on failure the
  /// result carries [MeshToBrepResult.error] and the report explains it.
  MeshToBrepResult brepFromMesh(Float64List xyz, Int32List triangles,
      {int mode = 1,
      double tolFraction = 0,
      double sharpDegrees = 0,
      int maxFacetedTriangles = 0}) {
    // 23, not 21: "v21" was claimed independently by two lineages and only
    // one of them was this converter (see occt_shim_version). 23 is the first
    // version in which occt_brep_from_mesh is unambiguously present.
    if (shimVersion < 23) {
      return MeshToBrepResult._(null, const MeshToBrepReport.empty(),
          'This build has no mesh converter.');
    }
    final nv = xyz.length ~/ 3, nt = triangles.length ~/ 3;
    if (nv < 3 || nt < 1) {
      return MeshToBrepResult._(
          null, const MeshToBrepReport.empty(), 'That mesh has no triangles.');
    }
    final pXyz = calloc<Double>(nv * 3);
    final pTri = calloc<Int32>(nt * 3);
    final pInts = calloc<Int32>(_kMeshReportInts);
    final pReals = calloc<Double>(_kMeshReportReals);
    try {
      // setRange, NOT setAll. The buffers are nv*3 and nt*3 long, and those
      // are FLOORED divisions — a list whose length is not a multiple of three
      // is one or two elements longer than the buffer made for it, and setAll
      // copies all of it. That writes past the end of a calloc'd block, which
      // is heap corruption at an FFI boundary: it does not fail here, it fails
      // later, somewhere unrelated, with nothing to connect it back.
      //
      // mesh_io never produces a ragged list today. This does not depend on
      // that staying true.
      pXyz.asTypedList(nv * 3).setRange(0, nv * 3, xyz);
      pTri.asTypedList(nt * 3).setRange(0, nt * 3, triangles);
      final h = _brepFromMesh(pXyz, nv, pTri, nt, mode, tolFraction,
          sharpDegrees, maxFacetedTriangles, pInts, pReals);
      // The report is filled in even when the conversion failed — that is the
      // point of it, so a refusal can be explained with numbers.
      final report = MeshToBrepReport._(
          Int32List.fromList(pInts.asTypedList(_kMeshReportInts)),
          Float64List.fromList(pReals.asTypedList(_kMeshReportReals)));
      if (h == nullptr) {
        return MeshToBrepResult._(null, report, lastError());
      }
      return MeshToBrepResult._(OcctShape._(this, h), report, null);
    } finally {
      calloc.free(pXyz);
      calloc.free(pTri);
      calloc.free(pInts);
      calloc.free(pReals);
    }
  }

  /// Read a STEP file (all roots, compound if several). Null on failure.
  OcctShape? importStep(String path) {
    final p = path.toNativeUtf8();
    try {
      return ffiSpan('ffi.occt.importStep', () => _wrap(_importStep(p)));
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
      final n = ffiSpan(
          'ffi.occt.splitSolids', () => _splitSolids(whole._handle, out, max));
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
