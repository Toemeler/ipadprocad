// M193 — deleting one entity.
//
// Until now the smallest thing a sketch could lose was a whole LAYER: there was
// no per-entity delete anywhere in the app — not on a key, not in a menu, not
// on a button. Drawing one wrong line meant undoing back past everything drawn
// after it.
//
// What these tests pin is the part that goes silently wrong: index arithmetic.
// Geometry is addressed by INDEX, and constraints, dimensions and projection
// tags all hold those indices. Removing an entity from the middle shifts every
// index above it, so a delete that only removes geometry leaves dimensions
// measuring the wrong line — a corruption nobody notices until it is saved.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/widgets/quick_tools.dart';

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

/// A rectangle: four lines plus the constraints the rect tool creates.
AppState withRect() {
  final app = makeApp();
  app.tool = Tool.rectTwoPoint;
  app.toolClick(const Offset(0, 0));
  app.toolClick(const Offset(100, 80));
  app.tool = Tool.none;
  return app;
}

/// Every entity index any constraint refers to.
Set<int> refs(SketchModel s) => {
      for (final c in s.constraints) ...[
        ...c.ents,
        for (final p in c.pts) p.ent,
      ]
    };

void main() {
  test('a selected line is deleted and the rest of the sketch survives', () {
    final app = withRect();
    final s = app.current!;
    expect(s.geometry.length, 4);

    app.selection.add(1);
    expect(app.deleteSelection(), 1);
    expect(s.geometry.length, 3);
    expect(app.selection, isEmpty,
        reason: 'the indices just shifted — a stale selection points at the '
            'wrong entity');
  });

  test('no constraint is left pointing past the end of the geometry', () {
    // The failure this guards against: remove index 1 without remapping and
    // every reference to 2 and 3 now measures the wrong line, while a
    // reference to the last index dangles off the end.
    final app = withRect();
    final s = app.current!;
    expect(refs(s), isNotEmpty, reason: 'the rect tool constrains its corners');

    app.selection.add(0);
    app.deleteSelection();
    for (final i in refs(s)) {
      expect(i, lessThan(s.geometry.length),
          reason: 'constraint refers to entity $i of ${s.geometry.length}');
      expect(i, greaterThanOrEqualTo(0));
    }
  });

  test('deleting several at once is one step, not one per entity', () {
    final app = withRect();
    final s = app.current!;
    final before = s.undoDepth;
    app.selection.addAll([0, 2]);
    expect(app.deleteSelection(), 2);
    expect(s.geometry.length, 2);
    expect(s.undoDepth, before + 1,
        reason: 'one delete of two lines must undo in one press');
  });

  test('undo brings the deleted line back', () {
    final app = withRect();
    final s = app.current!;
    app.selection.add(3);
    app.deleteSelection();
    expect(s.geometry.length, 3);
    app.undo();
    expect(s.geometry.length, 4);
  });

  test('nothing is deletable outside edit mode', () {
    final app = withRect();
    final s = app.current!;
    app.selection.add(0);
    app.editingLayer = null;
    expect(app.canDeleteSelection, isFalse);
    expect(app.deleteSelection(), 0);
    expect(s.geometry.length, 4, reason: 'the layer is the editing scope');
  });

  test('geometry on another layer is never deleted', () {
    // The rect lives on the default layer; editing a different one must not
    // reach it, exactly like trim, drag and dimension cannot (M17).
    final app = withRect();
    final s = app.current!;
    s.layers.add('Layer 2');
    app.editingLayer = 'Layer 2';
    app.selection.addAll([0, 1, 2, 3]);
    expect(app.canDeleteSelection, isFalse);
    expect(app.deleteSelection(), 0);
    expect(s.geometry.length, 4);
  });

  test('an empty selection deletes nothing and says so', () {
    final app = withRect();
    expect(app.canDeleteSelection, isFalse);
    expect(app.deleteSelection(), 0);
    expect(app.current!.geometry.length, 4);
  });

  test('the Delete button appears with a selection, and appears LAST', () {
    final app = withRect();
    expect([for (final i in buildQuickTools(app)) i.id],
        isNot(contains(QuickToolId.delete)));

    app.selection.add(0);
    final ids = [for (final i in buildQuickTools(app)) i.id];
    expect(ids, contains(QuickToolId.delete));
    expect(ids.last, QuickToolId.delete,
        reason: 'arriving last means nothing above it moves under the thumb');

    final del =
        buildQuickTools(app).firstWhere((i) => i.id == QuickToolId.delete);
    expect(del.destructive, isTrue);
    expect(del.enabled, isTrue,
        reason: 'it only exists when it can act, so it is never dark');
    expect(del.symbol, isNotEmpty);
  });

  test('the bar button really deletes', () {
    final app = withRect();
    app.selection.add(0);
    runQuickTool(app, QuickToolId.delete);
    expect(app.current!.geometry.length, 3);
  });
}
