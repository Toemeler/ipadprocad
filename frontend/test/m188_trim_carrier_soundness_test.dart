// M188 — the M187 trim carrier bound a round piece UNSOUNDLY.
//
// Device session 2026-08-04 15:00–15:06 on build d6df102, five reports from one
// sketch: two circles joined by two tangent lines ("belt"), both circles then
// trimmed to arcs.
//
//   "after i trimmed part of the first circle the new curve and the remaining
//    construction circle should keep a equal constraint. now they are not
//    constrained together and also the tangent constraint is lost"
//   "i moved the second circle and the first circle collapsed"
//
// The bundle shows why: `arc data=[-1.5312, -0.0920, 8.4957 …]` on a carrier
// centred at the origin. M187 bound a round piece with EQUAL + both endpoints
// on the rim, which pins the centre only DISCRETELY — the mirror of the centre
// across the chord satisfies every one of those equations just as well, and the
// solver walked into it. The same slack let a drag take the carrier's radius to
// zero (`circle data=[0, 0, 0.0000]`), after which the sketch carried a
// permanent 3.6e-6 residual and every later fillet was refused as unsatisfiable
// (`lm: … err=1.26e+0 satisfied=false` -> "fillet REJECTED").
//
// The fix is CONCENTRIC + EQUAL: the arc IS the carrier's circle, no second
// solution, and the carrier's tangencies reach the arc through the shared
// centre and radius.

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

/// The device sketch as it stood just before the two trims, to the digit:
/// circle 0 at the origin, circle 1 to its right, two lines tangent to both
/// with their endpoints on the rims.
AppState beltSketch() {
  final app = makeApp();
  final s = app.current!;
  s.engine.addCircle(0, 0, 8.495672);
  s.engine.addCircle(13.396885, 0.805149, 9.706889);
  s.engine.addLine(-1.273178, 8.39973, 11.942705, 10.402496);
  s.engine.addLine(-0.257946, -8.491755, 13.102521, -8.897276);
  s.refresh();
  s.constraints.addAll([
    Constraint(CType.coincident,
        pts: [const PRef(kProjCenter, 0), const PRef(0, 0)]),
    Constraint(CType.coincident, pts: [const PRef(2, 0)], ents: [0]),
    Constraint(CType.coincident, pts: [const PRef(2, 1)], ents: [1]),
    Constraint(CType.coincident, pts: [const PRef(3, 0)], ents: [0]),
    Constraint(CType.coincident, pts: [const PRef(3, 1)], ents: [1]),
    Constraint(CType.tangent, ents: [3, 1]),
    Constraint(CType.tangent, ents: [0, 3]),
    Constraint(CType.tangent, ents: [0, 2]),
    Constraint(CType.tangent, ents: [1, 2]),
  ]);
  return app;
}

/// Trims the INNER flank of each circle, which is what turns the belt into a
/// closed outline — the device session's two trims.
///
/// Each trim removes its entity and appends (kept span, cut-away span), so
/// afterwards the list is: the two lines, then kept/ghost for circle 1, then
/// kept/ghost for circle 0. Returns kept -> its construction leftover.
Map<int, int> trimBothCircles(AppState app) {
  final s = app.current!;
  app.selectTool(Tool.trim);
  app.toolClick(const Offset(3.69, 0.805)); // circle 1, facing circle 0
  app.toolClick(const Offset(8.4957, 0.0)); // circle 0, facing circle 1
  expect(s.geometry, hasLength(6));
  return {2: 3, 4: 5};
}

