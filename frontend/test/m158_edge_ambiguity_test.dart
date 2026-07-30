// M158 — a chamfer that walks is worse than one that disappears.
//
// M152 gave EdgeSel a radius term because two concentric rims could not be
// told apart by position. That decides WHICH candidate wins. It never asks
// the second question: was the winner meaningfully better than the next one?
// When it was not, the match is a coin toss — and the coin decides which edge
// a chamfer lands on. On the device one picked on the inner rim of a boss came
// back on the outer rim of the cylinder underneath it.
//
// A near-tie is now reported LOST. Losing a chamfer is recoverable and
// obvious; silently moving one is neither.
//
// It also stops the RATCHET: bestMatch feeds reanchor, which overwrites the
// stored fingerprint with whatever was matched. One bad match used to rewrite
// the selection onto the wrong edge permanently, so every later rebuild
// confirmed the mistake.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A circular edge of radius [r] in a plane at height [z], anchored at its
/// arc-length midpoint the way the shim reports one.
OcctEdgeInfo _circle(int i, double r, {double z = 0}) => OcctEdgeInfo(
    i, 2, r, 0, z, 0, 1, 0, 2 * math.pi * r, r, 2, 90, 1);

EdgeSel _selFor(OcctEdgeInfo e) =>
    EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius);

void main() {
  group('M158 — a near-tie is LOST, not guessed', () {
    test('two rims that score alike resolve to nothing', () {
      // The picked rim is gone; two survivors sit symmetrically around where
      // it was, so neither is a better answer than the other.
      final sel = EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10);
      final a = _circle(1, 10.4);
      final b = _circle(2, 9.6);
      expect(sel.bestMatch([a, b]), isNull,
          reason: 'a coin toss must not silently place a chamfer');
    });

    test('and the fingerprint is left alone, so the mistake cannot ratchet',
        () {
      final sel = EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10);
      final before = (sel.mx, sel.radius, sel.length);
      sel.bestMatch([_circle(1, 10.4), _circle(2, 9.6)]);
      expect((sel.mx, sel.radius, sel.length), before,
          reason: 'a rejected match never rewrites the selection');
    });

    test('an UNAMBIGUOUS match still resolves', () {
      final want = _circle(1, 10);
      final sel = _selFor(want);
      // The other rim is far enough that the winner is clearly the winner.
      final m = sel.bestMatch([want, _circle(2, 30)]);
      expect(m, isNotNull);
      expect(m!.index, 1);
    });

    test('an exact rebuild is never ambiguous, however many edges there are',
        () {
      final want = _circle(7, 12);
      final sel = _selFor(want);
      final m = sel.bestMatch(
          [_circle(1, 30), want, _circle(2, 4), _circle(3, 20, z: 8)]);
      expect(m?.index, 7);
    });

    test('a lone survivor inside tolerance is still accepted', () {
      // Nothing to be ambiguous WITH: one candidate is not a coin toss.
      final sel = EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10);
      final m = sel.bestMatch([_circle(1, 10, z: 0.3)]);
      expect(m, isNotNull, reason: 'a small shift is still followed');
    });

    test('a lone survivor OUTSIDE tolerance is still lost', () {
      final sel = EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10);
      expect(sel.bestMatch([_circle(1, 30)]), isNull);
    });

    test('the reported case: inner rim, outer rim, inner one gone', () {
      // A boss rim at r=5 on top of a cylinder rim at r=7.5 — the shape in the
      // screenshot. The picked inner rim no longer exists.
      final sel = EdgeSel(5, 15, 0, 2 * math.pi * 5, 2, 5);
      expect(sel.bestMatch([_circle(1, 7.5, z: 0)]), isNull,
          reason: 'the outer rim is not a substitute for the inner one');
    });
  });

  group('M158 — resolveEdges reports the loss honestly', () {
    test('an ambiguous selection counts as lost, not as a silent move', () {
      final f = ChamferFeature(
        name: 'Chamfer1',
        bodyName: 'Solid1',
        edges: [EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10)],
      );
      final (ids, src, lost) =
          f.resolveEdges([_circle(1, 10.4), _circle(2, 9.6)]);
      expect(ids, isEmpty);
      expect(src, isEmpty);
      expect(lost, 1);
    });

    test('a clean selection still resolves and reanchors', () {
      final want = _circle(3, 10, z: 0.2);
      final f = ChamferFeature(
        name: 'Chamfer1',
        bodyName: 'Solid1',
        edges: [EdgeSel(10, 0, 0, 2 * math.pi * 10, 2, 10)],
      );
      final (ids, src, lost) = f.resolveEdges([want, _circle(4, 40)]);
      expect(ids, [3]);
      expect(src, [0]);
      expect(lost, 0);
      expect(f.edges.single.mz, closeTo(0.2, 1e-9),
          reason: 'a confident match still tracks the model');
    });
  });
}
