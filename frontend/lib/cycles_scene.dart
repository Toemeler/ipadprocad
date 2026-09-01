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
// during a drag. Here nothing drags — a render only ever starts from a
// standstill — so the placement is baked into the vertices and the scene
// arrives as world-space triangles. One convention instead of two.
import 'app_state.dart';
import 'cycles_boot.dart';
import 'cycles_session.dart';
import 'cycles_view.dart';
import 'materials.dart' show materialArgb;
import 'part_render.dart' show Cam3;
import 'reality_assembly.dart' show assemblyPieces, assemblySceneSignature;
import 'reality_scene.dart' show sceneSignature, visibleSolids;
import 'theme.dart' show T;

/// True when a path-traced image is the right thing to be showing.
///
/// Rendered mode, and a renderer to do it with. Every other display mode is a
/// WORKING view — shaded, wireframe, hidden-line — where the point is to see
/// the model's structure quickly, and a photograph of it would be in the way.
bool cyclesWanted(AppState app) => app.displayMode.isRendered && cyclesReady;

/// M333 — whether the render includes the ground plane.
///
/// The same document setting the RealityKit view reads (PartModel.showFloor,
/// AssemblyModel.showFloor, pushed as `floor` in the payload), so the toggle
/// in the ribbon means one thing rather than two. It is already part of
/// [cyclesSceneKey] — both scene signatures write it — so turning it off
/// invalidates the image on screen exactly as a geometry change would, with
/// nothing extra to remember here.
bool cyclesFloorWanted(AppState app) {
  final a = app.currentAssembly;
  if (a != null) return a.showFloor;
  return app.currentPart?.showFloor ?? false;
}

/// The signature of what is currently drawable, part or assembly.
///
/// The same string the RealityKit push uses to decide whether the scene
/// changed, so a change that reaches the renderer reaches this too — and one
/// that does not is a bug in both places at once rather than in this one
/// alone.
String cyclesSceneKey(AppState app) {
  final a = app.currentAssembly;
  if (a != null) return assemblySceneSignature(a, app: app);
  final p = app.currentPart;
  if (p == null) return '';
  return sceneSignature(app, p);
}

/// The meshes of whatever is on screen, in world coordinates, each carrying
/// the appearance its body was given.
///
/// SELECTION AND HOVER ARE NOT APPEARANCES and deliberately do not travel. The
/// working views tint the selected body because selection is a question you
/// just asked; a render is a picture of the model, and a part that comes out
/// orange because a browser row happened to be highlighted is a picture of the
/// UI. Only the material — the fact set once — reaches the renderer.
List<CyclesMesh> cyclesSceneMeshes(AppState app) {
  final a = app.currentAssembly;
  if (a != null) {
    final out = <CyclesMesh>[];
    for (final (_, o, at, s) in assemblyPieces(a, app: app)) {
      final m = cyclesMeshAt(s, at,
          material: cyclesMaterial(o.material, materialArgb(o.material)));
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
    final mid = byFeature[id];
    final m = cyclesMeshAt(s, null,
        material: cyclesMaterial(mid, materialArgb(mid)));
    if (m != null) out.add(m);
  }
  return out;
}

/// The job that renders what [app] is showing, seen through [cam], at
/// [width]x[height] pixels.
///
/// Expensive — it copies every vertex — and called only on a frame where the
/// render key changed. See [CyclesSession.offer].
CyclesJob cyclesSceneJob(AppState app, Cam3 cam, int width, int height,
    {int samples = kCyclesSamples}) {
  // Copied into a growable list: cyclesSceneMeshes returns a const empty one
  // when there is nothing open, and the floor below appends. That case cannot
  // reach the append today — an empty scene has no lowest point, so there is
  // no floor to add — but that is a fact two functions away, and this is one
  // line.
  final meshes = [...cyclesSceneMeshes(app)];
  final (halfW, halfH) = cyclesViewplane(cam);
  // ORDER MATTERS. The camera is placed from the reach of the MODEL, and the
  // floor is four times that across — computing the camera after adding it
  // would pull the eye back far enough to lose the part. The floor is sized
  // from the same list, before it is in it, for the same reason.
  final matrix = cyclesCameraMatrix(cam, cyclesMeshReach(meshes));
  if (cyclesFloorWanted(app)) {
    final floor = cyclesFloorMesh(meshes,
        argb: T.floor.toARGB32(),
        halfWidth: halfW,
        halfHeight: halfH,
        // Column 2 of the row-major 3x4 is the direction the camera looks.
        forwardY: matrix[6]);
    if (floor != null) meshes.add(floor);
  }
  return CyclesJob(
    meshes: meshes,
    matrix: matrix,
    halfWidth: halfW,
    halfHeight: halfH,
    width: width,
    height: height,
    samples: samples,
  );
}
