// M208 — four reports from the device session of 2026-08-05 (build 96c3761),
// all of them about slots.
//
//   * bug20260805T191206 "A slot shouldn't be able to become a line like this"
//   * bug20260805T191340 "it says this constraint is not possible but it should
//     definitely be possible (concentric of the 2 slot circles)"
//   * bug20260805T191527 "I couldn't properly drag the point around. it jumps
//     around or doesnt move at all. this is a problem with all slots."
//   * bug20260805T191659 "slots should behave like in inventor. so set the
//     start then the end point and at last the midpoint ... the same with a
//     3 point arc. start then end then middle"
//
// Three of the four are ONE fault. A slot's cap arc is tangent to both rails,
// so `cornerFilletArcs` counted it as a corner fillet and handed it to the
// M196 branch-flip guard. A cap is a HALF TURN — its sweep is exactly π, by
// construction — and the guard's question was "was it under π before and over
// π after", decided at a margin of 1e-6 rad. On a shape that lives on the
// boundary that is a coin toss, and the logs show what it cost:
//
//     565 BRANCH FLIP ... REJECTED, keeping last good     (60 frames accepted)
//     lm: err=9.81e-10 satisfied=true
//     WARN solve: BRANCH FLIP via lm on arc(s) 3 ... REJECTED
//     INFO constraint: REJECTED concentric/ ents=7,3 — cannot be satisfied
//
// The concentric the user asked for HAD been solved, to 9.8e-10, and was
// thrown away by a guard that cannot apply to the shape it fired on: an arc
// tangent to two PARALLEL lines has its centre on their midline and its
// tangent points diametrically opposite, so both branches are the same half
// turn. There is nothing to flip.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/diag.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/tools.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// A linear slot from [a] to [b], [w] setting the width, through the real tool.
void slot(AppState app, Offset a, Offset b, Offset w) {
  app.tool = Tool.slotCC;
  app.toolClick(a);
  app.toolClick(b);
  app.toolClick(w);
  app.tool = Tool.none;
}

List<Offset> along(Offset a, Offset b, int n) =>
    [for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!];

Geo line(double x0, double y0, double x1, double y1) =>
    Geo(Geo.line, [x0, y0, x1, y1]);

Geo arc(double cx, double cy, double r, double a0, double a1, double rev) =>
    Geo(Geo.arc, [cx, cy, r, a0, a1, rev]);

/// The slot the device drew, written out exactly: rails at y = ±6 running
/// x = 0..40, caps of radius 6 around (0,0) and (40,0). Every cap sweep is
/// π to the last bit, which is the whole point.
List<Geo> textbookSlot() => [
      line(0, 6, 40, 6), // rail 1
      line(40, -6, 0, -6), // rail 2
      arc(0, 0, 6, math.pi / 2, 3 * math.pi / 2, 0), // cap 1: sweep = π
      arc(40, 0, 6, -math.pi / 2, math.pi / 2, 0), // cap 2: sweep = π
    ];

/// One slot exactly as bug20260805T191340 stored it — rails, caps and axis
/// copied out of the bundle's `state.txt`, not rounded or reconstructed.
List<Geo> deviceSlotCaps() => [
      line(-5.9294, 12.2673, 8.0904, 1.9333), // rail 1
      line(1.0147, -7.6660, -13.0052, 2.6680), // rail 2
      arc(-9.4673, 7.4676, 5.9627, 0.9356, -2.2060, 0), // cap 1
      arc(4.5525, -2.8663, 5.9627, -2.2060, 0.9356, 0), // cap 2
    ];

/// What the slot tool's auto-constraints say about the caps (the pair of
/// tangencies per cap is all the flip guard reads).
final slotTangencies = <Constraint>[
  Constraint(CType.tangent, ents: [0, 2]),
  Constraint(CType.tangent, ents: [1, 2]),
  Constraint(CType.tangent, ents: [0, 3]),
  Constraint(CType.tangent, ents: [1, 3]),
];

