// Shared picking arithmetic — the one implementation that four copies were
// collapsed into (tools.dart's _distToSegment, viewport3d's _distToSeg,
// part_pick's private copy, snap.dart's closestOnSegment).
//
// These tests exist because merging four implementations is exactly where a
// silent behaviour change hides: each copy handled the degenerate zero-length
// segment slightly differently.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/pick_math.dart';
import 'package:prototype/snap.dart';

double _dist(Offset p, Offset a, Offset b) => math.sqrt(segDistSq(p, a, b).$1);

void main() {
  group('segDistSq', () {
    test('perpendicular distance to the middle of a segment', () {
      expect(_dist(const Offset(5, 3), Offset.zero, const Offset(10, 0)),
          closeTo(3, 1e-12));
      expect(segDistSq(const Offset(5, 3), Offset.zero, const Offset(10, 0)).$2,
          closeTo(0.5, 1e-12));
    });

    test('clamps past the ends instead of using the infinite line', () {
      // 20 px beyond the far end: the answer is the distance to the ENDPOINT,
      // which is what stops an edge being pickable off into space.
      expect(_dist(const Offset(30, 0), Offset.zero, const Offset(10, 0)),
          closeTo(20, 1e-12));
      expect(_dist(const Offset(-4, 3), Offset.zero, const Offset(10, 0)),
          closeTo(5, 1e-12));
      expect(segDistSq(const Offset(30, 0), Offset.zero, const Offset(10, 0)).$2,
          1.0);
      expect(segDistSq(const Offset(-9, 0), Offset.zero, const Offset(10, 0)).$2,
          0.0);
    });

    test('a zero-length segment is the distance to that point', () {
      // The four old copies disagreed here; this pins the merged behaviour.
      const a = Offset(4, 4);
      expect(_dist(const Offset(4, 9), a, a), closeTo(5, 1e-12));
      expect(segDistSq(const Offset(4, 9), a, a).$2, 0.0);
    });

    test('a point ON the segment is distance zero', () {
      expect(_dist(const Offset(6, 0), Offset.zero, const Offset(10, 0)),
          closeTo(0, 1e-12));
    });

    test('the returned parameter reconstructs the closest point', () {
      const a = Offset(1, 2), b = Offset(9, 8), p = Offset(3, 9);
      final (d2, t) = segDistSq(p, a, b);
      final closest = a + (b - a) * t;
      expect((p - closest).distanceSquared, closeTo(d2, 1e-9));
    });
  });

  group('closestOnSegment still matches its old contract', () {
    test('returns the projected point', () {
      expect(closestOnSegment(const Offset(5, 3), Offset.zero,
              const Offset(10, 0)),
          const Offset(5, 0));
    });

    test('degenerate segment returns the endpoint, as before', () {
      const a = Offset(2, 2);
      expect(closestOnSegment(const Offset(9, 9), a, a), a);
    });

    test('clamps rather than extending the line', () {
      expect(
          closestOnSegment(const Offset(99, 0), Offset.zero, const Offset(10, 0)),
          const Offset(10, 0));
    });
  });

  group('PickBest', () {
    test('starts empty', () {
      final b = PickBest<String>();
      expect(b.isEmpty, isTrue);
      expect(b.value, isNull);
    });

    test('the NEARER candidate wins even when further in pixels', () {
      final b = PickBest<String>()
        ..offer('far', 100, 0.5)
        ..offer('near', 10, 9.0);
      expect(b.value, 'near');
    });

    test('at equal depth the closer one in pixels wins', () {
      final b = PickBest<String>()
        ..offer('a', 10, 8.0)
        ..offer('b', 10, 2.0);
      expect(b.value, 'b');
    });

    test('a worse candidate is rejected and reported as such', () {
      final b = PickBest<String>();
      expect(b.offer('first', 10, 5), isTrue);
      expect(b.offer('worse', 20, 1), isFalse);
      expect(b.value, 'first');
    });

    test('wouldTake agrees with offer, so callers can skip building losers', () {
      final b = PickBest<String>()..offer('first', 10, 5);
      expect(b.wouldTake(20, 1), isFalse);
      expect(b.wouldTake(5, 99), isTrue);
      expect(b.wouldTake(10, 4), isTrue);
      // and asking must not mutate anything
      expect(b.value, 'first');
      expect(b.depth, 10);
    });

    test('equal depth AND equal pixels keeps the first seen', () {
      // stable, so a redraw cannot flicker between two coincident edges
      final b = PickBest<String>()
        ..offer('first', 10, 5)
        ..offer('second', 10, 5);
      expect(b.value, 'first');
    });
  });
}
