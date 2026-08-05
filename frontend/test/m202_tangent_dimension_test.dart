// M202 — a dimension from a line to the NEAREST POINT of a circle.
//
//   "when i make a dimension from a line to a circle, also a dimension from
//    the line to the nearest point on the curve of the circle should be
//    possible. like in inventor. research inventor behavior here"
//
// Inventor, researched: since 2020 a 2D sketch can carry tangent dimensions to
// circular geometry. The interaction is the pick itself — select the line,
// then hover the CIRCLE'S EDGE near the tangent point and the glyph changes
// from the centre-distance symbol to the tangent one. So where you click
// decides, and that is exactly what is implemented here: click the middle of
// the circle for 'pline' (centre distance, unchanged), click its rim for
// 'plinetan'.
//
// The measure is the centre distance less the radius, which is what "the
// nearest point on the curve" means for a line that does not cut the circle.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// A horizontal line on y = 0 and a circle of r = 5 centred 20 above it, so
/// the centre distance is 20 and the tangent distance is 15.
AppState lineAndCircle() {
  final app = makeApp();
  final s = app.current!;
  s.engine.addLine(-40, 0, 40, 0);
  s.engine.addCircle(0, 20, 5);
  s.refresh();
  return app;
}

Constraint? dimOf(AppState app) {
  final ds = app.current!.constraints
      .where((c) => c.type == CType.dimension)
      .toList();
  return ds.isEmpty ? null : ds.last;
}

/// Drives the dimension tool: pick the line, pick the circle at [onCircle],
/// place the label, and confirm the value dialog the placement opens.
///
/// The third click only sets [AppState.pendingDim] — on the device that is
/// where the value editor appears — so a headless run has to answer it, the
/// same way flow_probe_test reads it. `null` keeps the measured value.
void dimension(AppState app, Offset onCircle) {
  app.selectTool(Tool.dimension);
  app.toolClick(const Offset(10, 0)); // the line
  app.toolClick(onCircle); // the circle
  app.toolClick(const Offset(30, 10)); // place
  if (app.pendingDim != null) app.confirmDimension(null);
}

void main() {
  test('clicking the RIM gives the tangent dimension', () {
    final app = lineAndCircle();
    dimension(app, const Offset(0, 25)); // top of the circle: the rim
    final d = dimOf(app);
    expect(d, isNotNull);
    expect(d!.dimKind, 'plinetan');
    expect(d.ents, isNotEmpty, reason: 'the radius has to come from somewhere');
  });

  test('clicking the MIDDLE still gives the centre distance', () {
    // The default this app has always produced must not move.
    final app = lineAndCircle();
    dimension(app, const Offset(0, 20.4)); // near the centre
    expect(dimOf(app)!.dimKind, 'pline');
  });

  test('the tangent dimension measures centre distance MINUS radius', () {
    final app = lineAndCircle();
    final s = app.current!;
    dimension(app, const Offset(0, 25));
    final d = dimOf(app)!;
    expect(measureDim(s.geometry, d), closeTo(15, 1e-6),
        reason: '20 to the centre, 5 of radius');
  });

  test('and the centre variant still measures 20', () {
    final app = lineAndCircle();
    final s = app.current!;
    dimension(app, const Offset(0, 20.4));
    expect(measureDim(s.geometry, dimOf(app)!), closeTo(20, 1e-6));
  });

  test('it DRIVES: setting it to 10 moves the circle, radius untouched', () {
    final app = lineAndCircle();
    final s = app.current!;
    dimension(app, const Offset(0, 25));
    final d = dimOf(app)!;
    app.setDimensionValue(d, 10);
    // WHICH of the two moves is the solver's business — nothing is fixed here,
    // so it is free to close the gap from either side. What the dimension
    // promises is the measure.
    expect(measureDim(s.geometry, d), closeTo(10, 1e-3));
    expect(s.geometry[1].data[2], closeTo(5, 1e-6),
        reason: 'a distance dimension must not resize the circle');
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
  });

  test('the solve counts it as exactly one equation', () {
    // A dimension that contributes nothing is a dimension that does not hold;
    // one that contributes twice makes the system singular.
    final app = lineAndCircle();
    final s = app.current!;
    final before = debugRank(s.geometry, s.constraints);
    dimension(app, const Offset(0, 25));
    final after = debugRank(s.geometry, s.constraints);
    expect(after.$2 - before.$2, 1, reason: 'one equation added');
    expect(after.$2 - after.$1, 0, reason: 'and it is independent');
  });

  test('it survives a save/load round trip', () {
    // dimKind rides in the sidecar as a plain string, so an unknown one would
    // silently become a dimension that measures nothing.
    final app = lineAndCircle();
    final s = app.current!;
    dimension(app, const Offset(0, 25));
    final json = encodeConstraints(s.constraints);
    final back = decodeConstraints(json);
    final d = back.lastWhere((c) => c.type == CType.dimension);
    expect(d.dimKind, 'plinetan');
    expect(d.ents, dimOf(app)!.ents);
    expect(measureDim(s.geometry, d), closeTo(15, 1e-6));
  });

  test('a line that CUTS the circle reads 0, not a negative gap', () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(-40, 19, 40, 19); // 1 below the centre: it cuts
    s.engine.addCircle(0, 20, 5);
    s.refresh();
    final d = Constraint(CType.dimension,
        pts: [const PRef(1, 0), const PRef(0, 0), const PRef(0, 1)],
        ents: [1],
        dimKind: 'plinetan',
        value: 0);
    expect(measureDim(s.geometry, d), 0);
  });
}
