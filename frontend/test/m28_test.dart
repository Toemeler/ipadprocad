// M28 — polyline EDGES participate in dimensions like lines.
//
// A rectangle side is a segment of ONE closed polyline: it has no line-entity
// index, so point->edge, line->edge and edge->edge picks fell through the
// old matrix and were dead clicks (buildDimensionAt returned null or placed
// the wrong thing). Edges now live in conEdges and combine exactly like
// lines: perpendicular distance to a point, gap to a parallel line/edge, and
// the new 'ang4' angle (over four points — an edge has no entity ref) for
// the non-parallel case.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

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
  app.tool = Tool.dimension;
  return app;
}

// rectangle (0,0)-(40,30): v0..v3 = BL, BR, TR, TL; edge 0 = bottom
final rect = Geo(Geo.polyline, [1, 4, 0, 0, 40, 0, 40, 30, 0, 30]);

void main() {
  test('POINT then rectangle EDGE -> perpendicular pt-edge distance', () {
    // a line whose free endpoint hovers above the rect's bottom edge
    final app = makeApp([Geo(Geo.line, [-30, 12, -10, 12]), rect]);
    app.toolClick(const Offset(-10, 12)); // line endpoint (a point pick)
    expect(app.conPts, hasLength(1));
    app.toolClick(const Offset(20, 0)); //  bottom edge BODY (mid-edge)
    expect(app.conEdges, hasLength(1),
        reason: 'edge must EXTEND a point pick, not fall through');
    app.toolClick(const Offset(5, 6)); //   place
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(12, 1e-9));
  });

  test('LINE then rectangle EDGE (parallel) -> linear gap (pline)', () {
    final app = makeApp([Geo(Geo.line, [0, 50, 40, 50]), rect]);
    app.toolClick(const Offset(20, 50)); // line body
    expect(app.conEnts, [0]);
    app.toolClick(const Offset(20, 30)); // TOP edge body (parallel, gap 20)
    expect(app.conEdges, hasLength(1));
    app.toolClick(const Offset(20, 40)); // place
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(20, 1e-9));
  });

  test('LINE then rectangle EDGE (non-parallel) -> ang4 angle', () {
    // 45-degree line vs the horizontal bottom edge
    final app = makeApp([Geo(Geo.line, [-40, 0, -10, 30]), rect]);
    app.toolClick(const Offset(-25, 15)); // line body
    app.toolClick(const Offset(20, 0)); //   bottom edge body
    expect(app.conEdges, hasLength(1));
    app.toolClick(const Offset(0, 15)); //   place
    expect(app.pendingDim?.dimKind, 'ang4');
    expect(app.pendingDim?.value, closeTo(45, 1e-6));
  });

  test('EDGE then EDGE (adjacent rectangle sides) -> ang4 of 90', () {
    final app = makeApp([rect]);
    app.toolClick(const Offset(20, 0)); //  bottom edge -> its vertex pair
    expect(app.conPts, hasLength(2));
    expect(app.pickedEdge, isNotNull);
    app.toolClick(const Offset(40, 15)); // right edge -> second edge
    expect(app.conEdges, hasLength(1));
    app.toolClick(const Offset(30, 10)); // place
    expect(app.pendingDim?.dimKind, 'ang4');
    expect(app.pendingDim?.value, closeTo(90, 1e-6));
  });

  test('circle then rectangle EDGE -> center-to-edge distance', () {
    // rim far enough from the center that the ENTITY wins the pick (a rim
    // click within the point tolerance of the center picks the center point
    // instead — Inventor's vertex-over-edge priority, same result via pt+edge)
    final app = makeApp([Geo(Geo.circle, [20, 60, 15]), rect]);
    app.toolClick(const Offset(35, 60)); // circle rim
    expect(app.conEnts, [0]);
    app.toolClick(const Offset(20, 30)); // top edge body
    app.toolClick(const Offset(20, 45)); // place
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(30, 1e-9)); // center y=60 -> edge y=30
  });

  test('ang4 drives through the LM solver', () {
    // free line vs a fixed rectangle edge: drive the angle from 45 to 30
    final gs = [Geo(Geo.line, [-40, 0, -10, 30]), rect];
    final cs = [
      Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [0, 0]),
      Constraint(CType.fix, pts: [PRef(1, 1)], anchors: [40, 0]),
      Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [-40, 0]),
      Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1), PRef(1, 0), PRef(1, 1)],
          dimKind: 'ang4',
          value: 30),
    ];
    solveConstraints(gs, cs); // mutates gs in place
    final c = Constraint(CType.dimension,
        pts: [PRef(0, 0), PRef(0, 1), PRef(1, 0), PRef(1, 1)],
        dimKind: 'ang4');
    expect(measureDim(gs, c), closeTo(30, 1e-3));
  });

  test('regressions: pt-pt, line+point, line+line angle still intact', () {
    // point + point
    final app = makeApp([Geo(Geo.line, [0, 0, 30, 0]), Geo(Geo.line, [0, 20, 30, 20])]);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(0, 20));
    app.toolClick(const Offset(-10, 10));
    expect(app.pendingDim?.dimKind, anyOf('dist', 'disty'));
    expect(app.pendingDim?.value, closeTo(20, 1e-9));
    app.cancelDimension();
    // line + its off-line point -> perpendicular distance
    app.toolClick(const Offset(15, 0)); //  line 0 body
    app.toolClick(const Offset(0, 20)); //  endpoint of line 1
    app.toolClick(const Offset(8, 10));
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(20, 1e-9));
    app.cancelDimension();
    // line + line -> parallel gap here (both horizontal)
    app.toolClick(const Offset(15, 0));
    app.toolClick(const Offset(15, 20));
    app.toolClick(const Offset(8, 10));
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(20, 1e-9));
  });
}
