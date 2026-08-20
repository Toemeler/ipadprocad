// S9 — A DRAG AROUND A CLOSED LOOP DOES NOT COME BACK, AND THAT IS CORRECT.
//
// Report: "dragging a sketch around a closed loop leaves it 14.64 units from
// where it started, unmodified". True, and measurable at any magnitude you
// like — but it is not a defect. It is the HOLONOMY of an under-constrained
// sketch, and it is the price M207 knowingly paid for a drag that follows the
// finger.
//
// The mechanism. A drag frame does not solve the sketch from scratch; it
// continues from the previous solved frame (M207, app_state.dart) and asks the
// solver for the nearest configuration that honours the cursor. On a sketch
// with DOF > 0 that is a PROJECTION onto a curved solution manifold, and a
// projection walked around a closed loop in cursor space does not have to
// return to its starting point — the same reason a car that drives a closed
// loop of steering inputs ends up parallel-parked one space over. Every frame
// still satisfies every constraint exactly, so the sketch never leaves the
// manifold; it only ends the gesture at a different point OF ITS OWN FREEDOM
// than it began.
//
// What the measurements showed (both solver paths, the coupled-slot fixture of
// m207_drag_continuity_test.dart, DOF 7, extent ~76-97):
//
//   * refining the cursor loop does NOT drive the drift out. r=20, steps
//     8/16/32/64/128/256 converge on a NON-ZERO limit (libslvs 13.3 -> 20.67,
//     Dart 32.9 -> 39.15), first order, halving the gap each doubling. A
//     discretisation artefact would go to zero; this does not.
//   * the drift is proportional to the AREA the cursor encloses:
//     drift/r^2 is flat to ~5% over r = 1..16 (libslvs 0.053 -> 0.047; Dart
//     0.176 -> 0.183 over r = 0.25..4), then saturates once the loop is
//     comparable to the sketch. Area-proportional is the signature of
//     holonomy, not of error.
//   * it is BOUNDED. 200 consecutive loops: the drift settles into a band
//     (libslvs 19..62, Dart 23..52) and the bounding box stays within 5%
//     (libslvs) / 60% (Dart) of where it started. It does not accumulate; the
//     loop map has an attracting cycle, it is not a ratchet.
//   * on DOF 0 there is no drift at all, and on a free line there is none
//     either. Both are locked below.
//   * and it is exactly what buys continuity. Restarting each frame from the
//     committed sketch — the pre-M207 behaviour — closes the loop to 0.000,
//     and teleports the sketch 42.16 units on a 1.96-unit cursor step. That
//     is the "dragging is really jumping and buggy" report M207 fixed. Loop
//     closure and a drag that follows the finger are mutually exclusive here;
//     M207 chose the finger.
//
// So there is nothing to fix, and these tests exist to stop a later session
// "fixing" it: they pin the two cases where drift must be zero, and pin that
// the drift on the coupled fixture stays bounded and area-proportional rather
// than running away.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/diag.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';

AppState _app() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void _slot(AppState app, Offset a, Offset b, Offset w) {
  app.tool = Tool.slotCC;
  app.toolClick(a);
  app.toolClick(b);
  app.toolClick(w);
  app.tool = Tool.none;
}

/// The M207 fixture: two slots, coupled the way the device's auto-constraints
/// coupled them (slot A's cap CENTRE pinned onto slot B's cap curve).
AppState _twoCoupledSlots() {
  final app = _app();
  final s = app.current!;
  _slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
  final firstB = s.geometry.length;
  _slot(app, const Offset(0, 60), const Offset(40, 60), const Offset(20, 66));
  s.constraints.add(Constraint(CType.coincident,
      pts: [const PRef(3, 0)], ents: [firstB + 2]));
  solveConstraints(s.geometry, s.constraints);
  return app;
}

/// The same sketch driven to DOF 0 by fixing points at where they already are
/// — nothing the tools built is removed or reordered, so this is the same
/// system with its freedom taken away and nothing else changed.
AppState _twoCoupledSlotsFullyConstrained() {
  final app = _twoCoupledSlots();
  final s = app.current!;
  int dof() => analyzeSketch(s.geometry, s.constraints).dof;
  for (var e = 0; e < s.geometry.length && dof() > 0; e++) {
    for (var p = 0; p < ptCount(s.geometry[e]) && dof() > 0; p++) {
      final was = dof();
      final q = getPt(s.geometry[e], p);
      final c = Constraint(CType.fix, pts: [PRef(e, p)], anchors: [q.dx, q.dy]);
      s.constraints.add(c);
      if (dof() >= was) s.constraints.remove(c); // redundant — take it back
    }
  }
  // A last ODD degree of freedom is a radius, which no point fix can reach.
  for (var e = 0; e < s.geometry.length && dof() > 0; e++) {
    final was = dof();
    final c = Constraint(CType.fix,
        ents: [e], anchors: List<double>.from(s.geometry[e].data));
    s.constraints.add(c);
    if (dof() >= was) s.constraints.remove(c);
  }
  return app;
}

List<Offset> _pts(List<Geo> gs) {
  final out = <Offset>[];
  for (final g in gs) {
    for (var p = 0; p < ptCount(g); p++) {
      out.add(getPt(g, p));
    }
  }
  return out;
}

/// How far the furthest defining point of the sketch moved.
double _maxMove(List<Geo> a, List<Geo> b) {
  final x = _pts(a), y = _pts(b);
  var m = 0.0;
  for (var i = 0; i < math.min(x.length, y.length); i++) {
    m = math.max(m, (y[i] - x[i]).distance);
  }
  return m;
}

