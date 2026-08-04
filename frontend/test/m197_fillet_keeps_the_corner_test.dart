// M197 — the fourth report of the 2026-08-05 device session:
//
//   "when i make a radius on a midpoint rect the construction lines dont go
//    into the corners anymore and the corners should stay there as
//    construction lines like with trimming"
//
// Two things in one sentence with one cause. A centre rectangle's diagonals
// are held by coincidences on the CORNER POINTS of its sides (M92), and a
// fillet moves exactly those points back to the tangent points — so the
// diagonals walked inward with them. In bug20260805T003600 diagonal 0 starts
// at -29.2119 where the corner is at -34.2119.
//
// Keeping the cut-away corner as construction (what M191 does for trim) fixes
// both halves: the virtual corner is a real point again, so the diagonals have
// something to hang on, and the corner is visibly still there.
//
// The load-bearing test in this file is the rank one. Two stubs are 8 new
// parameters, and they are worth having only if they come with 8 INDEPENDENT
// equations: one redundant row makes the LM normal equations singular and
// libslvs calls the whole sketch inconsistent, which is the failure mode this
// project has paid for twice (M37, M188).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/widgets/viewport.dart' show centreMarks;

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// A centre rectangle about the origin: corners at (±20, ±15), sides 0..3,
/// construction diagonals 4 and 5.
///
///   c0 (-20,-15)  c1 (20,-15)  c2 (20,15)  c3 (-20,15)
///   L0 c0->c1     L1 c1->c2    L2 c2->c3   L3 c3->c0
///   d0 c0->c2     d1 c1->c3
AppState centreRect() {
  final app = makeApp();
  app.tool = Tool.rect2PC;
  app.toolClick(const Offset(0, 0));
  app.toolClick(const Offset(20, 15));
  app.tool = Tool.none;
  return app;
}

/// Rounds the corner at c1 = (20,-15), between the bottom and right sides.
void filletC1(AppState app, {double r = 5}) {
  app.filletSess = FilletSession(Tool.fillet, radius: r);
  app.tool = Tool.fillet;
  app.toolClick(const Offset(15, -15)); // bottom edge, near c1
  app.toolClick(const Offset(20, -10)); // right edge, near c1
  app.tool = Tool.none;
}

List<int> constructionLines(SketchModel s) => [
      for (var i = 0; i < s.geometry.length; i++)
        if (s.geometry[i].type == Geo.line && s.geometry[i].isConstruction) i
    ];

