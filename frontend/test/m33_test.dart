// M33 — Project Geometry Ausbau: ALLE Entity-Typen projizierbar (Kreis,
// Bogen, Spline, Ellipse, Polylinie), Hover-Highlight im Project-Modus,
// Project-Button leuchtet bis Escape, und Geometrie ANDERER Layer ist im
// Edit-Modus nicht mehr selektierbar (grau = nur Referenz).
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
  s.engine.setCurrentLayer('A');
  s.engine.addCircle(0, 0, 10); //                          e0
  s.engine.addArc(60, 0, 8, 0, 2.0); //                     e1
  s.engine.addPolyline([100, 0, 110, 12, 125, 30]); //      e2 (fit spline)
  s.engine.addPolyline([0, 60, 20, 60, 20, 75, 0, 75],
      closed: true); //                                     e3 (rectangle)
  final tags = [
    Geo(Geo.circle, const [0, 0, 10], layer: 'A'),
    Geo(Geo.arc, const [60, 0, 8, 0, 2.0], layer: 'A'),
    Geo(Geo.polyline, const [0, 3, 100, 0, 110, 12, 125, 30], layer: 'A')
        .asSpline(Geo.splineFit),
    Geo(Geo.polyline, const [1, 4, 0, 60, 20, 60, 20, 75, 0, 75], layer: 'A'),
  ];
  s.refresh(tagSource: tags);
  s.layers
    ..clear()
    ..addAll(['A', 'B']);
  app.editingLayer = 'B';
  app.tool = Tool.project;
  return app;
}

void main() {
  test('circle projects: same-type copy, radius pinned, tracks the source',
      () {
    final app = makeApp();
    app.toolClick(const Offset(10, 0)); // circle rim
    final s = app.current!;
    final p = s.geometry.last;
    expect(p.type, Geo.circle);
    expect(p.proj, 0);
    expect(p.layer, 'B');
    // pinned: no free params — and a solve on a grown source follows it
    final a = analyzeSketch(s.geometry, s.constraints);
    expect(a.freePoints.where((f) => f.$1 == s.geometry.length - 1), isEmpty);
    final gs = List<Geo>.from(s.geometry);
    gs[0] = gs[0].withData([5, 5, 20]); // move + grow the source
    solveConstraints(gs, s.constraints);
    expect(gs.last.data[0], closeTo(5, 1e-9));
    expect(gs.last.data[2], closeTo(20, 1e-9),
        reason: 'projected circle mirrors center AND radius');
  });

  test('arc and rectangle project as same-type copies', () {
    final app = makeApp();
    app.toolClick(const Offset(68, 0)); //  arc
    app.toolClick(const Offset(10, 60)); // rectangle bottom edge
    final s = app.current!;
    expect(s.geometry[4].type, Geo.arc);
    expect(s.geometry[4].proj, 1);
    expect(s.geometry[5].type, Geo.polyline);
    expect(s.geometry[5].proj, 3);
    expect(s.geometry[5].data[0], 1, reason: 'closed flag survives');
  });

  test('spline projects WITH its spline tag and stays pinned', () {
    final app = makeApp();
    app.toolClick(const Offset(110, 12)); // fit spline defining point area
    final s = app.current!;
    final p = s.geometry.last;
    expect(p.type, Geo.polyline);
    expect(p.spline, Geo.splineFit, reason: 'tag copied from the source');
    expect(p.proj, 2);
    final a = analyzeSketch(s.geometry, s.constraints);
    expect(a.freePoints.where((f) => f.$1 == s.geometry.length - 1), isEmpty);
  });

  test('hover in project mode: only unprojected geometry of OTHER layers',
      () {
    final app = makeApp();
    final s = app.current!;
    app.setHover(const Offset(10, 0)); // circle on layer A
    expect(app.hoverEnt, 0);
    app.toolClick(const Offset(10, 0)); // project it
    app.setHover(const Offset(10, 0));
    expect(app.hoverEnt, isNull,
        reason: 'already projected onto B: no highlight');
    app.setHover(const Offset(400, 400));
    expect(app.hoverEnt, isNull);
    // outside project mode the old editing-layer hover applies
    app.tool = Tool.none;
    app.setHover(const Offset(68, 0)); // arc on A, not editable from B
    expect(app.hoverEnt, isNull);
    expect(s.geometry[1].layer, 'A');
  });

  test('other-layer geometry is NOT selectable in edit mode; '
      'projections are', () {
    final app = makeApp();
    app.toolClick(const Offset(10, 0)); // project the circle onto B
    app.tool = Tool.none;
    final s = app.current!;
    final projIdx = s.geometry.length - 1;
    // tap on the circle: source (A) must not be picked, the projection (B)
    // lies on top and is the only selectable thing there
    app.selectAt(const Offset(10, 0), 10);
    expect(app.selection, {projIdx});
    // tap the un-projected arc on A: nothing selectable
    app.selectAt(const Offset(68, 0), 10);
    expect(app.selection, isEmpty);
    // box select over everything: only editing-layer geometry
    app.boxSelectUpdate(const Offset(-50, -50), const Offset(200, 100));
    app.boxSelectFinish();
    expect(app.selection, {projIdx});
  });

  test('outside edit mode selection still works across layers', () {
    final app = makeApp();
    app.tool = Tool.none;
    app.editingLayer = null;
    app.selectAt(const Offset(68, 0), 10);
    expect(app.selection, {1}, reason: 'viewing mode: everything tappable');
  });
}
