// Shared synthetic meshes for the 3D render tests. A cylinder tessellation
// EXACTLY like OCCT's — barrel quads split into triangles, cap fans, rim
// polylines, per-vertex outward normals — now carrying the v4 display
// metadata (per-triangle face ids, per-face surface records, per-edge
// ANALYTIC curves) so the M59 "Shaded with Edges" pipeline can be exercised
// against realistic input without the native shim.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ipadprocad/ffi/occt_engine.dart' show OcctMeshData;
import 'package:ipadprocad/part_model.dart' show circleSegments;

/// Face-id convention of [synthCylinderMesh]:
///   0 = barrel (cylinder), 1 = bottom cap (plane -Z), 2 = top cap (plane +Z)
const int synthBarrelFace = 0, synthBottomFace = 1, synthTopFace = 2;

/// Builds the cylinder mesh with full v4 metadata. When [v4] is false the
/// display arrays are omitted, reproducing a legacy / fake-kernel mesh so the
/// pipeline's graceful-fallback paths stay covered.
OcctMeshData synthCylinderMesh(double r, double h, double lin,
    {bool v4 = true}) {
  final n = circleSegments(r, lin);
  final pos = <double>[], nor = <double>[], idx = <int>[];
  final triFace = <int>[];

  // barrel: 2 rings of n vertices, radial normals, face 0
  for (var ring = 0; ring < 2; ring++) {
    final z = ring == 0 ? 0.0 : h;
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      pos.addAll([r * math.cos(a), r * math.sin(a), z]);
      nor.addAll([math.cos(a), math.sin(a), 0]);
    }
  }
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    idx.addAll([i, j, n + j, i, n + j, n + i]); // CCW from outside
    triFace.addAll([synthBarrelFace, synthBarrelFace]);
  }
  // bottom cap: centre + ring, axial normals, face 1
  final b0 = pos.length ~/ 3;
  pos.addAll([0, 0, 0]);
  nor.addAll([0, 0, -1]);
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    pos.addAll([r * math.cos(a), r * math.sin(a), 0]);
    nor.addAll([0, 0, -1]);
  }
  for (var i = 0; i < n; i++) {
    idx.addAll([b0, b0 + 1 + (i + 1) % n, b0 + 1 + i]); // CCW from below
    triFace.add(synthBottomFace);
  }
  // top cap, face 2
  final t0 = pos.length ~/ 3;
  pos.addAll([0, 0, h]);
  nor.addAll([0, 0, 1]);
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    pos.addAll([r * math.cos(a), r * math.sin(a), h]);
    nor.addAll([0, 0, 1]);
  }
  for (var i = 0; i < n; i++) {
    idx.addAll([t0, t0 + 1 + i, t0 + 1 + (i + 1) % n]);
    triFace.add(synthTopFace);
  }

  // rim edges (seam suppressed, like the shim): bottom rim, then top rim
  final ep = <double>[], starts = <int>[0];
  for (final z in [0.0, h]) {
    for (var i = 0; i <= n; i++) {
      final a = 2 * math.pi * (i % n) / n;
      ep.addAll([r * math.cos(a), r * math.sin(a), z]);
    }
    starts.add(ep.length ~/ 3);
  }

  if (!v4) {
    return OcctMeshData(
        Float64List.fromList(pos),
        Float64List.fromList(nor),
        Int32List.fromList(idx),
        Int32List.fromList(starts),
        Float64List.fromList(ep));
  }

  // v4 face records (15 doubles each): barrel cylinder, then two cap planes.
  final faceInfos = <double>[
    // face 0: cylinder, axis +Z at origin, xdir +X, radius r, u 0..2pi, v 0..h
    1, 0, 0, 0, 0, 0, 1, 1, 0, 0, r, 0, 2 * math.pi, 0, h,
    // face 1: bottom plane, point origin, OUTWARD normal -Z, xdir +X
    0, 0, 0, 0, 0, 0, -1, 1, 0, 0, 0, -r, r, -r, r,
    // face 2: top plane at z=h, OUTWARD normal +Z, xdir +X
    0, 0, 0, h, 0, 0, 1, 1, 0, 0, 0, -r, r, -r, r,
  ];

  // v4 edge curves (16 doubles each): both rims are exact circles r,
  // sweeping the full 2pi. center / xdir / ydir / radius / t0 / t1.
  final edgeCurves = <double>[
    // bottom rim: z=0
    2, 0, 0, 0, 1, 0, 0, 0, 1, 0, r, 0, 2 * math.pi, 0, 0, 0,
    // top rim: z=h
    2, 0, 0, h, 1, 0, 0, 0, 1, 0, r, 0, 2 * math.pi, 0, 0, 0,
  ];

  return OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList(starts),
    Float64List.fromList(ep),
    triFaces: Int32List.fromList(triFace),
    faceInfos: Float64List.fromList(faceInfos),
    edgeCurves: Float64List.fromList(edgeCurves),
  );
}
