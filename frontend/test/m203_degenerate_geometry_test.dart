// M203 — one collapsed shape must not freeze the whole sketch.
//
//   "i cant drag around any point. it seems stuck somehow and buggy."
//   "the constraint should have worked here"
//
// Both reports are the same sketch and the same cause. bug20260805T131430
// records a rectangle drawn from two clicks 20 ms apart at the same y — a tap
// bounce, not a drawn shape — and the commit logged
//
//   construction auto-constraints unsatisfied for Tool.rectTwoPoint —
//   committing as drawn WITHOUT them
//
// so a box with two ZERO-LENGTH sides went into the document. From that point
// on the log is the same two lines over and over:
//
//   solve: done via lm-frozen maxAbs=18.803 resid=3.66e-9 ok=false
//   drag: frame solve unsatisfied — holding last good geometry
//   constraint: REJECTED [-1] horizontal/ ents=0 — cannot be satisfied
//
// A residual of 3.66e-9 is a SOLVED system. It was refused because the gate
// asked "does this sketch contain a degenerate entity" — and it did, forever.
// Every repair a user could attempt is itself a solve, so the document was
// unrecoverable from inside the app.
//
// Two changes, tested here:
//   1. the rect builders refuse a box with no width or no height, so the shape
//      never enters a document in the first place;
//   2. the solve gate asks whether THIS SOLVE collapsed something, comparing
//      against the pre-solve snapshot — the same continuity rule the fillet
//      branch guard uses — so a sketch that already contains one stays
//      draggable and constrainable.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/tools.dart';

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

