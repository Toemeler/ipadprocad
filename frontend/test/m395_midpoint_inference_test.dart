// M395 — #23: "this middle line should be fully constraint since i started and
// ended it on middle points of lines but this doesnt make automatic
// constraints there somehow".
//
// The snap engine offers 'midpoint' ahead of 'on' and lands the point exactly
// halfway, so the click was right; inference then treated it as any other
// landing on a curve and emitted a point-on-line coincidence. That removes ONE
// degree of freedom instead of two, so the line kept sliding along both
// carriers and the sketch was never fully constrained.
//
// The report from the same session two minutes later (#25) is the same defect
// paying out: the middle line was the MIRROR AXIS, it sat at y=167.9969 rather
// than 168, and every mirrored point therefore landed 0.0062 mm off the edge
// it was meant to close against. The last test here is that sketch.
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// The rectangle the reported sketch was drawn in: 50 wide, 336 tall, with
/// the left edge on x=0.
///
/// PROJECTED, as it was there — these are the four edges of the face the
/// sketch sits on. That matters for more than fidelity: a projection is
/// pinned reference geometry, so its midpoint is a FIXED point, which is
/// what makes the middle line fully constrained and the horizontal read off
/// it redundant. The same lines drawn in mid-air would be neither.
List<Geo> frame() => [
      Geo(Geo.line, [0, 0, -50, 0]).withProj(Geo.projSolid), // bottom
      Geo(Geo.line, [0, 336, -50, 336]).withProj(Geo.projSolid), // top
      Geo(Geo.line, [0, 0, 0, 336]).withProj(Geo.projSolid), // right
      Geo(Geo.line, [-50, 0, -50, 336]).withProj(Geo.projSolid), // left
    ];

List<Constraint> ofType(List<Constraint> cs, CType t) =>
    [for (final c in cs) if (c.type == t) c];

