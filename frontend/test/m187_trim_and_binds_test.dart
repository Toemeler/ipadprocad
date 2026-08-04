// M187 — three device reports from the 2026-08-04 session, all in 2D mode.
//
// 1. "when trying to trim one side of the circle with 2 lines attached the
//    whole circle was trimmed instead only the part of the circle"
//    Both lines were TANGENT to the circle and ended on it. Their touch points
//    were rejected (the root sat at t=1.000003, past a fixed 1e-9 parameter
//    window) while the other tangent contributed TWO roots 1e-5 apart, so the
//    trim kept the zero-sweep arc between those two — the rim vanished.
//
// 2. "the endpoint landed on a circle but no automatic point on circle was
//    made ... on the start point which also landed on a circle it worked"
//    The line was drawn FIRST and the circle second, through its endpoint.
//    Inference only ever asked "does a point of the NEW entity land on
//    something older", so the binding depended on drawing order.
//
// 3. "when trimming something away, the original line should always stay as a
//    construction line unless it is already a construction line so for example
//    dimensions or constraints aren't destroyed"

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/modify.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// The sketch from the device report, to the digit: a circle with two lines
/// running off it, each TANGENT and each ending exactly on the rim.
List<Geo> tangentSketch() => [
      Geo(Geo.circle, [
        29.53868754435371,
        4.295455894592541,
        8.22228441581702,
      ]),
      Geo(Geo.line, [
        -0.16917037445828162,
        12.103561294836608,
        29.423752529851875,
        12.516936963181708,
      ]),
      Geo(Geo.line, [
        3.285033014348538,
        -11.650466631670797,
        31.770281015780938,
        -3.6182001250812745,
      ]),
    ];

