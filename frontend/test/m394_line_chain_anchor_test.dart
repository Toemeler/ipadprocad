// M394 — #22: "one corner of the sketch has no point on point constraint but
// it should have made it automatically".
//
// Committing a line runs the solver, and the solver MOVES things: the
// constraints inference just added (a horizontal, a perpendicular to the
// previous segment) are equations the as-drawn points do not satisfy, so the
// endpoint settles a little away from where it was clicked. The chain then
// carried the raw click into the next line, which therefore started at a
// point the sketch no longer had — and inference, which compares at 1e-6, saw
// nothing to bind. The corner was held together by nothing, and the next
// solve pulled it apart: in the reported sketch the two ends of that corner
// ended up 0.04 mm apart.
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// The coincidence between point [pa] and point [pb], if inference made one.
bool joins(List<Constraint> cs, PRef pa, PRef pb) => cs.any((c) =>
    c.type == CType.coincident &&
    c.pts.length == 2 &&
    c.pts.contains(pa) &&
    c.pts.contains(pb));

void main() {
  test('the chain starts where the last line ENDED, not where it was clicked',
      () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    // A first segment drawn a third of a degree off horizontal. Inference
    // calls that horizontal (its tolerance is 1.5 deg) and the solve lays it
    // flat — so the end of the line is NOT the point that was clicked.
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(100, 0.5));
    expect(s.geometry, hasLength(1));
    final end = getPt(s.geometry[0], 1);
    expect(end.dy, closeTo(0, 1e-9), reason: 'the solve flattened it');
    expect(app.toolPoints.single, end,
        reason: 'the chain carries the SOLVED end, not the raw click');
  });

  test('so the next segment of a chain binds to the corner', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(100, 0.5)); // settles at (100, 0)
    app.toolClick(const Offset(100, 40)); // the second segment
    expect(s.geometry, hasLength(2));
    expect(joins(s.constraints, const PRef(0, 1), const PRef(1, 0)), isTrue,
        reason: 'the corner is a point-on-point coincidence '
            '(constraints: ${s.constraints.map((c) => c.toJson())})');
    // and it is one point, not two that merely look like one
    expect((getPt(s.geometry[0], 1) - getPt(s.geometry[1], 0)).distance,
        lessThan(1e-9));
  });

  test('a chain the solver never moves is unaffected', () {
    // The ordinary case: an exactly horizontal segment needs no correction,
    // so the solved end and the clicked point are the same place and the
    // chain behaves exactly as it always did.
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(100, 0));
    expect(app.toolPoints.single, const Offset(100, 0));
    app.toolClick(const Offset(100, 40));
    expect(joins(s.constraints, const PRef(0, 1), const PRef(1, 0)), isTrue);
  });
}
