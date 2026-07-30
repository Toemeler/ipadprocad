// M152 — the chamfer that walked.
//
// Picked on the inner rim of a boss; after OK it came back on the outer rim of
// the cylinder underneath. EdgeSel re-anchors a stored selection onto a live
// edge after every rebuild, and it was doing so on POSITION and LENGTH only:
// `radius` was written into the file from the beginning and never read. Two
// concentric circles have midpoints just (R - r) apart, so position cannot
// separate them, and length is deliberately a weak term. Radius is the one
// thing that can — hence these tests.
//
// The second half is the tolerance. It was 0.25 * (length + 1), and for a
// circle `length` is the CIRCUMFERENCE: a 30 mm rim is 188 mm long and bought
// itself a 47 mm search radius, wide enough to swallow most of the part.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A circular edge lying in z = [z], centred on the axis, of radius [r].
/// The arc-length midpoint of a full circle is a point on the rim, which is
/// exactly why two concentric circles look so similar to a position test.
OcctEdgeInfo circle(int index, double r, double z) => OcctEdgeInfo(
    index, 2, r, 0, z, 0, 1, 0, 2 * 3.141592653589793 * r, r, 2, 90, 1);

EdgeSel selFor(OcctEdgeInfo e) =>
    EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius);

void main() {
  group('concentric circles', () {
    test('the inner rim does not re-anchor onto the outer one', () {
      // The reported bug, reduced: a boss rim at r=20 sitting 10 mm above the
      // cylinder rim at r=30. Midpoints are 10 mm apart in x and 10 in z.
      final inner = circle(1, 20, 10);
      final outer = circle(2, 30, 0);
      final sel = selFor(inner);

      final m = sel.bestMatch([outer, inner]);
      expect(m, isNotNull);
      expect(m!.index, 1, reason: 'must stay on the edge that was picked');
    });

    test('with the inner edge gone it reports LOST, not the outer one',
        () {
      // Silently moving to a different edge is what produced a chamfer in a
      // place nobody asked for. Losing the edge is the honest outcome.
      final sel = selFor(circle(1, 20, 10));
      expect(sel.bestMatch([circle(2, 30, 0)]), isNull);
    });

    test('a tightly nested pair is still separated by radius alone', () {
      // Same plane, 4 mm apart radially — position gives almost nothing.
      final inner = circle(1, 20, 0);
      final outer = circle(2, 24, 0);
      expect(selFor(inner).bestMatch([outer, inner])!.index, 1);
      expect(selFor(outer).bestMatch([outer, inner])!.index, 2);
    });
  });

  group('the edge is still allowed to move', () {
    test('a small shift along the axis is followed', () {
      // Changing an extrusion's height moves its rim; the chamfer must ride
      // along rather than being dropped.
      final sel = selFor(circle(1, 20, 10));
      final moved = circle(7, 20, 12);
      expect(sel.bestMatch([moved])!.index, 7);
    });

    test('a modest radius change is followed, because neighbours shrink it',
        () {
      // A chamfer on an adjacent edge legitimately shrinks this circle. Radius
      // is weighted, NOT disqualifying, exactly so this case survives.
      final sel = selFor(circle(1, 20, 0));
      expect(sel.bestMatch([circle(9, 19, 0)])!.index, 9);
    });

    test('re-anchoring updates the fingerprint so it does not drift', () {
      final sel = selFor(circle(1, 20, 10));
      final moved = circle(7, 20, 13);
      sel.reanchor(sel.bestMatch([moved])!);
      expect(sel.mz, closeTo(13, 1e-9));
      // And from the new anchor it can follow a further step of the same size.
      expect(sel.bestMatch([circle(8, 20, 16)])!.index, 8);
    });
  });

  group('tolerance', () {
    test('a long circular edge no longer gets a huge search radius', () {
      // r=100 -> circumference 628. The old rule allowed 157 mm of drift.
      final sel = selFor(circle(1, 100, 0));
      final farAway = circle(2, 100, 60); // 60 mm away, same radius
      expect(sel.bestMatch([farAway]), isNull,
          reason: 'circumference must not set the tolerance');
    });

    test('a straight edge still scales with its own length', () {
      const line =
          OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 40, 0, 2, 90, 1);
      final sel = selFor(line);
      const moved =
          OcctEdgeInfo(5, 1, 0, 3, 0, 1, 0, 0, 40, 0, 2, 90, 1);
      expect(sel.bestMatch([moved])!.index, 5);
    });
  });

  group('unchanged guarantees', () {
    test('a type change still disqualifies', () {
      final sel = selFor(circle(1, 20, 0));
      const asLine =
          OcctEdgeInfo(2, 1, 20, 0, 0, 0, 1, 0, 125.6, 0, 2, 90, 1);
      expect(sel.bestMatch([asLine]), isNull);
    });

    test('a free boundary is never filletable', () {
      final sel = selFor(circle(1, 20, 0));
      final free = OcctEdgeInfo(2, 2, 20, 0, 0, 0, 1, 0,
          2 * 3.141592653589793 * 20, 20, 1, 90, 1);
      expect(sel.bestMatch([free]), isNull);
    });
  });
}