void main() {
  group('M187/1 — a tangency is an intersection, and only ONE', () {
    test('a line ending tangentially on a circle still crosses it', () {
      final gs = tangentSketch();
      for (final line in [1, 2]) {
        final xs = intersections(gs[line], gs[0]);
        expect(xs, hasLength(1),
            reason: 'line $line touches the rim in exactly one point');
        final d = (xs[0] - Offset(gs[0].data[0], gs[0].data[1])).distance;
        expect(d, closeTo(gs[0].data[2], 1e-6),
            reason: 'and that point is ON the rim');
      }
    });

    test('trimming the circle keeps the far span, not a zero-sweep stub', () {
      final gs = tangentSketch();
      // the click from the log: the LEFT flank of the circle
      final out = trimEntity(gs, 0, const Offset(21.44, 5.71));
      expect(out, hasLength(1));
      expect(out[0].type, Geo.arc);
      final sweep = (out[0].data[4] - out[0].data[3]).abs();
      expect(sweep, greaterThan(1.0),
          reason: 'the surviving arc spans the two tangent points, it is not '
              'the 1.7e-5 rad stub the device produced');
      expect(out[0].data[2], closeTo(gs[0].data[2], 1e-9));
    });

    test('an ordinary crossing still yields two distinct points', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.line, [-20, 3, 20, 3]),
      ];
      final xs = intersections(gs[1], gs[0]);
      expect(xs, hasLength(2));
      expect((xs[0] - xs[1]).distance, greaterThan(1.0));
    });

    test('a line that misses the circle still misses it', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.line, [-20, 10.5, 20, 10.5]),
      ];
      expect(intersections(gs[1], gs[0]), isEmpty);
    });

    test('a line ENDING on the rim mid-span binds there too', () {
      // not tangent: the line runs outward from a point on the rim
      final on = Offset(math.cos(0.4), math.sin(0.4)) * 10;
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.line, [on.dx, on.dy, on.dx * 4, on.dy * 4]),
      ];
      final xs = intersections(gs[1], gs[0]);
      expect(xs, hasLength(1));
      expect((xs[0] - on).distance, lessThan(1e-6));
    });
  });

  group('M187/2 — inference binds in BOTH directions', () {
    test('a circle drawn through an existing endpoint binds that endpoint', () {
      // the device order: line first, then the circle through its end
      final end = const Offset(30.1355, 10.4116);
      final c = const Offset(30.6091, 3.5170);
      final gs = [
        Geo(Geo.line, [3.0757, 10.4039, end.dx, end.dy]),
        Geo(Geo.circle, [c.dx, c.dy, (end - c).distance]),
      ];
      final cs = inferConstraints(gs, 1);
      final bind = cs.where((x) =>
          x.type == CType.coincident &&
          x.pts.length == 1 &&
          x.ents.length == 1 &&
          x.ents[0] == 1 &&
          x.pts[0] == const PRef(0, 1));
      expect(bind, hasLength(1),
          reason: 'the older endpoint is pinned onto the new circle');
      expect(isReverseBind(bind.first, 1), isTrue);
      // and it holds: the residual of that coincidence is zero as drawn
      expect(constraintResidualNorm(gs, cs.toList()), lessThan(1e-6));
    });

    test('the same landing through the app, drawn in that order', () {
      final app = makeApp();
      final s = app.current!;
      app.selectTool(Tool.line);
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.selectTool(Tool.circleCenter);
      app.toolClick(const Offset(40, 20)); // centre
      app.toolClick(const Offset(40, 0)); // rim ON the line's endpoint
      expect(s.geometry, hasLength(2));
      final onCircle = s.constraints.where((c) =>
          c.type == CType.coincident &&
          c.pts.length == 1 &&
          c.ents.length == 1 &&
          c.ents[0] == 1);
      expect(onCircle, hasLength(1),
          reason: 'point-on-circle on the line end (constraints: '
              '${s.constraints.map((c) => c.toJson())})');
      // dragging the circle's centre drags the bound endpoint along
      final probe = List<Geo>.from(s.geometry);
      probe[1] = setPt(probe[1], 0, const Offset(46, 26));
      expect(solveConstraints(probe, s.constraints, dragged: {(1, 0)}), isTrue);
      final q = getPt(probe[0], 1);
      final ctr = getPt(probe[1], 0);
      expect(((q - ctr).distance - probe[1].data[2]).abs(), lessThan(1e-6),
          reason: 'the endpoint stayed on the rim');
    });

    test('a curve drawn NEAR an existing point does not bind', () {
      final gs = [
        Geo(Geo.line, [0, 0, 40, 0]),
        Geo(Geo.circle, [40, 20, 20.01]), // 0.01 off the endpoint
      ];
      final cs = inferConstraints(gs, 1);
      expect(cs.where((c) => isReverseBind(c, 1)), isEmpty);
    });
  });

  group('M191/3 — Trim keeps the CUT-AWAY span as construction geometry', () {
    test('the cut-away span is construction, the kept piece is normal', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20); // cutter
      s.refresh();
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0)); // cut the left span away
      expect(s.geometry, hasLength(3), reason: 'cutter + kept piece + leftover');
      final kept = s.geometry[1], ghost = s.geometry[2];
      expect(kept.isConstruction, isFalse);
      expect(getPt(kept, 0).dx, closeTo(0, 1e-6));
      expect(getPt(kept, 1).dx, closeTo(20, 1e-6));
      // M191 — ONLY the removed span, not a copy of the whole line. The device
      // session saw the copy: "there are construction lines under the real
      // shape but there should only be construction line for the part that was
      // actually cut away".
      expect(ghost.isConstruction, isTrue);
      expect(getPt(ghost, 0).dx, closeTo(-20, 1e-6));
      expect(getPt(ghost, 1).dx, closeTo(0, 1e-6));
      // nothing lies under the visible piece
      for (final g in s.geometry.where((g) => g.isConstruction)) {
        expect((getPt(g, 0) - getPt(g, 1)).distance, closeTo(20, 1e-6),
            reason: 'the leftover is the 20-long removed span, not the 40 line');
      }
    });

    test('a dimension across the cut survives and still drives', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 40, 0);
      s.engine.addLine(20, -20, 20, 20); // cutter
      s.refresh();
      s.constraints.add(Constraint(CType.dimension,
          pts: [const PRef(0, 0), const PRef(0, 1)],
          dimKind: 'dist',
          value: 40));
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(30, 0)); // cut the right span away
      final dim = s.constraints.firstWhere((c) => c.type == CType.dimension);
      expect(dim.value, 40, reason: 'the dimension was not destroyed');
      // It measured the whole line, and it still does: one end rides the kept
      // piece, the other the construction leftover. That is what keeping the
      // cut-away span is FOR.
      final a = refPt(s.geometry, dim.pts[0]), b = refPt(s.geometry, dim.pts[1]);
      expect((a - b).distance, closeTo(40, 1e-6));
      dim.value = 60;
      final probe = List<Geo>.from(s.geometry);
      expect(solveConstraints(probe, s.constraints), isTrue);
      expect((refPt(probe, dim.pts[0]) - refPt(probe, dim.pts[1])).distance,
          closeTo(60, 1e-6),
          reason: 'driving it still moves the geometry');
      // and the two spans still meet in one place: [0] cutter, [1] kept,
      // [2] the cut-away leftover
      expect((getPt(probe[1], 1) - getPt(probe[2], 0)).distance,
          lessThan(1e-6));
    });

    test('trimming CONSTRUCTION geometry does not stack a second ghost', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.geometry[0] = s.geometry[0].withStyle(Geo.styleConstruction);
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0));
      expect(s.geometry, hasLength(2),
          reason: 'construction in, construction out: the old path');
      expect(s.geometry.where((g) => g.isConstruction), hasLength(1));
    });

    test('a circle trimmed to an arc keeps the rim it came from', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 10);
      s.engine.addLine(-20, 0, 20, 0);
      s.refresh();
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(0, -10)); // cut the lower half
      // a circle becomes TWO arcs: the kept upper half and the cut-away lower
      // half as construction. No circle is left underneath them.
      expect(s.geometry.where((g) => g.type == Geo.circle), isEmpty);
      final arcs = s.geometry.where((g) => g.type == Geo.arc).toList();
      expect(arcs, hasLength(2));
      final arc = arcs.firstWhere((g) => !g.isConstruction);
      final ghost = arcs.firstWhere((g) => g.isConstruction);
      expect(arc.data[2], closeTo(10, 1e-6));
      expect(ghost.data[2], closeTo(10, 1e-6));
      // The two halves stay ONE circle: push the kept arc out and the ghost
      // follows it, rather than drifting off as an unrelated dashed arc.
      final probe = List<Geo>.from(s.geometry);
      final ki = probe.indexWhere((g) => g.type == Geo.arc && !g.isConstruction);
      final gi = probe.indexWhere((g) => g.type == Geo.arc && g.isConstruction);
      probe[ki] = probe[ki].withData([...probe[ki].data]..[2] = 14);
      expect(solveConstraints(probe, s.constraints), isTrue);
      expect(probe[gi].data[2], closeTo(probe[ki].data[2], 1e-6),
          reason: 'equal radius ties the cut-away span to what was kept');
      expect((getPt(probe[gi], 0) - getPt(probe[ki], 0)).distance,
          lessThan(1e-5),
          reason: 'and they share a centre');
    });

    test('the trim still refuses to be picked out of another layer', () {
      // guard: the carrier path must not bypass the projection/lock checks
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(-20, 0, 20, 0);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.geometry[0] = s.geometry[0].withProj(1);
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(-10, 0));
      expect(s.geometry, hasLength(2), reason: 'projected geometry is pinned');
      expect(s.geometry[0].isConstruction, isFalse);
    });
  });
}
