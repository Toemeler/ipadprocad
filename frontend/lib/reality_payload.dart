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
import 'dart:ui' show Size;

import 'part_model.dart';

/// Material tags understood by Materials.swift.
const int kMatSteel = 0;
const int kMatPreview = 1;

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
Map<String, dynamic> solidPayload(String id, KernelSolid s,
    {int material = kMatSteel, bool includeGeometry = true}) {
  final m = s.mesh;
  if (!includeGeometry) {
    return {'id': id, 'rev': identityHashCode(m), 'material': material};
  }
  return {
    'id': id,
    'rev': identityHashCode(m),
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
