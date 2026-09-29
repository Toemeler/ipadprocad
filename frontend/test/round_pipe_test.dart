// The path of a round sweep recovered as lines and arcs (round_pipe.dart).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/round_pipe.dart';

void main() {
  // A handle path in the xy plane: leg, a quarter arc, a straight grip.
  List<double> handle() {
    final pts = <double>[0, 0, 0, 20, 0, 0];
    const r = 8.0;
    for (var k = 1; k <= 24; k++) {
      final t = -math.pi / 2 + (math.pi / 2) * k / 24;
      pts.addAll([20 + r * math.cos(t), r + r * math.sin(t), 0]);
    }
    pts.addAll([28, 40, 0]);
    return pts;
  }

  test('a leg, a tangent arc and a grip are three exact pieces', () {
    final s = roundPipeSegments(handle())!;
    expect(s.length, 30);
    expect(s[0], 0); // line
    expect(s[10], 1); // arc
    expect([s[17], s[18], s[19]], [closeTo(20, 1e-9), closeTo(8, 1e-9), 0]);
    expect(s[20], 0); // line
    expect([s[24], s[25]], [closeTo(28, 1e-9), closeTo(40, 1e-9)]);
  });

  test('a sharp corner is left to the ordinary sweep', () {
    expect(roundPipeSegments([0, 0, 0, 10, 0, 0, 10, 10, 0]), isNull);
  });

  test('a straight path is one line', () {
    final s = roundPipeSegments([0, 0, 0, 5, 5, 5, 10, 10, 10])!;
    expect(s.length, 10);
    expect(s[0], 0);
  });

  test('a half turn is split into pieces under 180 degrees', () {
    final pts = <double>[];
    for (var k = 0; k <= 48; k++) {
      final t = math.pi * k / 48;
      pts.addAll([10 * math.cos(t), 10 * math.sin(t), 0]);
    }
    final s = roundPipeSegments(pts)!;
    expect(s.length ~/ 10, greaterThanOrEqualTo(2));
    for (var i = 0; i < s.length; i += 10) {
      expect(s[i], 1);
    }
  });

  test('a path refitted as an even spline is not read as pieces', () {
    // The sweep's resolved path is a spline refitted through evenly spaced
    // samples: its bends are not circles, so the exact pieces come from the
    // path as drawn (SweepFeature.roundPath), never from these points.
    final raw = File('test/fixtures/handle_path.txt').readAsStringSync();
    final pts = [for (final v in raw.split(',')) double.parse(v)];
    expect(roundPipeSegments(pts), isNull);
  });

  test('a drawn path splits its long arcs and runs backwards', () {
    // A half turn (just over 180°) becomes two arcs under 180°.
    final half = <double>[1, 10, 0, 0, -10, 0.0001, 0, 0, 0, 0];
    final pieces = splitRoundArcs(half);
    expect(pieces.length, 20);
    final back = reverseRoundPath([0, 0, 0, 0, 5, 0, 0, 0, 0, 0]);
    expect([back[1], back[4]], [5, 0]);
  });
}
