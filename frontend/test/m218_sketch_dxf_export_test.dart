// M218 — long-press a sketch in the 3D viewport and export THAT sketch as a
// DXF ("i want to be able to long press a sketch in 3d mode and export as dxf
// only this sketch from the context menu").
//
// Until now a part could only leave the app whole, as STEP. The thing a
// machine actually cuts, though, is one profile — and that profile was
// reachable only by rebuilding it as a separate 2D document.
//
// The UIKit half (the action sheet, the Files exporter, the share sheet)
// cannot run on the host, so what is pinned here is everything the device
// build depends on:
//
//   * the MENU CONTRACT — ids, order, labels. The Swift side does not know
//     these strings; `sketch3dMenuItems` is their only source, exactly as
//     `sketchMenuGroups` is for the gallery card.
//   * the GUARD that decides whether the press may open a menu at all
//     (`AppState.picking3D`): during a command the press belongs to that
//     command, and a menu on top of it would be a trap.
//   * the EXPORT itself — that a file appears, what it is called, what is in
//     it, and that M112's Defpoints rule for construction geometry holds
//     here too. A sketch inside a part is a sketch; scaffolding must not
//     reach the cutter just because the drawing lives in a part document.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/widgets/viewport3d.dart' show sketch3dMenuItems;

AppState _app() => AppState()
  ..docsDirForTest = Directory.systemTemp.createTempSync('prototype_m218_');

/// A part named "Bracket" holding one sketch: a 20x10 rectangle, and — when
/// [construction] is set — a circle tagged as construction geometry.
Future<AppState> _bracket({bool construction = false}) async {
  final app = _app();
  await app.createNamedPart('Bracket');
  app.startPartSketch();
  app.planePicked('xy');
  final s = app.activeChild!;
  s.engine.setCurrentLayer(app.editingLayer!);
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  if (construction) s.engine.addCircle(10, 5, 4);
  s.refresh();
  if (construction) {
    // The style is a Dart-side tag; the backend has no notion of it, which is
    // the whole reason the export has to move the entity onto a layer.
    s.geometry[s.geometry.length - 1] =
        s.geometry.last.withStyle(Geo.styleConstruction);
  }
  app.finishPartSketch();
  await app.savePart('Bracket');
  return app;
}

String _sketchOf(AppState app) =>
    app.parts['Bracket']!.childSketches.single.model.name;

