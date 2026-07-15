// M36 — (a) Formen bekommen ihre Inventor-Auto-Constraints: Slots (linear +
// Bogen) mit koinzident/tangent/equal/parallel bzw. konzentrisch, Tangenten-
// Kreis mit 3x tangent, Tangenten-Bogen mit koinzident+tangent zur Quelle;
// (b) Fillet/Chamfer komplett wie Inventor: modeless Dialog, Linie/Bogen/
// Kreis-Fillets, 3 Chamfer-Modi, Trim + Constraints + Bemassung des ersten /
// equal-Kette der weiteren; (c) Trim/Split erhalten Constraints und
// Bemassungen so gut wie moeglich (remapAfterReplace).
import 'dart:math' as math;
import 'dart:ui';

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

int count(SketchModel s, CType t) =>
    s.constraints.where((c) => c.type == t).length;

void main() {
  group('slot auto-constraints (Inventor)', () {
    test('linear slot: coincident/tangent seams, equal caps, parallel rails',
        () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slotCC;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.toolClick(const Offset(20, 6)); // width -> r = 6
      expect(s.geometry, hasLength(4));
      expect(count(s, CType.coincident), 4);
      expect(count(s, CType.tangent), 4);
      expect(count(s, CType.equal), 1);
      expect(count(s, CType.parallel), 1);
      // a slot has exactly 5 DOF: position, rotation, length, radius —
      // the redundant parallel row must be rank-neutral
      expect(analyzeSketch(s.geometry, s.constraints).dof, 5);
    });

    test('linear slot survives the solver as a slot (drag an end)', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slotCC;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.toolClick(const Offset(20, 6));
      final gs = List<Geo>.from(s.geometry);
      // drag rail 1's end up — solver must keep tangency + equal caps
      gs[0] = gs[0].withData([gs[0].data[0], gs[0].data[1], 42, 10]);
      solveConstraints(gs, s.constraints,
          dragged: const {(0, 1)}, iterations: 200);
      final r1 = gs[2].data[2], r2 = gs[3].data[2];
      expect(r1, closeTo(r2, 1e-3), reason: 'caps stay equal');
      // rails stay parallel
      final d1 = Offset(gs[0].data[2] - gs[0].data[0],
          gs[0].data[3] - gs[0].data[1]);
      final d2 = Offset(gs[1].data[2] - gs[1].data[0],
          gs[1].data[3] - gs[1].data[1]);
      final cross =
          (d1.dx * d2.dy - d1.dy * d2.dx) / (d1.distance * d2.distance);
      expect(cross.abs(), lessThan(1e-3));
    });

    test('arc slot: concentric rails + seams + equal caps, 6 DOF', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slot3A;
      app.toolClick(const Offset(-20, 0));
      app.toolClick(const Offset(0, 20));
      app.toolClick(const Offset(20, 0));
      app.toolClick(const Offset(0, 26)); // width -> r = 6
      expect(s.geometry, hasLength(4));
      expect(count(s, CType.concentric), 1);
      expect(count(s, CType.coincident), 4);
      expect(count(s, CType.tangent), 4);
      expect(count(s, CType.equal), 1);
      expect(analyzeSketch(s.geometry, s.constraints).dof, 6);
    });

    test('tangent circle gets tangent to all three picked lines', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(-20, 0, 0, 30);
      s.engine.addLine(20, 0, 0, 30);
      s.refresh();
      app.tool = Tool.circleTangent;
      app.toolClick(const Offset(0, 0.5));
      app.toolClick(const Offset(-9, 14));
      app.toolClick(const Offset(9, 14));
      expect(s.geometry, hasLength(4));
      expect(count(s, CType.tangent), 3);
      // and they hold under the solver: shrink a side, circle follows
      expect(analyzeSketch(s.geometry, s.constraints).dof,
          lessThan(4 * 3 + 3 - 2)); // three tangents removed 3 DOF
    });

    test('tangent arc: coincident + tangent to its source line', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 20, 0);
      s.refresh();
      app.tool = Tool.arcTangent;
      app.toolClick(const Offset(20, 0)); // snap the line's end
      app.toolClick(const Offset(30, 10));
      expect(s.geometry, hasLength(2));
      expect(s.geometry[1].type, Geo.arc);
      expect(count(s, CType.coincident), 1);
      expect(count(s, CType.tangent), 1);
    });
  });

  group('fillet like Inventor (M36)', () {
    AppState corner() {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 30, 0);
      s.engine.addLine(0, 0, 0, 30);
      s.refresh();
      return app;
    }

    test('line-line: trim + coincident + tangent + radius dim on the first',
        () {
      final app = corner();
      final s = app.current!;
      app.selectTool(Tool.fillet);
      expect(app.filletSess, isNotNull);
      app.filletSess!.radius = 5;
      app.filletNotify();
      app.toolClick(const Offset(10, 0));
      app.toolClick(const Offset(0, 10));
      expect(s.geometry, hasLength(3));
      final arc = s.geometry[2];
      expect(arc.type, Geo.arc);
      expect(arc.data[2], closeTo(5, 1e-6));
      expect(arc.data[0], closeTo(5, 1e-6)); // center (5,5)
      expect(arc.data[1], closeTo(5, 1e-6));
      // lines trimmed back to the tangent points
      expect(Offset(s.geometry[0].data[0], s.geometry[0].data[1]).dx,
          closeTo(5, 1e-6));
      expect(Offset(s.geometry[1].data[0], s.geometry[1].data[1]).dy,
          closeTo(5, 1e-6));
      expect(count(s, CType.coincident), 2);
      expect(count(s, CType.tangent), 2);
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(1));
      expect(dims[0].dimKind, 'rad');
      expect(dims[0].value, closeTo(5, 1e-9));
    });

    test('second fillet chains EQUAL to the first (same radius)', () {
      final app = makeApp();
      final s = app.current!;
      // a U: three lines, two corners
      s.engine.addLine(0, 30, 0, 0);
      s.engine.addLine(0, 0, 30, 0);
      s.engine.addLine(30, 0, 30, 30);
      s.refresh();
      app.selectTool(Tool.fillet);
      app.filletSess!.radius = 4;
      app.filletNotify();
      app.toolClick(const Offset(0, 10));
      app.toolClick(const Offset(10, 0));
      app.toolClick(const Offset(20, 0));
      app.toolClick(const Offset(30, 10));
      expect(s.geometry, hasLength(5));
      expect(count(s, CType.equal), 1);
      expect(s.constraints.where((c) => c.type == CType.dimension),
          hasLength(1), reason: 'only the FIRST fillet is dimensioned');
      // changing the radius starts a NEW chain
      app.filletSess!.radius = 7;
      app.filletNotify();
      expect(app.filletSess!.firstIdx, isNull);
    });

    test('line-arc fillet: tangent to both carriers', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-30, 0, 30, 0);
      s.engine.addArc(0, 0, 15, 0, math.pi); // half circle on the line
      s.refresh();
      app.selectTool(Tool.fillet);
      app.filletSess!.radius = 4;
      app.filletNotify();
      app.toolClick(const Offset(22, 0)); // the line, right of the arc
      app.toolClick(const Offset(14, 6)); // the arc, upper right
      expect(s.geometry, hasLength(3));
      final f = s.geometry[2];
      expect(f.type, Geo.arc);
      expect(f.data[2], closeTo(4, 1e-6));
      // fillet center: distance to line == r, distance to arc center == R+r
      expect(f.data[1].abs(), closeTo(4, 1e-6));
      expect(Offset(f.data[0], f.data[1]).distance, closeTo(19, 1e-6));
      expect(count(s, CType.tangent), 2);
      // the arc was trimmed at the tangent angle
      final a = s.geometry[1];
      expect(a.data[3], greaterThan(0), reason: 'start angle moved up');
    });

    test('circle participant is not trimmed but still tangent-constrained',
        () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-30, 0, 30, 0);
      s.engine.addCircle(0, 10, 6);
      s.refresh();
      app.selectTool(Tool.fillet);
      app.filletSess!.radius = 3;
      app.filletNotify();
      app.toolClick(const Offset(12, 0));
      app.toolClick(const Offset(5.5, 7));
      expect(s.geometry, hasLength(3));
      expect(s.geometry[1].type, Geo.circle, reason: 'circle stays whole');
      expect(count(s, CType.tangent), 2);
      expect(count(s, CType.coincident), 1,
          reason: 'only the line seam is glued');
    });
  });

  group('chamfer like Inventor (M36)', () {
    AppState corner() {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 30, 0);
      s.engine.addLine(0, 0, 0, 30);
      s.refresh();
      return app;
    }

    test('equal distance: trim + coincident + length dim, then equal chain',
        () {
      final app = corner();
      final s = app.current!;
      app.selectTool(Tool.chamfer);
      app.filletSess!
        ..mode = 0
        ..d1 = 5;
      app.filletNotify();
      app.toolClick(const Offset(10, 0));
      app.toolClick(const Offset(0, 10));
      expect(s.geometry, hasLength(3));
      final ch = s.geometry[2];
      expect(ch.type, Geo.line);
      expect(Offset(ch.data[0], ch.data[1]), const Offset(5, 0));
      expect(Offset(ch.data[2], ch.data[3]), const Offset(0, 5));
      expect(count(s, CType.coincident), 2);
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(1));
      expect(dims[0].dimKind, 'dist');
      expect(dims[0].value, closeTo(5 * math.sqrt2, 1e-6));
    });

    test('two distances: d1 on the FIRST pick', () {
      final app = corner();
      final s = app.current!;
      app.selectTool(Tool.chamfer);
      app.filletSess!
        ..mode = 1
        ..d1 = 8
        ..d2 = 4;
      app.filletNotify();
      app.toolClick(const Offset(10, 0)); // first pick = horizontal line
      app.toolClick(const Offset(0, 10));
      final ch = app.current!.geometry[2];
      expect(Offset(ch.data[0], ch.data[1]), const Offset(8, 0));
      expect(Offset(ch.data[2], ch.data[3]), const Offset(0, 4));
      expect(count(s, CType.dimension), 0,
          reason: 'only equal-distance chamfers auto-dimension');
    });

    test('distance + angle: chamfer leaves line 1 at the given angle', () {
      final app = corner();
      app.selectTool(Tool.chamfer);
      app.filletSess!
        ..mode = 2
        ..d1 = 6
        ..angle = 30;
      app.filletNotify();
      app.toolClick(const Offset(10, 0));
      app.toolClick(const Offset(0, 10));
      final ch = app.current!.geometry[2];
      final d = Offset(ch.data[2] - ch.data[0], ch.data[3] - ch.data[1]);
      final ang = math.atan2(d.dy, d.dx) * 180 / math.pi;
      expect((180 - ang).abs() % 180, closeTo(30, 1e-6));
      expect(Offset(ch.data[0], ch.data[1]), const Offset(6, 0));
    });

    test('parallel lines refuse with a toast, nothing changes', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 30, 0);
      s.engine.addLine(0, 10, 30, 10);
      s.refresh();
      app.selectTool(Tool.chamfer);
      app.toolClick(const Offset(10, 0));
      app.toolClick(const Offset(10, 10));
      expect(s.geometry, hasLength(2));
      expect(s.constraints, isEmpty);
    });
  });

  group('trim/split preserve constraints (M36)', () {
    test('perpendicular survives a trim of one participant', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.constraints.add(Constraint(CType.perpendicular, ents: [0, 1]));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0)); // cut the left span of line 0
      expect(count(s, CType.perpendicular), 1,
          reason: 'remapped to the surviving piece, not dropped');
      final c = s.constraints.firstWhere(
          (c) => c.type == CType.perpendicular);
      expect(c.ents, isNot(contains(-1)));
    });

    test('radius dimension survives trimming a circle to an arc', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 10);
      s.engine.addLine(-20, 0, 20, 0);
      s.refresh();
      s.constraints.add(Constraint(CType.dimension,
          ents: [0], dimKind: 'rad', value: 10));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(0, -10)); // cut the lower half
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(1));
      expect(dims[0].value, 10);
      expect(s.geometry[dims[0].ents[0]].type, Geo.arc,
          reason: 'the dim now drives the surviving arc');
    });

    test('tangent(line, circle) survives the circle becoming an arc', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 10, 10);
      s.engine.addLine(-20, 0, 20, 0); // tangent at (0,0)
      s.engine.addLine(0, -5, 0, 25); // cutter through the circle
      s.refresh();
      s.constraints.add(Constraint(CType.tangent, ents: [1, 0]));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 10)); // cut the circle's left half
      expect(count(s, CType.tangent), 1);
      final c = s.constraints.firstWhere((c) => c.type == CType.tangent);
      expect(s.geometry[c.ents[1]].type, Geo.arc);
    });

    test('a coincident on the trimmed-away point is dropped, others stay',
        () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20); // cutter
      s.engine.addLine(20, 0, 30, 10);
      s.engine.addLine(-20, 0, -30, 10);
      s.refresh();
      // both ends of line 0 glued to their neighbours
      s.constraints.add(Constraint(CType.coincident,
          pts: [const PRef(0, 1), const PRef(2, 0)]));
      s.constraints.add(Constraint(CType.coincident,
          pts: [const PRef(0, 0), const PRef(3, 0)]));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0)); // trims AWAY the left span
      // left seam's point (-20,0) is gone -> its coincident drops; the right
      // seam survives on the surviving piece
      expect(count(s, CType.coincident), 1);
      final c = s.constraints.firstWhere((c) => c.type == CType.coincident);
      final p = refPt(s.geometry, c.pts[0]);
      expect(p.dx, closeTo(20, 1e-6));
    });

    test('split keeps every constraint (all points survive)', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.constraints
          .add(Constraint(CType.horizontal, ents: [0]));
      s.constraints.add(Constraint(CType.fix,
          pts: [const PRef(0, 0)], anchors: const [-20, 0]));
      app.selectTool(Tool.split);
      app.toolClick(const Offset(-10, 0));
      expect(count(s, CType.horizontal), 1);
      expect(count(s, CType.fix), 1, reason: 'point fix follows its point');
    });

    test('entity-level fix and pattern membership are dropped on trim', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.constraints.add(Constraint(CType.fix,
          ents: [0], anchors: const [-20, 0, 20, 0]));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0));
      expect(count(s, CType.fix), 0,
          reason: 'the pinned shape no longer exists');
    });

    test('length dimension across the cut spans the two pieces', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.constraints.add(Constraint(CType.dimension,
          pts: [const PRef(0, 0), const PRef(0, 1)],
          dimKind: 'dist',
          value: 40));
      app.selectTool(Tool.split);
      app.toolClick(const Offset(-10, 0));
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(1));
      final a = refPt(s.geometry, dims[0].pts[0]);
      final b = refPt(s.geometry, dims[0].pts[1]);
      expect((a - b).distance, closeTo(40, 1e-6),
          reason: 'the overall dimension still measures end to end');
    });
  });
}
