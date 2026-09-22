/// Geometry fixtures whose answers are known by hand.
///
/// A stub kernel that returns an EMPTY mesh is enough to test bookkeeping —
/// which feature landed in the timeline, what the undo journal holds — but it
/// cannot test anything that reads geometry, because there is none. The digest
/// and every op built on it need a body with real triangles and real per-face
/// analytic records, so this file builds one.
///
/// Nothing here fakes a kernel's ANSWERS. It builds the same mesh layout the
/// shim publishes (positions, normals, indices, `triFaces`, the 15-double
/// `faceInfos` record per face) and lets the code under test do its own
/// arithmetic on it.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A closed box as the shim would hand it over: 6 planar faces, 2 triangles
/// each, wound counter-clockwise seen from outside.
OcctMeshData boxMesh(double dx, double dy, double dz) {
  final pos = <double>[], nor = <double>[], idx = <int>[], tri = <int>[];
  final info = <double>[];
  // (origin, u, v, outward normal) per face.
  final faces = <(List<double>, List<double>, List<double>, List<double>)>[
    ([0, 0, 0], [dx, 0, 0], [0, dy, 0], [0, 0, -1]),
    ([0, 0, dz], [dx, 0, 0], [0, dy, 0], [0, 0, 1]),
    ([0, 0, 0], [dx, 0, 0], [0, 0, dz], [0, -1, 0]),
    ([0, dy, 0], [dx, 0, 0], [0, 0, dz], [0, 1, 0]),
    ([0, 0, 0], [0, dy, 0], [0, 0, dz], [-1, 0, 0]),
    ([dx, 0, 0], [0, dy, 0], [0, 0, dz], [1, 0, 0]),
  ];
  for (var f = 0; f < faces.length; f++) {
    var (o, u, v, n) = faces[f];
    // OCCT winds every triangle counter-clockwise seen from OUTSIDE, and the
    // digest's projected-area sum reads that winding. Half of the face frames
    // above span the wrong way round, so swap them rather than hand the code
    // a mesh no kernel would ever produce.
    final cross = [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ];
    if (cross[0] * n[0] + cross[1] * n[1] + cross[2] * n[2] < 0) {
      final t = u;
      u = v;
      v = t;
    }
    final base = pos.length ~/ 3;
    for (final c in [
      [0.0, 0.0],
      [1.0, 0.0],
      [1.0, 1.0],
      [0.0, 1.0]
    ]) {
      for (var k = 0; k < 3; k++) {
        pos.add(o[k] + u[k] * c[0] + v[k] * c[1]);
        nor.add(n[k]);
      }
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    tri.addAll([f, f]);
    // type 0 (plane), a point on it, its normal, then the fields the digest
    // does not read — radius sits at [10].
    info.addAll([
      0,
      o[0] + (u[0] + v[0]) / 2,
      o[1] + (u[1] + v[1]) / 2,
      o[2] + (u[2] + v[2]) / 2,
      n[0], n[1], n[2],
      0, 0, 0, 0, 0, 0, 0, 0,
    ]);
  }
  // M458 — the twelve display EDGES, as the shim publishes them: a CSR-style
  // `edgeStarts` indexing into `edgePoints`, two points an edge. Without them
  // the box has no edges to project, pick or fillet by proximity, and a
  // fixture that omits them quietly makes those features untestable.
  final ex = <double>[], estart = <int>[];
  void edge(List<double> a, List<double> b) {
    estart.add(ex.length ~/ 3);
    ex.addAll([...a, ...b]);
  }

  final c = <List<double>>[
    [0, 0, 0], [dx, 0, 0], [dx, dy, 0], [0, dy, 0], //
    [0, 0, dz], [dx, 0, dz], [dx, dy, dz], [0, dy, dz],
  ];
  for (final pair in const [
    [0, 1], [1, 2], [2, 3], [3, 0], // bottom
    [4, 5], [5, 6], [6, 7], [7, 4], // top
    [0, 4], [1, 5], [2, 6], [3, 7], // uprights
  ]) {
    edge(c[pair[0]], c[pair[1]]);
  }
  estart.add(ex.length ~/ 3); // the closing offset every CSR array needs

  return OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList(estart),
    Float64List.fromList(ex),
    triFaces: Int32List.fromList(tri),
    faceInfos: Float64List.fromList(info),
    faceIds: Int32List.fromList([for (var f = 0; f < faces.length; f++) f + 1]),
  );
}

