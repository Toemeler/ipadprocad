// Regression (device session 2026-07-17): two overlapping rectangles, then
// trimming away one span of EACH so that the two new cut endpoints land
// exactly on top of each other. Inventor binds such stacked cut points
// point-ON-POINT. The app instead left them with only the point-on-curve
// bind from the FIRST trim: the stale on-curve coincidence both blocked the
// re-bind (`bound` matched any coincident) and made the point-on-point
// candidate redundant (the over-constraint gate rejected it silently) —
// log: "cut-bind ... pts=e6.p1,e9.p0" with "constraints 22 -> 22".
// Fix: only a point-on-point blocks re-binding, and a found point-on-point
// REPLACES the on-curve bind it subsumes.

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

/// All point refs of [gs] lying within [tol] of [q].
List<PRef> refsAt(List<Geo> gs, Offset q, [double tol = 1e-6]) => [
      for (var e = 0; e < gs.length; e++)
        for (var p = 0; p < ptCount(gs[e]); p++)
          if ((getPt(gs[e], p) - q).distance < tol) PRef(e, p)
    ];

void main() {
  test('stacked trim endpoints of two rectangles get point-on-point', () {
    final app = makeApp();
    final s = app.current!;
    // rectangle 1: (0,0)-(100,80); rectangle 2 overlaps its top-right corner
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(100, 80));
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(60, 50));
    app.toolClick(const Offset(140, 120));
    expect(solveConstraints(List<Geo>.from(s.geometry), s.constraints), isTrue);

    // Trim 1: rect2's bottom edge, the span INSIDE rect1 — the surviving
    // piece's new endpoint (100,50) lies on the INTERIOR of rect1's right
    // edge -> a point-on-curve bind is correct at this moment.
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(80, 50));
    expect(solveConstraints(List<Geo>.from(s.geometry), s.constraints), isTrue);
    final afterFirst = refsAt(s.geometry, const Offset(100, 50));
    expect(afterFirst.length, 1,
        reason: 'first trim leaves ONE endpoint at the crossing');
    final onCurve = s.constraints.where((c) =>
        c.type == CType.coincident &&
        c.pts.length == 1 &&
        c.ents.length == 1 &&
        c.pts[0] == afterFirst[0]);
    expect(onCurve.length, 1,
        reason: 'first cut endpoint is bound point-on-curve onto the cutter');

    // Trim 2: rect1's right edge, the span INSIDE rect2 — the surviving
    // piece's new endpoint lands EXACTLY on the endpoint trim 1 created.
    app.toolClick(const Offset(100, 70));
    final gs = s.geometry;
    expect(solveConstraints(List<Geo>.from(gs), s.constraints), isTrue);

    final stacked = refsAt(gs, const Offset(100, 50));
    expect(stacked.length, 2,
        reason: 'second trim stacks its endpoint on the first one');

    // THE regression: the stacked pair shares a point-ON-POINT coincidence…
    final pp = s.constraints.where((c) =>
        c.type == CType.coincident &&
        c.pts.length == 2 &&
        c.pts.toSet().containsAll(stacked.toSet()));
    expect(pp.length, 1,
        reason: 'stacked cut endpoints must be bound point-on-point '
            '(constraints: ${s.constraints.map((c) => c.toJson())})');

    // …and the subsumed point-on-curve of either onto the other's entity is
    // GONE (it would make the pair redundant and re-break the gate).
    final subsumed = s.constraints.where((c) =>
        c.type == CType.coincident &&
        c.pts.length == 1 &&
        c.ents.length == 1 &&
        stacked.contains(c.pts[0]) &&
        stacked.any((r) => r.ent == c.ents[0]));
    expect(subsumed, isEmpty,
        reason: 'the on-curve bind is upgraded, not stacked');

    // Behavioural check: dragging one of the stacked points keeps them glued.
    final mover = stacked[0];
    final probe = List<Geo>.from(gs);
    probe[mover.ent] =
        setPt(probe[mover.ent], mover.pt, const Offset(95, 45));
    final ok = solveConstraints(probe, s.constraints,
        dragged: {(mover.ent, mover.pt)});
    expect(ok, isTrue);
    final a = getPt(probe[stacked[0].ent], stacked[0].pt);
    final b = getPt(probe[stacked[1].ent], stacked[1].pt);
    expect((a - b).distance, lessThan(1e-6),
        reason: 'stacked trim endpoints move as one point');
  });
}
