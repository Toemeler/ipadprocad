// M57 — 3D part gallery thumbnails and reliable preview refresh.
//
// What is pinned here (the device can't run in the host suite, but all of this
// is plain Dart + off-screen ui.Picture rendering, which flutter_test does
// execute):
//
//   * savePart writes <name>.png once a solid exists, and refreshSaved surfaces
//     it on the part's gallery card (kind 'part', preview non-null). A part
//     with no drawable solid gets NO png and any stale one is removed, so its
//     card honestly falls back to the steel-cube glyph.
//   * the png follows the part through delete / rename / duplicate — otherwise a
//     renamed part would show the wrong (or a phantom) thumbnail.
//   * flushCurrentDocument persists the OPEN document + preview unconditionally,
//     which is the fix for stale previews: it runs on goHome and on app
//     suspend even when the user was only viewing (finishEdit early-returns
//     there, and a fresh part had no preview at all). Works for 2D and 3D.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A kernel that hands back a one-triangle solid with a real mesh, so the
/// off-screen preview renderer has something to draw (the host build links no
/// OCCT). Mirrors the fake in m56_part_test.
class FakeKernel implements PartKernel {
  bool fail = false;
  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    if (fail) return null;
    return KernelSolid(
        OcctMeshData(
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
            Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
            Int32List.fromList(const [0, 1, 2]),
            Int32List.fromList(const [0, 3]),
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
        height,
        null);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      fail ? null : KernelSolid(a.mesh, a.volume + b.volume, null);

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) =>
      fail ? null : KernelSolid(base.mesh, base.volume - tool.volume, null);

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) =>
      fail ? null : KernelSolid(a.mesh, math.min(a.volume, b.volume), null);

  @override
  bool exportStep(List<KernelSolid> solids, String path) => false;

  // M217 — this fake implements EVERY member explicitly (no noSuchMethod), so
  // face surgery has to land here too. It models none of it, and says so.
  @override
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) => null;
  @override
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) =>
      null;
  @override
  KernelSolid? scaleSolid(KernelSolid base, Vec3 centre, double factor) => null;

  // M214 — this fake implements EVERY member explicitly (no noSuchMethod), so
  // a new member on PartKernel has to land here too. It writes nothing, like
  // exportStep above.
  @override
  bool exportStepBodies(List<(String, KernelSolid)> bodies, String path,
          {String product = ''}) =>
      exportStep([for (final b in bodies) b.$2], path);

  // M102 — the fake does not model revolve or body modification; saying so
  // honestly is what the feature will surface as its computeError.
  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
          double axPx, double axPy, double axDx, double axDy,
          List<double> mat34) =>
      null;
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => const [];
  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
          List<double> radii, {List<double> radii2 = const [], BlendReport? report}) =>
      null;
  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
          double d1, double d2, double angleDeg, {BlendReport? report}) =>
      null;

  @override
  List<KernelSolid> importStepSolids(String path) => const [];
  // M212 — the two placements a pattern needs. This fake models neither, and
  // says so rather than inventing a solid.
  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) => null;

  @override
  MeshImportOutcome meshToBrep(Float64List xyz, Int32List triangles,
          {double tolFraction = 0}) =>
      const MeshImportOutcome(
          null, MeshToBrepReport.empty(), 'fake kernel: no mesh converter');
  @override
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 planePoint, Vec3 planeNormal) =>
      null;
  @override
  List<double> revolveHits(KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p) =>
      const [];
  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
          List<double> pathPts,
          {int orientation = 0,
           double taperDeg = 0,
           double twistDeg = 0,
           int pathMode = SweepPathMode.auto}) =>
      null;
  @override
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
          {bool solid = true, bool ruled = false, bool closed = false}) =>
      null;
  @override
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
          Vec3 axP, Vec3 axD,
          {required double revolutions,
          required double height,
          double taperDeg = 0,
          bool clockwise = false}) =>
      null;
  @override
  List<double> revolveHitsFace(
          KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p, Vec3 facePoint) =>
      const [];
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest =
      Directory.systemTemp.createTempSync('prototype_m57_');
  return app;
}

/// The DXF-backed rectangle the sketcher produces — four separate lines.
void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {required String layer}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// New part -> sketch on xy -> 20x10 rectangle -> extrude 5 mm. Leaves the part
/// open (curTab == name) with one computed solid.
Future<AppState> partWithSolid(String name) async {
  final app = makeApp();
  app.partKernel = FakeKernel();
  await app.createNamedPart(name);
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: '5 mm');
  await app.applyExtrude();
  return app;
}

/// M177 — the preview lives INSIDE the document now, as its `preview.png`
/// entry. Read straight out of the file: that is the only copy that travels
/// with the part when it is moved or sent.
bool hasPreview(AppState app, String name) {
  final path = app.pathOfDocument(name);
  if (path == null) return false;
  final b = readDocEntry(path, kPreviewEntry);
  return b != null && b.isNotEmpty;
}

