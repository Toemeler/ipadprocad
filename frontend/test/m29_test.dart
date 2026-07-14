// M29 — tangent constraint with SPLINES (Inventor: spline+line, spline+
// circle/arc, spline+spline act at the spline's ENDPOINT: its end tangent —
// which for both CV and fit splines runs along the two defining points at
// that end — is aligned with the other entity).
// M30 — keyboard shortcuts (tested in m30_test.dart).
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
  return app;
}

void main() {
  group('tangent with splines (M29)', () {
    test('spline end + line: solver aligns the end tangent with the line',
        () {
      // horizontal fixed line; open fit spline whose first chord starts at
      // 45 degrees. Tangency at spline end 0 must rotate that chord flat.
      final gs = [
        Geo(Geo.line, [0, 0, 40, 0]),
        Geo(Geo.polyline, [0, 3, 50, 0, 60, 10, 80, 30])
            .asSpline(Geo.splineFit),
      ];
      final cs = [
        Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [PRef(0, 1)], anchors: [40, 0]),
        Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [50, 0]),
        Constraint(CType.fix, pts: [PRef(1, 2)], anchors: [80, 30]),
        Constraint(CType.tangent, ents: [0, 1], pts: [PRef(1, 0)]),
      ];
      solveConstraints(gs, cs);
      final d = _pt(gs[1], 1) - _pt(gs[1], 0); // end chord = end tangent
      expect(d.dy.abs() / d.distance, lessThan(1e-4),
          reason: 'end tangent must be parallel to the horizontal line');
    });

    test('CV spline end + circle: end tangent perpendicular to the radius',
        () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        // open CV spline starting on the circle rim at (10, 0)
        Geo(Geo.polyline, [0, 4, 10, 0, 22, 4, 30, 15, 40, 30])
            .asSpline(Geo.splineCv),
      ];
      final cs = [
        Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.dimension, ents: [0], dimKind: 'rad', value: 10),
        Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [10, 0]),
        Constraint(CType.fix, pts: [PRef(1, 2)], anchors: [30, 15]),
        Constraint(CType.fix, pts: [PRef(1, 3)], anchors: [40, 30]),
        Constraint(CType.tangent, ents: [0, 1], pts: [PRef(1, 0)]),
      ];
      solveConstraints(gs, cs);
      final dir = _pt(gs[1], 1) - _pt(gs[1], 0);
      final rad = _pt(gs[1], 0) - Offset(gs[0].data[0], gs[0].data[1]);
      final dot = (dir.dx * rad.dx + dir.dy * rad.dy) /
          (dir.distance * rad.distance);
      expect(dot.abs(), lessThan(1e-4),
          reason: 'end tangent must be perpendicular to the radius');
    });

    test('tangency counts one equation in the DOF analysis', () {
      final gs = [
        Geo(Geo.line, [0, 0, 40, 0]),
        Geo(Geo.polyline, [0, 3, 50, 0, 60, 10, 80, 30])
            .asSpline(Geo.splineFit),
      ];
      final a0 = analyzeSketch(gs, []);
      final a1 = analyzeSketch(gs,
          [Constraint(CType.tangent, ents: [0, 1], pts: [PRef(1, 0)])]);
      expect(a0.dof - a1.dof, 1, reason: 'Inventor tangency is 1 DOF');
    });

    test('UI: line + open spline -> tangent with the NEAR end resolved', () {
      final spline = Geo(Geo.polyline, [0, 3, 50, 0, 60, 10, 80, 30])
          .asSpline(Geo.splineFit);
      final app = makeApp([Geo(Geo.line, [0, 0, 40, 0]), spline]);
      app.tool = Tool.cTangent;
      app.toolClick(const Offset(20, 0)); //  line body
      app.toolClick(const Offset(60, 10)); // spline (middle defining point)
      final s = app.current!;
      expect(s.constraints.where((c) => c.type == CType.tangent), hasLength(1));
      final c = s.constraints.firstWhere((c) => c.type == CType.tangent);
      expect(c.pts, [PRef(1, 0)],
          reason: 'end 0 at (50,0) is nearer to the line than end 2');
    });

    test('UI: CLOSED spline is rejected with a toast, no constraint', () {
      final closed = Geo(Geo.polyline, [1, 4, 0, 0, 20, 0, 20, 20, 0, 20])
          .asSpline(Geo.splineCv);
      final app = makeApp([Geo(Geo.line, [0, -20, 40, -20]), closed]);
      app.tool = Tool.cTangent;
      app.toolClick(const Offset(20, -20));
      app.toolClick(const Offset(10, 0));
      expect(app.current!.constraints.where((c) => c.type == CType.tangent),
          isEmpty);
    });

    test('UI: line + line is still rejected (needs a curved entity)', () {
      final app = makeApp(
          [Geo(Geo.line, [0, 0, 40, 0]), Geo(Geo.line, [0, 10, 40, 10])]);
      app.tool = Tool.cTangent;
      app.toolClick(const Offset(20, 0));
      app.toolClick(const Offset(20, 10));
      expect(app.current!.constraints, isEmpty);
    });

    test('regression: circle + line tangency still solves', () {
      final gs = [
        Geo(Geo.line, [0, 0, 40, 0]),
        Geo(Geo.circle, [20, 15, 10]),
      ];
      final cs = [
        Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [PRef(0, 1)], anchors: [40, 0]),
        Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [20, 15]),
        Constraint(CType.tangent, ents: [0, 1]),
      ];
      solveConstraints(gs, cs);
      expect(gs[1].data[2], closeTo(15, 1e-4),
          reason: 'radius must grow to touch the line');
    });
  });
}
