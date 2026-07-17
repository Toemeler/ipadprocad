// M34 — (a) Rechtecke sind VIER Linien mit Constraints (Inventor), nie mehr
// eine Polyline; (b) eine Rechteck-/Polygon-KANTE projiziert als EINZELNE
// gelbe Linie (proj + projSeg), die ihrer Quell-Kante folgt; (c) Hover im
// Project-Modus funktioniert auch auf Polylines (hoverEdge).
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
  group('rectangle = four lines (Inventor model)', () {
    test('two-point rect commits 4 LINES + coincident corners + H/V', () {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 70));
      final s = app.current!;
      expect(s.geometry, hasLength(4));
      expect(s.geometry.every((g) => g.type == Geo.line), isTrue,
          reason: 'never one polyline');
      final co =
          s.constraints.where((c) => c.type == CType.coincident).length;
      final h =
          s.constraints.where((c) => c.type == CType.horizontal).length;
      final v = s.constraints.where((c) => c.type == CType.vertical).length;
      expect(co, 4);
      expect(h, 2);
      expect(v, 2);
      // rectangle semantics survive the solver: dof = 4 (x, y, w, h)
      expect(analyzeSketch(s.geometry, s.constraints).dof, 4);
      // and each side is independently selectable
      app.tool = Tool.none;
      app.selectAt(const Offset(120, 40), 5);
      expect(app.selection, hasLength(1));
    });

    test('rect stays a rectangle when a corner is dragged (constraints)',
        () {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 70));
      final s = app.current!;
      final gs = List<Geo>.from(s.geometry);
      // stretch: move line0's end x from 140 to 160, solver must keep H/V +
      // corners glued
      gs[0] = gs[0].withData([100, 40, 160, 40]);
      solveConstraints(gs, s.constraints,
          dragged: const {(0, 1)}, iterations: 120);
      expect(gs[1].data[0], closeTo(gs[0].data[2], 1e-3),
          reason: 'right side follows the dragged corner');
      expect(gs[0].data[1], closeTo(gs[0].data[3], 1e-6), reason: 'bottom H');
      expect(gs[1].data[0], closeTo(gs[1].data[2], 1e-3), reason: 'right V');
    });

    test('3-point rect: 4 lines + coincident + 3 perpendicular, dof 5', () {
      final app = makeApp();
      app.tool = Tool.rect3P;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 50)); // rotated first edge
      app.toolClick(const Offset(130, 80));
      final s = app.current!;
      expect(s.geometry, hasLength(4));
      expect(
          s.constraints.where((c) => c.type == CType.perpendicular).length,
          3);
      expect(analyzeSketch(s.geometry, s.constraints).dof, 5,
          reason: 'x, y, w, h and the rotation stay free');
    });
  });

  group('edge projection of legacy polylines/polygons', () {
    AppState polyApp() {
      final app = makeApp();
      final s = app.current!;
      s.engine.setCurrentLayer('A');
      s.engine.addPolyline([0, 0, 40, 0, 40, 30, 0, 30], closed: true);
      s.refresh(tagSource: [
        Geo(Geo.polyline, const [1, 4, 0, 0, 40, 0, 40, 30, 0, 30],
            layer: 'A'),
      ]);
      s.layers
        ..clear()
        ..addAll(['A', 'B']);
      app.editingLayer = 'B';
      app.tool = Tool.project;
      return app;
    }

    test('clicking a polygon side projects THAT edge as one yellow line',
        () {
      final app = polyApp();
      app.toolClick(const Offset(40, 15)); // right edge
      final s = app.current!;
      final p = s.geometry.last;
      expect(p.type, Geo.line);
      expect(p.proj, 0);
      expect(p.projSeg, 1);
      expect(p.data, [40, 0, 40, 30]);
      // second edge of the SAME polyline is still projectable
      app.toolClick(const Offset(20, 30)); // top edge
      expect(app.current!.geometry.last.projSeg, 2);
      // ...but the same edge again is a duplicate
      final n = app.current!.geometry.length;
      app.toolClick(const Offset(40, 15));
      expect(app.current!.geometry, hasLength(n));
    });

    test('the projected edge TRACKS its source segment through the solver',
        () {
      final app = polyApp();
      app.toolClick(const Offset(40, 15)); // right edge (seg 1)
      final s = app.current!;
      final gs = List<Geo>.from(s.geometry);
      gs[0] = gs[0].withData([1, 4, 0, 0, 60, 0, 60, 30, 0, 30]); // widen
      solveConstraints(gs, s.constraints);
      expect(gs.last.data, [60, 0, 60, 30],
          reason: 'edge projection mirrors the moved source segment');
    });

    test('hover in project mode highlights the polyline EDGE', () {
      final app = polyApp();
      app.setHover(const Offset(40, 15));
      expect(app.hoverEnt, 0);
      expect(app.hoverEdge, (0, 1),
          reason: 'the halo painter needs hoverEdge for plain polylines');
      // an edge projection does not kill the highlight of the OTHER edges
      app.toolClick(const Offset(40, 15));
      app.setHover(const Offset(20, 30));
      expect(app.hoverEdge, (0, 2));
    });

    test('projSeg survives copy methods and the sidecar round-trip format',
        () {
      final g = Geo(Geo.line, const [0, 0, 1, 0]).withProj(3, 2);
      expect(g.withData(const [0, 0, 2, 0]).projSeg, 2);
      expect(g.onLayer('X').projSeg, 2);
      expect(g.withStyle(Geo.styleCenterline).projSeg, 2);
      expect(g.proj, 3);
    });
  });
}
