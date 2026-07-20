// M49 — SPLIT, exactly as Inventor's 2D sketch Split behaves.
//
// Autodesk's documented contract, which these tests pin down:
//  * "the Split command splits a selected curve to the NEAREST INTERSECTING
//    CURVE" — the cut lands on an intersection, never under the cursor,
//  * "When multiple intersections are possible, Inventor selects the nearest
//    one" — nearest to the CURSOR, along the curve,
//  * closed curves have no ends to bound one cut, so Inventor runs outward in
//    both directions from the cursor: the hovered span + its complement,
//  * "Both segments of the split inherit the Horizontal, Vertical, Parallel,
//    Perpendicular, and Collinear constraints of the original. Equal and
//    Symmetric constraints are broken when necessary.",
//  * dimensions are maintained,
//  * unlike Trim, Split NEVER deletes: with nothing to cut against, nothing
//    happens at all.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/modify.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);
Geo circle(double cx, double cy, double r) => Geo(Geo.circle, [cx, cy, r]);
Geo arc(double cx, double cy, double r, double a0, double a1) =>
    Geo(Geo.arc, [cx, cy, r, a0, a1, 0.0]);

Offset p0(Geo g) => Offset(g.data[0], g.data[1]);
Offset p1(Geo g) => Offset(g.data[2], g.data[3]);

