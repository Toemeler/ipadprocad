// User report #2: TWO BARE CROSSING LINES (no rectangles).
//   trim one side of line A  -> A's new endpoint lies on line B's interior
//                               => point-on-CURVE bind expected
//   trim one side of line B  -> B's new endpoint stacks exactly on A's
//                               => upgraded to point-ON-POINT expected

import 'dart:ui';

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
        final onCurve = s.constraints
            .where((c) =>
                c.type == CType.coincident &&
                c.pts.length == 1 &&
                c.ents.length == 1 &&
                c.pts[0] == at[0])
            .toList();
        // M125 — the trimmed line stays as a construction CARRIER, so the cut
        // endpoint is bound twice: onto the crossing line (the cutter) and
        // onto the carrier it was cut out of. Exactly one of them is the
        // cutter, i.e. the one that is not construction.
        final ontoCutter = onCurve
            .where((c) => !s.geometry[c.ents[0]].isConstruction)
            .toList();
        expect(ontoCutter.length, 1,
            reason: 'single trim: new endpoint bound point-on-CURVE onto the '
                'crossing line (constraints: '
                '${s.constraints.map((c) => c.toJson())})');
        expect(onCurve.length - ontoCutter.length, 1,
            reason: 'and once onto the kept construction carrier (M125)');

        // Trim 2
        app.toolClick(second);
        final gs = s.geometry;
        expect(solveConstraints(List<Geo>.from(gs), s.constraints), isTrue);
        at = refsAt(gs, x);
        expect(at.length, 2,
            reason: 'both trimmed endpoints stack at the crossing');
        // M125 — each cut endpoint is pinned by TWO curve binds (its own
        // construction carrier and the line it was cut against), so it sits on
        // the crossing by construction. A point-on-point on top of that is the
        // redundant row the gate exists to refuse; what the device session
        // needed was for the two points not to slide apart, and being pinned
        // to the same intersection is a stronger guarantee than gluing two
        // otherwise free points together.
        for (final r in at) {
          final binds = s.constraints.where((c) =>
              c.type == CType.coincident &&
              c.pts.length == 1 &&
              c.ents.length == 1 &&
              c.pts[0] == r);
          expect(binds.length, 2,
              reason: 'cut endpoint $r pinned by carrier AND cutter '
                  '(constraints: ${s.constraints.map((c) => c.toJson())})');
        }
        final subsumed = s.constraints.where((c) =>
            c.type == CType.coincident &&
            c.pts.length == 1 &&
            c.ents.length == 1 &&
            at.contains(c.pts[0]) &&
            at.any((r) => r.ent == c.ents[0]));
        expect(subsumed, isEmpty,
            reason: 'on-curve bind upgraded, not stacked');

        // and they come back to ONE point: shove both off the crossing, solve,
        // and the constraint system pulls them onto it again, together.
        final probe = List<Geo>.from(gs);
        probe[at[0].ent] =
            setPt(probe[at[0].ent], at[0].pt, const Offset(45, 55));
        probe[at[1].ent] =
            setPt(probe[at[1].ent], at[1].pt, const Offset(62, 41));
        expect(solveConstraints(probe, s.constraints), isTrue);
        final pa = getPt(probe[at[0].ent], at[0].pt);
        final pb = getPt(probe[at[1].ent], at[1].pt);
        // (Where the crossing ENDS UP is free — the carriers themselves still
        // have degrees of freedom, and the shove moves them. What must hold is
        // that the two cut endpoints are one point again.)
        expect((pa - pb).distance, lessThan(1e-6));
      });
    }
  }
}