void main() {
  // -------------------------------------------------------------------------
  group('a slot cap is not a corner fillet (T191340, T191527)', () {
    test('the caps are half turns, exactly', () {
      // Not approximately. This is why a 1e-6 margin was a coin toss.
      for (final i in [2, 3]) {
        expect(arcSweep(textbookSlot()[i]).abs(), closeTo(math.pi, 1e-12));
      }
    });

    test('the guard does not claim them', () {
      expect(cornerFilletArcs(textbookSlot(), slotTangencies), isEmpty,
          reason: 'the two rails are parallel — there is no corner to round');
    });

    test('a rail that is only NEARLY parallel is still not a corner', () {
      // A drag frame lands a few digits off exact; the classification must not
      // change between two frames of the same gesture.
      final gs = textbookSlot();
      gs[0] = line(0, 6, 40, 6.02); // 0.03°
      expect(cornerFilletArcs(gs, slotTangencies), isEmpty);
    });

    test('a real corner IS still claimed', () {
      // Two rails turned into a 90° corner: now there are two branches and the
      // guard has something to decide.
      final gs = textbookSlot();
      gs[1] = line(6, -6, 6, -40);
      expect(cornerFilletArcs(gs, slotTangencies), contains(2));
    });

    test('the device sits 7 microradians off the half turn', () {
      // Not a hypothetical. These are the two caps of one slot as
      // bug20260805T191340 recorded them, and they straddle π: one cap is a
      // hair under a half turn, its twin a hair over. The margin that decided
      // "minor" from "major" was 1e-6 — an order of magnitude finer than the
      // distance the real shape lives from the boundary, which is why the same
      // drag was accepted and rejected at random.
      for (final (i, want) in [(2, -7.346e-6), (3, 7.346e-6)]) {
        expect(arcSweep(deviceSlotCaps()[i]).abs() - math.pi,
            closeTo(want, 1e-9));
      }
    });

    test('the wobble across the half turn is no longer a flip', () {
      // One solve turning the cap on the left into the cap on the right: the
      // same arc, the same radius, the same centre, its sweep 15 microradians
      // further round. Nothing about that shape changed.
      final before = deviceSlotCaps();
      final after = List<Geo>.of(before)..[2] = before[3].withData([
            before[2].data[0],
            before[2].data[1],
            ...before[3].data.sublist(2),
          ]);
      expect(arcSweep(before[2]).abs(), lessThan(math.pi));
      expect(arcSweep(after[2]).abs(), greaterThan(math.pi));
      expect(flippedCornerFillets(before, after, slotTangencies), isEmpty,
          reason: 'seven microradians is not a corner going the long way '
              'round');
    });

    test('M196 is still caught — a 90° fillet may not become a 270° lobe', () {
      // The guard keeps its job. Same corner as m196_device_session_test, the
      // one the user photographed: two lines meeting at a right angle.
      final cs = [
        Constraint(CType.tangent, ents: [2, 0]),
        Constraint(CType.tangent, ents: [2, 1]),
      ];
      final gs = <Geo>[
        line(-30, 17, -5, 17),
        line(-35, 12, -35, -8),
        arc(-30, 12, 5, math.pi / 2, math.pi, 0), // 90°
      ];
      final lobe = List<Geo>.of(gs)
        ..[2] = arc(-30, 12, 5, math.pi, math.pi / 2, 0); // 270° the long way
      expect(arcSweep(lobe[2]).abs(), closeTo(3 * math.pi / 2, 1e-9));
      expect(flippedCornerFillets(gs, lobe, cs), [2]);
    });

    test('the half-turn band is narrow enough to leave a quarter turn alone',
        () {
      expect(kHalfTurnSlack, lessThan(math.pi / 4));
    });
  });

  // -------------------------------------------------------------------------
  group('the concentric the solver had already found (T191340)', () {
    // "it says this constraint is not possible but it should definitely be
    // possible (concentric of the 2 slot circles)".
    AppState twoSlots() {
      final app = makeApp();
      slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
      slot(app, const Offset(10, 30), const Offset(50, 30),
          const Offset(30, 36));
      return app;
    }

    /// Picks both caps with the Concentric tool, exactly as the device did
    /// (`toolClick tool=Tool.cConcentric` twice, one point on each arc).
    void pickBothCaps(AppState app) {
      final s = app.current!;
      app.selectTool(Tool.cConcentric);
      app.toolClick(_midOfArc(s.geometry[3]));
      app.toolClick(_midOfArc(s.geometry[7]));
    }

    test('concentric between two slot caps is accepted', () {
      final app = twoSlots();
      final s = app.current!;
      expect(s.geometry[3].type, Geo.arc);
      expect(s.geometry[7].type, Geo.arc);
      pickBothCaps(app);
      expect(
          s.constraints.where((c) => c.type == CType.concentric), hasLength(1),
          reason: 'the constraint must survive, not be rejected as impossible');
    });

    test('and the two caps really do end up sharing a centre', () {
      final app = twoSlots();
      final s = app.current!;
      pickBothCaps(app);
      final a = s.geometry[3], b = s.geometry[7];
      expect(
          (Offset(a.data[0], a.data[1]) - Offset(b.data[0], b.data[1]))
              .distance,
          lessThan(1e-3),
          reason: 'accepted means applied');
      expect(hasDegenerateGeometry(s.geometry), isFalse);
    });

    test('both slots survive it intact', () {
      final app = twoSlots();
      final s = app.current!;
      pickBothCaps(app);
      // Applying a constraint moves geometry — that is what applying one is
      // for, and the solver spreads the change over the free parameters. What
      // must survive is that both shapes are still slots.
      expect(s.geometry[2].data[2], closeTo(s.geometry[3].data[2], 1e-6),
          reason: 'slot A: the two caps are equal by construction');
      expect(s.geometry[7].data[2], closeTo(s.geometry[8].data[2], 1e-6),
          reason: 'slot B: likewise');
      for (final i in [2, 3, 7, 8]) {
        expect(s.geometry[i].data[2], greaterThan(1),
            reason: 'cap e$i is still a cap, not a pinprick');
        expect(arcSweep(s.geometry[i]).abs(), closeTo(math.pi, 1e-3),
            reason: 'cap e$i is still a half turn');
      }
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-4));
    });
  });

  // -------------------------------------------------------------------------
  group('a slot may not become a line (T191206)', () {
    // The bundle's committed sketch, which is what "became a line" means:
    //
    //   [0] line data=[-15.0305, 3.1698, 11.9094, -5.0201]
    //   [1] line data=[11.9094, -5.0201, -15.0305, 3.1698]   the SAME line
    //   [2] arc  data=[-15.0305, 3.1698, 0.0000, ...]        radius zero
    //   [3] arc  data=[ 11.9094, -5.0201, 0.0000, ...]
    test('collapsedSince sees a cap that lost its radius', () {
      final start = textbookSlot();
      final now = List<Geo>.of(start)
        ..[2] = arc(0, 0, 0, math.pi / 2, 3 * math.pi / 2, 0);
      expect(collapsedSince(start, now), [2]);
    });

    test('it also sees a cap merely shrunk to nothing', () {
      // The device's radius printed as 0.0000 at four decimals. Whether the
      // last frame reached exactly zero or stopped a micron short, the slot on
      // the screen is a line either way.
      final start = textbookSlot();
      final now = List<Geo>.of(start)
        ..[2] = arc(0, 0, 6e-6, math.pi / 2, 3 * math.pi / 2, 0);
      expect(hasDegenerateGeometry(now), isFalse, reason: 'finite, positive r');
      expect(collapsedSince(start, now), [2]);
    });

    test('an honest resize is not a collapse', () {
      final start = textbookSlot();
      final now = List<Geo>.of(start)
        ..[2] = arc(0, 0, 0.6, math.pi / 2, 3 * math.pi / 2, 0);
      expect(collapsedSince(start, now), isEmpty,
          reason: 'a tenth of the radius is a smaller slot, not a dead one');
    });

    test('M203 still holds: a sketch that arrives broken stays editable', () {
      // The floor is about what THIS gesture did. Something already collapsed
      // when the finger went down is not the drag's fault, and blaming it
      // would freeze the document — which is the bug M203 exists to prevent.
      final start = List<Geo>.of(textbookSlot())
        ..[2] = arc(0, 0, 0, math.pi / 2, 3 * math.pi / 2, 0);
      final now = List<Geo>.of(start)..[0] = line(0, 6, 41, 6);
      expect(collapsedSince(start, now), isEmpty);
    });

    test('a zero-length line counts too', () {
      final start = textbookSlot();
      final now = List<Geo>.of(start)..[0] = line(0, 6, 0, 6);
      expect(collapsedSince(start, now), [0]);
    });

    test('the drag itself never commits a collapsed slot', () {
      // The device gesture: grab a rail's endpoint and pull it across the slot
      // and out the far side. The grip stops where the shape would die.
      final app = makeApp();
      final s = app.current!;
      slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
      final r0 = s.geometry[2].data[2];
      expect(r0, closeTo(6, 1e-6));

      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      expect(app.dragGrip, isNotNull);
      for (final w in along(start, const Offset(-4, -34), 60)) {
        app.updateGripDrag(w);
        final gs = app.displayGeometry(s);
        expect(allFinite(gs), isTrue);
        expect(hasDegenerateGeometry(gs), isFalse);
        for (final i in [2, 3]) {
          expect(gs[i].data[2], greaterThan(r0 * kGestureShrinkFloor),
              reason: 'shown frame: cap e\$i has been squeezed out of '
                  'existence');
        }
      }
      app.endGripDrag();

      expect(hasDegenerateGeometry(s.geometry), isFalse);
      for (final i in [2, 3]) {
        expect(s.geometry[i].data[2], greaterThan(r0 * kGestureShrinkFloor),
            reason: 'committed: cap e$i must still be a cap');
      }
      // ...and the two rails must not have become the same line, which is what
      // the screenshot showed.
      final railGap =
          (getPt(s.geometry[0], 0) - getPt(s.geometry[1], 1)).distance;
      expect(railGap, greaterThan(1e-3),
          reason: 'rail 1 and rail 2 sitting on top of each other IS the bug');
    });
  });

  // -------------------------------------------------------------------------
  group('the drag follows the finger (T191527)', () {
    // "I couldn't properly drag the point around. it jumps around or doesnt
    // move at all." Both halves of that sentence are the rejected frames: a
    // held frame does not move, and the accepted one after a run of held ones
    // arrives all at once.
    test('the shown frames are not mostly rejects', () {
      final app = makeApp();
      final s = app.current!;
      slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      var held = 0, frames = 0;
      List<Geo>? prev;
      for (final w in along(start, start + const Offset(14, 9), 40)) {
        app.updateGripDrag(w);
        final gs = app.displayGeometry(s);
        frames++;
        if (prev != null && _same(prev, gs)) held++;
        prev = gs;
      }
      app.endGripDrag();
      // The device log's ratio was 565 rejected to 60 accepted. Anything near
      // that is the bug; a healthy drag holds only where the constraints
      // genuinely run out.
      expect(held / frames, lessThan(0.25),
          reason: 'held $held of $frames frames — the drag is stuck again');
    });

    test('and it never teleports', () {
      final app = makeApp();
      final s = app.current!;
      slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      List<Geo>? prev;
      final path = along(start, start + const Offset(14, 9), 40);
      for (final w in path) {
        app.updateGripDrag(w);
        final gs = app.displayGeometry(s);
        if (prev != null) {
          for (var i = 0; i < gs.length; i++) {
            for (var p = 0; p < ptCount(gs[i]); p++) {
              final jump = (getPt(gs[i], p) - getPt(prev[i], p)).distance;
              expect(jump, lessThan(5),
                  reason: 'e$i.p$p moved $jump mm while the cursor moved 0.4');
            }
          }
        }
        prev = gs;
      }
      app.endGripDrag();
      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-4));
    });
  });

  // -------------------------------------------------------------------------
  group('start, then end, then the middle (T191659)', () {
    // "so set the start then the end point and at last the midpoint so i have
    // an exact preview while drawing. the same with a 3 point arc. start then
    // end then middle"
    test('the 3-point arc ends where the SECOND pick was', () {
      final gs = buildToolGeometry(Tool.arcThreePoint,
          const [Offset(0, 0), Offset(20, 0), Offset(10, 6)]);
      expect(gs, isNotNull);
      final a = gs!.single;
      expect(a.type, Geo.arc);
      expect(getPt(a, 1), _near(const Offset(0, 0)));
      expect(getPt(a, 2), _near(const Offset(20, 0)));
    });

    test('and it passes through the THIRD, in the middle of the sweep', () {
      final gs = buildToolGeometry(Tool.arcThreePoint,
          const [Offset(0, 0), Offset(20, 0), Offset(10, 6)])!;
      final a = gs.single;
      final c = Offset(a.data[0], a.data[1]);
      const through = Offset(10, 6);
      expect((through - c).distance, closeTo(a.data[2], 1e-9));
      expect(_onArc(a, through), isTrue,
          reason: 'on the drawn side of the chord, not the other one');
      // and STRICTLY between the ends — an endpoint would also satisfy the two
      // checks above, and an endpoint is exactly what the third pick used to
      // be.
      for (final end in [getPt(a, 1), getPt(a, 2)]) {
        expect((through - end).distance, greaterThan(1),
            reason: 'the third pick must not be an end of the arc');
      }
    });

    test('the arc slot reads its centre arc the same way', () {
      // The device's own picks, in the order the user made them: they aimed
      // the second one at the far END of the slot and got the point the slot
      // bulged through, 91 mm away.
      final gs = buildToolGeometry(Tool.slot3A, const [
        Offset(-76.62, 31.76), // start
        Offset(-3.05, 32.09), // end
        Offset(26.28, -45.37), // through
        Offset(-23.11, 17.13), // width
      ]);
      expect(gs, isNotNull);
      expect(gs!, hasLength(6));
      final outer = gs[0], inner = gs[1];
      expect(outer.type, Geo.arc);
      final c = Offset(outer.data[0], outer.data[1]);
      final rMid = (outer.data[2] + inner.data[2]) / 2;
      // All three picks lie on the centre arc's circle whichever order they
      // are read in — being on the circle proves nothing. What the order
      // decides is where the slot ENDS, and the ends are the cap centres.
      final caps = [
        Offset(gs[2].data[0], gs[2].data[1]),
        Offset(gs[3].data[0], gs[3].data[1]),
      ];
      for (final want in const [Offset(-76.62, 31.76), Offset(-3.05, 32.09)]) {
        expect(caps.any((q) => (q - want).distance < 1e-6), isTrue,
            reason: 'the slot must end at $want — the point that was picked '
                'as an end. The bundle put a cap at (-76.6155, 31.7606) and '
                'the other at (-3.0508, 32.0877), 91 mm apart, because the '
                'second pick was read as the point to bulge through.');
      }
      // ...and the third pick is what it bulges through.
      expect((const Offset(26.28, -45.37) - c).distance, closeTo(rMid, 1e-6));
      expect(_onArc(outer, _towards(c, const Offset(26.28, -45.37), rMid)),
          isTrue,
          reason: 'the through point is on the drawn side');
    });

    test('the shape is the same one the old order drew, just reached in the '
        'order Inventor asks for', () {
      final now = buildToolGeometry(Tool.arcThreePoint,
          const [Offset(0, 0), Offset(20, 0), Offset(10, 6)])!.single;
      // start, MIDDLE, end — what the third pick used to mean
      final then = arcFrom3Points(
          const Offset(0, 0), const Offset(10, 6), const Offset(20, 0))!;
      expect(now.data[0], closeTo(then.$1.dx, 1e-9));
      expect(now.data[1], closeTo(then.$1.dy, 1e-9));
      expect(now.data[2], closeTo(then.$2, 1e-9));
    });
  });
}

