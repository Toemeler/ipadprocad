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
import 'materials.dart';
import 'part_model.dart';
import 'quat.dart';
import 'reality_payload.dart';
import 'theme.dart';

/// One drawable piece of an assembly: the payload id it travels under, the
/// occurrence it belongs to, its WORLD transform, and the solid itself.
///
/// The id is `<occurrence>/<path>` — "Bracket:1/Extrusion1", and one level
/// deeper "Machine:1/Bracket:1/Extrusion1". It has to be unique across the
/// whole scene (the renderer keys its entity cache on it), and two
/// occurrences of one part carry the same inner names, so the occurrence id
/// is the only thing that can separate them.
///
/// M246 — the TRANSFORM travels with the piece rather than being taken from
/// the occurrence, because a subassembly's parts each sit somewhere inside
/// it: reading the occurrence's own placement would put every part of a
/// subassembly at the subassembly's origin, stacked.
///
/// M248 — the transform is a [Placement], which can be a REFLECTION. On the
/// native side that is a negative scale on the holder Entity plus a reversed
/// index winding; see [solidPayload]'s `mirror`.
typedef AssemblyPiece = (String, AssemblyOccurrence, Placement, KernelSolid);

/// Everything the assembly draws, in occurrence order.
///
/// A component whose source part could not be loaded (the part was deleted
/// from the gallery) contributes nothing here and still keeps its browser row
/// — see AppState._loadAssemblyModel for why the occurrence survives.
List<AssemblyPiece> assemblyPieces(AssemblyModel a) => [
      for (final o in a.occurrences)
        if (o.visible)
          for (final (path, at, s) in o.worldSolids)
            ('${o.id}/$path', o, at, s),
    ];

/// The tint a component is drawn in, as a packed ARGB, or [kNoTint] for the
/// ordinary steel.
///
/// Selection is Inventor's: the WHOLE component changes colour, not an edge of
/// it — an assembly is picked by the body, so the body is what answers. The
/// hover tone is the same hue mixed most of the way back to steel, so the two
/// states are told apart at a glance without the hover shouting.
///
/// M284 — [previewMaterial] wins over the selection highlight on the SELECTED
/// component while the appearance menu is open, for the same reason as the
/// part side's `_bodyRowTint`: a colour can't be judged through a wash over
/// it. This file cannot read [AppState] (see the header note), so the value
/// travels in as a plain string, same as [hoverId].
int assemblyTint(AssemblyModel a, AssemblyOccurrence o,
    {String? hoverId, String? previewMaterial}) {
  if (identical(a.selected, o)) {
    if (previewMaterial != null) {
      return materialArgb(previewMaterial) ?? kNoTint;
    }
    return T.faceHighlight.toARGB32();
  }
  if (hoverId != null && o.id == hoverId) {
    return (Color.lerp(T.solid, T.faceHighlight, 0.38) ?? T.faceHighlight)
        .toARGB32();
  }
  // M272 — and under both, the component's own appearance. Selection and hover
  // are questions being asked right now; a material is a fact set once, so it
  // sits underneath them. Same rule as _bodyRowTint on the part side.
  return materialArgb(o.material) ?? kNoTint;
}

/// Mesh revisions currently on screen, so the next push can omit the buffers
/// of everything that did not change. Mirrors `sceneRevs` on the part side.
Map<String, int> assemblySceneRevs(AssemblyModel a) => {
      for (final (id, _, _, s) in assemblyPieces(a))
        id: identityHashCode(s.mesh),
    };