/// The same box with every surface type relabelled free-form — which is what
/// an imported organic body actually looks like to the digest.
OcctMeshData freeFormMesh(double dx, double dy, double dz) {
  final m = boxMesh(dx, dy, dz);
  final info = Float64List.fromList(m.faceInfos);
  for (var f = 0; f * 15 < info.length; f++) {
    info[f * 15] = 5; // kFaceOther
  }
  return OcctMeshData(
      m.positions, m.normals, m.indices, m.edgeStarts, m.edgePoints,
      triFaces: m.triFaces, faceInfos: info, faceIds: m.faceIds);
}

KernelSolid solidOf(OcctMeshData m, double volume) =>
    KernelSolid(m, volume, null);

/// A tube standing on the ground: a ring of [outerR] with a bore of [innerR],
/// [height] tall along +Y (this app's up axis).
///
/// The bore is a real opening — the end faces are annuli, not discs — which is
/// what makes it a fixture for "can you see through it" rather than a cylinder
/// with a decorative inner wall. Four faces: bore, outer wall, bottom, top.
OcctMeshData ringMesh(double outerR, double innerR, double height,
    {int segments = 48}) {
  final pos = <double>[], nor = <double>[], idx = <int>[], tri = <int>[];

  int vertex(double x, double y, double z, double nx, double ny, double nz) {
    final i = pos.length ~/ 3;
    pos.addAll([x, y, z]);
    nor.addAll([nx, ny, nz]);
    return i;
  }

  void quad(int a, int b, int c, int d, int face) {
    idx.addAll([a, b, c, a, c, d]);
    tri.addAll([face, face]);
  }

  for (var s = 0; s < segments; s++) {
    final a0 = 2 * math.pi * s / segments;
    final a1 = 2 * math.pi * (s + 1) / segments;
    final c0 = math.cos(a0), s0 = math.sin(a0);
    final c1 = math.cos(a1), s1 = math.sin(a1);

    // Face 0 — the bore. Normals point INWARD, toward the axis: that is what
    // makes the digest call it concave, and therefore a hole.
    quad(
      vertex(innerR * c0, 0, innerR * s0, -c0, 0, -s0),
      vertex(innerR * c1, 0, innerR * s1, -c1, 0, -s1),
      vertex(innerR * c1, height, innerR * s1, -c1, 0, -s1),
      vertex(innerR * c0, height, innerR * s0, -c0, 0, -s0),
      0,
    );
    // Face 1 — the outer wall, normals outward.
    quad(
      vertex(outerR * c0, 0, outerR * s0, c0, 0, s0),
      vertex(outerR * c0, height, outerR * s0, c0, 0, s0),
      vertex(outerR * c1, height, outerR * s1, c1, 0, s1),
      vertex(outerR * c1, 0, outerR * s1, c1, 0, s1),
      1,
    );
    // Faces 2 and 3 — the annular ends.
    quad(
      vertex(innerR * c0, 0, innerR * s0, 0, -1, 0),
      vertex(outerR * c0, 0, outerR * s0, 0, -1, 0),
      vertex(outerR * c1, 0, outerR * s1, 0, -1, 0),
      vertex(innerR * c1, 0, innerR * s1, 0, -1, 0),
      2,
    );
    quad(
      vertex(innerR * c0, height, innerR * s0, 0, 1, 0),
      vertex(innerR * c1, height, innerR * s1, 0, 1, 0),
      vertex(outerR * c1, height, outerR * s1, 0, 1, 0),
      vertex(outerR * c0, height, outerR * s0, 0, 1, 0),
      3,
    );
  }

  // 15 doubles a face: [type, point(3), axis(3), …, radius at 10, …].
  final info = <double>[];
  void record(int type, List<double> at, List<double> dir, double radius) {
    info.addAll([
      type.toDouble(), at[0], at[1], at[2], dir[0], dir[1], dir[2],
      0, 0, 0, radius, 0, 0, 0, 0,
    ]);
  }

  record(1, [0, 0, 0], [0, 1, 0], innerR); // cylinder, on the axis
  record(1, [0, 0, 0], [0, 1, 0], outerR);
  record(0, [0, 0, 0], [0, -1, 0], 0);
  record(0, [0, height, 0], [0, 1, 0], 0);

  return OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList(tri),
    faceInfos: Float64List.fromList(info),
    faceIds: Int32List.fromList([1, 2, 3, 4]),
  );
}