/// [q] pulled onto the circle of radius [r] around [c] — the arc slot's rails
/// sit r_outer/r_inner from the centre, the centre arc between them.
Offset _towards(Offset c, Offset q, double r) =>
    c + (q - c) / (q - c).distance * r;

/// A point squarely ON [g], halfway along its sweep — where a finger aiming at
/// that arc would land.
Offset _midOfArc(Geo g) {
  // arcSweep is signed and already accounts for the reversed flag, so walking
  // half of it from the start angle stays on the drawn side.
  final mid = g.data[3] + arcSweep(g) / 2;
  return Offset(g.data[0] + g.data[2] * math.cos(mid),
      g.data[1] + g.data[2] * math.sin(mid));
}

bool _same(List<Geo> a, List<Geo> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].data.length != b[i].data.length) return false;
    for (var k = 0; k < a[i].data.length; k++) {
      if (a[i].data[k] != b[i].data[k]) return false;
    }
  }
  return true;
}

/// Is [q] on the arc's DRAWN side — inside the sweep, not on the rest of the
/// circle?
bool _onArc(Geo g, Offset q) {
  final c = Offset(g.data[0], g.data[1]);
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final rev = g.data.length > 5 && g.data[5] != 0;
  final a = math.atan2(q.dy - c.dy, q.dx - c.dx);
  final from = rev ? g.data[4] : g.data[3];
  final to = rev ? g.data[3] : g.data[4];
  return norm(a - from) <= norm(to - from) + 1e-9;
}

Matcher _near(Offset p) => predicate<Offset>(
    (q) => (q - p).distance < 1e-9, 'within a nanometre of $p');
