// M304 — what a Cycles render is a render OF.
//
// The one place that knows both halves: what the app currently has on screen
// (AppState, a part or an assembly, sectioned or not) and what the shim takes
// (flat 32-bit meshes and a camera matrix). It exists so that neither
// [CyclesSession] has to import AppState nor AppState has to know a mesh
// format.
//
// It also settles a question the RealityKit path answers differently. There,
// a component's placement rides on the entity and is rewritten per frame
// during a drag. Here the placement is baked into the vertices and the scene
// arrives as world-space triangles. One convention instead of two — and since
// M344 that costs nothing per frame either, because the vertices are uploaded
// when the MODEL changes and not when the camera does.
//
// ---------------------------------------------------------------------------
// M344 — WHERE THE LINE BETWEEN "SCENE" AND "VIEW" FALLS
// ---------------------------------------------------------------------------
//
// Everything in [cyclesSceneData] is one or the other, and the split has to be
// exact: anything on the scene side is megabytes and a GPU upload, anything on
// the view side is twelve floats sent thirty times a second.
//
// The awkward case is the FLOOR, which used to be both. It was sized from the
// viewplane (so a zoom changed the geometry) and dropped when the camera went
// below it (so an orbit did too). The size is fixed in M344 — see
// [kCyclesFloorSpan] — and what is left is one BIT: whether the camera is
// above the floor or under it. That bit is in the scene signature, so crossing
// the horizon rebuilds the scene, once, and every other frame of the orbit is
// twelve floats.
import 'dart:math' as math;

import 'app_state.dart';
import 'cycles_boot.dart';
import 'cycles_session.dart';
import 'cycles_view.dart';
import 'materials.dart' show materialArgb;
import 'part_render.dart' show Cam3;
import 'render_engine.dart';
import 'reality_assembly.dart' show assemblyPieces, assemblySceneSignature;
import 'reality_scene.dart' show sceneSignature, visibleSolids;
import 'theme.dart' show T;

/// True when a path-traced image is the right thing to be showing.
///
/// Rendered mode, and a renderer to do it with. Every other display mode is a
/// WORKING view — shaded, wireframe, hidden-line — where the point is to see
/// the model's structure quickly, and a photograph of it would be in the way.
bool cyclesWanted(AppState app) =>
    app.displayMode.isRendered && cyclesReady && RenderEngines.isCycles;

/// M333 — whether the render includes the ground plane.
///
/// The same document setting the RealityKit view reads (PartModel.showFloor,
/// AssemblyModel.showFloor, pushed as `floor` in the payload), so the toggle
/// in the ribbon means one thing rather than two. It is already part of
/// [cyclesSceneKey] — both scene signatures write it — so turning it off
/// invalidates the image on screen exactly as a geometry change would, with
/// nothing extra to remember here.
bool cyclesFloorWanted(AppState app) => app.showFloor;

/// The signature of what is currently drawable, part or assembly.
///
/// The same string the RealityKit push uses to decide whether the scene
/// changed, so a change that reaches the renderer reaches this too — and one
/// that does not is a bug in both places at once rather than in this one
/// alone.
String cyclesSceneKey(AppState app, Cam3 cam) {
  final base = () {
    final a = app.currentAssembly;
    if (a != null) return assemblySceneSignature(a, app: app);
    final p = app.currentPart;
    if (p == null) return '';
    return sceneSignature(app, p);
  }();
  if (base.isEmpty) return base;
  // The one bit of camera the GEOMETRY depends on. See the header.
  return '$base|${cyclesLookingDown(cam) ? 'd' : 'u'}';
}

/// Is the camera above the floor, looking down at it?
///
/// The Y component of the direction the camera LOOKS — column 2 of the matrix
/// [cyclesCameraMatrix] builds, which for this app's camera is -dir. Taken
/// from the camera rather than from the matrix so it can be asked before the
/// matrix is built, which is the order [cyclesSceneData] needs.
bool cyclesLookingDown(Cam3 cam) => cam.dir.y > 0;