/// A kernel whose extrusions are real boxes.
///
/// [width] and [depth] are fixed rather than derived from the profile: the
/// tests that use this assert against the box's own arithmetic, and a size
/// that depended on how the profile happened to be tessellated would make
/// those assertions about the fixture instead of about the code.
class BoxKernel implements PartKernel {
  BoxKernel({this.width = 60, this.depth = 40, this.rings = const []});
  final double width, depth;

  /// Radii of circular edges this kernel reports alongside the straight ones —
  /// the mouths of bores, which is what a blend selector has to be able to
  /// leave alone.
  final List<double> rings;
  int extrudes = 0, fillets = 0, chamfers = 0, deletes = 0, moves = 0;
  int sweeps = 0, lofts = 0, coils = 0, places = 0, mirrors = 0;

  /// The (revolutions, height, clockwise) the last coil resolved to — the
  /// arithmetic the four coil methods all funnel through.
  (double, double, bool)? lastCoil;

  @override
  bool get available => true;
  @override
  String get info => 'box stub';
  @override
  String get lastError => 'box stub failure';

  KernelSolid _box(double height) =>
      solidOf(boxMesh(width, depth, height), width * depth * height);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return _box(height);
  }

  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
          double axPx, double axPy, double axDx, double axDy,
          List<double> mat34) =>
      _box(angleDeg / 36);

  /// M456 — the three M131 features. PartKernel declares these concrete and
  /// null-returning so a fake that does not model them says so; this one
  /// does model them, because the ops that drive them are under test.
  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0,
      double taperDeg = 0,
      double twistDeg = 0,
      int pathMode = 0}) {
    sweeps++;
    return _box(12);
  }

  @override
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
      {bool solid = true, bool ruled = false, bool closed = false}) {
    lofts++;
    return _box(14);
  }

  @override
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
      Vec3 axP, Vec3 axD,
      {required double revolutions,
      required double height,
      double taperDeg = 0,
      bool clockwise = false}) {
    coils++;
    lastCoil = (revolutions, height, clockwise);
    return _box(16);
  }

  /// What a PATTERN needs: each occurrence is the source solid placed by a
  /// 3x4 matrix, or mirrored about a plane.
  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) {
    places++;
    return _box(11);
  }

  @override
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 point, Vec3 normal) {
    mirrors++;
    return _box(11);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) => _box(10);
  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) => _box(9);
  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) => _box(8);

  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> e, List<double> r,
      {List<double> radii2 = const [], BlendReport? report}) {
    fillets++;
    return _box(7);
  }

  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
      double d1, double d2, double angleDeg, {BlendReport? report}) {
    chamfers++;
    return _box(6);
  }

  /// M217's face surgery. A fake that returns null here is saying "this
  /// kernel cannot do face edits", and the feature then fails honestly — which
  /// is right for a fake that does not model it, and wrong for these tests,
  /// whose whole subject is the op reaching the kernel at all.
  /// #85 — a shell is a face operation on the body; the box it returns is
  /// thinner, which is all a fake can honestly say about a hollowed part.
  int shells = 0;
  @override
  KernelSolid? shellSolid(KernelSolid base, List<int> faceIds,
      double thickness,
      {bool outward = false}) {
    shells++;
    return _box(4);
  }

  @override
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) {
    deletes++;
    return _box(5);
  }

  @override
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) {
    moves++;
    return _box(10 + delta.length);
  }

  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => [
        OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, width, 0, 2, 90, 1),
        OcctEdgeInfo(2, 1, width, 0, 0, 0, 1, 0, depth, 0, 2, 90, 1),
        for (var i = 0; i < rings.length; i++)
          OcctEdgeInfo(3 + i, 2, 10.0 * i, 0, 0, 1, 0, 0,
              2 * math.pi * rings[i], rings[i], 2, 90, 1),
      ];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}
