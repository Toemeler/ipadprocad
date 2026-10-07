// The DOF / redundancy rank is computed on an EXACT Jacobian.
//
// A rectangle's two opposite sides are equal already (H/V + coincident
// corners), so "equal" on them adds no equation: Inventor refuses it and the
// DOF stays 4. The forward-difference Jacobian's O(h/L) noise made that row
// look independent — accepted, and the status bar then said 3 DOF.
//
// A tangency at a SEAM (the slot's and the corner fillet's arc shares its end
// with the line) must still count as one equation each.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';

AppState _app() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

(int, int) _opposite(SketchModel s, bool horizontal) {
  final ids = <int>[];
  for (var i = 0; i < s.geometry.length; i++) {
    final g = s.geometry[i];
    if (g.type != Geo.line) continue;
    final dx = (g.data[2] - g.data[0]).abs(),
        dy = (g.data[3] - g.data[1]).abs();
    if (horizontal ? dy < 1e-9 && dx > 0 : dx < 1e-9 && dy > 0) ids.add(i);
  }
  expect(ids, hasLength(2));
  return (ids[0], ids[1]);
}

void main() {
  for (final at in const [Offset(5, 3), Offset(100, 40), Offset(-850, 1200)]) {
    for (final horizontal in const [true, false]) {
      test(
          'equal on the two opposite ${horizontal ? 'horizontal' : 'vertical'} '
          'sides of a rectangle at $at is redundant', () {
        final app = _app();
        app.tool = Tool.rectTwoPoint;
        app.toolClick(at);
        app.toolClick(at + const Offset(37, 23));
        final s = app.current!;
        expect(analyzeSketch(s.geometry, s.constraints).dof, 4);
        final (a, b) = _opposite(s, horizontal);
        final eq = Constraint(CType.equal, ents: [a, b]);
        expect(wouldOverconstrain(s.geometry, s.constraints, eq), isTrue);
        final (rank, eqs, _) = debugRank(s.geometry, [...s.constraints, eq]);
        expect(eqs - rank, 1, reason: 'the equal row is implied');
        expect(analyzeSketch(s.geometry, [...s.constraints, eq]).dof, 4);
      });
    }
  }

  test('equal on two ADJACENT sides is a real equation (square): 3 DOF', () {
    final app = _app();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(137, 63));
    final s = app.current!;
    final (h, _) = _opposite(s, true);
    final (v, _) = _opposite(s, false);
    final eq = Constraint(CType.equal, ents: [h, v]);
    expect(wouldOverconstrain(s.geometry, s.constraints, eq), isFalse);
    expect(analyzeSketch(s.geometry, [...s.constraints, eq]).dof, 3);
  });

  test('slot seams stay one equation each: 13 independent rows, 5 DOF', () {
    final app = _app();
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(140, 40));
    app.toolClick(const Offset(120, 46));
    final s = app.current!;
    final (rank, eqs, params) = debugRank(s.geometry, s.constraints);
    expect(eqs - rank, 0);
    expect(params - rank, 5);
    // a parallel between the rails IS implied (equal caps tangent to both)
    final rails = [
      for (var i = 0; i < s.geometry.length; i++)
        if (s.geometry[i].type == Geo.line && !s.geometry[i].isConstruction) i
    ];
    expect(rails, hasLength(2));
    final par = Constraint(CType.parallel, ents: rails);
    expect(wouldOverconstrain(s.geometry, s.constraints, par), isTrue);
  });
}
