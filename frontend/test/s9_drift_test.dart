// S9 — THE LOOP DRIFT IS HOLONOMY, AND IT IS NOT A DEFECT.
//
// S4-painter.md §9.4 measured it and the integrator routed it: dragging the
// two-coupled-slots fixture around a closed cursor loop and back leaves it
// 14.64 units from where it started, in the unmodified application. Committed
// geometry is not a function of the cursor path.
//
// That is true, reproduced here (14.4653 on the Dart path, same protocol), and
// it is CORRECT BEHAVIOUR. The fixture has DOF 7. A drag frame warm-starts from
// the previous solved frame and takes the cursor as a WISH, so on a sketch with
// freedom left the drag is a projection onto a curved solution manifold applied
// step after step — and a projection walked around a closed loop is under no
// obligation to return to its start. The sketch does not leave the manifold; it
// ends the gesture at a different point OF ITS OWN FREEDOM.
//
// The full argument, the numbers on both solver paths, and what was deliberately
// not done are in perf/findings/S9-drift.md. These tests pin the parts of it
// that must not silently change:
//
//   * the two numbers the integrator asked for — DOF and extent — so that a
//     later change to the fixture or to analyzeSketch cannot quietly move the
//     ground the ruling stands on;
//   * take the freedom away and the drift goes away, exactly (DOF 0, and a
//     free line). If a DETERMINED system ever walks, that is a defect with no
//     ambiguity in it, and these two tests are what would catch it;
//   * the drift is BOUNDED in N — the sketch wanders inside its reachable set
//     and never runs away. Measured to 500 laps / 6000 committed drags on both
//     paths; pinned here at a length the suite can afford;
//   * it falls off with the loop's AREA, not its path length, which is the
//     signature that separates holonomy from an error term.
//
// NO BEHAVIOUR WAS CHANGED by this session. These are pins on the application
// as it stands, in the same sense as s4_drag_accumulation_test.dart: they
// record measured behaviour, and the header of that file applies here too.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/diag.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';

// S4 §9's protocol, verbatim: successive COMPLETE drags, each committed through
// endGripDrag, walking a circle about the grip's start, 12 drags to the lap.
const _stepsPerDrag = 4;
const _perLap = 12;
// 25 laps = 300 committed drags. Past the point where the Dart path's ceiling
// is established (~lap 11) and into the native path's excursion. The full
// 500-lap runs behind the findings file are not affordable per-suite; this is
// the smallest length at which both claims below are still clearly separated.
const _lapsBounded = 25;
// Both radii run this many laps in the area comparison.
const _lapsArea = 20;

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

/// The fixture of m207_drag_continuity_test.dart and s4_drag_accumulation_test
/// .dart: two slots coupled by tangents and a cap centre pinned onto the other
/// slot's cap curve.
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

/// The same sketch with its freedom taken away and NOTHING else changed: points
/// fixed where they already are, redundant fixes discarded, so the tangents,
/// equals and coincidents the tools built are all still doing their work.
AppState _fullyConstrained() {
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

/// S4's metric, verbatim: the largest absolute difference over every packed
/// parameter, so radii and sweep angles count as well as point positions.
double _maxDelta(List<Geo> a, List<Geo> b) {
  if (a.length != b.length) return -1;
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (a[i].data.length != b[i].data.length) return -1;
    for (var k = 0; k < a[i].data.length; k++) {
      final d = (a[i].data[k] - b[i].data[k]).abs();
      if (d > worst) worst = d;
    }
  }
  return worst;
}

/// Bounding-box diagonal — the sketch's size. A runaway shows here even when
/// the drift on the lap we happen to sample is small.
double _extent(List<Geo> gs) {
  var lo = const Offset(1e18, 1e18), hi = const Offset(-1e18, -1e18);
  for (final g in gs) {
    for (var p = 0; p < ptCount(g); p++) {
      final q = getPt(g, p);
      lo = Offset(math.min(lo.dx, q.dx), math.min(lo.dy, q.dy));
      hi = Offset(math.max(hi.dx, q.dx), math.max(hi.dy, q.dy));
    }
  }
  return (hi - lo).distance;
}

/// One complete drag of entity 0's endpoint through [path], committed.
void _oneDrag(AppState app, List<Offset> path) {
  final s = app.current!;
  app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
  if (app.dragGrip == null) return; // refused — a point with no freedom
  for (final at in path) {
    app.updateGripDrag(at);
    app.displayGeometry(s);
  }
  app.endGripDrag();
}

/// [laps] laps of successive committed drags around the radius-[r] circle,
/// snapshotting committed geometry at the same phase of every lap.
List<List<Geo>> _laps(AppState app, double r, int laps) {
  final anchor = getPt(app.current!.geometry[0], 1);
  var prev = anchor;
  final snaps = <List<Geo>>[];
  for (var k = 1; k <= laps * _perLap; k++) {
    final th = 2 * math.pi * (k % _perLap) / _perLap;
    final target = anchor + Offset(r * math.cos(th), r * math.sin(th));
    final path = [
      for (var i = 1; i <= _stepsPerDrag; i++)
        Offset.lerp(prev, target, i / _stepsPerDrag)!
    ];
    prev = target;
    _oneDrag(app, path);
    if (k % _perLap == 0) snaps.add(List<Geo>.from(app.current!.geometry));
  }
  return snaps;
}

