// M47 — DIRECT BODY DRAG. In the layer edit mode you can now grab a line /
// circle / arc / polyline / spline / ellipse by its BODY (not just a grip
// point) and translate the whole entity. It reuses the grip-drag lifecycle
// (beginBodyDrag → updateGripDrag → displayGeometry → endGripDrag) with a
// body-grip sentinel, so the same frame invariants apply: every shown frame is
// finite, non-degenerate and constraint-satisfying, and the committed sketch is
// satisfied too. A body drag is refused (like a locked point grip) when the
// entity has no remaining freedom, and connected geometry follows through the
// constraints — exactly Inventor's behaviour.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/diag.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/snap.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: tools + drags are live
  return app;
}

void drawLine(AppState app, Offset a, Offset b) {
  app.tool = Tool.line;
  app.toolClick(a);
  app.toolClick(b);
  app.cancelTool(); // clears the chained leftover point (CAD line chaining)
}

void drawCircle(AppState app, Offset c, Offset onRim) {
  app.tool = Tool.circleCenter;
  app.toolClick(c);
  app.toolClick(onRim);
  app.cancelTool();
}

/// Runs a body drag through the REAL app lifecycle, checking the per-frame
/// invariants, and returns whether the drag actually started (false = refused).
bool bodyDragAlong(AppState app, int entity, Offset grabAt, List<Offset> path) {
  final s = app.current!;
  app.beginBodyDrag(entity, grabAt);
  if (app.dragGrip == null) return false; // refused (fully constrained)
  for (final w in path) {
    app.updateGripDrag(w);
    final gs = app.displayGeometry(s);
    expect(allFinite(gs), isTrue, reason: 'frame must be finite');
    expect(hasDegenerateGeometry(gs), isFalse,
        reason: 'no zero-length line / r<=0 / zero-sweep arc may be shown');
    expect(constraintResidualNorm(gs, s.constraints), lessThan(1e-4),
        reason: 'a shown frame must satisfy the constraints');
  }
  app.endGripDrag();
  expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-4),
      reason: 'the committed sketch must satisfy the constraints');
  expect(hasDegenerateGeometry(s.geometry), isFalse);
  return true;
}

void expectPt(Offset got, Offset want, {double tol = 1e-6, String? why}) {
  expect((got - want).distance, lessThan(tol),
      reason: why ?? 'expected $want got $got');
}

void main() {
  group('translateGeo rigidly moves every entity type', () {
    test('line: both endpoints shift by delta', () {
      final g = Geo(Geo.line, [0, 0, 40, 0], layer: 'L1');
      final t = translateGeo(g, const Offset(10, 15));
      expect(t.data, [10, 15, 50, 15]);
      expect(t.layer, 'L1', reason: 'translate keeps the layer');
    });

    test('circle: center shifts, radius unchanged', () {
      final g = Geo(Geo.circle, [5, 5, 12]);
      final t = translateGeo(g, const Offset(-3, 7));
      expect(t.data, [2, 12, 12]);
    });

    test('arc: center shifts, radius + angles unchanged', () {
      final g = Geo(Geo.arc, [0, 0, 10, 0.5, 2.0, 0.0]);
      final t = translateGeo(g, const Offset(4, -6));
      expect(t.data, [4, -6, 10, 0.5, 2.0, 0.0]);
    });

    test('polyline / spline: every vertex shifts by delta', () {
      final g = Geo(Geo.polyline, [0.0, 3.0, 0, 0, 10, 0, 10, 10])
          .asSpline(Geo.splineCv);
      final t = translateGeo(g, const Offset(2, 2));
      expect(t.data, [0.0, 3.0, 2, 2, 12, 2, 12, 12]);
      expect(t.spline, Geo.splineCv, reason: 'translate keeps the spline tag');
    });
  });

  test('free line: body drag translates the whole line by the drag delta', () {
    final app = makeApp();
    final s = app.current!;
    // off the origin and NOT axis-aligned so nothing auto-binds/locks it
    drawLine(app, const Offset(10, 20), const Offset(50, 40));
    expect(s.geometry.length, 1);

    final started = bodyDragAlong(
        app, 0, const Offset(30, 30), // grab the middle of the line
        [const Offset(34, 35), const Offset(40, 45)]); // -> delta (10, 15)
    expect(started, isTrue);

    // both endpoints moved by exactly (10, 15)
    final g = s.geometry[0];
    expectPt(getPt(g, 0), const Offset(20, 35), tol: 1e-4);
    expectPt(getPt(g, 1), const Offset(60, 55), tol: 1e-4);
  });

  test('circle: body drag moves the center, keeps the radius', () {
    final app = makeApp();
    final s = app.current!;
    drawCircle(app, const Offset(50, 50), const Offset(60, 50)); // r = 10
    expect(s.geometry.single.type, Geo.circle);
    final r0 = s.geometry.single.data[2];

    final started = bodyDragAlong(
        app, 0, const Offset(60, 50), // grab a point on the rim
        [const Offset(62, 53), const Offset(65, 58)]); // -> delta (5, 8)
    expect(started, isTrue);

    final c = s.geometry.single;
    expectPt(Offset(c.data[0], c.data[1]), const Offset(55, 58), tol: 1e-4);
    expect((c.data[2] - r0).abs(), lessThan(1e-4),
        reason: 'a body translation must not change the radius');
  });

  test('locked line: a fully-constrained entity refuses the body drag', () {
    final app = makeApp();
    final s = app.current!;
    drawLine(app, const Offset(10, 20), const Offset(50, 40));
    // pin BOTH endpoints -> zero DOF
    s.constraints.add(Constraint(CType.fix, pts: const [PRef(0, 0)], anchors: const [10, 20]));
    s.constraints.add(Constraint(CType.fix, pts: const [PRef(0, 1)], anchors: const [50, 40]));
    app.analysis = analyzeSketch(s.geometry, s.constraints);
    expect(app.analysis!.freePoints, isEmpty,
        reason: 'both endpoints are fixed');

    app.beginBodyDrag(0, const Offset(30, 30));
    expect(app.dragGrip, isNull,
        reason: 'a locked entity must not start a body drag (Inventor)');

    // the geometry did not move
    expectPt(getPt(s.geometry[0], 0), const Offset(10, 20));
    expectPt(getPt(s.geometry[0], 1), const Offset(50, 40));
  });

  test('connected lines: dragging one carries the shared endpoint', () {
    final app = makeApp();
    final s = app.current!;
    drawLine(app, const Offset(10, 10), const Offset(50, 10)); // horizontal
    drawLine(app, const Offset(50, 10), const Offset(50, 40)); // vertical, joins
    expect(s.geometry.length, 2);
    expect(s.constraints.any((c) => c.type == CType.coincident), isTrue,
        reason: 'drawing line2 on line1s endpoint auto-adds a coincidence');

    final started = bodyDragAlong(
        app, 0, const Offset(30, 10), // grab line1s body
        [const Offset(30, 15), const Offset(30, 20)]); // -> delta (0, 10)
    expect(started, isTrue);

    // line1 translated up by 10
    expectPt(getPt(s.geometry[0], 0), const Offset(10, 20), tol: 1e-3);
    expectPt(getPt(s.geometry[0], 1), const Offset(50, 20), tol: 1e-3);
    // line2s SHARED bottom endpoint followed; its far end stayed put
    expectPt(getPt(s.geometry[1], 0), const Offset(50, 20), tol: 1e-3);
    expectPt(getPt(s.geometry[1], 1), const Offset(50, 40), tol: 1e-3);
  });
}