void main() {
  group('the shape never gets in', () {
    test('THE REPORT: a rectangle with no height is refused', () {
      // The two device clicks: (x1,y) then (x2,y), 20 ms apart.
      final g = buildToolGeometry(
          Tool.rectTwoPoint, [const Offset(10, 40), const Offset(60, 40)]);
      expect(g, isNull,
          reason: 'this produced four lines, two of them zero-length');
    });

    test('and one with no width', () {
      expect(
          buildToolGeometry(
              Tool.rectTwoPoint, [const Offset(10, 5), const Offset(10, 90)]),
          isNull);
    });

    test('a real rectangle is untouched', () {
      final g = buildToolGeometry(
          Tool.rectTwoPoint, [const Offset(0, 0), const Offset(30, 20)]);
      expect(g, isNotNull);
      expect(g!.length, 4);
      expect(hasDegenerateGeometry(g), isFalse);
    });

    test('the centre-out rectangle refuses the same way', () {
      expect(
          buildToolGeometry(
              Tool.rect2PC, [const Offset(0, 0), const Offset(25, 0)]),
          isNull);
      expect(
          buildToolGeometry(
              Tool.rect2PC, [const Offset(0, 0), const Offset(25, 15)]),
          isNotNull);
    });

    test('nothing lands in the document, and the tool stays armed', () {
      final app = makeApp();
      app.selectTool(Tool.rectTwoPoint);
      app.toolClick(const Offset(10, 40));
      app.toolClick(const Offset(60, 40)); // the bounce
      expect(app.current!.geometry, isEmpty,
          reason: 'a collapsed box must not enter the sketch');
      expect(app.toolPoints, isEmpty, reason: 'and the tool is ready again');
      // The very next attempt, drawn properly, must work.
      app.toolClick(const Offset(10, 40));
      app.toolClick(const Offset(60, 70));
      expect(app.current!.geometry.length, 4);
    });
  });

  group('newlyDegenerate: what THIS solve broke', () {
    test('a line that collapsed during the solve is reported', () {
      final before = [line(0, 0, 10, 0)];
      final after = [line(0, 0, 0, 0)];
      expect(newlyDegenerate(before, after), [0]);
    });

    test('a line that was ALREADY collapsed is not', () {
      // This is the whole fix: the poisoned sketch must not keep being blamed
      // on every solve that touches it.
      final zero = line(5, 5, 5, 5);
      expect(newlyDegenerate([zero], [zero]), isEmpty);
    });

    test('healthy geometry reports nothing', () {
      final gs = [line(0, 0, 10, 0), Geo(Geo.circle, [0, 0, 4])];
      expect(newlyDegenerate(gs, gs), isEmpty);
    });

    test('an entity with no counterpart in the snapshot is not blamed', () {
      // Indices past the snapshot cannot be compared, so they are left alone.
      expect(newlyDegenerate([line(0, 0, 10, 0)], [line(0, 0, 10, 0), line(1, 1, 1, 1)]),
          isEmpty);
    });

    test('isDegenerateGeo knows the three collapsed forms', () {
      expect(isDegenerateGeo(line(0, 0, 0, 0)), isTrue);
      expect(isDegenerateGeo(line(0, 0, 1e-9, 0)), isTrue);
      expect(isDegenerateGeo(line(0, 0, 10, 0)), isFalse);
      expect(isDegenerateGeo(Geo(Geo.circle, [0, 0, 0])), isTrue);
      expect(isDegenerateGeo(Geo(Geo.circle, [0, 0, 3])), isFalse);
      expect(isDegenerateGeo(Geo(Geo.arc, [0, 0, 5, 1, 1])), isTrue,
          reason: 'zero sweep');
      expect(isDegenerateGeo(Geo(Geo.arc, [0, 0, 5, 0, 1.5])), isFalse);
    });

    test('hasDegenerateGeometry is still the any() of it', () {
      expect(hasDegenerateGeometry([line(0, 0, 10, 0), line(2, 2, 2, 2)]),
          isTrue);
      expect(hasDegenerateGeometry([line(0, 0, 10, 0)]), isFalse);
    });
  });

  group('a poisoned sketch stays usable', () {
    /// The device document, reduced: one collapsed line beside real geometry.
    (List<Geo>, List<Constraint>) poisoned() {
      final gs = <Geo>[
        line(20, 20, 20, 20), // the bounce
        line(0, 0, 40, 3), // a real, slightly sloped edge
      ];
      return (gs, <Constraint>[]);
    }

    test('THE REPORT: the solve is no longer refused', () {
      final (gs, cs) = poisoned();
      cs.add(Constraint(CType.horizontal, ents: [1]));
      expect(solveConstraints(gs, cs), isTrue,
          reason: 'resid was 3.66e-9 and it was still called unsatisfied');
      expect(constraintResidualNorm(gs, cs), lessThan(1e-6));
    });

    test('and the collapsed line is still collapsed — it was not "fixed"', () {
      // Nothing here repairs the bad entity. It stays exactly as it was; it
      // simply stops vetoing everything else.
      final (gs, cs) = poisoned();
      cs.add(Constraint(CType.horizontal, ents: [1]));
      solveConstraints(gs, cs);
      expect(isDegenerateGeo(gs[0]), isTrue);
    });

    test('a drag on the healthy edge moves it', () {
      final (gs, cs) = poisoned();
      cs.add(Constraint(CType.horizontal, ents: [1]));
      solveConstraints(gs, cs);
      final start = getPt(gs[1], 1);
      gs[1] = gs[1].withData([gs[1].data[0], gs[1].data[1], 55, 12]);
      expect(solveConstraints(gs, cs, dragged: {(1, 1)}), isTrue,
          reason: '"i cant drag around any point"');
      expect(getPt(gs[1], 1).dx, isNot(closeTo(start.dx, 1e-6)));
    });

    test('a solve that WOULD collapse a healthy line is still refused', () {
      // The guard has to keep working, or M185's blank geometry comes back.
      // Coincidence between a line's OWN two ends is linear, so the solve
      // lands on it exactly — the residual is zero and the only thing that can
      // refuse it is the degeneracy check.
      final gs = [line(0, 0, 10, 0)];
      final cs = [
        Constraint(CType.coincident,
            pts: [const PRef(0, 0), const PRef(0, 1)]),
      ];
      expect(solveConstraints(gs, cs), isFalse,
          reason: 'pulling a line onto itself collapses it');
      expect(isDegenerateGeo(gs[0]), isTrue,
          reason: 'and the solve really did collapse it — not a false alarm');
    });
  });
}
