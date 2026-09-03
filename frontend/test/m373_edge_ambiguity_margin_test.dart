// M373 — an EXACT edge match is not a coin toss.
//
// Issue #13, from the device:
//
//   "i somehow cant make a radius here on the 2 top edges. it says the edges
//    dont exist but i can see them they are clearly there"
//
// The bundle's log is the whole diagnosis. The pick and the loss are two lines
// apart, on the same edge, in the same rebuild:
//
//   edge: pick edge 24  r=0.0000 l=310.000 k=1 m=(0.000,50.000,168.000)
//   edge: sel[0] LOST — r=0.0000 l=310.000 k=1 m=(0.000,50.000,168.000);
//         no confident match among 30 live edges
//
// A fingerprint taken off a live edge scores ZERO against that edge, so the
// match was perfect and was thrown away anyway. M158's ambiguity guard used
// [EdgeSel.tol] — a DISPLACEMENT budget that scales with the edge's size — as
// the SEPARATION threshold between the best candidate and the next one. On the
// user's 310 x 336 x 50 plate that budget is 77.75 mm, and the bottom edge
// directly below the picked one is 50 mm away: a different edge by any human
// reading, and inside the window.
//
// The fix scales the margin with the WINNER'S OWN score instead, capped at the
// old tolerance so the rule is never stricter than it was. These tests pin
// both halves: the perfect match now resolves, and the genuinely ambiguous
// pair M158 was written about still does not.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart' show OcctEdgeInfo;
import 'package:prototype/part_model.dart' show EdgeSel;

/// An ordinary filletable straight edge: two adjacent faces, no radius.
OcctEdgeInfo line(int i, double mx, double my, double mz, double length) =>
    OcctEdgeInfo(i, 1, mx, my, mz, 1, 0, 0, length, 0, 2);

/// A filletable circular edge.
OcctEdgeInfo circle(int i, double mx, double my, double mz, double radius) =>
    OcctEdgeInfo(i, 2, mx, my, mz, 1, 0, 0, 2 * 3.141592653589793 * radius,
        radius, 2);

/// The twelve edges of the reporter's plate: 310 in x, 336 in z, 50 tall,
/// centred on the origin in x and z and sitting on y = 0.
///
/// The numbers are the bundle's, not invented ones: `state.txt` gives the
/// extrusion bbox as -155,0,-168 .. 155,50,168, and the log's own fingerprints
/// (l=310 at m=(0,50,±168), l=336 at m=(±155,50,0)) fall straight out of it.
List<OcctEdgeInfo> plateEdges() {
  final e = <OcctEdgeInfo>[];
  var i = 0;
  for (final y in [0.0, 50.0]) {
    // the two 310 mm edges, running along x at z = +-168
    e.add(line(i++, 0, y, 168, 310));
    e.add(line(i++, 0, y, -168, 310));
    // the two 336 mm edges, running along z at x = +-155
    e.add(line(i++, 155, y, 0, 336));
    e.add(line(i++, -155, y, 0, 336));
  }
  // the four 50 mm uprights
  for (final x in [155.0, -155.0]) {
    for (final z in [168.0, -168.0]) {
      e.add(line(i++, x, 25, z, 50));
    }
  }
  return e;
}

