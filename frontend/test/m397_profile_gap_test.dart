// M397 — #25: "the mirrored part of the sketch is somehow not closed and i
// cant extrude it or select it for extrusion but it clearly should be closed".
//
// It was six MICROMETRES open. The profile finder welds nodes within 1e-6 and
// must not weld more than that — two walls 20 um apart are a real feature of a
// real part — so it correctly found no region, the tap did nothing, and there
// was no way on earth to see why. This measures the miss so the app can say
// it out loud.
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

SketchModel sketchOf(List<Geo> gs) => SketchModel('t')..geometry.addAll(gs);

void main() {
  test('a closed square reports no gap', () {
    final s = sketchOf([
      Geo(Geo.line, [0, 0, 10, 0]),
      Geo(Geo.line, [10, 0, 10, 10]),
      Geo(Geo.line, [10, 10, 0, 10]),
      Geo(Geo.line, [0, 10, 0, 0]),
    ]);
    expect(nearestProfileGap(s), isNull);
  });

  test('the miss from the report is measured, and pointed at', () {
    // The square, with the last corner 0.0062 short of closing — the exact
    // amount a mirror about y=167.9969 instead of 168 left behind.
    final s = sketchOf([
      Geo(Geo.line, [0, 0, 10, 0]),
      Geo(Geo.line, [10, 0, 10, 10]),
      Geo(Geo.line, [10, 10, 0, 10]),
      Geo(Geo.line, [0, 10, 0, 0.0062]),
    ]);
    final gap = nearestProfileGap(s);
    expect(gap, isNotNull);
    expect(gap!.gap, closeTo(0.0062, 1e-9));
    // Either side of the miss is the same place to send the user; the finder
    // reports the first loose end it measures.
    expect(gap.at, anyOf(const Offset(0, 0), const Offset(0, 0.0062)),
        reason: 'the loose end, which is where the user must look');
  });

  test('an end that lands ON another curve is joined, not a gap', () {
    // A square split down the middle: both ends of the divider land on the
    // INTERIOR of an edge, which the arrangement splits there. Nothing is
    // loose, so there is nothing to report.
    final s = sketchOf([
      Geo(Geo.line, [0, 0, 10, 0]),
      Geo(Geo.line, [10, 0, 10, 10]),
      Geo(Geo.line, [10, 10, 0, 10]),
      Geo(Geo.line, [0, 10, 0, 0]),
      Geo(Geo.line, [5, 0, 5, 10]),
    ]);
    expect(nearestProfileGap(s), isNull);
  });

  test('the SMALLEST miss wins when a sketch has several', () {
    final s = sketchOf([
      Geo(Geo.line, [0, 0, 10, 0]),
      Geo(Geo.line, [10, 0.5, 10, 10]), // half a millimetre out
      Geo(Geo.line, [10, 10, 0, 10]),
      Geo(Geo.line, [0, 10, 0, 0.01]), // ten microns out
    ]);
    final gap = nearestProfileGap(s);
    expect(gap, isNotNull);
    expect(gap!.gap, closeTo(0.01, 1e-9));
  });
}