void main() {
  test('a point on a line MIDPOINT infers a midpoint constraint', () {
    final gs = frame()..add(Geo(Geo.line, [0, 168, -50, 168]));
    final cs = inferConstraints(gs, 4);
    final mids = ofType(cs, CType.midpoint);
    expect(mids, hasLength(2), reason: 'one per end');
    expect({for (final c in mids) c.ents.single}, {2, 3});
    expect({for (final c in mids) c.pts.single}, {const PRef(4, 0), const PRef(4, 1)});
    // and NOT the weaker point-on-curve bind it used to be
    expect(
        [
          for (final c in ofType(cs, CType.coincident))
            if (c.pts.length == 1 && c.ents.length == 1) c
        ],
        isEmpty);
  });

  test('anywhere else on the same line is still a point-on-line', () {
    // A third of the way up: on the carrier, not at its middle.
    final gs = frame()..add(Geo(Geo.line, [0, 112, -50, 112]));
    final cs = inferConstraints(gs, 4);
    expect(ofType(cs, CType.midpoint), isEmpty);
    expect(
        [
          for (final c in ofType(cs, CType.coincident))
            if (c.pts.length == 1 && c.ents.length == 1) c
        ],
        hasLength(2));
  });

  test('a midpoint pins BOTH coordinates — the middle line has no DOF left',
      () {
    // What the report asked for in one number. The frame is fixed; the middle
    // line's four parameters are answered by the two midpoint constraints.
    final gs = frame()..add(Geo(Geo.line, [0, 168, -50, 168]));
    final inferred = inferConstraints(gs, 4);
    // The frame needs no constraints of its own: analyzeSketch pins every
    // projection where its source is, exactly as the solver does.
    final cs = <Constraint>[
      // What the commit path keeps: the bindings, and no direction constraint
      // they have already implied.
      for (final c in inferred)
        if (!isDirectionConstraint(c)) c,
    ];
    expect(analyzeSketch(gs, cs).dof, 0, reason: 'fully constrained');
  });

  test('the horizontal the bindings already imply is redundant', () {
    // The middle line IS horizontal, and inference reads that off it as
    // well. Against two midpoints on FIXED edges that is a fifth equation on
    // four parameters — which is what the commit path's gate is there to
    // catch, because a solve that refuses the set throws away the midpoints
    // with it.
    final gs = frame()..add(Geo(Geo.line, [0, 168, -50, 168]));
    final inferred = inferConstraints(gs, 4);
    final horiz = ofType(inferred, CType.horizontal);
    expect(horiz, hasLength(1), reason: 'inference still reads it off');
    final bindings = [
      for (final c in inferred)
        if (!isDirectionConstraint(c)) c
    ];
    expect(wouldOverconstrain(gs, bindings, horiz.single), isTrue);
  });

  test('but the closing edge of a free rectangle keeps its horizontal', () {
    // The case the gate must NOT swallow: both ends of this line are bound
    // to other points, and those points are free themselves, so the
    // direction still says something no binding said.
    final gs = [
      Geo(Geo.line, [0, 0, 40, 0]), // A -> B
      Geo(Geo.line, [40, 0, 40, 30]), // B -> C
      Geo(Geo.line, [40, 30, 0, 30]), // C -> D
      Geo(Geo.line, [0, 30, 0, 0]), // D -> A, the closing edge
    ];
    final inferred = inferConstraints(gs, 3);
    final vert = ofType(inferred, CType.vertical);
    expect(vert, hasLength(1));
    final prior = <Constraint>[
      for (var i = 0; i < 3; i++) ...inferConstraints(gs.sublist(0, i + 1), i),
    ];
    final bindings = [
      for (final c in inferred)
        if (!isDirectionConstraint(c)) c
    ];
    expect(
        wouldOverconstrain(gs, [...prior, ...bindings], vert.single), isFalse,
        reason: 'nothing has fixed this edge in space');
  });

  test('one end on a midpoint still gets its direction constraint', () {
    // Only the left end lands on a midpoint; the right end is free, so
    // horizontal says something no binding said.
    final gs = frame()..add(Geo(Geo.line, [0, 168, -30, 168]));
    final cs = inferConstraints(gs, 4);
    expect(ofType(cs, CType.midpoint), hasLength(1));
    expect(ofType(cs, CType.horizontal), hasLength(1));
    final bindings = [
      for (final c in cs)
        if (!isDirectionConstraint(c)) c
    ];
    expect(
        wouldOverconstrain(
            gs, bindings, ofType(cs, CType.horizontal).single),
        isFalse);
  });

  test('drawn through the app, the middle line comes out fully constrained',
      () {
    // The report, end to end: the projected edges of the face, and one line
    // drawn from the middle of one to the middle of the other.
    final app = makeApp();
    final s = app.current!;
    s.geometry.addAll(frame());
    app.editingLayer = kDefaultLayer;
    for (final g in s.geometry) {
      if (!s.layers.contains(g.layer)) s.layers.add(g.layer);
    }
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 168)); // the midpoint snap put it here
    app.toolClick(const Offset(-50, 168));
    expect(s.geometry, hasLength(5));
    final mine = s.constraints;
    expect(ofType(mine, CType.midpoint), hasLength(2),
        reason: 'both ends (${mine.map((c) => c.toJson())})');
    expect(ofType(mine, CType.horizontal), isEmpty,
        reason: 'the bindings already said it');
    expect(app.analysis?.dof, 0, reason: 'nothing left to drag');
  });

  test('the mirror axis lands on 168, so the mirrored profile closes', () {
    // #25, reduced: the three drawn segments off the top edge, the middle
    // line, and their mirror images about it. With the axis exactly halfway,
    // the mirror of a point on y=336 is a point on y=0 — the bottom edge —
    // and the arrangement finds the closed region. Off by the 0.0031 that a
    // point-on-line axis allowed, it does not.
    List<Geo> sketch(double axisY) {
      final f = frame();
      final drawn = [
        Geo(Geo.line, [0, 336, -6.0116, 343.9913]),
        Geo(Geo.line, [-6.0116, 343.9913, -7.6099, 342.7889]),
        Geo(Geo.line, [-7.6099, 342.7889, -2.5027, 336]),
      ];
      Offset mirror(Offset p) => Offset(p.dx, 2 * axisY - p.dy);
      final copies = <Geo>[];
      for (final g in drawn) {
        final a = mirror(getPt(g, 0)), b = mirror(getPt(g, 1));
        copies.add(Geo(Geo.line, [a.dx, a.dy, b.dx, b.dy]));
      }
      return [...f, ...drawn, Geo(Geo.line, [0, axisY, -50, axisY]), ...copies];
    }

    // The mirrored bump hangs BELOW the frame (its source rises to y=344, so
    // its image drops to y=-8). A loop whose centroid is under y=0 therefore
    // exists exactly when the mirrored part closed.
    bool mirroredPartClosed(double axisY) {
      final s = SketchModel('t')..geometry.addAll(sketch(axisY));
      return profileLoops(s).any((l) => l.centroid.dy < 0);
    }

    expect(mirroredPartClosed(168), isTrue);
    expect(mirroredPartClosed(167.9969), isFalse,
        reason: 'the 6 um miss is what the report ran into');
  });
}
