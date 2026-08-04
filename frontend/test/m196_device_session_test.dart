// M196 — three of the four reports from the device session of 2026-08-05
// (build a2d3107). The numbers below are lifted from the bundles, not invented.
//
//  * bug20260805T003320 "a midpoint rect should have a point in the middle"
//  * bug20260805T003448 "when i use a tool from the ribbon, then click again on
//    the tool, it should be deselected ... like canceling"
//  * bug20260805T003702 "i dragged the shape around and now there is a shape
//    which should not be possible"
//
// The fourth (fillet on a centre rect must leave the corners behind as
// construction) is diagnosed but NOT fixed here, so it has no test yet.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/widgets/viewport.dart' show centreMarks;

Geo line(double x0, double y0, double x1, double y1, {bool con = false}) {
  final g = Geo(Geo.line, [x0, y0, x1, y1]);
  return con ? g.withStyle(Geo.styleConstruction) : g;
}

Geo arc(double cx, double cy, double r, double a0, double a1, double rev) =>
    Geo(Geo.arc, [cx, cy, r, a0, a1, rev]);

AppState editingApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  group('the centre of a centre rectangle is drawn (T003320)', () {
    // The sketch as the bundle recorded it: four sides plus the two M92
    // construction diagonals. The centre is where they cross.
    List<Geo> deviceRect() => [
          line(-34.212, 16.902, 9.971, 16.902),
          line(9.971, 16.902, 9.971, -7.607),
          line(9.971, -7.607, -34.212, -7.607),
          line(-34.212, -7.607, -34.212, 16.902),
          line(-34.212, 16.902, 9.971, -7.607, con: true),
          line(9.971, 16.902, -34.212, -7.607, con: true),
        ];

    test('one mark, at the crossing of the diagonals', () {
      final marks = centreMarks(deviceRect(), visible: (_) => true);
      expect(marks, hasLength(1));
      expect(marks.single.dx, closeTo((-34.212 + 9.971) / 2, 1e-9));
      expect(marks.single.dy, closeTo((16.902 - 7.607) / 2, 1e-9));
    });

    test('it follows the shape instead of being stored beside it', () {
      // Derived, so a drag cannot leave it behind — which is the whole reason
      // it is not an entity. Move one corner: the mark moves with the
      // diagonals, no solve, no constraint, no extra degree of freedom.
      final gs = deviceRect();
      gs[4] = line(-20, 30, 9.971, -7.607, con: true);
      gs[5] = line(9.971, 30, -20, -7.607, con: true);
      final m = centreMarks(gs, visible: (_) => true).single;
      expect(m.dx, closeTo((-20 + 9.971) / 2, 1e-9));
      expect(m.dy, closeTo((30 - 7.607) / 2, 1e-9));
    });

    test('a plain rectangle gets no mark — it has no diagonals', () {
      final gs = deviceRect().sublist(0, 4);
      expect(centreMarks(gs, visible: (_) => true), isEmpty);
    });

    test('two construction lines that merely cross do NOT make a centre', () {
      // An X drawn by hand shares no midpoint; only a rectangle's diagonals
      // bisect each other. Without this the app would sprinkle dots over any
      // construction scaffolding.
      final gs = [
        line(0, 0, 10, 10, con: true), // midpoint (5, 5)
        line(0, 8, 6, 0, con: true), // crosses it, midpoint (3, 4)
      ];
      expect(centreMarks(gs, visible: (_) => true), isEmpty);
    });

    test('two collinear construction lines do not make a centre either', () {
      // One line drawn twice shares a midpoint but has no crossing.
      final gs = [
        line(0, 0, 10, 0, con: true),
        line(0, 0, 10, 0, con: true),
      ];
      expect(centreMarks(gs, visible: (_) => true), isEmpty);
    });

    test('normal geometry is never mistaken for a diagonal', () {
      final gs = [
        line(-5, -5, 5, 5), // not construction
        line(-5, 5, 5, -5),
      ];
      expect(centreMarks(gs, visible: (_) => true), isEmpty);
    });

    test('hidden or foreign-layer geometry contributes nothing', () {
      expect(centreMarks(deviceRect(), visible: (_) => false), isEmpty);
    });
  });

  group('a ribbon tool toggles off (T003448)', () {
    // The ribbon calls cancelTool twice; these pin the AppState semantics that
    // rests on, because "tap the armed tool again" must end with NO tool.
    test('with picks pending: first cancel clears them, second disarms', () {
      final app = editingApp();
      app.selectTool(Tool.line);
      app.toolClick(const Offset(0, 0));
      expect(app.toolPoints, isNotEmpty);

      app.cancelTool();
      expect(app.tool, Tool.line, reason: 'M53: the command stays armed');
      expect(app.toolPoints, isEmpty);

      app.cancelTool();
      expect(app.tool, Tool.none);
    });

    test('with nothing pending: one cancel already disarms', () {
      final app = editingApp();
      app.selectTool(Tool.circleCenter);
      app.cancelTool();
      expect(app.tool, Tool.none,
          reason: 'the second cancel the ribbon would send is guarded on the '
              'tool still being up, so it never runs here');
    });

    test('disarming does not cost the user their selection', () {
      // Why the ribbon guards its second cancelTool: with no tool armed,
      // cancelTool clears the SELECTION.
      final app = editingApp();
      app.selectTool(Tool.line);
      app.selection.add(0);
      app.cancelTool(); // tool was armed, no picks -> disarms
      expect(app.tool, Tool.none);
      expect(app.selection, {0}, reason: 'the selection is not the tool');
    });
  });

  group('a corner fillet may not go the long way round (T003702)', () {
    // The device sketch, before and after the drag. Both states satisfy every
    // constraint exactly — the log recorded `verify ok residual=2.51e-15` for
    // the broken one — so nothing but continuity can tell them apart.
    List<Geo> before() => [
          line(-29.212, 16.902, 4.971, 16.902),
          line(9.971, 11.902, 9.971, -7.607),
          line(9.971, -7.607, -34.212, -7.607),
          line(-34.212, -7.607, -34.212, 11.902),
          line(-29.212, 16.902, 9.971, -7.607, con: true),
          line(9.971, 11.902, -34.212, -7.607, con: true),
          arc(-29.212, 11.902, 5, 3.1416, 1.5708, 1),
          arc(4.971, 11.902, 5, 1.5708, 0, 1),
        ];

    List<Geo> after() => [
          line(-34.8688, 17.1711, -11.9138, 17.1711),
          line(-16.9138, 12.1711, -16.9138, 28.71),
          line(-16.9138, 28.71, -29.8688, 28.71),
          line(-29.8688, 28.71, -29.8688, 12.1711),
          line(-34.8688, 17.1711, -16.9138, 28.71, con: true),
          line(-16.9138, 12.1711, -29.8688, 28.71, con: true),
          arc(-34.8688, 12.1711, 5, 0, 1.5708, 1),
          arc(-11.9138, 12.1711, 5, 1.5708, 3.1416, 1),
        ];

    // The tangency/coincidence set the bundle listed, trimmed to what the
    // guard reads: which arcs are tangent to which lines.
    final cs = <Constraint>[
      Constraint(CType.tangent, ents: [6, 3]),
      Constraint(CType.tangent, ents: [6, 0]),
      Constraint(CType.tangent, ents: [7, 0]),
      Constraint(CType.tangent, ents: [7, 1]),
    ];

    test('the sweep, not the reversed flag, is what changed', () {
      // Both arcs kept reversed=1 the whole time. The flag is not the shape.
      expect(before()[6].data[5], after()[6].data[5]);
      expect(arcSweep(before()[6]).abs(), closeTo(1.5708, 1e-3),
          reason: 'a 90° corner round');
      expect(arcSweep(after()[6]).abs(), closeTo(3 * 1.5708, 1e-3),
          reason: 'the 270° lobe on the screenshot');
    });

    test('both arcs are recognised as corner fillets', () {
      expect(cornerFilletArcs(after(), cs), {6, 7});
    });

    test('an arc tangent to only ONE line is not a corner fillet', () {
      expect(
          cornerFilletArcs(after(), [Constraint(CType.tangent, ents: [6, 0])]),
          isEmpty);
    });

    test('the flip is caught', () {
      expect(flippedCornerFillets(before(), after(), cs), [6, 7]);
    });

    test('an ordinary drag is not caught', () {
      // Same shape, moved 3 mm. Nothing flipped, so nothing is rejected —
      // a guard that fires on normal editing would be worse than the bug.
      final moved = [
        for (final g in before())
          g.type == Geo.arc
              ? g.withData([g.data[0] + 3, ...g.data.sublist(1)])
              : g.withData([
                  g.data[0] + 3,
                  g.data[1],
                  g.data[2] + 3,
                  g.data[3],
                ])
      ];
      expect(flippedCornerFillets(before(), moved, cs), isEmpty);
    });

    test('an arc that was ALREADY major is left alone', () {
      // The guard is about crossing the half turn during one solve, not about
      // policing shapes. A sketch that legitimately holds a major arc — or one
      // saved before this existed — must stay editable.
      final major = after();
      expect(flippedCornerFillets(major, major, cs), isEmpty);
    });

    test('the guard reads the solver-visible state, not the drawing', () {
      // A flip in the other direction (major -> minor) is a repair, not a
      // corruption, and must not be rejected.
      expect(flippedCornerFillets(after(), before(), cs), isEmpty);
    });
  });
}
