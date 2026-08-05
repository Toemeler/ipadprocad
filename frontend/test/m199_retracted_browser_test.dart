// M199 — the retracted model browser, inside a sketch.
//
//   "when the Modell browser is retracted i still want to see all icons from
//    it so layer and end of sketch and i dont want to see a Liquid Glass
//    background anymore when retracted jut transparent"
//
// The first half was not a styling wish, it was a blank panel. The collapse
// path only knew how to draw a PART timeline, and inside a sketch there is no
// part (buildBrowserRows deliberately returns null for `part` while a child
// sketch is open), so it returned `const []`. Retracting the browser while
// sketching — which is most of the time — showed nothing whatsoever.
//
// bug20260805T112226 is exactly that state: Part4, one child sketch open, one
// layer, End of Sketch at the end.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

/// The device's document: a part with one child sketch, and that sketch open.
AppState insideSketch({int layers = 1, int? eosAfter}) {
  final app = AppState();
  final p = PartModel('Part4');
  final m = SketchModel('Sketch1');
  for (var i = 0; i < layers; i++) {
    m.layers.add('Layer ${i + 1}');
  }
  m.eosAfter = eosAfter ?? layers;
  // ChildSketch's third positional is the face frame, not a seq.
  p.childSketches.add(ChildSketch(m, 'xy'));
  app.parts['Part4'] = p;
  app.curTab = 'Part4';
  app.activeChild = m;
  app.editingLayer = 'Layer 1';
  return app;
}

List<GlassRow> collapsed(AppState app) =>
    buildBrowserRows(app, expanded: const {}, collapsed: true);

void main() {
  test('THE REPORT: retracted inside a sketch is no longer empty', () {
    final rows = collapsed(insideSketch());
    expect(rows, isNotEmpty,
        reason: 'this returned const [] — a blank strip while sketching');
  });

  test('the layer and the End of Sketch marker are both there', () {
    final rows = collapsed(insideSketch());
    expect(rows.map((r) => r.id), contains('${kIdLayer}Layer 1'));
    expect(rows.map((r) => r.id), contains(kIdEos));
  });

  test('icons only — no labels at 78 pt wide', () {
    final rows = collapsed(insideSketch(layers: 3));
    for (final r in rows) {
      expect(r.label, isEmpty, reason: r.id);
      expect(r.symbol, isNotEmpty, reason: '${r.id} must still have a glyph');
    }
  });

  test('the marker sits where it sits, not always at the end', () {
    // Two layers with the marker after the first: the retracted panel has to
    // show the same order the wide one does, or it is a different document.
    final rows = collapsed(insideSketch(layers: 2, eosAfter: 1));
    final ids = rows.map((r) => r.id).toList();
    expect(ids, [
      '${kIdLayer}Layer 1',
      kIdEos,
      '${kIdLayer}Layer 2',
    ]);
  });

  test('every id survives the collapse, so a tap does the same thing', () {
    final app = insideSketch(layers: 2, eosAfter: 2);
    final wide = buildBrowserRows(app, expanded: const {})
        .map((r) => r.id)
        .where((id) => id.startsWith(kIdLayer) || id == kIdEos)
        .toList();
    final narrow = collapsed(app).map((r) => r.id).toList();
    expect(narrow, wide);
  });

  test('the layer being edited stays marked when the labels go', () {
    // Which layer you are in is the one thing the canvas cannot tell you.
    final app = insideSketch(layers: 2, eosAfter: 2);
    app.editingLayer = 'Layer 2';
    final rows = collapsed(app);
    final sel = rows.where((r) => r.selected).map((r) => r.id);
    expect(sel, ['${kIdLayer}Layer 2']);
  });

  test('a hidden layer still reads as hidden', () {
    final app = insideSketch(layers: 2, eosAfter: 2);
    app.activeChild!.hiddenLayers.add('Layer 1');
    final rows = collapsed(app);
    final l1 = rows.firstWhere((r) => r.id == '${kIdLayer}Layer 1');
    expect(l1.dim, isTrue);
  });

  test('a layer below the marker is dimmed, like in the wide panel', () {
    final rows = collapsed(insideSketch(layers: 2, eosAfter: 1));
    final l2 = rows.firstWhere((r) => r.id == '${kIdLayer}Layer 2');
    expect(l2.dim, isTrue, reason: 'it is rolled back');
  });

  test('the context menus come along', () {
    // A retracted row is still a right-click target; losing the menus would
    // make the narrow panel a picture of a browser.
    final rows = collapsed(insideSketch());
    for (final r in rows) {
      expect(r.menu, isNotEmpty, reason: r.id);
    }
  });

  test('a part timeline still collapses the way it did', () {
    // The part path is untouched; this is the guard that says so.
    final app = insideSketch();
    app.activeChild = null; // back out to the part
    final rows = collapsed(app);
    expect(rows.map((r) => r.id), contains(kIdEop));
    for (final r in rows) {
      expect(r.label, isEmpty);
    }
  });

  test('no document, no rows', () {
    final app = AppState();
    expect(collapsed(app), isEmpty);
  });
}
