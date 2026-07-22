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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/occt_engine.dart';
import 'package:ipadprocad/part_model.dart';

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
  bool exportStep(List<KernelSolid> solids, String path) => false;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest =
      Directory.systemTemp.createTempSync('ipadprocad_m57_');
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

File pngOf(AppState app, String name) =>
    File('${app.docsDirForTest!.path}/sketches/$name.png');

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
      final png = pngOf(app, 'Bracket');
      expect(png.existsSync(), isTrue,
          reason: 'savePart renders the 3D scene to <name>.png');
      expect(png.lengthSync(), greaterThan(0));

      final info = savedInfo(app, 'Bracket');
      expect(info, isNotNull);
      expect(info!.kind, 'part');
      expect(info.preview, isNotNull,
          reason: 'refreshSaved must surface the part png, not null');
      expect(info.preview!.path, png.path);
    });

    test('a part with no solid has no png and falls back to the cube', () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('Empty');
      expect(pngOf(app, 'Empty').existsSync(), isFalse);
      final info = savedInfo(app, 'Empty');
      expect(info, isNotNull);
      expect(info!.kind, 'part');
      expect(info.preview, isNull, reason: 'blank card -> steel cube glyph');
    });

    test('deleting a feature drops the stale png on next save', () async {
      final app = await partWithSolid('P');
      expect(pngOf(app, 'P').existsSync(), isTrue);
      // remove the only feature, then persist again
      app.currentPart!.features.clear();
      await app.savePart('P');
      expect(pngOf(app, 'P').existsSync(), isFalse,
          reason: 'no solid -> the previous thumbnail must be cleared');
    });
  });

  group('png follows the part through file ops', () {
    test('delete removes the png', () async {
      final app = await partWithSolid('P');
      expect(pngOf(app, 'P').existsSync(), isTrue);
      await app.deleteDocument('P');
      expect(pngOf(app, 'P').existsSync(), isFalse);
    });

    test('rename moves the png with the part', () async {
      final app = await partWithSolid('Old');
      expect(pngOf(app, 'Old').existsSync(), isTrue);
      await app.renameDocument('Old', 'New');
      expect(pngOf(app, 'Old').existsSync(), isFalse);
      expect(pngOf(app, 'New').existsSync(), isTrue);
      expect(savedInfo(app, 'New')?.preview?.path, pngOf(app, 'New').path);
    });

    test('duplicate copies the png', () async {
      final app = await partWithSolid('P');
      final copy = await app.duplicateDocument('P');
      expect(copy, isNotNull);
      expect(pngOf(app, 'P').existsSync(), isTrue);
      expect(pngOf(app, copy!).existsSync(), isTrue,
          reason: 'the duplicate carries its own thumbnail');
    });
  });

  group('flushCurrentDocument refreshes previews', () {
    test('rewrites the part png even when not in edit mode', () async {
      final app = await partWithSolid('P');
      pngOf(app, 'P').deleteSync(); // simulate a stale/absent thumbnail
      expect(pngOf(app, 'P').existsSync(), isFalse);
      await app.flushCurrentDocument();
      expect(pngOf(app, 'P').existsSync(), isTrue,
          reason: 'flush persists the open part unconditionally');
    });

    test('goHome flushes the open part before leaving', () async {
      final app = await partWithSolid('P');
      pngOf(app, 'P').deleteSync();
      app.goHome();
      // goHome fires flush without awaiting; drain the microtask/IO queue.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(app.curTab, isNull, reason: 'we left the document');
      expect(pngOf(app, 'P').existsSync(), isTrue,
          reason: 'leaving a part for the gallery refreshes its card');
    });

    test('rewrites a 2D sketch png (finishEdit would have skipped it)',
        () async {
      final app = makeApp();
      await app.createNamedSketch('S');
      addRectLines(app.current!, 0, 0, 30, 20, layer: app.editingLayer!);
      await app.saveSketch('S');
      final png = File('${app.docsDirForTest!.path}/sketches/S.png');
      expect(png.existsSync(), isTrue);

      // Leave edit mode: now finishEdit(save:true) would early-return and NOT
      // rewrite the thumbnail — flush must still do it.
      app.finishEdit(save: false);
      png.deleteSync();
      await app.flushCurrentDocument();
      expect(png.existsSync(), isTrue);
    });

    test('is a harmless no-op with no document open', () async {
      final app = makeApp();
      expect(app.curTab, isNull);
      await app.flushCurrentDocument(); // must not throw
    });
  });
}