/// The geometry a DXF actually holds, read back through the engine — so the
/// assertion is about the FILE and not about the model that wrote it.
List<Geo> _readDxf(String path) {
  final s = SketchModel('_read');
  try {
    expect(s.engine.loadDxf(path), isTrue, reason: 'the DXF must be readable');
    s.refresh();
    return List<Geo>.of(s.geometry);
  } finally {
    s.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the menu contract', () {
    test('four items, in the order the sheet shows them', () {
      final items = sketch3dMenuItems(L.stringsFor(kEn));
      expect(items.map((i) => i.id).toList(),
          ['skEdit', 'skVisible', 'skExportDxf', 'skShareDxf']);
      expect(items.map((i) => i.title).toList(),
          ['Edit Sketch', 'Hide', 'Export DXF…', 'Share DXF…']);
    });

    test('Edit and Hide keep the model browser ids', () {
      // Same command, same id: the two menus are two ways to the same place,
      // and a rename on one side that forgot the other would leave a dead row.
      final ids = sketch3dMenuItems(L.stringsFor(kEn)).map((i) => i.id);
      expect(ids, containsAll(['skEdit', 'skVisible']));
    });

    test('nothing in it is destructive', () {
      // Deliberate: Delete lives in the browser, where the row you press is
      // unambiguous. A long press in the viewport can land on a curve you did
      // not mean, and that must never be able to cost a sketch.
      expect(sketch3dMenuItems(L.stringsFor(kEn)).every((i) => !i.destructive),
          isTrue);
    });

    test('every item carries a glyph', () {
      expect(
          sketch3dMenuItems(L.stringsFor(kEn))
              .every((i) => (i.symbol ?? '').isNotEmpty),
          isTrue);
    });
  });

  group('picking3D — when the press may NOT open a menu', () {
    test('a plain part viewport is not picking anything', () async {
      final app = await _bracket();
      expect(app.picking3D, isFalse);
    });

    test('an armed plane pick claims the press', () async {
      final app = await _bracket();
      app.startPartSketch(); // "Start 2D Sketch" — waiting for a plane
      expect(app.pickPlane, isTrue);
      expect(app.picking3D, isTrue);
    });

    test('an edge pick claims the press', () async {
      final app = await _bracket();
      app.pickingEdges = true;
      expect(app.picking3D, isTrue);
    });

    test('a revolve-axis pick claims the press', () async {
      final app = await _bracket();
      app.pickingRevolveAxis = true;
      expect(app.picking3D, isTrue);
    });

    test('cancelling a command gives the press back', () async {
      final app = await _bracket();
      app.startPartSketch();
      app.escape3D();
      expect(app.picking3D, isFalse);
    });
  });

  group('exporting one sketch', () {
    test('writes a DXF named for the part AND the sketch', () async {
      final app = await _bracket();
      final path = await app.childSketchExportPath('Bracket', _sketchOf(app));

      expect(path, isNotNull);
      expect(path, endsWith('Bracket - ${_sketchOf(app)}.dxf'),
          reason: 'every part may call its first sketch "Sketch1"; the file '
              'name has to say which part it came from');
      expect(File(path!).existsSync(), isTrue,
          reason: 'export must never hand out a path that is not on disk yet');
      expect(File(path).lengthSync(), greaterThan(0));
    });

    test('the file holds the sketch geometry, in sketch coordinates',
        () async {
      final app = await _bracket();
      final gs = _readDxf(
          (await app.childSketchExportPath('Bracket', _sketchOf(app)))!);

      expect(gs.where((g) => g.type == Geo.line).length, 4,
          reason: 'the four sides of the rectangle');
      // The sketch is on XY at the origin, and the DXF carries its own 2D
      // coordinates — 0..20 by 0..10, not a placement in the part.
      for (final g in gs) {
        for (var i = 0; i < g.data.length; i += 2) {
          expect(g.data[i], inInclusiveRange(0, 20));
          expect(g.data[i + 1], inInclusiveRange(0, 10));
        }
      }
    });

    test('construction geometry ships on Defpoints, the rest does not',
        () async {
      // M112, on this side of the app too: construction geometry is only
      // construction because of a tag that the DXF cannot carry, so it goes
      // onto the layer every CAD package treats as non-plotting. Anyone
      // manufacturing from the file would otherwise cut the scaffolding.
      final app = await _bracket(construction: true);
      final gs = _readDxf(
          (await app.childSketchExportPath('Bracket', _sketchOf(app)))!);

      final circles = gs.where((g) => g.type == Geo.circle).toList();
      expect(circles, hasLength(1));
      expect(circles.single.layer, AppState.kDxfConstructionLayer);
      for (final g in gs.where((g) => g.type == Geo.line)) {
        expect(g.layer, isNot(AppState.kDxfConstructionLayer),
            reason: 'real geometry must stay on its own layer');
      }
    });

    test('the export is a COPY — the document keeps its own file', () async {
      final app = await _bracket();
      final path = await app.childSketchExportPath('Bracket', _sketchOf(app));
      expect(path, isNotNull);
      expect(path, isNot(contains('/sketches/')),
          reason: 'the storage file is never what gets shared');
      // And the part is still openable afterwards, with its sketch intact.
      expect(app.parts['Bracket']!.childSketches.single.model.geometry,
          hasLength(4));
    });

    test('a second export reflects an edit made in between', () async {
      // The flush is the point: what leaves the app has to be what is on
      // screen, not what happened to be on disk.
      final app = await _bracket();
      final name = _sketchOf(app);
      final first =
          _readDxf((await app.childSketchExportPath('Bracket', name))!);
      expect(first, hasLength(4));

      final s = app.parts['Bracket']!.childSketches.single.model;
      s.engine.addCircle(10, 5, 3);
      s.refresh();

      final second =
          _readDxf((await app.childSketchExportPath('Bracket', name))!);
      expect(second, hasLength(5),
          reason: 'a stale file from the previous export must not survive');
    });

    test('an unknown sketch exports nothing', () async {
      final app = await _bracket();
      expect(await app.childSketchExportPath('Bracket', 'Nope'), isNull);
    });

    test('an empty sketch exports nothing and says so', () async {
      final app = _app();
      await app.createNamedPart('Bracket');
      app.startPartSketch();
      app.planePicked('xy');
      app.finishPartSketch();
      await app.savePart('Bracket');

      expect(await app.childSketchExportPath('Bracket', _sketchOf(app)), isNull,
          reason: 'an empty DXF is worse than a refusal');
      // M234 — pinned to the l10n key, not to an English substring: the
      // message is German now, and a `contains('empty')` was only ever
      // checking that SOME message mentioned emptiness.
      expect(app.message,
          L.current.msgNothingToExportEmpty(_sketchOf(app)));
    });

    test('exporting from a CLOSED part does not open it', () async {
      // M214's rule, which this inherits by going through _loadPartModel:
      // exporting is not navigation.
      final app = await _bracket();
      final name = _sketchOf(app);
      await app.closeTab('Bracket');
      app.goHome();
      expect(app.parts.containsKey('Bracket'), isFalse);
      final tabsBefore = List<String>.of(app.openTabs);

      final path = await app.childSketchExportPath('Bracket', name);
      expect(path, isNotNull, reason: 'it still has to EXPORT');
      expect(_readDxf(path!), hasLength(4));

      expect(app.openTabs, tabsBefore,
          reason: 'Export must not add the part to the tab bar');
      expect(app.parts.containsKey('Bracket'), isFalse,
          reason: 'the headless copy must not be left in the session');
    });
  });
}
