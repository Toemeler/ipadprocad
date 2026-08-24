// M241 — the ASSEMBLY's RealityKit scene, on the same surface the part uses.
//
// M240 shipped the assembly viewport on the CPU painter, with a note saying
// why: the scene payload addressed solids by id in ONE world space and carried
// no per-solid placement, so two occurrences of a part would have arrived as
// one solid drawn once, at the origin. That note is now out of date — the
// payload carries `at`, the renderer puts it on the solid's holder Entity, and
// this file is the assembly's side of that.
//
// WHAT THAT BUYS, beyond "it is the GPU now":
//
//   * ONE UPLOAD PER PART, however many times it is placed. Two occurrences
//     of a bracket are two holders over one mesh; the second placement costs
//     a transform, not 3 MB across the platform channel.
//   * A DEPTH BUFFER between components. The CPU painter sorted components by
//     the depth of their origin, which is right only while they do not
//     overlap on screen — an assembly is precisely the document where things
//     DO overlap.
//   * A DRAG THAT DOES NOT RE-UPLOAD ANYTHING. Placements ride the LIGHT push
//     (`setOverlays`), the same one hover tints use, so moving a component is
//     a transform write per frame. That is why [assemblySceneSignature] leaves
//     placements out and reads [AssemblyModel.gen] instead: the heavy push is
//     for the assembly's STRUCTURE changing, not for a finger moving.
//
// This file deliberately does NOT import app_state.dart. reality_scene.dart
// does (it maps the live part-editing state onto the surface) and is therefore
// imported BY app_state through the pure reality_payload.dart shim; an
// assembly has no editing sessions to map, so it needs no such detour and
// app_state can import this directly.
import 'package:flutter/painting.dart' show Color;

import 'assembly.dart';
import 'part_model.dart';
import 'reality_payload.dart';
import 'theme.dart';

/// One drawable piece of an assembly: the payload id it travels under, the
/// occurrence it belongs to, and the solid itself.
///
/// The id is `<occurrence>/<feature>` — "Bracket:1/Extrusion1". It has to be
/// unique across the whole scene (the renderer keys its entity cache on it),
/// and two occurrences of one part carry the same feature names, so the
/// occurrence id is the only thing that can separate them.
typedef AssemblyPiece = (String, AssemblyOccurrence, KernelSolid);

/// Everything the assembly draws, in occurrence order.
///
/// A component whose source part could not be loaded (the part was deleted
/// from the gallery) contributes nothing here and still keeps its browser row
/// — see AppState._loadAssemblyModel for why the occurrence survives.
List<AssemblyPiece> assemblyPieces(AssemblyModel a) => [
      for (final o in a.occurrences)
        if (o.visible)
          for (final (feature, s) in o.namedSolids) ('${o.id}/$feature', o, s),
    ];

/// The tint a component is drawn in, as a packed ARGB, or [kNoTint] for the
/// ordinary steel.
///
/// Selection is Inventor's: the WHOLE component changes colour, not an edge of
/// it — an assembly is picked by the body, so the body is what answers. The
/// hover tone is the same hue mixed most of the way back to steel, so the two
/// states are told apart at a glance without the hover shouting.
int assemblyTint(AssemblyModel a, AssemblyOccurrence o, {String? hoverId}) {
  if (identical(a.selected, o)) return T.faceHighlight.toARGB32();
  if (hoverId != null && o.id == hoverId) {
    return (Color.lerp(T.solid, T.faceHighlight, 0.38) ?? T.faceHighlight)
        .toARGB32();
  }
  return kNoTint;
}

/// Mesh revisions currently on screen, so the next push can omit the buffers
/// of everything that did not change. Mirrors `sceneRevs` on the part side.
Map<String, int> assemblySceneRevs(AssemblyModel a) => {
      for (final (id, _, s) in assemblyPieces(a)) id: identityHashCode(s.mesh),
    };