void main() {
  group('the two numbers the ruling asked for', () {
    test('the fixture is under-constrained, and by how much', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final a = analyzeSketch(s.geometry, s.constraints);
      // DOF 7 out of 48 packed parameters, on a sketch whose bounding box
      // measures ~76 units corner to corner (60 across the slot pair, which is
      // the span S4 quoted). The drift is a fraction of that extent, not a
      // multiple of it — which is the comparison that decides whether 14.64 is
      // alarming, and it is the reason it is not.
      expect(a.dof, 7);
      expect(a.fullyConstrained, isFalse);
      final extent = _extent(s.geometry);
      expect(extent, greaterThan(60));
      expect(extent, lessThan(110)); // 76.3 Dart / 97.1 libslvs
    });
  });

  group('take the freedom away and the drift goes away', () {
    test('a fully constrained sketch will not be gripped at all', () {
      final app = _fullyConstrained();
      final s = app.current!;
      final a = analyzeSketch(s.geometry, s.constraints);
      expect(a.dof, 0, reason: 'the control must actually be determined');
      app.analysis = a;
      app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
      expect(app.dragGrip, isNull);
    });

    test('and 33 laps of drags leave it EXACTLY where it started', () {
      // The unambiguous-defect test. A determined system that walks would be a
      // bug with nothing to argue about. It does not walk: measured 0.0, not
      // "small", on both solver paths.
      final app = _fullyConstrained();
      app.analysis = analyzeSketch(
          app.current!.geometry, app.current!.constraints);
      // Against the PRE-DRAG state, not merely same-phase: with the grip
      // refused the geometry never moves at all, which is the stronger claim.
      final before = List<Geo>.from(app.current!.geometry);
      final snaps = _laps(app, 3.0, 33);
      expect(_maxDelta(before, snaps.last), 0.0);
    });

    test('a free line comes back to the digit', () {
      // Nothing has to be projected, so the cursor is honoured exactly and the
      // loop closes. Drift is not a property of dragging — it is a property of
      // dragging a COUPLED under-constrained system.
      //
      // Compared SAME-PHASE (lap 1 against lap 8), which is how S4 measured it
      // and the only comparison that means anything here: a lap boundary falls
      // at theta=0, i.e. cursor at anchor+(r,0), not back at the anchor. A free
      // endpoint sits exactly under the cursor, so start-against-lap-N would
      // read 3.0 units of "drift" that are just where the finger is.
      final app = _app();
      app.tool = Tool.line;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.tool = Tool.none;
      final snaps = _laps(app, 3.0, 8);
      expect(_maxDelta(snaps[0], snaps.last), lessThan(1e-6));
    });
  });

  group('on the coupled fixture it drifts — bounded, and with the AREA', () {
    test('$_lapsBounded laps do not walk the sketch off the page', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final base = _extent(s.geometry);
      final r0 = constraintResidualNorm(s.geometry, s.constraints);
      final snaps = _laps(app, 3.0, _lapsBounded);
      for (var i = 0; i < snaps.length; i++) {
        expect(allFinite(snaps[i]), isTrue, reason: 'lap ${i + 1} non-finite');
        // The question the finding actually asks: does it ACCUMULATE? It does
        // not. Measured over 500 laps the extent stays within 3% of its start
        // on the Dart path and peaks at +20% on the native one, then returns.
        expect(_extent(snaps[i]), lessThan(1.6 * base),
            reason: 'lap ${i + 1}: the sketch is growing without bound');
      }
      // And it is still a legitimate solution of the same system: the drift
      // moved the sketch WITHIN its freedom, it did not bend a constraint.
      // 2.828e-6 on the Dart path — S4's own figure — and 1e-14 natively.
      expect(constraintResidualNorm(s.geometry, s.constraints),
          lessThan(math.max(r0 * 1.5, 1e-5)));
      expect(analyzeSketch(s.geometry, s.constraints).dof, 7,
          reason: 'the drift must not have changed what the sketch IS');
    });

    test('a quarter of the radius drifts far less than a quarter as far', () {
      // Quartering the radius sixteenths the enclosed area. An error term would
      // fall off with the PATH LENGTH — a factor of four. It falls off with the
      // area instead: measured 0.060 of the r=1 drift on the Dart path and
      // 0.078 on libslvs, against 0.25 for a length law.
      final bigLaps = _laps(_twoCoupledSlots(), 1.0, _lapsArea);
      final smallLaps = _laps(_twoCoupledSlots(), 0.25, _lapsArea);
      final big = _maxDelta(bigLaps.first, bigLaps.last);
      final small = _maxDelta(smallLaps.first, smallLaps.last);
      expect(big, greaterThan(1e-3), reason: 'there IS a drift to compare');
      expect(small, lessThan(0.15 * big),
          reason: 'area-proportional, not length-proportional');
    });
  });
}