/// The meshes of whatever is on screen, in world coordinates, each carrying
/// the appearance its body was given.
///
/// SELECTION AND HOVER ARE NOT APPEARANCES and deliberately do not travel. The
/// working views tint the selected body because selection is a question you
/// just asked; a render is a picture of the model, and a part that comes out
/// orange because a browser row happened to be highlighted is a picture of the
/// UI. Only the material — the fact set once — reaches the renderer.
List<CyclesMesh> cyclesSceneMeshes(AppState app, {bool environment = false}) {
  // M344: whether there is an HDRI decides what a metal IS, not merely how it
  // is lit — see [kCyclesMetallicNoEnvironment]. It travels down here rather
  // than being asked for per body because it is a fact about the scene.
  // M344 — AND STEEL IS AN APPEARANCE LIKE THE OTHERS. It used to be the
  // absence of one: materialArgb returns null for it, the mesh travelled with
  // no material, and the shim substituted its own. That still works and is
  // still the contract cycles_shim.h states — but it also meant the commonest
  // body in any assembly was the only one that could not carry a texture set
  // or become a real metal under an HDRI. So the app names it now, and the
  // shim's fallback is left for the warm-up and the render test, which is
  // where an unnamed material actually occurs.
  CyclesMaterial paint(String? id) =>
      cyclesMaterial(id, materialArgb(id), environment: environment) ??
      cyclesSteel(environment: environment);

  final a = app.currentAssembly;
  if (a != null) {
    final out = <CyclesMesh>[];
    for (final (_, o, at, s) in assemblyPieces(a, app: app)) {
      final m = cyclesMeshAt(s, at, material: paint(o.material));
      if (m != null) out.add(m);
    }
    return out;
  }
  final p = app.currentPart;
  if (p == null) return const [];
  // visibleSolids keys by FEATURE; materials are stored per BODY, and a body
  // is the name several features build into — the same indirection
  // _bodyRowTint walks for the shaded view.
  final byFeature = <String, String?>{
    for (final f in p.features) f.name: p.bodyMaterials[f.bodyName],
  };
  final out = <CyclesMesh>[];
  for (final (id, s) in visibleSolids(app, p)) {
    final m = cyclesMeshAt(s, null, material: paint(byFeature[id]));
    if (m != null) out.add(m);
  }
  return out;
}

/// The scene [app] is currently showing, in the form the renderer holds
/// between camera moves.
///
/// EXPENSIVE — it copies every vertex — and called only on a frame where the
/// SCENE key changed. See [CyclesSession.offer].
CyclesScene cyclesSceneData(AppState app, Cam3 cam,
    {bool environment = true}) {
  // Copied into a growable list: cyclesSceneMeshes returns a const empty one
  // when there is nothing open, and the floor below appends. That case cannot
  // reach the append today — an empty scene has no lowest point, so there is
  // no floor to add — but that is a fact two functions away, and this is one
  // line.
  final env = environment
      ? cyclesEnvFor(T.viewport.toARGB32())
      : CyclesEnv(world: cyclesWorld(T.viewport.toARGB32()));
  final meshes = [...cyclesSceneMeshes(app, environment: env.hasHdri)];
  // ORDER MATTERS. The reach the camera is placed from is the MODEL's, taken
  // before the floor is in the list, and the floor is sized from the same
  // number — a floor sized from a list that already contains a floor grows
  // without limit.
  final reach = cyclesMeshReach(meshes);
  if (cyclesFloorWanted(app)) {
    final floor = cyclesFloorMesh(meshes,
        argb: T.floor.toARGB32(), lookingDown: cyclesLookingDown(cam));
    if (floor != null) meshes.add(floor);
  }
  return CyclesScene(
    meshes: meshes,
    env: env,
    // The FLOOR's reach, not the model's, and only for the eye pullback. An
    // orthographic camera's position does not change what is in frame — only
    // the viewplane does — but it does decide what is behind the camera, and
    // Cycles clips that. A floor twelve times the part across, seen edge-on,
    // would otherwise have its far half behind the eye plane.
    reach: math.max(reach, cyclesMeshReach(meshes)),
  );
}

/// Where the camera is, for a scene of the given reach.
///
/// CHEAP, and it has to be: this runs on every frame of an orbit, where the
/// scene it is a view of has not moved at all.
CyclesViewParams cyclesViewParams(Cam3 cam, double reach) {
  final (halfW, halfH) = cyclesViewplane(cam);
  return CyclesViewParams(
    matrix: cyclesCameraMatrix(cam, reach),
    halfWidth: halfW,
    halfHeight: halfH,
  );
}