/// The full scene: solids with their placements, the origin planes, the origin
/// axes and the centre point.
///
/// [knownRevs] is what the renderer already holds; a solid whose mesh is
/// unchanged travels as identity + placement + tint alone.
Map<String, dynamic> buildAssemblyScenePayload(
  AssemblyModel a, {
  String? hoverId,
  String? previewMaterial,
  Map<String, int>? knownRevs,
}) =>
    {
      'solids': [
        for (final (id, o, at, s) in assemblyPieces(a))
          solidPayload(
            id,
            s,
            at: at.at,
            rot: at.rot,
            mirror: at.reflect,
            tint: assemblyTint(a, o,
                hoverId: hoverId, previewMaterial: previewMaterial),
            includeGeometry: knownRevs?[id] != identityHashCode(s.mesh),
          ),
      ],
      // M273 — see buildScenePayload.
      'render': a.displayMode.isRendered,
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
        {String? hoverId, String? previewMaterial}) =>
    {
      'placements': [
        for (final (id, o, at, _) in assemblyPieces(a))
          {
            'id': id,
            'at': [at.at.x, at.at.y, at.at.z],
            'rot': [at.rot.x, at.rot.y, at.rot.z, at.rot.w],
            // M248 — nothing about the mirror here, and that is the point of
            // reflecting the buffers rather than scaling the holder: a
            // mirrored component's placement IS a rigid transform, so a drag
            // stays the transform write per frame this push exists to be.
            'tint': assemblyTint(a, o,
                hoverId: hoverId, previewMaterial: previewMaterial),
          },
      ],
      'planes': [
        for (final key in kPlaneKeys)
          {'key': key, 'visible': a.vis[key] == true, 'hot': false},
        // M247 — a work plane's eye has to reach the device on the light push
        // as well, or toggling one would wait for whatever next moved the
        // scene signature.
        for (final w in a.workPlanes)
          {'key': w.id, 'visible': w.visible, 'hot': false},
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
      // M247 — the assembly's own work planes ride the SAME list, exactly as a
      // part's do in _planePayloads (M165). A work plane is a filled quad that
      // has to be depth-tested against the components, which is a thing the
      // screen-space HUD cannot do and the RealityKit scene already does — so
      // this is the one of the three work features that goes through the
      // payload, and the axes and points stay on the HUD.
      //
      // Sized by planeRectInBounds against the assembly's padded extent, which
      // is the very function the origin planes above go through: a work plane
      // frames the model the way they do rather than being a fixed square, and
      // the picker hit-tests the same rectangle.
      for (final w in a.workPlanes)
        planePayload(w.id, w.frame,
            planeRectInBounds(assemblyOriginExtent(a), w.frame),
            visible: w.visible, hot: false),
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
    // M273 — a mode switch rebuilds every material and adds or removes the
    // whole edge overlay: the heaviest rebuild there is, and one no light push
    // could express.
    //
    // An APPEARANCE needs no line here, unlike the part's: an assembly's light
    // push already carries a per-component tint (buildAssemblyOverlaysPayload)
    // because a selected component has always had to recolour on a drag.
    ..write(';view:')
    ..write(a.displayMode.id)
    ..write(';vis:');
  for (final k in const ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) {
    sb.write(a.vis[k] == true ? '1' : '0');
  }
  // M247 — the work planes' GEOMETRY is in the heavy push, and unlike a
  // component's it is not expressible as a placement the renderer can apply
  // itself: a re-solve changes the quad's corners. So the frame goes in the
  // signature, and a work feature that moves rebuilds the plane meshes and
  // nothing else. (gen already covers a feature being created or deleted.)
  sb.write(';wp:');
  for (final w in a.workPlanes) {
    final f = w.frame;
    sb
      ..write(w.id)
      ..write(w.visible ? '=' : '-')
      ..write(f.origin.x.toStringAsFixed(3))
      ..write(',')
      ..write(f.origin.y.toStringAsFixed(3))
      ..write(',')
      ..write(f.origin.z.toStringAsFixed(3))
      ..write(',')
      ..write(f.n.x.toStringAsFixed(4))
      ..write(',')
      ..write(f.n.y.toStringAsFixed(4))
      ..write(',')
      ..write(f.n.z.toStringAsFixed(4))
      ..write(';');
  }
  sb.write(';s:');
  for (final (id, _, at, s) in assemblyPieces(a)) {
    sb
      ..write(id)
      ..write('=')
      ..write(identityHashCode(s.mesh))
      // M248 — the HANDEDNESS is in the heavy signature, unlike the placement
      // beside it, because it is not something the renderer can apply to a
      // mesh it already holds: a mirrored solid travels with its triangle
      // winding reversed. Mirroring a component has to re-upload it.
      ..write(at.mirrored ? '*' : '')
      ..write(';');
  }
  return sb.toString();
}
