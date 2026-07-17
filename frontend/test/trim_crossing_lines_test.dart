// User report #2: TWO BARE CROSSING LINES (no rectangles).
//   trim one side of line A  -> A's new endpoint lies on line B's interior
//                               => point-on-CURVE bind expected
//   trim one side of line B  -> B's new endpoint stacks exactly on A's
//                               => upgraded to point-ON-POINT expected

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

List<PRef> refsAt(List<Geo> gs, Offset q, [double tol = 1e-6]) => [
      for (var e = 0; e < gs.length; e++)
        for (var p = 0; p < ptCount(gs[e]); p++)
          if ((getPt(gs[e], p) - q).distance < tol) PRef(e, p)
    ];

void main() {
  for (final oblique in const [false, true]) {
    for (final reversed in const [false, true]) {
      test(
          'crossing lines (oblique=$oblique, reversedOrder=$reversed): '
          'trim one -> on-curve, trim both -> point-on-point', () {
        final app = makeApp();
        final s = app.current!;
        // line A and B crossing at x
        final a0 = oblique ? const Offset(0, 0) : const Offset(0, 50);
        final a1 = oblique ? const Offset(100, 100) : const Offset(100, 50);
        final b0 = oblique ? const Offset(0, 100) : const Offset(50, 0);
        final b1 = oblique ? const Offset(100, 0) : const Offset(50, 100);
        const x = Offset(50, 50); // the crossing
        app.selectTool(Tool.line);
        app.toolClick(a0);
        app.toolClick(a1);
        app.selectTool(Tool.line); // break the chain
        app.toolClick(b0);
        app.toolClick(b1);
        expect(s.geometry.length, 2);

        // pick points on the spans to cut away, one per line
        final pickA = oblique ? const Offset(80, 80) : const Offset(80, 50);
        final pickB = oblique ? const Offset(80, 20) : const Offset(50, 80);
        final first = reversed ? pickB : pickA;
        final second = reversed ? pickA : pickB;

        // Trim 1
        app.selectTool(Tool.trim);
        app.toolClick(first);
        expect(
            solveConstraints(List<Geo>.from(s.geometry), s.constraints), isTrue);
        var at = refsAt(s.geometry, x);
        expect(at.length, 1,
            reason: 'one endpoint at the crossing after trim 1');
        final onCurve = s.constraints.where((c) =>
            c.type == CType.coincident &&
            c.pts.length == 1 &&
            c.ents.length == 1 &&
            c.pts[0] == at[0]);
        expect(onCurve.length, 1,
            reason: 'single trim: new endpoint bound point-on-CURVE onto the '
                'crossing line (constraints: '
                '${s.constraints.map((c) => c.toJson())})');

        // Trim 2
        app.toolClick(second);
        final gs = s.geometry;
        expect(solveConstraints(List<Geo>.from(gs), s.constraints), isTrue);
        at = refsAt(gs, x);
        expect(at.length, 2,
            reason: 'both trimmed endpoints stack at the crossing');
        final pp = s.constraints.where((c) =>
            c.type == CType.coincident &&
            c.pts.length == 2 &&
            c.pts.toSet().containsAll(at.toSet()));
        expect(pp.length, 1,
            reason: 'stacked endpoints bound point-ON-POINT (constraints: '
                '${s.constraints.map((c) => c.toJson())})');
        final subsumed = s.constraints.where((c) =>
            c.type == CType.coincident &&
            c.pts.length == 1 &&
            c.ents.length == 1 &&
            at.contains(c.pts[0]) &&
            at.any((r) => r.ent == c.ents[0]));
        expect(subsumed, isEmpty,
            reason: 'on-curve bind upgraded, not stacked');

        // and they drag as one point
        final mover = at[0];
        final probe = List<Geo>.from(gs);
        probe[mover.ent] =
            setPt(probe[mover.ent], mover.pt, const Offset(45, 55));
        expect(
            solveConstraints(probe, s.constraints,
                dragged: {(mover.ent, mover.pt)}),
            isTrue);
        final pa = getPt(probe[at[0].ent], at[0].pt);
        final pb = getPt(probe[at[1].ent], at[1].pt);
        expect((pa - pb).distance, lessThan(1e-6));
      });
    }
  }
}
