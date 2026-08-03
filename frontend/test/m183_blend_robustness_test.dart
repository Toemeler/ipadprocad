// M183 — a fillet and chamfer that cannot break.
//
// Three failures from the device session of build 0ad6cc3, all of them in the
// path between "the user picked this edge" and "the kernel rounded it":
//
//  F1  Making a wall 2 mm taller translated a boss and both of a chamfer's
//      edges with it. 2 mm is further than a fingerprint may drift, so both
//      selections were reported LOST and the feature died with "none of the
//      selected edges exist any more" — for an edit that removed neither edge.
//
//  F2  A fillet stored against a 17.96 mm edge re-matched onto a 12.80 mm one
//      because length was only a 0.05-weighted nudge and the radius and
//      midpoint happened to agree. The body silently changed shape.
//
//  F3  (shim, not reachable from a host test) OCCT cannot build a blend that
//      lands exactly on a tangency, so a 2 mm fillet on a 2 mm wall failed
//      while 1.999 mm worked.
//
// F1 and F2 are pinned here. The rule that makes F1 safe rather than merely
// permissive is that a displacement must be CORROBORATED: either a sibling
// selection resolved at it, or it independently explains two lost selections.
// An offset invented for one selection alone would let a fillet walk to any
// edge on the body, which is the failure M158 was written to stop.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A circular edge of radius [r] whose arc-length midpoint sits at (x, y, z),
/// the way the shim reports one.
OcctEdgeInfo _rim(int i, double r,
        {double x = 0, double y = 0, double z = 0, double? len}) =>
    OcctEdgeInfo(i, 2, x, y, z, 1, 0, 0, len ?? 2 * math.pi * r, r, 2, 90, 1);

/// A straight edge of length [len] centred at (x, y, z).
OcctEdgeInfo _line(int i, double len,
        {double x = 0, double y = 0, double z = 0}) =>
    OcctEdgeInfo(i, 1, x, y, z, 1, 0, 0, len, 0, 2, 90, 1);

EdgeSel _selOf(OcctEdgeInfo e) =>
    EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius);

/// A fillet carrying [sels], for exercising resolveEdges.
FilletFeature _fillet(List<EdgeSel> sels) => FilletFeature(
      name: 'Fillet1',
      bodyName: 'Solid1',
      edges: sels,
      radii: [for (var i = 0; i < sels.length; i++) 2.0],
    );

