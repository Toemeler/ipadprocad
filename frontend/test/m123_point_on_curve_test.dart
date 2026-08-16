// M123 — a drawn point that LANDS on a curve must bind to it.
//
// Reported from the 2D mode: drawing so that a point lands on a LINE produced
// the point-on-line coincidence, but landing on a circle, an arc or a spline
// produced NOTHING. The point looked attached and slid off at the first drag.
//
// The snap engine has always offered the 'on' snap for every one of those types
// (snap.dart), so the point was already landing exactly on the carrier — only
// inferPointBindings still had a line-only test in it. The circle/arc residual
// existed on both solver paths (the trim/split cut-bind used it); the polyline
// carriers (polygon edge, spline, ellipse, gear) needed a residual of their own.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// A point a given FRACTION along the sampled curve of [g].
///
/// Deliberately NOT `sampleEntity(g)[k]`: the sample count of a spline follows
/// the curve's own tolerance (M219 made it adaptive), so a fixed index is a
/// different place on the curve whenever the sampler changes. Every test here
/// wants "a point on the curve, well away from its ends" — that is a fraction,
/// not an index.
Offset onCurveAt(Geo g, double frac) {
  final pts = sampleEntity(g);
  final i = (pts.length * frac).round().clamp(1, pts.length - 2);
  return pts[i];
}

/// The point-on-CURVE binds of [cs]: one point, one entity.
List<Constraint> onCurveOf(List<Constraint> cs) => [
      for (final c in cs)
        if (c.type == CType.coincident &&
            c.pts.length == 1 &&
            c.ents.length == 1)
          c
    ];

/// Distance from [q] to the carrier of [g], measured on the sampled curve —
/// the same chain the snap and the hit-test use.
double distToCarrier(Geo g, Offset q) {
  if (g.type == Geo.circle || g.type == Geo.arc) {
    return ((q - Offset(g.data[0], g.data[1])).distance - g.data[2]).abs();
  }
  final pts = sampleEntity(g);
  var best = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final d = (q - closestOnSegment(q, pts[i], pts[i + 1])).distance;
    if (d < best) best = d;
  }
  return best;
}