void main() {
  test('the sketch under test is the one the report describes', () {
    final app = centreRect();
    final s = app.current!;
    expect(s.geometry, hasLength(6), reason: '4 sides + 2 diagonals');
    expect(getPt(s.geometry[1], 0).dx, closeTo(20, 1e-9));
    expect(getPt(s.geometry[1], 0).dy, closeTo(-15, 1e-9));
    expect(getPt(s.geometry[5], 0).dx, closeTo(20, 1e-9),
        reason: 'diagonal 1 starts at the corner c1 the fillet will eat');
  });

  test('THE REPORT: the diagonal still reaches the corner', () {
    final app = centreRect();
    final s = app.current!;
    filletC1(app);

    // The right edge has been pulled back — that is the fillet doing its job.
    expect(getPt(s.geometry[1], 0).dy, closeTo(-10, 1e-6),
        reason: 'the right edge now starts 5 above the old corner');
    // ...and the diagonal has NOT come with it.
    final d1 = getPt(s.geometry[5], 0);
    expect(d1.dx, closeTo(20, 1e-6));
    expect(d1.dy, closeTo(-15, 1e-6),
        reason: 'this is the whole bug: the diagonal used to be dragged to '
            '(20,-10) with the trimmed edge');
  });

  test('the cut-away corner is still there, as construction', () {
    final app = centreRect();
    final s = app.current!;
    final before = constructionLines(s).length;
    filletC1(app);
    final cons = constructionLines(s);
    expect(cons.length, before + 2, reason: 'one stub per trimmed edge');

    // They meet at the old corner, and each starts where its edge now ends.
    final stubs = cons.sublist(before);
    for (final i in stubs) {
      expect(getPt(s.geometry[i], 1).dx, closeTo(20, 1e-6));
      expect(getPt(s.geometry[i], 1).dy, closeTo(-15, 1e-6));
    }
    expect(getPt(s.geometry[stubs[0]], 0).dx, closeTo(15, 1e-6),
        reason: 'the bottom edge now ends 5 short of the corner');
    expect(getPt(s.geometry[stubs[1]], 0).dy, closeTo(-10, 1e-6),
        reason: 'the right edge now starts 5 above it');
  });

  test('the stubs cost no degrees of freedom and add no redundant row', () {
    // The one that matters. 8 parameters, 8 independent equations: the near
    // end coincident with the trimmed endpoint (2), the far end on that same
    // carrier (1 — a point-on-curve, which with the near end IS collinearity
    // but without the dependent row `collinear` would contribute), and the two
    // far ends coincident (2). A redundant row here is what makes libslvs
    // declare the sketch inconsistent.
    final app = centreRect();
    final s = app.current!;
    final (r0, e0, p0) = debugRank(s.geometry, s.constraints);
    expect(e0 - r0, 0, reason: 'the centre rectangle starts clean');
    expect(p0 - r0, 4, reason: 'centre x, centre y, width, height');

    filletC1(app);
    final (r1, e1, p1) = debugRank(s.geometry, s.constraints);
    expect(e1 - r1, 0, reason: 'still redundancy-free with the stubs in');
    expect(p1 - r1, 4, reason: 'a fillet with a radius dimension is neutral');
    expect(analyzeSketch(s.geometry, s.constraints).dof, 4);
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
  });

  test('the corner survives a drag, because it is constrained and not drawn',
      () {
    final app = centreRect();
    final s = app.current!;
    filletC1(app);
    final stub = constructionLines(s).last;

    // Drag the opposite corner outward; the whole rectangle changes size.
    final gs = List<Geo>.from(s.geometry);
    final c3 = getPt(gs[3], 0);
    gs[3] = gs[3].withData(
        [c3.dx - 10, c3.dy + 8, gs[3].data[2], gs[3].data[3]]);
    expect(
        solveConstraints(gs, s.constraints,
            dragged: const {(3, 0)}, iterations: 200),
        isTrue,
        reason: 'the drag itself has to succeed for the rest to mean anything');

    // Wherever the corner ended up, the two stubs still meet there — it is a
    // constrained point now, not a remembered coordinate.
    final corner = getPt(gs[stub], 1);
    final other = getPt(gs[stub - 1], 1);
    expect((corner - other).distance, lessThan(1e-6));
    // ...and it is still the crossing of the two carriers, i.e. still square
    // with the shape: the right edge's x and the bottom edge's y.
    expect(corner.dx, closeTo(getPt(gs[1], 1).dx, 1e-6));
    expect(corner.dy, closeTo(getPt(gs[0], 0).dy, 1e-6));
  });

  test('the centre mark still finds the centre after a corner is rounded', () {
    // M196 draws the centre from the diagonals' shared midpoint. If a fillet
    // had dragged one diagonal end inward, the dot would drift off-centre too
    // — the same bug seen from the other side.
    final app = centreRect();
    final s = app.current!;
    filletC1(app);
    final marks = centreMarks(s.geometry, visible: (_) => true);
    expect(marks, hasLength(1));
    expect(marks.single.dx, closeTo(0, 1e-6));
    expect(marks.single.dy, closeTo(0, 1e-6));
  });

  test('two lines that never met keep no corner', () {
    // Nothing was cut away, so there is nothing to keep: inventing a corner
    // where the picks did not share one would pin two carriers to a crossing
    // that the user never drew.
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(0, 0, 40, 0);
    s.engine.addLine(60, 20, 60, 60); // disjoint from the first
    s.refresh();
    final before = constructionLines(s).length;
    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(20, 0));
    app.toolClick(const Offset(60, 40));
    expect(s.geometry.any((g) => g.type == Geo.arc), isTrue,
        reason: 'the fillet itself must land, or this proves nothing');
    expect(constructionLines(s).length, before,
        reason: 'no shared corner, no stubs');
  });

  test('a re-anchored dimension keeps everything except its point', () {
    // The corner refs are rewritten with Constraint.withPts. A dimension that
    // lost its value, name, expression, label position or driven flag on the
    // way would be silent data loss dressed up as a constraint edit.
    final d = Constraint(CType.dimension,
        pts: [const PRef(1, 0), const PRef(2, 1)],
        ents: [7],
        value: 42.5,
        dimKind: 'distx',
        textPos: const Offset(3, 4),
        driven: true,
        anchors: [1, 2],
        tanBranch: 1,
        paramName: 'd7',
        expr: 'd3*2');
    final moved = d.withPts([const PRef(9, 1), const PRef(2, 1)]);
    expect(moved.pts[0], const PRef(9, 1));
    expect(moved.type, d.type);
    expect(moved.ents, d.ents);
    expect(moved.value, 42.5);
    expect(moved.dimKind, 'distx');
    expect(moved.textPos, const Offset(3, 4));
    expect(moved.driven, isTrue);
    expect(moved.anchors, [1, 2]);
    expect(moved.tanBranch, 1);
    expect(moved.paramName, 'd7');
    expect(moved.expr, 'd3*2');
  });
}
