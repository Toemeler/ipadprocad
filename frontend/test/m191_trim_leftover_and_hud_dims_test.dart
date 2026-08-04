// M191 — three device reports on build 83dc216, all in 2D mode.
//
// 1. "i trimmed the second shape 2 times so the construction lines are gone.
//    there are construction lines under the real shape but there should only
//    be construction line for the part that was actually cut away"
//
//    M187 kept the whole trimmed ENTITY as construction geometry, so every
//    trim left a full-length dashed copy under the visible piece (the bundle
//    shows the pairs: `line [23.98,19.50 -0.99,19.50]` twice over). Only the
//    span the cut removed should stay.
//
// 2. "somehow the second circle cannot be dragged around from center point or
//    also other points but it should since it has no dimensions. also the
//    lines are all white but i dont have diameter dimensions anywhere"
//
//    Same cause: the binds that tied each visible piece onto its carrier copy
//    took the sketch to `dof=0 freePoints={}`, which is also why everything
//    rendered as fully constrained.
//
// 3. "i used dynamic dimensions to type in dimensions while i draw but after i
//    placed the shape the size was correct but the dimensions weren't there.
//    they should actually be placed a little next to the line exactly how i
//    would place a dimension myself"
//
//    The centre-start rectangles commit SIX entities (four sides plus two
//    construction diagonals) and the HUD dimension branch required exactly
//    four, so it never ran.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/hud.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  group('M191/1 — only the cut-away span stays as construction', () {
    test('a trimmed line leaves the removed span, not a copy of the line', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 40, 0);
      s.engine.addLine(10, -10, 10, 10); // cutter at x=10
      s.refresh();
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(5, 0)); // cut the short left end away

      final ghosts = s.geometry.where((g) => g.isConstruction).toList();
      expect(ghosts, hasLength(1));
      // 10 long, the removed span — NOT the 40 of the whole line
      expect((getPt(ghosts[0], 0) - getPt(ghosts[0], 1)).distance,
          closeTo(10, 1e-6));
      final kept = s.geometry.where((g) => !g.isConstruction).toList();
      expect(kept, hasLength(2)); // cutter + surviving span
      // and nothing dashed lies along the surviving span
      final survivor =
          kept.firstWhere((g) => (getPt(g, 0) - getPt(g, 1)).distance > 25);
      expect((getPt(survivor, 0) - getPt(survivor, 1)).distance,
          closeTo(30, 1e-6));
      for (final g in ghosts) {
        for (final p in [getPt(g, 0), getPt(g, 1)]) {
          expect(p.dx, lessThan(10 + 1e-6),
              reason: 'the ghost stays on its own side of the cut');
        }
      }
    });

    test('trimming the same shape twice does not stack ghosts', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 30));
      app.selectTool(Tool.line);
      app.toolClick(const Offset(10, -5));
      app.toolClick(const Offset(10, 35)); // one cutter across two sides
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(5, 0)); // bottom, left of the cutter
      app.toolClick(const Offset(5, 30)); // top, left of the cutter

      final ghosts = s.geometry.where((g) => g.isConstruction).toList();
      expect(ghosts, hasLength(2), reason: 'one per cut, no more');
      for (final g in ghosts) {
        expect((getPt(g, 0) - getPt(g, 1)).distance, closeTo(10, 1e-6),
            reason: 'each ghost is the 10-long removed span');
      }
    });

    test('the cut-away span keeps riding the geometry it came from', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 40, 0);
      s.engine.addLine(10, -10, 10, 10);
      s.refresh();
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(5, 0));
      final gi = s.geometry.indexWhere((g) => g.isConstruction);
      final ki = s.geometry.indexWhere(
          (g) => !g.isConstruction && (getPt(g, 0) - getPt(g, 1)).distance > 25);

      // swing the kept span and the ghost must stay on its line, not hang in
      // the air where the cut used to be
      final probe = List<Geo>.from(s.geometry);
      probe[ki] = setPt(probe[ki], 1, const Offset(40, 12));
      expect(solveConstraints(probe, s.constraints, dragged: {(ki, 1)}), isTrue);
      final a = getPt(probe[ki], 0), b = getPt(probe[ki], 1);
      final d = b - a;
      for (final p in [getPt(probe[gi], 0), getPt(probe[gi], 1)]) {
        final off = ((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / d.distance;
        expect(off, lessThan(1e-5),
            reason: 'the cut-away span is still collinear with what was kept');
      }
    });
  });

  group('M191/2 — a trim leaves the sketch movable', () {
    test('trimmed pieces keep their freedom (device: dof=0, all white)', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 10);
      s.engine.addLine(-20, 0, 20, 0);
      s.refresh();
      final before = analyzeSketch(s.geometry, s.constraints).dof;
      app.selectTool(Tool.trim);
      app.toolClick(const Offset(0, -10));
      final after = analyzeSketch(s.geometry, s.constraints).dof;
      expect(after, greaterThan(0),
          reason: 'the device session found dof=0 and nothing draggable '
              '(was $before before the trim)');

      // and it really moves: shove the arc centre and it goes
      final ai = s.geometry
          .indexWhere((g) => g.type == Geo.arc && !g.isConstruction);
      final probe = List<Geo>.from(s.geometry);
      probe[ai] = setPt(probe[ai], 0, const Offset(4, 6));
      expect(solveConstraints(probe, s.constraints, dragged: {(ai, 0)}), isTrue);
      expect((getPt(probe[ai], 0) - getPt(s.geometry[ai], 0)).distance,
          greaterThan(0.5));
    });
  });

  group('M191/3 — typed dimensions land, beside the line', () {
    /// Draws [tool] the way the device session did: first point, then TYPE the
    /// two dynamic-input fields, then place. Goes through the same
    /// hudInput/hudTab path the on-screen HUD drives, so the test exercises
    /// what the user actually did rather than the state it leaves behind.
    SketchModel typedRect(AppState app, Tool tool, Offset a, Offset b,
        double w, double h) {
      final s = app.current!;
      app.tool = tool;
      app.toolClick(a);
      app.hoverWorld = b;
      expect(app.hudActive, isTrue, reason: 'the HUD is up after point 1');
      expect(hudFieldsFor(app.tool, app.toolPoints.length).length, 2);
      app.hudInput = '$w';
      app.hudTab(); // locks the first field, moves to the second
      app.hudInput = '$h';
      app.hudTab(); // locks the second
      app.toolClick(b); // placed: the locks decide the size, not the point
      return s;
    }

    test('a centre-start rectangle gets its typed width and height', () {
      final app = makeApp();
      final s = typedRect(app, Tool.rect2PC, const Offset(-13.73, 45.25),
          const Offset(-100.39, 72.64), 20, 20);
      // four sides + two construction diagonals — the count that used to make
      // the dimension branch skip
      expect(s.geometry, hasLength(6));
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(2),
          reason: 'the typed width and height became real dimensions');
      expect(dims.map((d) => d.value), everyElement(closeTo(20, 1e-6)));
      expect(dims.map((d) => d.dimKind).toSet(), {'distx', 'disty'});
    });

    test('the label sits OUTSIDE the shape, not on top of it', () {
      final app = makeApp();
      final s = typedRect(
          app, Tool.rect2PC, const Offset(0, 0), const Offset(30, 30), 24, 16);
      final dims =
          s.constraints.where((c) => c.type == CType.dimension).toList();
      expect(dims, hasLength(2));
      // centre of the rectangle's four sides
      var cx = 0.0, cy = 0.0;
      for (var e = 0; e < 4; e++) {
        cx += (getPt(s.geometry[e], 0).dx + getPt(s.geometry[e], 1).dx) / 2;
        cy += (getPt(s.geometry[e], 0).dy + getPt(s.geometry[e], 1).dy) / 2;
      }
      final centre = Offset(cx / 4, cy / 4);
      for (final d in dims) {
        final t = d.textPos!;
        final mid = (refPt(s.geometry, d.pts[0]) + refPt(s.geometry, d.pts[1])) /
            2;
        expect((t - mid).distance, closeTo(8, 1e-6),
            reason: 'a little next to the line it measures');
        expect((t - centre).distance, greaterThan((mid - centre).distance),
            reason: 'and on the OUTSIDE of the shape');
      }
    });

    test('a plain two-point rectangle still dimensions as before', () {
      final app = makeApp();
      final s = typedRect(app, Tool.rectTwoPoint, const Offset(0, 0),
          const Offset(20, 20), 20, 20);
      expect(s.geometry, hasLength(4));
      expect(s.constraints.where((c) => c.type == CType.dimension), hasLength(2));
    });
  });
}