/// The staged working copy of the preview, which is what savePart writes
/// before packing.
File pngOf(AppState app, String name) =>
    File('${app.stageDirForTest(name).path}/$kPreviewEntry');

SavedSketchInfo? savedInfo(AppState app, String name) {
  for (final s in app.saved) {
    if (s.name == name) return s;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('part thumbnail', () {
    test('extruded part gets a png and the card shows it', () async {
      final app = await partWithSolid('Bracket');
      expect(hasPreview(app, 'Bracket'), isTrue,
          reason: 'savePart renders the 3D scene into the document');
      expect(pngOf(app, 'Bracket').lengthSync(), greaterThan(0));

      final info = savedInfo(app, 'Bracket');
      expect(info, isNotNull);
      expect(info!.kind, 'part');
      expect(info.preview, isNotNull,
          reason: 'refreshSaved must surface the part png, not null');
      expect(info.preview!.existsSync(), isTrue);
      expect(info.preview!.lengthSync(),
          readDocEntry(app.pathOfDocument('Bracket')!, kPreviewEntry)!.length,
          reason: 'the card shows the picture that is IN the document');
    });

    test('a part with no solid has no png and falls back to the cube', () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('Empty');
      expect(hasPreview(app, 'Empty'), isFalse);
      final info = savedInfo(app, 'Empty');
      expect(info, isNotNull);
      expect(info!.kind, 'part');
      expect(info.preview, isNull, reason: 'blank card -> steel cube glyph');
    });

    test('deleting a feature drops the stale png on next save', () async {
      final app = await partWithSolid('P');
      expect(hasPreview(app, 'P'), isTrue);
      // remove the only feature, then persist again
      app.currentPart!.features.clear();
      await app.savePart('P');
      expect(hasPreview(app, 'P'), isFalse,
          reason: 'no solid -> the previous thumbnail must be cleared');
      expect(savedInfo(app, 'P')?.preview, isNull,
          reason: 'and the stale card thumbnail goes with it');
    });
  });

  group('png follows the part through file ops', () {
    test('delete removes the png', () async {
      final app = await partWithSolid('P');
      final path = app.pathOfDocument('P')!;
      expect(hasPreview(app, 'P'), isTrue);
      await app.deleteDocument('P');
      expect(File(path).existsSync(), isFalse,
          reason: 'one file: deleting the document deletes the thumbnail too');
      expect(savedInfo(app, 'P'), isNull);
    });

    test('rename moves the png with the part', () async {
      final app = await partWithSolid('Old');
      expect(hasPreview(app, 'Old'), isTrue);
      await app.renameDocument('Old', 'New');
      expect(app.pathOfDocument('Old'), isNull);
      expect(hasPreview(app, 'New'), isTrue);
      expect(savedInfo(app, 'New')?.preview?.existsSync(), isTrue,
          reason: 'the renamed card must not show a phantom thumbnail');
    });

    test('duplicate copies the png', () async {
      final app = await partWithSolid('P');
      final copy = await app.duplicateDocument('P');
      expect(copy, isNotNull);
      expect(hasPreview(app, 'P'), isTrue);
      expect(hasPreview(app, copy!), isTrue,
          reason: 'the duplicate carries its own thumbnail');
    });
  });

  group('flushCurrentDocument refreshes previews', () {
    test('rewrites the part png even when not in edit mode', () async {
      final app = await partWithSolid('P');
      pngOf(app, 'P').deleteSync(); // simulate a stale/absent thumbnail
      expect(pngOf(app, 'P').existsSync(), isFalse);
      await app.flushCurrentDocument();
      expect(hasPreview(app, 'P'), isTrue,
          reason: 'flush persists the open part unconditionally');
    });

    test('goHome flushes the open part before leaving', () async {
      final app = await partWithSolid('P');
      pngOf(app, 'P').deleteSync();
      app.goHome();
      // goHome fires flush without awaiting; drain the microtask/IO queue.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(app.curTab, isNull, reason: 'we left the document');
      expect(hasPreview(app, 'P'), isTrue,
          reason: 'leaving a part for the gallery refreshes its card');
    });

    test('rewrites a 2D sketch png (finishEdit would have skipped it)',
        () async {
      final app = makeApp();
      await app.createNamedSketch('S');
      addRectLines(app.current!, 0, 0, 30, 20, layer: app.editingLayer!);
      await app.saveSketch('S');
      expect(hasPreview(app, 'S'), isTrue);

      // Leave edit mode: now finishEdit(save:true) would early-return and NOT
      // rewrite the thumbnail — flush must still do it.
      app.finishEdit(save: false);
      pngOf(app, 'S').deleteSync();
      await app.flushCurrentDocument();
      expect(hasPreview(app, 'S'), isTrue);
    });

    test('is a harmless no-op with no document open', () async {
      final app = makeApp();
      expect(app.curTab, isNull);
      await app.flushCurrentDocument(); // must not throw
    });
  });
}
