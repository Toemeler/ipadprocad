// M25: dimensioning against the PROJECTED CENTER POINT, and ellipse axes as
// real constrained centerline entities.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  test('point + projected center point -> distance dimension', () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(30, 40, 100, 40);
    s.refresh(tagSource: [Geo(Geo.line, [30, 40, 100, 40])]);
    app.tool = Tool.dimension;
    app.toolClick(const Offset(30, 40)); //  line endpoint
    app.toolClick(Offset.zero); //           the projected CP
    expect(app.conPts, contains(const PRef(kProjCenter, 0)));
    app.toolClick(const Offset(55, -10)); // place out along the normal -> aligned
    expect(app.pendingDim, isNotNull);
    expect(app.pendingDim!.value, closeTo(50, 1e-9));
    // and the measurement itself resolves the sentinel via refPt
    expect(measureDim(s.geometry, app.pendingDim!), closeTo(50, 1e-9));
  });

  test('line + projected CP -> perpendicular distance', () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(-50, 25, 80, 25);
    s.refresh(tagSource: [Geo(Geo.line, [-50, 25, 80, 25])]);
    app.tool = Tool.dimension;
    app.toolClick(const Offset(10, 25)); // line body
    app.toolClick(Offset.zero); //          projected CP
    app.toolClick(const Offset(30, 12)); // place
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(25, 1e-9));
  });

  test('ellipse commit creates two constrained axis centerlines', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.ellipse;
    app.toolClick(const Offset(50, 40)); // center
    app.toolClick(const Offset(90, 40)); // major vertex (a=40)
    app.toolClick(const Offset(50, 55)); // minor extent (b=15)
    expect(s.geometry, hasLength(3), reason: 'ellipse + 2 axes');
    final maj = s.geometry[1], min = s.geometry[2];
    expect(maj.type, Geo.line);
    expect(maj.isCenterline, isTrue);
    expect(min.isCenterline, isTrue);
    // major axis spans quadrant+ to quadrant-
    expect(maj.data, [90, 40, 10, 40]);
    expect(min.data, [50, 55, 50, 25]);
    // 4 binding constraints (plus whatever inference added for the ellipse)
    final mid = s.constraints.where((c) => c.type == CType.midpoint);
    final coi = s.constraints.where((c) => c.type == CType.coincident);
    expect(mid.length, 2);
    expect(coi.length, greaterThanOrEqualTo(2));
  });

  test('axes follow the ellipse through the solver', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.ellipse;
    app.toolClick(const Offset(50, 40));
    app.toolClick(const Offset(90, 40));
    app.toolClick(const Offset(50, 55));
    // move the whole ellipse (center grip semantics), PIN it (a bare solve
    // without a pin lets least-squares drag both sides toward each other —
    // the app always solves with the dragged entity soft-pinned), re-solve
    final gs = List<Geo>.from(s.geometry);
    gs[0] = gs[0].withData([
      1, 3, 60, 50, 100, 50, 60, 65, // translated by (10,10)
    ]);
    final cs = List<Constraint>.from(s.constraints)
      ..add(Constraint(CType.fix,
          ents: [0], anchors: [60, 50, 100, 50, 60, 65]));
    solveConstraints(gs, cs);
    // the axis lines must have followed
    expect(gs[1].data[0], closeTo(100, 1e-3));
    expect(gs[1].data[1], closeTo(50, 1e-3));
    expect(gs[1].data[2], closeTo(20, 1e-3));
    expect(gs[1].data[3], closeTo(50, 1e-3));
    expect(gs[2].data, [
      closeTo(60, 1e-3),
      closeTo(65, 1e-3),
      closeTo(60, 1e-3),
      closeTo(35, 1e-3),
    ]);
  });

  test('centerline style survives the engine round-trip', () {
    final s = SketchModel('t');
    s.engine.addLine(0, 0, 10, 0);
    final tagged = [
      Geo(Geo.line, [0, 0, 10, 0]).withStyle(Geo.styleCenterline)
    ];
    s.refresh(tagSource: tagged);
    expect(s.geometry[0].isCenterline, isTrue);
    s.refresh(); // and again from its own state
    expect(s.geometry[0].isCenterline, isTrue);
  });
}