/// The full scene: solids with their placements, the origin planes, the origin
/// axes and the centre point.
///
/// [knownRevs] is what the renderer already holds; a solid whose mesh is
/// unchanged travels as identity + placement + tint alone.
Map<String, dynamic> buildAssemblyScenePayload(
  AssemblyModel a, {
  String? hoverId,
  Map<String, int>? knownRevs,
}) =>
    {
      'solids': [
        for (final (id, o, s) in assemblyPieces(a))
          solidPayload(
            id,
            s,
            at: o.offset,
            rot: o.rot,
            tint: assemblyTint(a, o, hoverId: hoverId),
            includeGeometry: knownRevs?[id] != identityHashCode(s.mesh),
          ),
      ],
      'planes': assemblyPlanePayloads(a),
      'axes': assemblyAxisPayloads(a),
      'cp': {'visible': a.vis['cp'] == true, 'hot': false},
      // Present and empty, deliberately: the renderer clears its sketch root
      // from this key, and an assembly holds no sketches. Leaving it out would
      // strand whatever a previously open PART left in the same view.
      'sketches': const <Map<String, dynamic>>[],
      'selSketch': const <String>[],
    };

/// The LIGHT push: placements, tints and the origin scaffolding's state.
///
/// This is the drag path. It carries no geometry, no plane meshes and no
/// camera work — just where every component sits and what colour it is.
Map<String, dynamic> buildAssemblyOverlaysPayload(AssemblyModel a,
        {String? hoverId}) =>
    {
      'placements': [
        for (final (id, o, _) in assemblyPieces(a))
          {
            'id': id,
            'at': [o.offset.x, o.offset.y, o.offset.z],
            'rot': [o.rot.x, o.rot.y, o.rot.z, o.rot.w],
            'tint': assemblyTint(a, o, hoverId: hoverId),
          },
      ],
      'planes': [
        for (final key in kPlaneKeys)
          {'key': key, 'visible': a.vis[key] == true, 'hot': false},
      ],
      'axes': [
        for (final (key, _) in kAssemblyAxes)
          {'key': key, 'visible': a.vis[key] == true, 'hot': false},
      ],
      'cp': {'visible': a.vis['cp'] == true, 'hot': false},
      'selSketch': const <String>[],
    };

const List<(String, Vec3)> kAssemblyAxes = [
  ('x', Vec3(1, 0, 0)),
  ('y', Vec3(0, 1, 0)),
  ('z', Vec3(0, 0, 1)),
];

List<Map<String, dynamic>> assemblyPlanePayloads(AssemblyModel a) => [
      for (final key in kPlaneKeys)
        planePayload(key, planeFrame(key), assemblyPlaneRect(a, key),
            visible: a.vis[key] == true, hot: false),
    ];

List<Map<String, dynamic>> assemblyAxisPayloads(AssemblyModel a) => [
      for (final (key, d) in kAssemblyAxes)
        () {
          final (lo, hi) = assemblyAxisSpan(a, d);
          return axisPayload(key, d, lo, hi,
              visible: a.vis[key] == true, hot: false);
        }(),
    ];

/// When the HEAVY push has to fire.
///
/// Placements are NOT in here, and that is the design rather than an omission:
/// they travel on every light push, so a drag must not move this string or the
/// whole scene — meshes, plane quads, camera fit — would be rebuilt sixty
/// times a second for a translation the renderer can apply itself.
///
/// [AssemblyModel.gen] stands in for everything a drag SHOULD eventually
/// change and cannot express here: the origin planes are sized to the
/// assembly's contents, so once a drag ENDS the extent is stale until the
/// generation ticks and brings the planes with it.
String assemblySceneSignature(AssemblyModel a) {
  final sb = StringBuffer()
    ..write('gen:')
    ..write(a.gen)
    ..write(';vis:');
  for (final k in const ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) {
    sb.write(a.vis[k] == true ? '1' : '0');
  }
  sb.write(';s:');
  for (final (id, _, s) in assemblyPieces(a)) {
    sb
      ..write(id)
      ..write('=')
      ..write(identityHashCode(s.mesh))
      ..write(';');
  }
  return sb.toString();
}