/// Bounding-box diagonal — the sketch's size, so a runaway shows up even when
/// the drift itself happens to be small on the frame we look at.
double _extent(List<Geo> gs) {
  final p = _pts(gs);
  var lo = p.first, hi = p.first;
  for (final q in p) {
    lo = Offset(math.min(lo.dx, q.dx), math.min(lo.dy, q.dy));
    hi = Offset(math.max(hi.dx, q.dx), math.max(hi.dy, q.dy));
  }
  return (hi - lo).distance;
}

/// One circuit of a circle of radius [r], landing EXACTLY back on [home] — so
/// the cursor path is closed to the last digit and any residue is the
/// solver's, not the caller's arithmetic.
void _loop(AppState app, SketchModel s, Offset home, double r, int steps) {
  for (var i = 1; i <= steps; i++) {
    final t = 2 * math.pi * i / steps;
    final to = home + Offset(r * math.sin(t), r * (1 - math.cos(t)));
    app.updateGripDrag(to);
    app.displayGeometry(s);
  }
  app.updateGripDrag(home);
  app.displayGeometry(s);
}

double _loopDrift(double r, int steps) {
  final app = _twoCoupledSlots();
  final s = app.current!;
  final start = List<Geo>.from(s.geometry);
  final home = getPt(s.geometry[0], 1);
  app.beginGripDrag(Grip(0, 1, home, 'end'));
  _loop(app, s, home, r, steps);
  final d = _maxMove(start, app.displayGeometry(s));
  app.endGripDrag();
  return d;
}

void main() {
  group('a closed drag loop on a sketch with NO freedom leaves nothing behind',
      () {
    test('a fully constrained sketch refuses the grip in the first place', () {
      final app = _twoCoupledSlotsFullyConstrained();
      final s = app.current!;
      final a = analyzeSketch(s.geometry, s.constraints);
      expect(a.dof, 0, reason: 'the fixture must actually be DOF 0');
      app.analysis = a;
      app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
      expect(app.dragGrip, isNull,
          reason: 'a point with no freedom is not draggable');
    });

    test('and forced past that refusal, the solve still comes back exactly',
        () {
      final app = _twoCoupledSlotsFullyConstrained();
      final s = app.current!;
      final start = List<Geo>.from(s.geometry);
      final home = getPt(s.geometry[0], 1);
      // Straight at the solver, bypassing the refusal above: this is the part
      // that says the drift lives in the FREEDOM, not in the drag machinery.
      final gs = List<Geo>.from(s.geometry);
      for (var i = 1; i <= 33; i++) {
        final t = 2 * math.pi * math.min(i, 32) / 32;
        final to = i > 32
            ? home
            : home + Offset(20 * math.sin(t), 20 * (1 - math.cos(t)));
        gs[0] = moveGrip(gs[0], Grip(0, 1, to, 'end'), to);
        solveConstraints(gs, s.constraints, dragged: {(0, 1)}, iterations: 25);
      }
      // Generous by five orders of magnitude against what both paths measure
      // (libslvs 2e-12, Dart LM 1e-3 — the LM iteration budget, not drift).
      expect(_maxMove(start, gs), lessThan(0.1),
          reason: 'with DOF 0 there is nowhere to drift TO');
    });

    test('a free line comes back to the digit', () {
      final app = _app();
      final s = app.current!;
      app.tool = Tool.line;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.tool = Tool.none;
      final start = List<Geo>.from(s.geometry);
      final home = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, home, 'end'));
      _loop(app, s, home, 20, 64);
      app.endGripDrag();
      // Nothing has to be projected, so the cursor is honoured exactly and the
      // loop closes. Drift is not a property of dragging; it is a property of
      // dragging a COUPLED under-constrained system.
      expect(_maxMove(start, s.geometry), lessThan(1e-6));
    });
  });

  group('on the coupled fixture it drifts — bounded, and with the loop AREA',
      () {
    test('the sketch is under-constrained, which is the precondition', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final a = analyzeSketch(s.geometry, s.constraints);
      expect(a.dof, greaterThan(0),
          reason: 'no freedom, no holonomy — the rest of this group is void');
      expect(a.fullyConstrained, isFalse);
    });

    test('a quarter of the enclosed area drifts far less than a quarter as far',
        () {
      // Halving the radius quarters the area. If the drift were an error term
      // it would fall off with the PATH LENGTH (a factor of two); it falls off
      // with the AREA instead (measured 0.24 of the r=4 drift on the Dart
      // path, 0.26 on libslvs — both comfortably under a half).
      final big = _loopDrift(4, 64);
      final small = _loopDrift(2, 64);
      expect(big, greaterThan(1e-3), reason: 'there IS a drift to compare');
      expect(small, lessThan(0.4 * big),
          reason: 'area-proportional, not length-proportional');
    });

    test('forty loops do not walk the sketch off the page', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final start = List<Geo>.from(s.geometry);
      final base = _extent(start);
      final home = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, home, 'end'));
      for (var k = 0; k < 40; k++) {
        _loop(app, s, home, 20, 32);
        final now = app.displayGeometry(s);
        expect(allFinite(now), isTrue, reason: 'loop $k went non-finite');
        // The real question the report asks: does it ACCUMULATE? Measured
        // over 200 loops it settles into a band instead (libslvs stays within
        // 5% of the starting extent, the Dart path within 60%).
        expect(_extent(now), lessThan(2.5 * base),
            reason: 'loop $k: the sketch is growing without bound');
      }
      app.endGripDrag();
      // And it is still a legitimate solution of the same system: the drift
      // moved the sketch WITHIN its freedom, it did not bend a constraint.
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-2));
      expect(analyzeSketch(s.geometry, s.constraints).dof,
          analyzeSketch(start, s.constraints).dof,
          reason: 'the drift must not have changed what the sketch IS');
    });
  });
}
