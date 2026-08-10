// M209 — AN ANGLE DIMENSION MEASURES A PARTICULAR ANGLE, AND SHOULD SAY SO.
//
// "Angle dimensions work good but they look very weird ... currently it's
// possible to move the dimension so it's not clear that the chosen angle is
// meant, also no arrows."
//
// The arc was centred on the direction of the LABEL and swept the measured
// value about it. That is an arc of the right SIZE at an arbitrary bearing:
// drag the text around the vertex and the arc follows it, so the picture stops
// saying which of the four angles at that crossing the number belongs to.
//
// Inventor draws the arc BETWEEN THE TWO LEGS. The text only chooses the
// radius and which side it is on; dragging it across the vertex switches to
// the adjacent angle instead of spinning the same one somewhere new. This
// pins the arithmetic that decides the span — the arrowheads and the dashed
// extensions hang off the same two numbers.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/pick_math.dart';

const _deg = math.pi / 180;

/// The bearing halfway along the span, which is where the label goes.
double _mid(double start, double sweep) => start + sweep / 2;

/// Normalised to (-pi, pi].
double _n(double a) {
  var v = a;
  while (v <= -math.pi) {
    v += 2 * math.pi;
  }
  while (v > math.pi) {
    v -= 2 * math.pi;
  }
  return v;
}

void main() {
  group('the arc runs between the legs, not around the label', () {
    test('two legs at 60 degrees: the span is the legs, whatever the value',
        () {
      // Leg A along +x, leg B at 60 degrees.
      final (start, sweep) = angleArcSpan(0, 60 * _deg, 30 * _deg, 60);
      expect(sweep.abs() / _deg, closeTo(60, 1e-6));
      // and it STARTS on a leg — the whole point.
      expect(_n(start) / _deg, closeTo(0, 1e-6));
    });

    test('moving the label does not move the arc off the legs', () {
      // Same legs, label dragged out to 45 and then to 10 degrees: the arc is
      // the same span both times. Under the old rule it rotated with the text.
      final a = angleArcSpan(0, 60 * _deg, 45 * _deg, 60);
      final b = angleArcSpan(0, 60 * _deg, 10 * _deg, 60);
      expect(a.$1, closeTo(b.$1, 1e-9));
      expect(a.$2, closeTo(b.$2, 1e-9));
    });

    test('the label picks WHICH angle, by being inside it', () {
      // Legs at 0 and 60. The label at 30 is inside the 60-degree wedge; at
      // 210 it is inside the opposite one. Both are 60 degrees, and the arc
      // must be drawn where the user put the text.
      final near = angleArcSpan(0, 60 * _deg, 30 * _deg, 60);
      final far = angleArcSpan(0, 60 * _deg, 210 * _deg, 60);
      expect(near.$2.abs() / _deg, closeTo(60, 1e-6));
      expect(far.$2.abs() / _deg, closeTo(60, 1e-6));
      expect(_n(_mid(near.$1, near.$2)) / _deg, closeTo(30, 1e-6));
      expect(_n(_mid(far.$1, far.$2)) / _deg, closeTo(-150, 1e-6),
          reason: 'the opposite wedge, which is where the label is');
    });

    test('the supplementary angle is drawn when that is what was measured',
        () {
      // Same two legs, but the dimension measures 120 — the OTHER pair of
      // directions. The arc must span 120, not 60.
      final (_, sweep) = angleArcSpan(0, 60 * _deg, 120 * _deg, 120);
      expect(sweep.abs() / _deg, closeTo(120, 1e-6));
    });

    test('a right angle comes out square', () {
      final (start, sweep) = angleArcSpan(0, 90 * _deg, 45 * _deg, 90);
      expect(sweep.abs() / _deg, closeTo(90, 1e-6));
      expect(_n(start) / _deg, closeTo(0, 1e-6));
    });

    test('a label inside a 70-degree wedge gets THAT wedge', () {
      // Legs at 0 and 70 leave two 70-degree wedges: 0..70 and 180..250. A
      // label in either must be inside the arc that is drawn for it.
      for (final labelDeg in [5.0, 25.0, 55.0, 65.0, 185.0, 205.0, 245.0]) {
        final (start, sweep) = angleArcSpan(0, 70 * _deg, labelDeg * _deg, 70);
        expect(sweep.abs() / _deg, closeTo(70, 1e-6));
        final delta = _n(_mid(start, sweep) - labelDeg * _deg).abs() / _deg;
        expect(delta, lessThanOrEqualTo(35 + 1e-6),
            reason: 'label at $labelDeg fell outside its own 70-degree arc');
      }
    });

    test('a label in the OTHER wedge still gets an arc of the right size', () {
      // At 95 or 350 degrees the label sits in one of the 110-degree wedges,
      // which is not what this dimension measures. There is no honest wedge to
      // put it in, so the rule falls back to measuring correctly — drawing a
      // 110-degree arc for a 70-degree number would be the real lie.
      for (final labelDeg in [95.0, 350.0]) {
        final (_, sweep) = angleArcSpan(0, 70 * _deg, labelDeg * _deg, 70);
        expect(sweep.abs() / _deg, closeTo(70, 1e-6));
      }
    });
  });

  group('degenerate input still draws something', () {
    test('parallel legs fall back to a label-centred arc', () {
      // Nothing between two parallel legs measures 30 degrees; rather than
      // draw nothing, the old behaviour is the fallback.
      final (start, sweep) = angleArcSpan(0, 0, 90 * _deg, 30);
      expect(sweep.isFinite, isTrue);
      expect(start.isFinite, isTrue);
    });

    test('a zero-degree dimension does not blow up', () {
      final (start, sweep) = angleArcSpan(0, 0, 0, 0);
      expect(sweep.isFinite, isTrue);
      expect(start.isFinite, isTrue);
    });
  });
}
