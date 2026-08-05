// M199/M200 — the retracted model browser.
//
//   "when the Modell browser is retracted i still want to see all icons from
//    it so layer and end of sketch and i dont want to see a Liquid Glass
//    background anymore when retracted jut transparent"
//   "...in 2d but also in 3d when i retract and expand Modell browser again"
//
// The first half was not a styling wish, it was a blank panel. Collapsing was
// a SEPARATE code path that drew only a part timeline: inside a sketch there
// is no part, so it returned `const []` and retracting while sketching showed
// nothing at all (bug20260805T112226 is exactly that state). In a part it
// dropped the folders instead.
//
// So collapsing is now a VIEW of the same tree — the rows it would have drawn,
// with the labels, the indentation and the eye taken off. That is one rule for
// 2D and 3D, and it makes the property below testable: the narrow panel and
// the wide one must list the same ids in the same order, or expanding again
// shows you a different document than the one you retracted.
import 'package:flutter_test/flutter_test.dart';
// GlassRow is the plugin's type; native_browser only builds them.
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
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
    buildBrowserRows(app, expanded: const {'bodies'}, collapsed: true);

List<GlassRow> wide(AppState app) =>
    buildBrowserRows(app, expanded: const {'bodies'});

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

  test('icons only — no labels at 56 pt wide', () {
    final rows = collapsed(insideSketch(layers: 3));
    for (final r in rows) {
      expect(r.label, isEmpty, reason: r.id);
      expect(r.symbol, isNotEmpty, reason: '${r.id} must still have a glyph');
    }
  });

  test('the marker sits where it sits, not always at the end', () {
    final rows = collapsed(insideSketch(layers: 2, eosAfter: 1));
    final ids = rows.map((r) => r.id).where((id) => id != 'root').toList();
    expect(ids, [
      '${kIdLayer}Layer 1',
      kIdEos,
      '${kIdLayer}Layer 2',
    ]);
  });

  test('THE CONTRACT: retracted lists the same ids, in the same order', () {
    // 2D and 3D both, because it is now one rule rather than two paths.
    for (final app in [
      insideSketch(layers: 2, eosAfter: 1),
      insideSketch()..activeChild = null, // the part, i.e. 3D
    ]) {
      expect(collapsed(app).map((r) => r.id).toList(),
          wide(app).map((r) => r.id).toList());
    }
  });

  test('3D keeps its folders when retracted — "all icons from it"', () {
    final app = insideSketch()..activeChild = null;
    final ids = collapsed(app).map((r) => r.id);
    expect(ids, contains('root'));
    expect(ids, contains('origin'),
        reason: 'the Origin folder used to be dropped by the collapse');
    expect(ids, contains(kIdEop));
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
    // make the narrow panel a picture of a browser. Compared against the wide
    // panel row for row, because that is the actual rule — compact() keeps
    // what the row had, and the document row never had a menu to keep.
    final app = insideSketch();
    final w = {for (final r in wide(app)) r.id: r.menu.length};
    for (final r in collapsed(app)) {
      expect(r.menu.length, w[r.id], reason: r.id);
    }
  });

  test('nothing is indented and nothing carries an eye at 56 pt', () {
    final app = insideSketch()..activeChild = null;
    for (final r in collapsed(app)) {
      expect(r.depth, 0, reason: '${r.id} — the glyph column must stay straight');
      expect(r.hasEye, isFalse, reason: r.id);
    }
  });

  test('with no document open, narrow and wide still agree', () {
    // The browser is not rendered on the home gallery at all, so what matters
    // here is only that the two widths cannot disagree.
    final app = AppState();
    expect(collapsed(app).map((r) => r.id).toList(),
        wide(app).map((r) => r.id).toList());
  });
}