void main() {
  group('M188 — a trimmed arc IS its carrier circle', () {
    test('the belt trims to two arcs, each concentric and equal', () {
      final app = beltSketch();
      final s = app.current!;
      final arcs = trimBothCircles(app);

      expect(s.geometry, hasLength(6),
          reason: '2 lines + kept/cut-away for each circle');
      // No circle is left under the shape (M191): each is now a kept arc plus
      // the construction span the cut took away.
      expect(s.geometry.where((g) => g.type == Geo.circle), isEmpty);
      arcs.forEach((kept, ghost) {
        expect(s.geometry[kept].isConstruction, isFalse);
        expect(s.geometry[ghost].isConstruction, isTrue);
        // THE M188 regression, in its M191 place: centre AND radius, not just
        // radius. The device bundle had the centre 1.53 away, mirrored across
        // the chord, because the binding pinned it only discretely.
        expect(
            (getPt(s.geometry[ghost], 0) - getPt(s.geometry[kept], 0)).distance,
            lessThan(1e-6),
            reason: 'the cut-away span shares the kept arc\'s centre');
        expect(s.geometry[ghost].data[2],
            closeTo(s.geometry[kept].data[2], 1e-6));
        expect(
            s.constraints.any((c) =>
                c.type == CType.equal &&
                c.ents.contains(kept) &&
                c.ents.contains(ghost)),
            isTrue,
            reason: 'tied by an equal radius, one equation');
      });
      // and the sketch is still MOVABLE — the device found it pinned to dof=0,
      // "the second circle cannot be dragged ... it should since it has no
      // dimensions".
      // (arc 4 is the left one, whose centre is the grounded origin; arc 2 is
      // the one the report is about — "the second circle cannot be dragged")
      final probe = List<Geo>.from(s.geometry);
      probe[2] = setPt(probe[2], 0, const Offset(16, 3));
      expect(solveConstraints(probe, s.constraints, dragged: {(2, 0)}), isTrue);
      expect((getPt(probe[2], 0) - getPt(s.geometry[2], 0)).distance,
          greaterThan(0.5),
          reason: 'the second arc centre actually moved');
    });

    test('the trimmed sketch really is satisfied, not 3.6e-6 off', () {
      final app = beltSketch();
      final s = app.current!;
      trimBothCircles(app);
      // The device log showed `satisfied=false` on EVERY solve after the trims
      // (err=3.06e-6), and that standing residual is what later made the
      // fillet solve give up.
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-7));
      final probe = List<Geo>.from(s.geometry);
      expect(solveConstraints(probe, s.constraints), isTrue);
    });

    test('dragging the second circle does not collapse the first', () {
      final app = beltSketch();
      final s = app.current!;
      final arcs = trimBothCircles(app);

      // the device drag: the right-hand circle's centre to (14.12,-2.76),
      // after which the device sketch read `circle data=[0, 0, 0.0000]`.
      final probe = List<Geo>.from(s.geometry);
      probe[2] = setPt(probe[2], 0, const Offset(14.122, -2.755));
      expect(solveConstraints(probe, s.constraints, dragged: {(2, 0)}), isTrue);

      // The belt carries no radius dimension, so the radii MAY breathe — what
      // must not happen is the degenerate solution the slack direction opened.
      for (final kept in arcs.keys) {
        expect(probe[kept].data[2], greaterThan(1.0),
            reason: 'arc $kept did not collapse (device: r went to 0)');
      }
      arcs.forEach((kept, ghost) {
        expect((getPt(probe[ghost], 0) - getPt(probe[kept], 0)).distance,
            lessThan(1e-5),
            reason: 'the cut-away span stayed on arc $kept through the drag');
        expect(probe[ghost].data[2], closeTo(probe[kept].data[2], 1e-5));
      });
    });

    test('the kept arcs stay tangent to the lines', () {
      final app = beltSketch();
      final s = app.current!;
      final arcs = trimBothCircles(app);
      final probe = List<Geo>.from(s.geometry);
      probe[2] = setPt(probe[2], 0, const Offset(16.0, 3.0));
      expect(solveConstraints(probe, s.constraints, dragged: {(2, 0)}), isTrue);
      // The tangencies moved onto the kept arcs with the remap, so the belt
      // still holds: each centre's distance to each line equals its radius.
      for (final a in arcs.keys) {
        final c = getPt(probe[a], 0);
        for (final line in [0, 1]) {
          final p = getPt(probe[line], 0), q = getPt(probe[line], 1);
          final d = q - p;
          final len = d.distance;
          final dist =
              ((c - p).dx * d.dy - (c - p).dy * d.dx).abs() / len;
          expect(dist, closeTo(probe[a].data[2], 1e-4),
              reason: 'arc $a still tangent to line $line');
        }
      }
    });

    test('dragging a rectangle in that sketch keeps it rectangular', () {
      // Report 150656: "when dragging the rect around it behaved really buggy
      // and fucked up. it should try to hold its shape". The rect shared its
      // sketch with the degenerate belt above, so every drag frame solved a
      // system with a collapsed circle in it — the device log shows the solver
      // bailing to `lm-relaxed` with err=6.77e+0 and maxAbs jumping 27→33→35.
      final app = beltSketch();
      final s = app.current!;
      trimBothCircles(app);
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(15.26, 13.88));
      app.toolClick(const Offset(29.27, -1.38));
      final r0 = s.geometry.length - 4; // the four sides, in order

      for (final target in const [
        Offset(20, 20),
        Offset(35, -6),
        Offset(12, 4)
      ]) {
        final probe = List<Geo>.from(s.geometry);
        probe[r0 + 2] = setPt(probe[r0 + 2], 1, target); // a corner
        expect(solveConstraints(probe, s.constraints, dragged: {(r0 + 2, 1)}),
            isTrue,
            reason: 'drag to $target solved');
        // still a rectangle: the horizontals horizontal, the verticals vertical
        for (final side in [0, 2]) {
          expect((getPt(probe[r0 + side], 1) - getPt(probe[r0 + side], 0)).dy,
              closeTo(0, 1e-6));
        }
        for (final side in [1, 3]) {
          expect((getPt(probe[r0 + side], 1) - getPt(probe[r0 + side], 0)).dx,
              closeTo(0, 1e-6));
        }
        expect(constraintResidualNorm(probe, s.constraints), lessThan(1e-6),
            reason: 'no standing residual after the drag');
      }
    });

    test('a rectangle can still be filleted on TWO corners afterwards', () {
      // Reports 150503 / 150528: with the sketch carrying the M187 residual,
      // the second fillet was refused ("fillet REJECTED — result cannot be
      // satisfied"). A healthy sketch must not poison later edits.
      final app = beltSketch();
      final s = app.current!;
      trimBothCircles(app);
      final before = s.geometry.length;

      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(15.26, 13.88));
      app.toolClick(const Offset(29.27, -1.38));
      expect(s.geometry.length, before + 4);

      app.selectTool(Tool.fillet);
      app.toolClick(const Offset(14.76, 11.33)); // left edge
      app.toolClick(const Offset(16.53, 13.88)); // top edge
      expect(s.geometry.length, before + 5, reason: 'first fillet landed');

      app.toolClick(const Offset(27.73, 13.88)); // top edge
      app.toolClick(const Offset(29.76, 12.49)); // right edge
      expect(s.geometry.length, before + 6,
          reason: 'the SECOND corner fillets too (device: rejected)');
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    });
  });

  // A SEPARATE defect the same session exposed, in filletInventor and nothing
  // to do with the trim carrier: reports 150503 ("couldn't make a radius on the
  // second corner of the rect") and 150528 ("the horizontal line of the rect
  // was lost when making a radius") reproduce on a bare rectangle.
  group('M188 — a fillet trims the CORNER end, not the nearer one', () {
    AppState rect(Offset a, Offset b) {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(a);
      app.toolClick(b);
      return app;
    }

    test('two adjacent corners: the shared edge keeps both its ends', () {
      final app = rect(const Offset(15.26, 13.88), const Offset(29.27, -1.38));
      final s = app.current!;
      // sides: [0] top, [1] right, [2] bottom, [3] left
      app.selectTool(Tool.fillet);
      app.toolClick(const Offset(14.76, 11.33)); // left
      app.toolClick(const Offset(16.53, 13.88)); // top
      expect(s.geometry, hasLength(5));
      final topAfterFirst = s.geometry[0];
      expect(getPt(topAfterFirst, 0).dx, closeTo(20.26, 1e-6),
          reason: 'the first fillet ate 5 off the LEFT end of the top edge');

      app.toolClick(const Offset(27.73, 13.88)); // top
      app.toolClick(const Offset(29.76, 12.49)); // right
      expect(s.geometry, hasLength(6),
          reason: 'the second corner is not refused');
      // The top edge is now 9.01 - 5 = 4.01 long. Before the fix the tangent
      // point at 5.0 from the right end was NEARER the left end (4.01), so the
      // fillet moved the left end — the end the first fillet had already glued
      // to its arc — and the edge collapsed onto itself.
      final top = s.geometry[0];
      expect(getPt(top, 0).dx, closeTo(20.26, 1e-6),
          reason: 'left end untouched by the second fillet');
      expect(getPt(top, 1).dx, closeTo(24.27, 1e-6),
          reason: 'right end pulled back to the new tangent point');
      expect((getPt(top, 1) - getPt(top, 0)).distance, greaterThan(1e-3),
          reason: 'the horizontal line still exists');
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-9));
    });

    test('all four corners round, and the shape does not move', () {
      final app = rect(const Offset(10, 10), const Offset(50, 40));
      final s = app.current!;
      app.selectTool(Tool.fillet);
      for (final pick in const [
        [Offset(45, 10), Offset(50, 15)],
        [Offset(50, 35), Offset(45, 40)],
        [Offset(15, 40), Offset(10, 35)],
        [Offset(10, 15), Offset(15, 10)],
      ]) {
        app.toolClick(pick[0]);
        app.toolClick(pick[1]);
      }
      expect(s.geometry, hasLength(8), reason: '4 sides + 4 fillet arcs');
      // the exact rounded rectangle: sides inset by the radius, arcs at the
      // corners, and the rectangle still spans 10..50 x 10..40
      final xs = <double>[], ys = <double>[];
      for (final g in s.geometry) {
        if (g.type == Geo.arc) {
          expect(g.data[2], closeTo(5, 1e-6));
          xs.add(g.data[0]);
          ys.add(g.data[1]);
        }
      }
      xs.sort();
      ys.sort();
      expect(xs.first, closeTo(15, 1e-6));
      expect(xs.last, closeTo(45, 1e-6));
      expect(ys.first, closeTo(15, 1e-6));
      expect(ys.last, closeTo(35, 1e-6));
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-9));
    });

    test('the corner coincidence is dropped, so nothing pulls the corner back',
        () {
      final app = rect(const Offset(10, 10), const Offset(50, 40));
      final s = app.current!;
      final before = s.constraints
          .where((c) => c.type == CType.coincident && c.pts.length == 2)
          .length;
      app.selectTool(Tool.fillet);
      app.toolClick(const Offset(45, 10));
      app.toolClick(const Offset(50, 15));
      final after = s.constraints
          .where((c) =>
              c.type == CType.coincident &&
              c.pts.length == 2 &&
              c.pts.every((r) => r.ent < 4))
          .length;
      expect(after, before - 1,
          reason: 'the filleted corner no longer holds the two edges together '
              '(the caller finds it by the trimmed point indices, so a wrong '
              'index left it standing and fought the new arc)');
    });
  });
}