void main() {
  group('M123 inference — a landing on any carrier binds', () {
    test('line endpoint landing on a CIRCLE gets point-on-circle', () {
      // circle r=50 at the origin; a line whose end sits exactly on it.
      final on = Offset(math.cos(0.7), math.sin(0.7)) * 50;
      final gs = [
        Geo(Geo.circle, [0, 0, 50]),
        Geo(Geo.line, [120, 90, on.dx, on.dy]),
      ];
      final cs = inferConstraints(gs, 1);
      final binds = onCurveOf(cs);
      expect(binds, hasLength(1), reason: 'exactly one point-on-curve bind');
      expect(binds[0].ents[0], 0);
      expect(binds[0].pts[0], const PRef(1, 1));
    });

    test('landing on an ARC binds only on the DRAWN sweep', () {
      // arc from 0 to pi/2 (ccw). A point at 45 deg is ON it; the mirror at
      // 225 deg sits on the same circle but on the complementary arc.
      final arc = Geo(Geo.arc, [0, 0, 50, 0, math.pi / 2, 0]);
      final onSweep = Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * 50;
      final offSweep = -onSweep;

      expect(pointLandsOn(arc, onSweep), isTrue);
      expect(pointLandsOn(arc, offSweep), isFalse,
          reason: 'the complementary arc is not geometry that exists');

      final gs = [
        arc,
        Geo(Geo.line, [100, 100, onSweep.dx, onSweep.dy])
      ];
      expect(onCurveOf(inferConstraints(gs, 1)), hasLength(1));

      final gs2 = [
        arc,
        Geo(Geo.line, [-100, -100, offSweep.dx, offSweep.dy])
      ];
      expect(onCurveOf(inferConstraints(gs2, 1)), isEmpty);
    });

    test('an arc END is a point-on-POINT, never a second on-curve bind', () {
      final arc = Geo(Geo.arc, [0, 0, 50, 0, math.pi / 2, 0]);
      final end = const Offset(50, 0); // arc point 1
      expect(pointLandsOn(arc, end), isFalse);
      final gs = [
        arc,
        Geo(Geo.line, [100, 100, end.dx, end.dy])
      ];
      final cs = inferConstraints(gs, 1);
      expect(onCurveOf(cs), isEmpty);
      expect(cs.where((c) => c.type == CType.coincident && c.pts.length == 2),
          hasLength(1),
          reason: 'the stronger point-on-point bind wins');
    });

    test('landing on a SPLINE binds to the curve, not the control polygon', () {
      final sp = Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
          .asSpline(Geo.splineCv);
      final curve = sampleEntity(sp);
      final mid = curve[curve.length ~/ 2];
      // A CV spline's control vertices are OFF the curve — the point the snap
      // offers is on the sampled curve.
      expect(distToCarrier(sp, mid), lessThan(1e-9));
      expect(pointLandsOn(sp, mid), isTrue);

      final gs = [
        sp,
        Geo(Geo.line, [200, 200, mid.dx, mid.dy])
      ];
      final binds = onCurveOf(inferConstraints(gs, 1));
      expect(binds, hasLength(1));
      expect(binds[0].ents[0], 0);

      // A control VERTEX that is not on the curve must not bind on-curve.
      final v = getPt(sp, 1);
      expect(distToCarrier(sp, v), greaterThan(1.0));
      expect(pointLandsOn(sp, v), isFalse);
    });

    test('landing on a POLYGON edge and on an ELLIPSE binds too', () {
      final poly = Geo(Geo.polyline, [1, 4, 0, 0, 100, 0, 100, 100, 0, 100]);
      expect(pointLandsOn(poly, const Offset(50, 0)), isTrue,
          reason: 'interior of an edge');
      expect(pointLandsOn(poly, const Offset(0, 50)), isTrue,
          reason: 'the CLOSING edge is an edge as well');
      expect(pointLandsOn(poly, const Offset(0, 0)), isFalse,
          reason: 'a corner is a defining vertex -> point-on-point');
      expect(pointLandsOn(poly, const Offset(50, 50)), isFalse,
          reason: 'inside the polygon is not on it');

      final ell = Geo(Geo.polyline, [1, 3, 0, 0, 60, 0, 0, 30])
          .asSpline(Geo.ellipseTag);
      final ec = sampleEntity(ell);
      expect(pointLandsOn(ell, ec[ec.length ~/ 3]), isTrue);
      expect(pointLandsOn(ell, const Offset(0, 0)), isFalse,
          reason: 'the ellipse CENTRE is not on the ellipse');
    });

    test('drawing a line onto a circle through the tool binds it (end to end)',
        () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.circleCenter;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(50, 0)); // r = 50
      final on = Offset(math.cos(0.4), math.sin(0.4)) * 50;
      app.selectTool(Tool.line);
      app.toolClick(const Offset(150, 120));
      app.toolClick(on);
      app.selectTool(Tool.none);

      final binds = onCurveOf(s.constraints);
      expect(binds, hasLength(1),
          reason: 'the drawn endpoint is bound to the circle');
      expect(s.geometry[binds[0].ents[0]].type, Geo.circle);
    });
  });

  group('M123 solver — the bind is actually enforced', () {
    test('every carrier type contributes exactly ONE equation', () {
      final carriers = <String, Geo>{
        'line': Geo(Geo.line, [0, 0, 100, 0]),
        'circle': Geo(Geo.circle, [0, 0, 50]),
        'arc': Geo(Geo.arc, [0, 0, 50, 0, math.pi / 2, 0]),
        'polygon': Geo(Geo.polyline, [1, 4, 0, 0, 100, 0, 100, 100, 0, 100]),
        'spline': Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
            .asSpline(Geo.splineCv),
        'ellipse': Geo(Geo.polyline, [1, 3, 0, 0, 60, 0, 0, 30])
            .asSpline(Geo.ellipseTag),
      };
      carriers.forEach((name, carrier) {
        final gs = [
          carrier,
          Geo(Geo.line, [200, 200, 10, 10])
        ];
        final c =
            Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0]);
        expect(residualCount(gs, c), 1,
            reason: '$name must consume exactly one DOF');
      });
    });

    test('the solver PULLS a point onto a spline and onto a polygon edge', () {
      for (final carrier in [
        Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
            .asSpline(Geo.splineCv),
        Geo(Geo.polyline, [1, 4, 0, 0, 100, 0, 100, 100, 0, 100]),
      ]) {
        final target = onCurveAt(carrier, 0.25);
        // The free end starts 6 mm OFF the carrier; the carrier itself is
        // pinned, so the only way to satisfy the bind is to move the point.
        final gs = [
          carrier,
          Geo(Geo.line, [180, 180, target.dx + 4, target.dy + 4.5]),
        ];
        final cs = <Constraint>[
          for (var i = 0; i < ptCount(carrier); i++)
            Constraint(CType.fix,
                pts: [PRef(0, i)],
                anchors: [getPt(carrier, i).dx, getPt(carrier, i).dy]),
          Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [180, 180]),
          Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0]),
        ];
        expect(solveConstraints(gs, cs), isTrue);
        expect(distToCarrier(gs[0], getPt(gs[1], 1)), lessThan(1e-3),
            reason: 'the bound endpoint ended up ON the carrier');
      }
    });

    test('a bound point RIDES ALONG when the spline is moved', () {
      // Exactness under a rigid move is the property the frozen frame is
      // renormalised for: the weights must reproduce a translation.
      final sp = Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
          .asSpline(Geo.splineCv);
      final target = onCurveAt(sp, 0.25);
      final gs = [
        sp,
        Geo(Geo.line, [180, 180, target.dx, target.dy])
      ];
      final cs = <Constraint>[
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [180, 180]),
        Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0]),
        // Drag the whole spline 25 to the right and 10 up by pinning every
        // control vertex to its shifted position.
        for (var i = 0; i < ptCount(sp); i++)
          Constraint(CType.fix,
              pts: [PRef(0, i)],
              anchors: [getPt(sp, i).dx + 25, getPt(sp, i).dy - 10]),
      ];
      expect(solveConstraints(gs, cs), isTrue);
      expect(distToCarrier(gs[0], getPt(gs[1], 1)), lessThan(1e-3),
          reason: 'the point stayed on the spline while the spline moved');
    });

    test('a bound point follows a DEFORMED spline, not just a moved one', () {
      // The frame models the carrier as following its vertices rigidly, so a
      // deformation is exactly the case it approximates: dragging ONE control
      // vertex must still leave the point on the curve, which is what the
      // re-projection passes in _lm are there to deliver.
      final sp = Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
          .asSpline(Geo.splineCv);
      final target = onCurveAt(sp, 0.25);
      final gs = [sp, Geo(Geo.line, [180, 180, target.dx, target.dy])];
      final cs = <Constraint>[
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [180, 180]),
        Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0]),
        // vertex 1 is hauled 40 up and 15 across; the other three stay put
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [const PRef(0, 1)], anchors: [45, 100]),
        Constraint(CType.fix, pts: [const PRef(0, 2)], anchors: [70, 60]),
        Constraint(CType.fix, pts: [const PRef(0, 3)], anchors: [100, 0]),
      ];
      expect(solveConstraints(gs, cs), isTrue);
      expect((getPt(gs[0], 1) - const Offset(45, 100)).distance, lessThan(1e-6),
          reason: 'the control vertex really did move');
      expect(distToCarrier(gs[0], getPt(gs[1], 1)), lessThan(1e-3),
          reason: 'the bound point ended up on the DEFORMED curve');
    });

    test('the bind removes exactly one DOF', () {
      final sp = Geo(Geo.polyline, [0, 4, 0, 0, 30, 60, 70, 60, 100, 0])
          .asSpline(Geo.splineCv);
      final onCurve = onCurveAt(sp, 0.25);
      final gs = [
        sp,
        Geo(Geo.line, [180, 180, onCurve.dx, onCurve.dy])
      ];
      final base = <Constraint>[
        for (var i = 0; i < ptCount(sp); i++)
          Constraint(CType.fix,
              pts: [PRef(0, i)], anchors: [getPt(sp, i).dx, getPt(sp, i).dy]),
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [180, 180]),
      ];
      final before = analyzeSketch(gs, base).dof;
      final after = analyzeSketch(gs, [
        ...base,
        Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0])
      ]).dof;
      expect(before, 2, reason: 'the free endpoint owns x and y');
      expect(after, 1, reason: 'it may still SLIDE along the curve');
    });

    test('the same bind is not accepted twice (over-constraint gate)', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 50]),
        Geo(Geo.line, [120, 90, 50, 0]),
      ];
      final c =
          Constraint(CType.coincident, pts: [const PRef(1, 1)], ents: [0]);
      final cs = <Constraint>[c];
      expect(wouldOverconstrain(gs, cs, c), isTrue,
          reason: 'a duplicate on-curve bind is redundant');
    });
  });

  group('M123 manual Coincident tool', () {
    test('second pick may be a circle, an arc or a spline', () {
      for (final carrier in [
        Geo(Geo.circle, [0, 0, 50]),
        Geo(Geo.arc, [0, 0, 50, 0, math.pi, 0]),
        Geo(Geo.polyline, [0, 4, -60, 40, -20, 90, 20, 90, 60, 40])
            .asSpline(Geo.splineCv),
      ]) {
        final app = makeApp();
        final s = app.current!;
        s.geometry.addAll([
          carrier,
          Geo(Geo.line, [150, 150, 200, 200])
        ]);
        app.selectTool(Tool.cCoincident);
        app.toolClick(const Offset(150, 150)); // the free endpoint
        // second pick: somewhere on the carrier, away from any of its points
        final mid = sampleEntity(carrier)[sampleEntity(carrier).length ~/ 2];
        app.toolClick(mid);
        expect(onCurveOf(s.constraints), hasLength(1),
            reason: 'a carrier of type ${carrier.type} is accepted');
      }
    });
  });
}
