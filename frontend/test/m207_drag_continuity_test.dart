// M207 — A DRAG IS A PATH, NOT A SEQUENCE OF INDEPENDENT ANSWERS.
//
// "The dragging around of those 2 slots is really jumping and buggy."
//
// The slots in `bug20260805T180020` are auto-constrained to each other, and
// that is wanted — it is not the bug. Their state file shows the coupling:
//
//     [22] coincident/ pts=e3.p0 ents=7     one slot's cap CENTRE, on the
//                                           other slot's cap curve
//     [23] tangent/    ents=6,3             and a rail tangent to that cap
//
// What was wrong is how a drag FRAME was computed. Every frame copied the
// COMMITTED geometry, moved the grip to the cursor, and solved from there. For
// one free line that is the same answer either way. For a coupled system it is
// not: several configurations satisfy the constraints for any given cursor
// position, and restarting from the same fixed configuration each frame lets
// the solver pick a different one as the cursor moves a pixel. The sketch then
// flips between solutions, which is what jumping looks like — and it is why it
// only ever showed up once two shapes were constrained to each other.
//
// Continuing from the previous solved frame makes each step a small one from a
// point already on the constraint manifold, so the drag stays on the branch
// the user is watching.
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

/// One slot, built by the real tool, from [a] to [b] with the given width.
void _slot(AppState app, Offset a, Offset b, Offset w) {
  app.tool = Tool.slotCC;
  app.toolClick(a);
  app.toolClick(b);
  app.toolClick(w);
  app.tool = Tool.none;
}

/// Two slots, coupled the way the device's auto-constraints coupled them:
/// slot B's cap carries slot A's cap CENTRE on its curve.
AppState _twoCoupledSlots() {
  final app = _app();
  final s = app.current!;
  _slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
  final firstB = s.geometry.length;
  _slot(app, const Offset(0, 60), const Offset(40, 60), const Offset(20, 66));

  // Slot A's far cap is entity 3; slot B's near cap is firstB + 2. Pin A's
  // cap centre onto B's cap curve — the shape of constraint [22] in the
  // bundle. The solve below moves the sketch onto it, exactly as the commit
  // would have.
  s.constraints.add(Constraint(CType.coincident,
      pts: [const PRef(3, 0)], ents: [firstB + 2]));
  // Put the sketch on the new constraint, the way the commit would have.
  solveConstraints(s.geometry, s.constraints);
  return app;
}

/// How far one point travelled between two frames.
double _jump(List<Geo> a, List<Geo> b, int ent, int pt) =>
    (getPt(b[ent], pt) - getPt(a[ent], pt)).distance;

void main() {
  group('a drag frame continues from the last one', () {
    test('nothing teleports while the cursor walks in small steps', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      expect(app.dragGrip, isNotNull, reason: 'the rail end has free DOF');

      var prev = app.displayGeometry(s);
      var from = start;
      for (var i = 1; i <= 40; i++) {
        final to = from + const Offset(1.5, 0.9);
        app.updateGripDrag(to);
        final now = app.displayGeometry(s);
        // Every point of the coupled system, not just the dragged one: a
        // branch flip shows up as some OTHER point teleporting while the one
        // under the finger moves smoothly.
        for (var e = 0; e < now.length; e++) {
          for (var p = 0; p < ptCount(now[e]); p++) {
            expect(_jump(prev, now, e, p), lessThan(25),
                reason: 'frame $i: entity $e point $p jumped on a 1.7 mm '
                    'cursor step — the solver changed branch',);
          }
        }
        prev = now;
        from = to;
      }
      app.endGripDrag();
    });

    test('and it still ends where the cursor did', () {
      // Continuity must not cost accuracy.
      final app = _twoCoupledSlots();
      final s = app.current!;
      var from = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, from, 'end'));
      late Offset last;
      for (var i = 1; i <= 20; i++) {
        last = from + const Offset(1.5, 0.9);
        app.updateGripDrag(last);
        app.displayGeometry(s);
        from = last;
      }
      final shown = app.displayGeometry(s);
      expect((getPt(shown[0], 1) - last).distance, lessThan(2.0),
          reason: 'the dragged point still follows the cursor');
      app.endGripDrag();
    });

    test('the committed sketch is still on the constraints afterwards', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      var from = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, from, 'end'));
      for (var i = 1; i <= 15; i++) {
        from += const Offset(1.5, 0.9);
        app.updateGripDrag(from);
        app.displayGeometry(s);
      }
      app.endGripDrag();
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-4),
          reason: 'the warm start must not accumulate into the commit — '
              'endGripDrag settles from scratch');
      expect(hasDegenerateGeometry(s.geometry), isFalse);
    });
  });

  group('an uncoupled drag is unchanged', () {
    test('a single free line still goes exactly where it is put', () {
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 100, 0]));
      app.beginGripDrag(Grip(0, 1, const Offset(100, 0), 'end'));
      for (var i = 1; i <= 10; i++) {
        final to = Offset(100 + i * 10.0, i * 5.0);
        app.updateGripDrag(to);
        final gs = app.displayGeometry(s);
        expect((getPt(gs[0], 1) - to).distance, lessThan(1e-6),
            reason: 'nothing constrains it');
      }
      app.endGripDrag();
    });

    test('a slot on its own still drags as a slot', () {
      // The M207 warm start must not disturb what T-1 already pins.
      final app = _app();
      final s = app.current!;
      _slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
      final start = getPt(s.geometry[3], 2);
      app.beginGripDrag(Grip(3, 2, start, 'end'));
      for (var i = 1; i <= 20; i++) {
        app.updateGripDrag(start + Offset(i * 0.75, i * 1.1));
        final gs = app.displayGeometry(s);
        expect(allFinite(gs), isTrue);
        expect(hasDegenerateGeometry(gs), isFalse);
      }
      app.endGripDrag();
      final r1 = s.geometry[2].data[2], r2 = s.geometry[3].data[2];
      expect(r1, closeTo(r2, 1e-6), reason: 'the caps stay equal');
      expect(r1, greaterThan(0));
      expect(math.max(r1, r2).isFinite, isTrue);
    });
  });
}
