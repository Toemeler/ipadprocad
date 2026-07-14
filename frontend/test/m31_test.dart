// M31 — tangent with a rectangle/polygon EDGE, and click-based resolution.
//
// From the device log (Sketch1): tangent spline+rectangle was built but then
// REJECTED "would over-constrain" — the residual had no case for a plain
// polyline partner, emitted a constant 0, the rank never grew, and the
// redundancy check killed the constraint. Additionally BOTH spline ends sat
// on rectangle corners, so "nearest end to the partner" was a tie: the end
// (and the edge) must be resolved from where the user actually clicked.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

Offset _pt(Geo g, int i) => Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]);

AppState makeApp(List<Geo> tagged) {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  for (final g in tagged) {
    switch (g.type) {
      case Geo.line:
        s.engine.addLine(g.data[0], g.data[1], g.data[2], g.data[3]);
        break;
      case Geo.circle:
        s.engine.addCircle(g.data[0], g.data[1], g.data[2]);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        s.engine.addPolyline(
            [
              for (var i = 0; i < n; i++) ...[
                g.data[2 + 2 * i],
                g.data[3 + 2 * i]
              ]
            ],
            closed: g.data[0] != 0);
        break;
    }
  }
  s.refresh(tagSource: tagged);
  app.tool = Tool.cTangent;
  return app;
}

void main() {
  test('USER SCENARIO: tangent spline + rectangle edge is ACCEPTED '
      'at the clicked end, not rejected as over-constraining', () {
    // the sketch from the device log, simplified to the same topology:
    // rectangle v0(0,0) v1(-202.4,0) v2(-202.4,210.61) v3(0,210.61) and an
    // open spline whose ends sit on TWO rectangle corners (v3 and v1).
    final rect = Geo(Geo.polyline,
        [1, 4, 0, 0, -202.4, 0, -202.4, 210.61, 0, 210.61]);
    final spline = Geo(Geo.polyline, [
      0, 5, //   open, 5 defining points
      0, 210.61, 213.9, 241.7, 356.4, 28.1, -189.1, -105.3, -202.4, 0,
    ]).asSpline(Geo.splineFit);
    final app = makeApp([rect, spline]);
    // the log's click order: rectangle LEFT edge first, then the spline
    // near its LAST point (p4 here) — the end at v1
    app.toolClick(const Offset(-202.4, 24.9)); // left edge body
    app.toolClick(const Offset(-190, -100)); //  spline near its p4 end
    final s = app.current!;
    final tangents =
        s.constraints.where((c) => c.type == CType.tangent).toList();
    expect(tangents, hasLength(1),
        reason: 'must be accepted — the residual now has a polyline case');
    final c = tangents.single;
    expect(c.pts[0], PRef(1, 4),
        reason: 'the CLICKED end (both ends touch the rectangle — the old '
            'nearest-to-partner heuristic tied and picked the wrong one)');
    expect(c.pts.sublist(1), [PRef(0, 1), PRef(0, 2)],
        reason: 'the clicked LEFT edge v1->v2');
    // and it actually constrains: one equation in the DOF analysis
    final without = List.of(s.constraints)..remove(c);
    expect(
        analyzeSketch(s.geometry, without).dof -
            analyzeSketch(s.geometry, s.constraints).dof,
        1);
  });

  test('solver: spline end tangent aligns with the rectangle edge', () {
    final gs = [
      Geo(Geo.polyline, [1, 4, 0, 0, 40, 0, 40, 30, 0, 30]),
      Geo(Geo.polyline, [0, 3, 40, 12, 60, 25, 80, 50]).asSpline(Geo.splineFit),
    ];
    final cs = [
      for (var v = 0; v < 4; v++)
        Constraint(CType.fix,
            pts: [PRef(0, v)],
            anchors: [gs[0].data[2 + 2 * v], gs[0].data[3 + 2 * v]]),
      Constraint(CType.fix, pts: [PRef(1, 1)], anchors: [60, 25]),
      Constraint(CType.fix, pts: [PRef(1, 2)], anchors: [80, 50]),
      // tangent to the RIGHT edge v1->v2 (vertical) at spline end 0
      Constraint(CType.tangent,
          ents: [0, 1], pts: [PRef(1, 0), PRef(0, 1), PRef(0, 2)]),
    ];
    solveConstraints(gs, cs);
    final d = _pt(gs[1], 1) - _pt(gs[1], 0);
    expect(d.dx.abs() / d.distance, lessThan(1e-4),
        reason: 'end chord must be VERTICAL like the right edge');
  });

  test('circle + rectangle edge: radius grows to touch the edge carrier',
      () {
    final gs = [
      Geo(Geo.polyline, [1, 4, 0, 0, 40, 0, 40, 30, 0, 30]),
      Geo(Geo.circle, [20, 45, 5]),
    ];
    final cs = [
      for (var v = 0; v < 4; v++)
        Constraint(CType.fix,
            pts: [PRef(0, v)],
            anchors: [gs[0].data[2 + 2 * v], gs[0].data[3 + 2 * v]]),
      Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [20, 45]),
      // tangent to the TOP edge v2->v3 (y = 30), center is 15 above it
      Constraint(CType.tangent,
          ents: [0, 1], pts: [PRef(0, 2), PRef(0, 3)]),
    ];
    solveConstraints(gs, cs);
    expect(gs[1].data[2], closeTo(15, 1e-4));
  });

  test('UI: circle + rectangle edge builds the edge-ref constraint', () {
    final app = makeApp([
      Geo(Geo.polyline, [1, 4, 0, 0, 40, 0, 40, 30, 0, 30]),
      Geo(Geo.circle, [20, 60, 12]),
    ]);
    app.toolClick(const Offset(32, 60)); // circle rim
    app.toolClick(const Offset(20, 30)); // top edge body
    final tangents =
        app.current!.constraints.where((c) => c.type == CType.tangent);
    expect(tangents, hasLength(1));
    expect(tangents.single.pts, [PRef(0, 2), PRef(0, 3)]);
  });

  test('UI: rectangle + rectangle stays rejected (nothing curved)', () {
    final app = makeApp([
      Geo(Geo.polyline, [1, 4, 0, 0, 40, 0, 40, 30, 0, 30]),
      Geo(Geo.polyline, [1, 4, 60, 0, 90, 0, 90, 30, 60, 30]),
    ]);
    app.toolClick(const Offset(20, 0));
    app.toolClick(const Offset(75, 0));
    expect(app.current!.constraints, isEmpty);
  });
}