void main() {
  group('cut point = nearest intersecting curve, not the click', () {
    test('a horizontal line crossed once splits AT the crossing', () {
      // carrier 0..10 on y=0, cutter crosses it at x=4
      final gs = [line(0, 0, 10, 0), line(4, -5, 4, 5)];
      // click far away from the crossing — Inventor still cuts at x=4
      final parts = splitEntity(gs, 0, const Offset(8.5, 0));
      expect(parts, isNotNull);
      expect(parts!.length, 2);
      final cut = p1(parts[0]);
      expect(cut.dx, closestTo(4.0));
      expect(cut.dy, closestTo(0.0));
      // pieces cover the original end to end
      expect(p0(parts[0]).dx, closestTo(0.0));
      expect(p1(parts[1]).dx, closestTo(10.0));
    });

    test('multiple crossings: the one NEAREST the cursor wins', () {
      final gs = [
        line(0, 0, 10, 0),
        line(2, -5, 2, 5),
        line(5, -5, 5, 5),
        line(9, -5, 9, 5),
      ];
      expect(splitPoints(gs, 0, const Offset(1.0, 0)).single.dx,
          closestTo(2.0));
      expect(splitPoints(gs, 0, const Offset(4.4, 0)).single.dx,
          closestTo(5.0));
      expect(splitPoints(gs, 0, const Offset(9.8, 0)).single.dx,
          closestTo(9.0));
    });

    test('an intersection sitting ON an end is not a cut', () {
      // cutter touches the carrier exactly at its start point
      final gs = [line(0, 0, 10, 0), line(0, -5, 0, 5)];
      expect(splitEntity(gs, 0, const Offset(5, 0)), isNull);
    });

    test('nothing to cut against: NO split, and nothing is deleted', () {
      final gs = [line(0, 0, 10, 0)];
      expect(splitEntity(gs, 0, const Offset(5, 0)), isNull);

      final app = makeApp();
      final s = app.current!;
      s.geometry.add(line(0, 0, 10, 0));
      app.tool = Tool.split;
      app.toolClick(const Offset(5, 0));
      // Trim would delete here — Split must leave the sketch untouched.
      expect(s.geometry.length, 1);
      expect(s.geometry.first.type, Geo.line);
    });
  });

  group('arcs', () {
    test('an arc splits at the crossing nearest the cursor', () {
      // quarter arc r=10 from 0 to 90 deg, cut by the 45-deg ray
      final a = arc(0, 0, 10, 0, math.pi / 2);
      const d = 10 / math.sqrt2;
      final gs = [a, line(0, 0, d * 2, d * 2)];
      final parts = splitEntity(gs, 0, Offset(d * 0.9, d * 1.1));
      expect(parts, isNotNull);
      expect(parts!.length, 2);
      for (final piece in parts) {
        expect(piece.type, Geo.arc);
        expect(piece.data[2], closestTo(10.0)); // radius kept
      }
      // the two sweeps add up to the original
      final total = (parts[0].data[4] - parts[0].data[3]).abs() +
          (parts[1].data[4] - parts[1].data[3]).abs();
      expect(total, closestTo(math.pi / 2));
    });
  });

  group('closed carriers run outward in BOTH directions', () {
    test('a circle crossed twice yields exactly two arcs', () {
      // circle r=10 at origin, a chord line y=6 cuts it twice
      final gs = [circle(0, 0, 10), line(-20, 6, 20, 6)];
      final plan = planSplit(gs, 0, const Offset(0, 10)); // cursor on top
      expect(plan, isNotNull);
      expect(plan!.pieces.length, 2); // NOT one arc per intersection
      expect(plan.cuts.length, 2);
      for (final piece in plan.pieces) {
        expect(piece.type, Geo.arc);
        expect(piece.data[2], closestTo(10.0));
      }
      // full circle conserved
      double sweep(Geo g) {
        var v = (g.data[4] - g.data[3]) % (2 * math.pi);
        if (v <= 0) v += 2 * math.pi;
        return v;
      }

      expect(sweep(plan.pieces[0]) + sweep(plan.pieces[1]),
          closestTo(2 * math.pi));
      // both cuts sit on the chord
      for (final c in plan.cuts) {
        expect(c.dy, closestTo(6.0));
        expect(c.distance, closestTo(10.0));
      }
    });

    test('the hovered span is the SHORT top arc when the cursor is on top',
        () {
      final gs = [circle(0, 0, 10), line(-20, 6, 20, 6)];
      final plan = planSplit(gs, 0, const Offset(0, 10))!;
      final hovered = plan.pieces[plan.hovered];
      // the top cap above y=6 is the minor arc
      final other = plan.pieces[1 - plan.hovered];
      double sweep(Geo g) {
        var v = (g.data[4] - g.data[3]) % (2 * math.pi);
        if (v <= 0) v += 2 * math.pi;
        return v;
      }

      expect(sweep(hovered), lessThan(sweep(other)));
    });

    test('a circle with only one touch point cannot be split', () {
      // tangent line touches the circle exactly once
      final gs = [circle(0, 0, 10), line(-20, 10, 20, 10)];
      expect(splitEntity(gs, 0, const Offset(0, -10)), isNull);
    });

    test('a closed polyline splits into two open chains', () {
      // unit-ish square 0,0 .. 10,10 as a closed polyline
      final sq = const Geo(Geo.polyline,
          [1.0, 4.0, 0, 0, 10, 0, 10, 10, 0, 10]);
      // two cutters crossing the bottom and the top edge
      final gs = [sq, line(4, -5, 4, 5), line(6, 5, 6, 15)];
      final plan = planSplit(gs, 0, const Offset(10, 5)); // cursor: right edge
      expect(plan, isNotNull);
      expect(plan!.pieces.length, 2);
      expect(plan.cuts.length, 2);
      for (final piece in plan.pieces) {
        // never a loop again
        if (piece.type == Geo.polyline) expect(piece.data[0], 0.0);
      }
    });
  });

  group('open polyline', () {
    test('splits at the crossing nearest the cursor', () {
      final pl = const Geo(Geo.polyline, [0.0, 3.0, 0, 0, 10, 0, 10, 10]);
      final gs = [pl, line(4, -5, 4, 5)];
      final cuts = splitPoints(gs, 0, const Offset(9, 0));
      expect(cuts.length, 1);
      expect(cuts.single.dx, closestTo(4.0));
      expect(cuts.single.dy, closestTo(0.0));
    });
  });

  group('layer / style / spline tags ride along', () {
    test('a split piece keeps layer and construction style', () {
      final carrier =
          line(0, 0, 10, 0).onLayer('3').withStyle(Geo.styleConstruction);
      final gs = [carrier, line(4, -5, 4, 5)];
      final parts = splitEntity(gs, 0, const Offset(8, 0))!;
      for (final piece in parts) {
        expect(piece.layer, '3');
        expect(piece.style, Geo.styleConstruction);
      }
    });
  });

  group("Inventor's constraint rules", () {
    test('Horizontal is inherited by BOTH segments', () {
      final gs = [line(0, 0, 10, 0), line(4, -5, 4, 5)];
      final cs = [Constraint(CType.horizontal, ents: [0])];
      final parts = splitEntity(gs, 0, const Offset(8, 0))!;
      final after = [...gs]..removeAt(0);
      final start = after.length;
      after.addAll(parts);
      final out = remapAfterSplit(cs, 0, gs[0], after, start);
      final hs = out.where((c) => c.type == CType.horizontal).toList();
      expect(hs.length, 2);
      expect(hs.map((c) => c.ents.single).toSet(), {start, start + 1});
    });

    test('Vertical / Parallel / Perpendicular / Collinear likewise', () {
      for (final t in [
        CType.vertical,
        CType.parallel,
        CType.perpendicular,
        CType.collinear,
      ]) {
        final gs = [line(0, 0, 10, 0), line(4, -5, 4, 5), line(0, 8, 10, 8)];
        // single-entity kinds carry one ent, pair kinds carry two
        final cs = [
          t == CType.vertical
              ? Constraint(t, ents: [0])
              : Constraint(t, ents: [0, 2])
        ];
        final parts = splitEntity(gs, 0, const Offset(8, 0))!;
        final after = [...gs]..removeAt(0);
        final start = after.length;
        after.addAll(parts);
        final out = remapAfterSplit(cs, 0, gs[0], after, start);
        final got = out.where((c) => c.type == t).toList();
        expect(got.length, 2, reason: '$t should land on both pieces');
        expect(got.map((c) => c.ents.first).toSet(), {start, start + 1},
            reason: '$t');
      }
    });

    test('Equal and Symmetric are broken by a split', () {
      for (final t in [CType.equal, CType.symmetric]) {
        final gs = [line(0, 0, 10, 0), line(4, -5, 4, 5), line(0, 8, 10, 8)];
        final cs = [Constraint(t, ents: [0, 2])];
        final parts = splitEntity(gs, 0, const Offset(8, 0))!;
        final after = [...gs]..removeAt(0);
        final start = after.length;
        after.addAll(parts);
        final out = remapAfterSplit(cs, 0, gs[0], after, start);
        expect(out.where((c) => c.type == t), isEmpty,
            reason: '$t must not survive a split');
      }
    });

    test('constraints NOT touching the carrier are untouched', () {
      final gs = [line(0, 0, 10, 0), line(4, -5, 4, 5), line(0, 8, 10, 8)];
      final cs = [Constraint(CType.horizontal, ents: [2])];
      final parts = splitEntity(gs, 0, const Offset(8, 0))!;
      final after = [...gs]..removeAt(0);
      final start = after.length;
      after.addAll(parts);
      final out = remapAfterSplit(cs, 0, gs[0], after, start);
      final hs = out.where((c) => c.type == CType.horizontal).toList();
      expect(hs.length, 1);
      expect(hs.single.ents.single, 1); // index 2 shifted down to 1
    });
  });

  group('end to end through AppState', () {
    test('a split leaves two entities glued at the cut', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([line(0, 0, 10, 0), line(4, -5, 4, 5)]);
      app.tool = Tool.split;
      app.toolClick(const Offset(8, 0));
      // carrier replaced by two pieces, cutter untouched
      expect(s.geometry.length, 3);
      final lines = s.geometry.where((g) => g.type == Geo.line).toList();
      expect(lines.length, 3);
      // the two halves meet at x=4 and are held there by a coincidence
      final glued = s.constraints.any((c) => c.type == CType.coincident);
      expect(glued, isTrue);
    });

    test('a dimension on the carrier is maintained', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([line(0, 0, 10, 0), line(4, -5, 4, 5)]);
      final before = s.constraints.length;
      s.constraints.add(Constraint(CType.horizontal, ents: [0]));
      app.tool = Tool.split;
      app.toolClick(const Offset(8, 0));
      // horizontal survived — on both halves (Inventor's inheritance rule)
      final hs =
          s.constraints.where((c) => c.type == CType.horizontal).toList();
      expect(hs.length, 2);
      expect(s.constraints.length, greaterThan(before));
    });

    test('projected geometry cannot be split', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([
        line(0, 0, 10, 0).withProj(1),
        line(4, -5, 4, 5),
      ]);
      app.tool = Tool.split;
      app.toolClick(const Offset(8, 0));
      expect(s.geometry.length, 2); // refused, nothing replaced
    });
  });

  group('one command session (Split / Trim / Extend)', () {
    test('right-click cycles Split -> Trim -> Extend -> Split', () {
      final app = makeApp();
      app.tool = Tool.split;
      expect(app.cycleModifyTool(), isTrue);
      expect(app.tool, Tool.trim);
      expect(app.cycleModifyTool(), isTrue);
      expect(app.tool, Tool.extendT);
      expect(app.cycleModifyTool(), isTrue);
      expect(app.tool, Tool.split);
    });

    test('outside the family the right-click is not consumed', () {
      final app = makeApp();
      app.tool = Tool.line;
      expect(app.cycleModifyTool(), isFalse);
      expect(app.tool, Tool.line);
    });

    test('the tool stays active so several curves can be split in a row', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([
        line(0, 0, 10, 0),
        line(0, 4, 10, 4),
        line(6, -5, 6, 9),
      ]);
      app.tool = Tool.split;
      app.toolClick(const Offset(9, 0));
      expect(app.tool, Tool.split, reason: 'session must not end on a split');
      app.toolClick(const Offset(9, 4));
      expect(s.geometry.length, 5); // both carriers halved, cutter intact
    });
  });
}

Matcher closestTo(double v) => closeTo(v, 1e-6);
