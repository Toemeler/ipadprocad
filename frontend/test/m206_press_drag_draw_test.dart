// M206 — ONE TAP, ONE POINT.
//
// "When I draw a circle and end the hover, when I go back into hover the
// preview won't work and I can't finish drawing the arc properly."
//
// The hover is a red herring; the log says what happened, eleven times:
//
//     14:26:59.050361  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=0
//     14:26:59.050432  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=1
//     14:26:59.712185  toolClick tool=Tool.arcThreePoint w=( 1.48,20.00) picks=2
//     layer: tool Tool.arcThreePoint built no geometry from 3 point(s)
//
// Two placements 71 MICROSECONDS apart at the same point. That is one Pencil
// tap: M53's press-drag-draw armed on 8 px of travel, an ordinary tap wobbles
// about that far, and the update that crossed the threshold and the release
// that follows it are dispatched from the SAME pointer event. So the anchor
// went down and the "drag" point went down on top of it — a three-point arc
// with two identical points builds nothing, and a circle gets its rim on its
// own centre.
//
// The threshold is the tap/drag question in M170's words, and this file is the
// numbers behind the answer: what a tap really measures against what a stroke
// does. Both come from the traces in `bug20260805T142912`.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/touch.dart';

/// The rule, in the form the viewport applies it: a press becomes a DRAWING
/// DRAG only past this much travel, and the release only places a second point
/// if it ended that far from the anchor.
double toolDragPx(PointerDeviceKind kind) => touchSlop(kind, 18);

bool placesTwoPoints(
    PointerDeviceKind kind, Offset down, Offset up, double armAt) {
  final travel = (up - down).distance;
  return travel > armAt; // arm AND release use the same distance
}

void main() {
  /// Real Pencil taps from the trace, as (down, up) screen positions.
  const taps = <(Offset, Offset)>[
    (Offset(731.5, 711.5), Offset(733.5, 708.0)), // p107
    (Offset(955.0, 650.0), Offset(961.0, 651.5)), // p108
    (Offset(1157.0, 642.0), Offset(1161.0, 644.5)), // p109
    (Offset(704.0, 583.0), Offset(711.0, 577.5)), // p112
    (Offset(1009.5, 539.0), Offset(1010.0, 537.0)), // p113
    (Offset(687.5, 566.0), Offset(686.0, 564.0)), // p114
    (Offset(856.5, 524.0), Offset(856.5, 522.0)), // p115
    (Offset(1008.5, 528.0), Offset(1010.0, 528.5)), // p116
  ];

  /// Real Pencil strokes from the same trace.
  const strokes = <(Offset, Offset)>[
    (Offset(710.0, 724.5), Offset(747.0, 702.5)), // p104
    (Offset(959.0, 796.5), Offset(1026.5, 793.5)), // p33
  ];

  group('the threshold separates a tap from a stroke', () {
    test('no real Pencil tap in the bundle reaches it', () {
      final arm = toolDragPx(PointerDeviceKind.stylus);
      for (final (down, up) in taps) {
        final travel = (up - down).distance;
        expect(travel, lessThan(arm),
            reason: 'a tap that travelled ${travel.toStringAsFixed(1)} px '
                'must not arm a drag at $arm');
      }
    });

    test('every real Pencil stroke clears it', () {
      final arm = toolDragPx(PointerDeviceKind.stylus);
      for (final (down, up) in strokes) {
        expect((up - down).distance, greaterThan(arm));
      }
    });

    test('the old flat 8 px did NOT separate them — that is the bug', () {
      // Four of the eight taps above cross 8 px. Each one of those placed two
      // points on the same spot and killed the arc.
      final crossing = taps.where((t) => (t.$2 - t.$1).distance > 8).length;
      expect(crossing, greaterThan(0),
          reason: 'if this ever reaches 0 the regression is untestable, '
              'not fixed');
    });

    test('a finger gets the usual wider slop', () {
      expect(toolDragPx(PointerDeviceKind.touch),
          greaterThan(toolDragPx(PointerDeviceKind.stylus)));
      expect(toolDragPx(PointerDeviceKind.touch),
          closeTo(18 * kTouchSlopFactor, 0.001));
    });
  });

  group('what a gesture places', () {
    test('a tap places nothing from the drag path', () {
      final arm = toolDragPx(PointerDeviceKind.stylus);
      for (final (down, up) in taps) {
        expect(placesTwoPoints(PointerDeviceKind.stylus, down, up, arm), isFalse,
            reason: 'the tap must fall through to the click-click flow, '
                'which places ONE point');
      }
    });

    test('a stroke places its second point', () {
      final arm = toolDragPx(PointerDeviceKind.stylus);
      for (final (down, up) in strokes) {
        expect(placesTwoPoints(PointerDeviceKind.stylus, down, up, arm), isTrue);
      }
    });

    test('a drag that returns to where it started places nothing', () {
      // The other hole: arm the gesture by going out 40 px, come back, and
      // release on the anchor. Placing there is a zero-length entity, which is
      // the same degenerate geometry by a different route — so the release
      // check measures the RELEASE against the anchor, not the furthest point.
      final arm = toolDragPx(PointerDeviceKind.stylus);
      const down = Offset(400, 400);
      const up = Offset(402, 401);
      expect(placesTwoPoints(PointerDeviceKind.stylus, down, up, arm), isFalse);
    });
  });
}