void main() {
  // =========================================================================
  group('issue #13 — the top edges of a plate', () {
    test('an edge picked off the live body matches ITSELF', () {
      // The report's edge 24, exactly as the log recorded it.
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      final m = sel.bestMatch(plateEdges());
      expect(m, isNotNull,
          reason: 'the fingerprint came off this very edge; it cannot be gone');
      expect(m!.mz, closeTo(168, 1e-9));
      expect(m.my, closeTo(50, 1e-9));
      expect(m.length, closeTo(310, 1e-9));
    });

    test('and so does the second one the user picked', () {
      final sel = EdgeSel(0, 50, -168, 310, 1, 0);
      final m = sel.bestMatch(plateEdges());
      expect(m, isNotNull);
      expect(m!.mz, closeTo(-168, 1e-9));
    });

    test('the 336 mm pair resolves too — same bug, other axis', () {
      // The log's second attempt: m=(+-155,50,0) l=336.
      for (final x in [155.0, -155.0]) {
        final sel = EdgeSel(x, 50, 0, 336, 1, 0);
        final m = sel.bestMatch(plateEdges());
        expect(m, isNotNull, reason: 'x=$x');
        expect(m!.mx, closeTo(x, 1e-9));
        expect(m.my, closeTo(50, 1e-9));
      }
    });

    test('the match is the TOP edge, not the bottom one 50 mm below it', () {
      // The whole point: the near neighbour that made this ambiguous is a
      // real edge and must not be the answer.
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      expect(sel.bestMatch(plateEdges())!.my, closeTo(50, 1e-9));
      final bottom = EdgeSel(0, 0, 168, 310, 1, 0);
      expect(bottom.bestMatch(plateEdges())!.my, closeTo(0, 1e-9));
    });

    test('every edge of the plate resolves to itself', () {
      // A sweep, because the reporter tried four different edges and the
      // failure has to be gone for all of them rather than for the two named.
      final live = plateEdges();
      for (final e in live) {
        final sel = EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius);
        final m = sel.bestMatch(live);
        expect(m, isNotNull,
            reason: 'edge ${e.index} at (${e.mx},${e.my},${e.mz})');
        expect(m!.index, e.index);
      }
    });
  });

  // =========================================================================
  group('M158 still holds — a real coin toss is still refused', () {
    test('two concentric rims a hair apart stay ambiguous', () {
      // The bug M158 was written about: a chamfer picked on the inner rim of a
      // boss came back on the outer rim of the cylinder underneath. The
      // fingerprint has DRIFTED (it does not match either exactly), and the
      // two candidates are within a hair of each other.
      final live = [
        circle(0, 0, 10, 0, 12.0),
        circle(1, 0, 10, 0, 12.3),
      ];
      // Sits between them: 0.15 from each in radius, identical in position.
      final sel = EdgeSel(0, 10, 0, 2 * 3.141592653589793 * 12.15, 2, 12.15);
      expect(sel.bestMatch(live), isNull,
          reason: 'neither candidate is meaningfully better than the other');
    });

    test('a drifted match with a close runner-up is still refused', () {
      final live = [
        line(0, 0, 3.0, 0, 40),
        line(1, 0, 3.4, 0, 40),
      ];
      final sel = EdgeSel(0, 0, 0, 40, 1, 0); // 3.0 and 3.4 away
      expect(sel.bestMatch(live), isNull);
    });

    test('two live edges with the SAME fingerprint are ambiguous', () {
      // The degenerate tie the floor exists for: an exact match on both.
      final live = [
        line(0, 0, 50, 168, 310),
        line(1, 0, 50, 168, 310),
      ];
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      expect(sel.bestMatch(live), isNull);
    });

    test('an edge that really is gone is still reported gone', () {
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      // Nothing within the displacement budget.
      final live = [line(0, 900, 900, 900, 310)];
      expect(sel.bestMatch(live), isNull);
    });

    test('a type change is still disqualifying', () {
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      final live = [circle(0, 0, 50, 168, 49.34)];
      expect(sel.bestMatch(live), isNull);
    });
  });

  // =========================================================================
  group('the margin is never stricter than the rule it replaces', () {
    test('a drifted-but-clear match still resolves', () {
      // M183's case: the body moved 2 mm and the edge went with it. One
      // candidate, no runner-up anywhere near.
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      final live = [
        line(0, 0, 52, 168, 310),
        line(1, 0, 52, -168, 310),
      ];
      final m = sel.bestMatch(live);
      expect(m, isNotNull);
      expect(m!.index, 0);
    });

    test('the offset search still finds an edge the body carried away', () {
      final sel = EdgeSel(0, 50, 168, 310, 1, 0);
      final live = [line(0, 0, 58, 168, 310)];
      // 8 mm is inside the 77.75 mm budget for a 310 mm edge.
      expect(sel.bestMatch(live), isNotNull);
      // ... and an explicit offset finds it dead on.
      expect(sel.bestMatch(live, oy: 8), isNotNull);
    });
  });
}
