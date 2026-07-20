// M53 — END OF SKETCH marker (Inventor's End of Part, mapped onto layers).
// Pins the contract:
//   * the marker defaults to the END; new layers insert ABOVE it
//   * layers below the marker are rolled back: geoVisible false, their
//     constraints hidden, enterEdit refused, selection pruned
//   * moving the marker is ONE undoable step and perfectly lossless
//   * "Delete all layers below" removes layers + entities atomically (one
//     undo step), remaps constraint refs, and parks the marker at the end
//   * deleteLayer above the marker keeps the marker on the same layers
//   * the sidecar round-trips the marker (and pre-M53 files load at the end)

import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Draws one line on a fresh layer via the real tool path.
void drawLineOnNewLayer(AppState app) {
  app.startNewLayer();
  app.tool = Tool.line;
  app.toolClick(const Offset(0, 0));
  app.toolClick(const Offset(50, 0));
  app.finishEdit(save: false);
}

void main() {
  test('marker defaults to the end; startNewLayer inserts above it', () {
    final app = makeApp();
    final s = app.current!;
    expect(s.eosAfter, 0); // no layers yet == marker at the end

    drawLineOnNewLayer(app); // Layer 1
    drawLineOnNewLayer(app); // Layer 2
    expect(s.layers, ['Layer 1', 'Layer 2']);
    expect(s.eosAfter, 2); // still at the end

    // Roll back Layer 2, then create a layer: Inventor puts the new feature
    // just ABOVE the marker — Layer 2 must stay below, still rolled back.
    app.setEndOfSketch(1);
    app.startNewLayer(); // Layer 3
    expect(s.layers, ['Layer 1', 'Layer 3', 'Layer 2']);
    expect(s.eosAfter, 2);
    expect(app.layerRolledBack('Layer 2'), isTrue);
    expect(app.layerRolledBack('Layer 3'), isFalse);
    app.finishEdit(save: false);
  });

  test('rollback hides geometry + constraints, blocks editing, prunes '
      'selection; the move is lossless', () {
    final app = makeApp();
    final s = app.current!;
    drawLineOnNewLayer(app); // Layer 1
    drawLineOnNewLayer(app); // Layer 2
    final g2 = s.geometry.indexWhere((g) => g.layer == 'Layer 2');
    expect(g2, isNot(-1));

    app.selection.add(g2);
    app.setEndOfSketch(1);

    expect(app.layerRolledBack('Layer 2'), isTrue);
    expect(app.geoVisible(s.geometry[g2]), isFalse);
    expect(app.selection.contains(g2), isFalse, reason: 'selection pruned');
    // the line tool auto-constrains: every constraint touching the rolled
    // back entity must be hidden with it
    for (final c in s.constraints) {
      final touches =
          c.ents.contains(g2) || c.pts.any((p) => p.ent == g2);
      if (touches) expect(app.constraintVisible(s, c), isFalse);
    }

    app.enterEdit('Layer 2');
    expect(app.editingLayer, isNull, reason: 'below the marker: refused');

    // lossless round-trip
    app.setEndOfSketch(2);
    expect(app.geoVisible(s.geometry[g2]), isTrue);
    app.enterEdit('Layer 2');
    expect(app.editingLayer, 'Layer 2');
    app.finishEdit(save: false);
  });

  test('marker move is ONE undo step and restores exactly', () {
    final app = makeApp();
    final s = app.current!;
    drawLineOnNewLayer(app);
    drawLineOnNewLayer(app);
    final before = s.undoDepth;

    app.setEndOfSketch(1);
    expect(s.undoDepth, before + 1);
    expect(s.eosAfter, 1);

    app.undo();
    expect(s.eosAfter, 2);
    app.redo();
    expect(s.eosAfter, 1);
  });

  test('deleteBelowEndOfSketch: atomic, remapped, one undo step', () {
    final app = makeApp();
    final s = app.current!;
    drawLineOnNewLayer(app); // Layer 1
    drawLineOnNewLayer(app); // Layer 2
    drawLineOnNewLayer(app); // Layer 3
    final geoBefore = s.geometry.length;
    final consOnL1 = s.constraints.length; // per-layer autoconstraints exist

    app.setEndOfSketch(1); // Layer 2 + Layer 3 below
    final depth = s.undoDepth;
    final removed = app.deleteBelowEndOfSketch();

    expect(removed, 2);
    expect(s.layers, ['Layer 1']);
    expect(s.eosAfter, 1);
    expect(s.geometry.length, geoBefore - 2);
    expect(s.geometry.every((g) => g.layer == 'Layer 1'), isTrue);
    // every surviving constraint ref must still point INSIDE the list
    for (final c in s.constraints) {
      for (final e in c.ents) {
        expect(e < s.geometry.length, isTrue);
      }
      for (final p in c.pts) {
        expect(p.ent < s.geometry.length, isTrue);
      }
    }
    expect(s.undoDepth, depth + 1, reason: 'one atomic journal step');

    app.undo(); // the whole delete comes back in one step
    expect(s.layers, ['Layer 1', 'Layer 2', 'Layer 3']);
    expect(s.geometry.length, geoBefore);
    expect(s.constraints.length, greaterThanOrEqualTo(consOnL1));
  });

  test('deleteLayer above the marker keeps the marker on the same layers', () {
    final app = makeApp();
    final s = app.current!;
    drawLineOnNewLayer(app); // Layer 1
    drawLineOnNewLayer(app); // Layer 2
    drawLineOnNewLayer(app); // Layer 3
    app.setEndOfSketch(2); // Layer 3 rolled back

    app.deleteLayer('Layer 1');
    expect(s.layers, ['Layer 2', 'Layer 3']);
    expect(s.eosAfter, 1, reason: 'marker still right after Layer 2');
    expect(app.layerRolledBack('Layer 3'), isTrue);
    expect(app.layerRolledBack('Layer 2'), isFalse);
  });

  test('sidecar round-trips the marker; pre-M53 sidecars load at the end',
      () async {
    final dir = Directory.systemTemp.createTempSync('m53eos');
    addTearDown(() => dir.deleteSync(recursive: true));

    final app = makeApp(name: 'S');
    app.docsDirForTest = dir;
    drawLineOnNewLayer(app);
    drawLineOnNewLayer(app);
    app.setEndOfSketch(1);
    await app.saveSketch('S');

    final app2 = AppState()..docsDirForTest = dir;
    await app2.openSketch('S');
    final s2 = app2.current!;
    expect(s2.layers, ['Layer 1', 'Layer 2']);
    expect(s2.eosAfter, 1, reason: 'marker survives the round-trip');
    expect(app2.layerRolledBack('Layer 2'), isTrue);

    // strip the key -> a pre-M53 file: the marker must land at the END
    final lf = File('${dir.path}/sketches/S.layers.json');
    final txt = lf.readAsStringSync().replaceAll(RegExp(r',"eos":\d+'), '');
    lf.writeAsStringSync(txt);
    final app3 = AppState()..docsDirForTest = dir;
    await app3.openSketch('S');
    expect(app3.current!.eosAfter, app3.current!.layers.length);
  });
}
