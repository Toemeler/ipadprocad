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

int count(SketchModel s, CType t) =>
    s.constraints.where((c) => c.type == t).length;

void main() {
  group('slot auto-constraints (Inventor)', () {
    test('linear slot: coincident/tangent seams, equal caps — rank-perfect',
        () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slotCC;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 40));
      app.toolClick(const Offset(120, 46)); // width -> r = 6
      // [rail1, rail2, cap1, cap2, construction axis] (M40)
      expect(s.geometry, hasLength(5));
      expect(s.geometry[4].isConstruction, isTrue,
          reason: 'slot axis is auto construction geometry');
      expect(count(s, CType.coincident), 6); // 4 seams + 2 axis-end binds
      expect(count(s, CType.tangent), 4);
      expect(count(s, CType.equal), 1);
      // NO explicit parallel: rail parallelism is implied by the tangencies.
      // The old redundant parallel row made the LM normal equations singular
      // and libslvs flag the sketch inconsistent — the slot-drag flicker bug.
      expect(count(s, CType.parallel), 0);
      final (rank, eqs, params) = debugRank(s.geometry, s.constraints);
      expect(eqs - rank, 0, reason: 'construction must be redundancy-free');
      expect(params - rank, 5,
          reason: 'slot DOF: position(2) + rotation + length + radius');
      // a slot has exactly 5 DOF: position, rotation, length, radius
      expect(analyzeSketch(s.geometry, s.constraints).dof, 5);
    });

    test('linear slot survives the solver as a slot (drag an end)', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slotCC;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 40));
      app.toolClick(const Offset(120, 46));
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

    test('arc slot: concentric rails + seams, caps equal by implication, 6 DOF',
        () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.slot3A;
      app.toolClick(const Offset(80, 40));
      app.toolClick(const Offset(100, 60));
      app.toolClick(const Offset(120, 40));
      app.toolClick(const Offset(100, 66)); // width -> r = 6
      // M114 — four rails/caps plus the two CONSTRUCTION radii.
      expect(s.geometry, hasLength(6));
      expect(s.geometry.where((g) => g.isConstruction), hasLength(2));
      expect(count(s, CType.concentric), 1);
      // 4 seam coincidences + 4 pinning the two radii (M114).
      expect(count(s, CType.coincident), 8);
      expect(count(s, CType.tangent), 4);
      // NO explicit equal: with concentric rails + both caps tangent to both
      // rails with their ends on them, each cap radius is forced to
      // (R_outer - R_inner)/2 — the equal row was measured redundant (rank
      // deficit 1) and made the solver unstable, exactly like the linear
      // slot's parallel.
      expect(count(s, CType.equal), 0);
      final (rank, eqs, _) = debugRank(s.geometry, s.constraints);
      // The whole point of using LINES for the radii rather than a centre arc:
      // 8 more parameters, 8 more equations, still not one redundant row.
      expect(eqs - rank, 0, reason: 'construction must be redundancy-free');
      expect(analyzeSketch(s.geometry, s.constraints).dof, 6,
          reason: 'the radii must not remove a slot DOF');
      // ...and the equality still HOLDS functionally
      expect(s.geometry[2].data[2], closeTo(s.geometry[3].data[2], 1e-6));
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

    test('EVERY fillet gets its own radius dimension', () {
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
      // no equal-chain: each fillet is dimensioned itself, a radius label per
      // fillet like the chamfer's setback labels
      expect(count(s, CType.equal), 0);
      final rads = s.constraints
          .where((c) => c.type == CType.dimension && c.dimKind == 'rad')
          .toList();
      expect(rads, hasLength(2), reason: 'one R-dim per fillet');
      for (final d in rads) {
        expect(d.value, closeTo(4, 1e-9));
      }
      // editing one radius drives ONLY that fillet
      app.setDimensionValue(rads.first, 7);
      final r1 = s.geometry[3].data[2], r2 = s.geometry[4].data[2];
      expect({r1, r2}.map((v) => (v * 10).round()).toSet(), {70, 40},
          reason: 'one fillet 7, the other still 4');
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

    test('equal distance: trim + coincident + x/y setback dims (Inventor)',
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
      // Inventor dimensions the chamfer's SETBACKS (the x/y legs), never the
      // diagonal — a 5×5 chamfer reads "5 / 5", not "7.07".
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(2));
      expect(dims.map((d) => d.dimKind).toSet(), {'distx', 'disty'});
      for (final d in dims) {
        expect(d.value, closeTo(5, 1e-6));
      }
      // the whole result must be exactly satisfiable (rank-perfect) — the old
      // implementation left the corner coincidence in place, which contradicted
      // the dimension and made the entire sketch diverge
      final (rank, eqs, _) = debugRank(s.geometry, s.constraints);
      expect(eqs - rank, 0, reason: 'no redundant/contradictory rows');
      expect(constraintResidualNorm(s.geometry, s.constraints),
          lessThan(1e-6));
    });

    test('two distances: d1 on the FIRST pick, x/y setback dims', () {
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
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(2));
      final byKind = {for (final d in dims) d.dimKind: d.value};
      expect(byKind['distx'], closeTo(8, 1e-6));
      expect(byKind['disty'], closeTo(4, 1e-6));
      expect(constraintResidualNorm(s.geometry, s.constraints),
          lessThan(1e-6));
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
      // M187 — the dimension keeps the geometry it was placed on: the circle
      // survives the cut as the construction CARRIER. What matters is that it
      // still DRIVES what is visible, so re-drive it and watch the arc follow.
      expect(s.geometry[dims[0].ents[0]].type, Geo.circle);
      expect(s.geometry[dims[0].ents[0]].isConstruction, isTrue);
      final arc = s.geometry.indexWhere((g) => g.type == Geo.arc);
      expect(arc, isNot(-1), reason: 'the trimmed circle left an arc');
      expect(s.geometry[arc].data[2], closeTo(10, 1e-6));
      dims[0].value = 12;
      final probe = List<Geo>.from(s.geometry);
      expect(solveConstraints(probe, s.constraints), isTrue);
      expect(probe[arc].data[2], closeTo(12, 1e-6),
          reason: 'the radius dim on the carrier still drives the arc');
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
      // M187 — the tangency stays on the carrier the circle became, and the
      // arc the cut left behind rides on that same rim (equal radius).
      expect(s.geometry[c.ents[1]].isConstruction, isTrue);
      final arc = s.geometry.indexWhere((g) => g.type == Geo.arc);
      expect(arc, isNot(-1));
      expect(s.geometry[arc].data[2],
          closeTo(s.geometry[c.ents[1]].data[2], 1e-6));
    });

    test('M187: the carrier keeps BOTH seam coincidents, the cut binds anew',
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
      // M187 — this is the device report the carrier rule came from: the left
      // seam's point (-20,0) used to be deleted with the span, taking its
      // coincident with it. The carrier still holds BOTH seam points, so both
      // coincidents stand. The NEW endpoint the cut made at (0,0) binds onto
      // the cutter (Inventor's trim coincidence) and onto the carrier.
      final seams = s.constraints
          .where((c) =>
              c.type == CType.coincident &&
              c.pts.length == 2 &&
              c.pts.any((r) => r.ent == 2 || r.ent == 3))
          .toList();
      expect(seams, hasLength(2), reason: 'neither seam was destroyed');
      final seamX = [
        for (final c in seams) refPt(s.geometry, c.pts[0]).dx
      ]..sort();
      expect(seamX[0], closeTo(-20, 1e-6));
      expect(seamX[1], closeTo(20, 1e-6));
      final onCutter = s.constraints.where((c) =>
          c.type == CType.coincident &&
          c.pts.length == 1 &&
          c.ents.length == 1 &&
          !s.geometry[c.ents[0]].isConstruction);
      expect(onCutter, hasLength(1));
      final q = refPt(s.geometry, onCutter.first.pts[0]);
      expect(q.dx, closeTo(0, 1e-6));
      expect(q.dy, closeTo(0, 1e-6));
      // ...and it really holds under a solve
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
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
      // M49 supersedes the original M36 expectation of 1: Autodesk documents
      // that BOTH segments of a split inherit Horizontal/Vertical/Parallel/
      // Perpendicular/Collinear, so the split line stays two horizontal lines.
      expect(count(s, CType.horizontal), 2);
      expect(count(s, CType.fix), 1, reason: 'point fix follows its point');
    });

    test('M187: an entity-level fix rides along on the kept carrier', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.constraints.add(Constraint(CType.fix,
          ents: [0], anchors: const [-20, 0, 20, 0]));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0));
      // The pinned shape still exists — as construction geometry — so the fix
      // keeps pinning it instead of being thrown away with the cut span.
      expect(count(s, CType.fix), 1);
      final c = s.constraints.firstWhere((c) => c.type == CType.fix);
      expect(s.geometry[c.ents[0]].isConstruction, isTrue);
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
