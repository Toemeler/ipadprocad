// Prototype — PURE RealityKit payload builders (M82).
//
// Split out of reality_scene.dart so that code which must NOT depend on
// AppState can still speak the RealityKit wire format. reality_scene.dart
// imports AppState (it maps the live editing state onto the surface), so
// app_state.dart importing it back would close a cycle — and the gallery
// thumbnail writer in AppState needs exactly these three builders.
//
// Everything here depends only on part_model.dart. reality_scene.dart
// re-exports this file, so existing `import 'reality_scene.dart'` callers are
// unaffected.
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'part_model.dart';
import 'quat.dart';

/// Material tags understood by Materials.swift.
const int kMatSteel = 0;
const int kMatPreview = 1;

/// M241 — "no tint", as an ARGB sentinel.
///
/// A fully transparent black is never a colour anyone asks for, and a sentinel
/// keeps the Swift cache out of `[String: Int?]`, where `dict[k] = nil` REMOVES
/// the entry rather than storing a nil. See Payload.argb in PartScene.swift.
const int kNoTint = 0;

/// The five orthographic camera doubles + the viewport size (for aspect).
Map<String, dynamic> cameraPayload(PartCamera c, Size size) => {
      'az': c.az,
      'pol': c.pol,
      'halfH': c.halfH,
      'ox': c.ox,
      'oy': c.oy,
      'roll': c.roll,
      'w': size.width,
      'h': size.height,
    };

/// One solid's mesh payload. Buffers are passed by reference (no copy).
/// With [includeGeometry] false only the identity travels — the renderer then
/// keeps the mesh it already holds for this id.
///
/// M241 — [at] is the solid's PLACEMENT, [rot] its orientation (M242), and
/// [tint] recolours it.
///
/// Both are carried by the renderer on the solid's holder Entity and its
/// material, so a payload that omits the geometry can still MOVE a solid or
/// RECOLOUR it. That is the whole assembly path: two occurrences of one part
/// are two holders over one uploaded mesh, and dragging one costs a transform
/// write instead of a multi-megabyte buffer upload.
///
/// A part sends neither. Its solids are already in world coordinates and are
/// all steel, so `at` is omitted and `tint` is [kNoTint] — the payload it
/// produces is byte-for-byte what it produced before.
Map<String, dynamic> solidPayload(String id, KernelSolid s,
    {int material = kMatSteel,
    bool includeGeometry = true,
    Vec3 at = Vec3.zero,
    Quat rot = Quat.identity,
    int tint = kNoTint}) {
  final m = s.mesh;
  // Component-wise, NOT `at != Vec3.zero`: Vec3 has no operator==, so that
  // comparison is identity and would hold only for the shared const instance.
  final placed = at.x != 0 || at.y != 0 || at.z != 0;
  final place = <String, dynamic>{
    if (placed) 'at': [at.x, at.y, at.z],
    // M242 — the ORIENTATION, as (x, y, z, w) because that is simd_quatf's
    // own component order on the Swift side. Omitted when there is none, so a
    // part's payload is byte-identical to what it has always been.
    if (!rot.isIdentity) 'rot': [rot.x, rot.y, rot.z, rot.w],
    if (tint != kNoTint) 'tint': tint,
  };
  if (!includeGeometry) {
    return {
      'id': id,
      'rev': identityHashCode(m),
      'material': material,
      ...place,
    };
  }
  return {
    'id': id,
    'rev': identityHashCode(m),
    ...place,
    // Float32 (M74): half the bytes of Float64 and no per-vertex conversion
    // on the Swift side, since the GPU wants Float32 regardless.
    'positions': m.positions32, // world xyz per vertex
    'normals': m.normals32, // unit outward
    'indices': m.indices, // Int32List, CCW from outside
    'edgePts': m.edgePoints32, // B-Rep edge polyline points
    'edgeStarts': m.edgeStarts, // Int32List, nEdges+1 offsets
    'triFaces': m.triFaces, // Int32List (empty on legacy meshes)
    'material': material,
  };
}

/// Scene payload for an OFF-SCREEN gallery still (M82).
///
/// Deliberately geometry-only: no origin planes, axes, centre point, sketches,
/// preview or highlight — a card should show the MODEL, not the editing
/// scaffolding. Every mesh travels in full (there is no renderer on the other
/// side that already holds a revision, since the off-screen ARView is built
/// fresh for the shot).
///
/// Pure — takes the solids the caller already chose, so it needs no AppState
/// and host tests can assert its shape directly.
Map<String, dynamic> buildThumbScenePayload(List<(String, KernelSolid)> solids) => {
      'solids': [
        for (final (id, s) in solids) solidPayload(id, s),
      ],
    };

/// M241 — [buildThumbScenePayload] for an ASSEMBLY: the same geometry-only
/// still, with each solid's placement travelling beside it.
Map<String, dynamic> buildPlacedThumbScenePayload(
        List<(String, KernelSolid, Quat, Vec3)> solids) =>
    {
      'solids': [
        for (final (id, s, rot, at) in solids)
          solidPayload(id, s, at: at, rot: rot),
      ],
    };

/// A [PlaneFrame]'s three axes, flattened the way PlaneEntity reads them.
///
/// M241 — lifted out of reality_scene.dart so the ASSEMBLY payload can build
/// an origin plane with exactly the bytes the part payload does. Two builders
/// for one native reader is two chances to disagree about a row order.
Float64List frame9(PlaneFrame f) => Float64List.fromList([
      f.u.x, f.u.y, f.u.z, //
      f.v.x, f.v.y, f.v.z, //
      f.n.x, f.n.y, f.n.z, //
    ]);

/// One plane for PlaneEntity: its frame, its (u, v) rectangle and its state.
///
/// [rect] is (uMin, uMax, vMin, vMax) — the padded rectangle the plane
/// occupies in its own axes, which is what makes an origin plane frame the
/// document rather than be a fixed square (M83).
Map<String, dynamic> planePayload(
  String key,
  PlaneFrame f,
  (double, double, double, double) rect, {
  required bool visible,
  required bool hot,
}) {
  final (uMin, uMax, vMin, vMax) = rect;
  return {
    'key': key,
    'frame': frame9(f),
    'origin': [f.origin.x, f.origin.y, f.origin.z],
    'uMin': uMin,
    'uMax': uMax,
    'vMin': vMin,
    'vMax': vMax,
    // The largest half-extent, purely so an older native build (which reads
    // only `ext`) still draws something sane.
    'ext': [uMin.abs(), uMax.abs(), vMin.abs(), vMax.abs()]
        .reduce((a, b) => a > b ? a : b),
    'visible': visible,
    'hot': hot,
  };
}

/// One origin axis for AxisEntity, spanning [lo, hi] along [dir].
Map<String, dynamic> axisPayload(String key, Vec3 dir, double lo, double hi,
        {required bool visible, required bool hot}) =>
    {
      'key': key,
      'dir': [dir.x, dir.y, dir.z],
      'lo': lo,
      'hi': hi,
      'ext': lo.abs() > hi.abs() ? lo.abs() : hi.abs(),
      'visible': visible,
      'hot': hot,
    };
