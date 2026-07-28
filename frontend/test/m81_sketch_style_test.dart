// M81/M88 — a sketch must read the same in 3D as it does in 2D.
//
// The 2D rule, from viewport.dart, is the specification:
//   segFull(i, 0) => hasAnalysis && analysis.carrierFixed(i, 0)
//   paint         = isProjection ? yellow : (segFull ? white : violet)
// Note what that means with NO analysis: segFull is false, so the curve is
// VIOLET. M81 defaulted to white instead, which is exactly why curves came
// out white in 3D while 2D showed them violet.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/reality_scene.dart';

void main() {
  const white = 0xFFFFFFFF;
  const violet = 0xFF9A8CF5;
  const yellow = 0xFFE8C84A;

  group('sketch curve colour matches Viewport2D', () {
    test('a projection is yellow whatever its constraint state', () {
      expect(
          sketchGeoColor(
              projection: true, dofKnown: true, fullyConstrained: true),
          yellow);
      expect(
          sketchGeoColor(
              projection: true, dofKnown: false, fullyConstrained: false),
          yellow);
    });

    test('fully constrained is white', () {
      expect(
          sketchGeoColor(
              projection: false, dofKnown: true, fullyConstrained: true),
          white);
    });

    test('under-constrained is blue-violet', () {
      expect(
          sketchGeoColor(
              projection: false, dofKnown: true, fullyConstrained: false),
          violet);
    });

    test('NO analysis means violet, not white — this was the bug', () {
      // Matches `hasAnalysis && ...` being false in 2D. Defaulting to white
      // made curves flip colour between the two viewports, most visibly right
      // after an edit, before the next _reanalyze() had run.
      expect(
          sketchGeoColor(
              projection: false, dofKnown: false, fullyConstrained: false),
          violet);
      expect(
          sketchGeoColor(
              projection: false, dofKnown: false, fullyConstrained: true),
          violet,
          reason: 'without analysis the constrained flag carries no meaning');
    });
  });
}