void main() {
  group('M183 F2 — an edge of a very different length is a different edge', () {
    test('the device case: 17.96 mm must not re-match onto 12.80 mm', () {
      // Same radius, same midpoint, two thirds the length. Before M183 the
      // length term cost 0.05 * 5.16 = 0.26 against a 0.96 tolerance, so this
      // matched and the fillet moved to an edge the user never picked.
      final sel = EdgeSel(0, 11.435, -8.451, 17.964, 2, 2.8590);
      final impostor = _rim(8, 2.8590, y: 11.435, z: -8.451, len: 12.802);
      expect(sel.bestMatch([impostor]), isNull,
          reason: 'a 29% length change with everything else equal is a '
              'different edge, and taking it silently reshapes the body');
    });

    test('a fillet legitimately shrinking its neighbour is still followed', () {
      // The reason length was weak in the first place: rounding one edge
      // shortens the ones beside it. A 10% trim must still resolve.
      final sel = EdgeSel(0, 0, 0, 20.0, 1, 0);
      expect(sel.bestMatch([_line(1, 18.0)])?.index, 1);
    });

    test('length is a COST, never a disqualification', () {
      // A long edge buys a proportionally larger tolerance, so the same
      // absolute trim that sinks a small edge is affordable on a big one.
      expect(EdgeSel(0, 0, 0, 100.0, 1, 0).bestMatch([_line(1, 90.0)])?.index, 1,
          reason: 'a tenth off a 100 mm edge is a trimmed neighbour');
      expect(EdgeSel(0, 0, 0, 10.0, 1, 0).bestMatch([_line(1, 4.0)]), isNull,
          reason: 'but losing well over half of a short one is another edge');
    });

    test('a zero-length fingerprint does not blow up', () {
      final sel = EdgeSel(0, 0, 0, 0, 1, 0);
      expect(() => sel.bestMatch([_line(1, 5)]), returnsNormally);
    });
  });

  group('M183 F1 — a body that MOVED has not lost its edges', () {
    test('the device case: both chamfer edges travel 2 mm and both survive',
        () {
      // Chamfer1 held the two rims of a boss, at y=10 and y=5. Extrusion1
      // underneath went from 5 mm to 7 mm tall, lifting both by 2 mm — four
      // times the 0.66 mm a 1.64 mm rim is allowed to drift.
      final top = EdgeSel(1.641, 10.0, 13.990, 10.308, 2, 1.6405);
      final bottom = EdgeSel(1.641, 5.0, 13.990, 10.308, 2, 1.6405);
      final f = _fillet([top, bottom]);
      final live = [
        _rim(4, 1.6405, x: 1.641, y: 12.0, z: 13.990, len: 10.308),
        _rim(5, 1.6405, x: 1.641, y: 7.0, z: 13.990, len: 10.308),
        _line(9, 34.2, x: 3.5, y: 3.5, z: 0), // unrelated base edges
        _line(10, 34.2, x: -3.5, y: 3.5, z: 0),
      ];

      final (ids, src, lost) = f.resolveEdges(live);
      expect(lost, 0, reason: 'the edit removed neither edge');
      expect(ids, [4, 5]);
      expect(src, [0, 1]);
    });

    test('and the fingerprints re-anchor, so the next rebuild starts level',
        () {
      final top = EdgeSel(1.641, 10.0, 13.990, 10.308, 2, 1.6405);
      final bottom = EdgeSel(1.641, 5.0, 13.990, 10.308, 2, 1.6405);
      final f = _fillet([top, bottom]);
      f.resolveEdges([
        _rim(4, 1.6405, x: 1.641, y: 12.0, z: 13.990, len: 10.308),
        _rim(5, 1.6405, x: 1.641, y: 7.0, z: 13.990, len: 10.308),
      ]);
      expect(top.my, 12.0);
      expect(bottom.my, 7.0);
    });

    test('a SIBLING that resolved lends its displacement to one that did not',
        () {
      // A wide rim (tol 5.25 mm) still matches after a 2 mm lift; the small
      // rim beside it (tol 0.66 mm) does not, and borrows the evidence.
      final wide = EdgeSel(0, 10.0, 0, 2 * math.pi * 20, 2, 20.0);
      final small = EdgeSel(0, 10.0, 8.0, 10.308, 2, 1.6405);
      final f = _fillet([wide, small]);
      final live = [
        _rim(1, 20.0, y: 12.0),
        _rim(2, 1.6405, y: 12.0, z: 8.0, len: 10.308),
      ];

      final (ids, _, lost) = f.resolveEdges(live);
      expect(lost, 0);
      expect(ids, [1, 2]);
    });

    test('a feature spanning a part that moved and one that did not keeps both',
        () {
      // Two edges on the raised boss, one on the base that never moved. Each
      // selection is tried against every justified displacement including the
      // zero one it already had, so the split resolves.
      final bossA = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final bossB = EdgeSel(0, 5.0, 0, 10.308, 2, 1.6405);
      final base = EdgeSel(0, 0, 20.0, 30.0, 1, 0);
      final f = _fillet([bossA, bossB, base]);
      final live = [
        _rim(1, 1.6405, y: 12.0, len: 10.308),
        _rim(2, 1.6405, y: 7.0, len: 10.308),
        _line(3, 30.0, z: 20.0),
      ];

      final (ids, src, lost) = f.resolveEdges(live);
      expect(lost, 0);
      expect(src, [0, 1, 2]);
      expect(ids, [1, 2, 3]);
    });
  });

  group('M183 — a displacement still has to be earned', () {
    test('one lost selection on its own may NOT invent an offset', () {
      // With a free displacement every live edge fits perfectly, so a single
      // unsupported selection would walk to whichever edge happened to be
      // nearest. It stays lost instead.
      final sel = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final f = _fillet([sel]);
      final (ids, _, lost) = f.resolveEdges([
        _rim(1, 1.6405, y: 40.0, len: 10.308),
      ]);
      expect(lost, 1);
      expect(ids, isEmpty);
      expect(sel.my, 10.0, reason: 'a refused match never rewrites the pick');
    });

    test('two lost selections that disagree about the offset stay lost', () {
      // One would have to move +30, the other +2. Neither displacement
      // explains the other selection, so neither is corroborated.
      final a = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final b = EdgeSel(0, 5.0, 8.0, 10.308, 2, 1.6405);
      final f = _fillet([a, b]);
      final (ids, _, lost) = f.resolveEdges([
        _rim(1, 1.6405, y: 40.0, len: 10.308),
        _rim(2, 1.6405, y: 7.0, z: 8.0, len: 10.308),
      ]);
      // b is explained by +2 alone, which no sibling corroborates.
      expect(lost, 2);
      expect(ids, isEmpty);
    });

    test('M158 still holds: a near-tie in the shifted frame is refused', () {
      // Both selections moved +2, but at the destination two rims sit
      // symmetrically around where each one lands. Displacement is not a
      // licence to guess between look-alikes.
      final a = EdgeSel(0, 10.0, 0, 2 * math.pi * 10, 2, 10.0);
      final b = EdgeSel(0, 30.0, 0, 2 * math.pi * 10, 2, 10.0);
      final f = _fillet([a, b]);
      final (_, __, lost) = f.resolveEdges([
        _rim(1, 10.4, y: 12.0),
        _rim(2, 9.6, y: 12.0),
        _rim(3, 10.4, y: 32.0),
        _rim(4, 9.6, y: 32.0),
      ]);
      expect(lost, 2, reason: 'a coin toss stays a coin toss after a shift');
    });

    test('two selections never collapse onto the same live edge', () {
      // The one-edge-per-selection rule has to survive the second pass too:
      // two picks drifting toward one survivor would otherwise become a
      // double-radius fillet on a single edge.
      final a = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final b = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final f = _fillet([a, b]);
      final (ids, _, lost) = f.resolveEdges([
        _rim(1, 1.6405, y: 10.0, len: 10.308),
      ]);
      expect(ids, [1]);
      expect(lost, 1);
    });

    test('an unmoved model resolves in the first pass, offsets unused', () {
      final live = [
        _rim(1, 1.6405, y: 10.0, len: 10.308),
        _rim(2, 1.6405, y: 5.0, len: 10.308),
      ];
      final f = _fillet([_selOf(live[0]), _selOf(live[1])]);
      final (ids, src, lost) = f.resolveEdges(live);
      expect(lost, 0);
      expect(ids, [1, 2]);
      expect(src, [0, 1]);
    });

    test('a deleted edge is reported gone while its moved siblings survive',
        () {
      // Three rims on a boss that rose 2 mm; the third was also deleted. The
      // two survivors corroborate the displacement and resolve, and the
      // missing one is NOT conjured onto either of them.
      final a = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final b = EdgeSel(0, 5.0, 0, 10.308, 2, 1.6405);
      final gone = EdgeSel(0, 0.0, 0, 10.308, 2, 1.6405);
      final f = _fillet([a, b, gone]);
      final (ids, src, lost) = f.resolveEdges([
        _rim(1, 1.6405, y: 12.0, len: 10.308),
        _rim(2, 1.6405, y: 7.0, len: 10.308),
      ]);
      expect(ids, [1, 2]);
      expect(src, [0, 1]);
      expect(lost, 1);
    });
  });

  group('M183 F3 — the kernel says what it actually did', () {
    test('a blend built exactly as asked reports nothing', () {
      final r = BlendReport();
      expect(r.resized, isFalse);
      expect(r.note(3, 'r=2 mm'), isNull);
    });

    test('a skipped edge is named', () {
      final r = BlendReport()..dropped.addAll([1]);
      expect(r.note(3, 'r=2 mm'), contains('1 of 3'));
      expect(r.note(3, 'r=2 mm'), contains('skipped'));
    });

    test('a tangency retry is reported as a deviation, not as a ratio', () {
      // "0.999" tells a user nothing. Parts per million of the radius is a
      // number they can weigh against their own tolerance.
      final r = BlendReport()..sizeScale = 1.0 - 1.0e-3;
      expect(r.resized, isTrue);
      final note = r.note(1, 'r=2 mm');
      expect(note, contains('1000 ppm'));
      expect(note, contains('tangency'));
    });

    test('both departures are reported together', () {
      final r = BlendReport()
        ..dropped.addAll([0, 2])
        ..sizeScale = 1.0 - 1.0e-5;
      final note = r.note(4, 'd=1 mm')!;
      expect(note, contains('2 of 4'));
      expect(note, contains('10 ppm'));
    });

    test('floating-point noise in the scale is not a deviation', () {
      expect((BlendReport()..sizeScale = 1.0).resized, isFalse);
      expect(BlendReport().note(1, 'r=2 mm'), isNull);
    });
  });

  group('M183 — the radii stay paired with the edges they belong to', () {
    test('a displaced set keeps each radius on its own edge', () {
      final a = EdgeSel(0, 10.0, 0, 10.308, 2, 1.6405);
      final b = EdgeSel(0, 5.0, 0, 10.308, 2, 1.6405);
      final f = FilletFeature(
        name: 'Fillet1',
        bodyName: 'Solid1',
        edges: [a, b],
        radii: [1.0, 3.0],
      );
      final (ids, src, _) = f.resolveEdges([
        _rim(7, 1.6405, y: 12.0, len: 10.308),
        _rim(8, 1.6405, y: 7.0, len: 10.308),
      ]);
      expect(ids, [7, 8]);
      // src is what the fold indexes the radius list with.
      expect([for (final i in src) f.radii[i]], [1.0, 3.0]);
    });
  });
}
