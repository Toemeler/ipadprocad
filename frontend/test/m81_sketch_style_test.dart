// M81 — a sketch must read the same in 3D as it does in 2D.
//
// Before this, the 3D view painted every sketch curve one flat colour and
// showed construction geometry that the 2D editor hides, so the same sketch
// looked like two different sketches depending on which viewport you were in.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/reality_scene.dart';

void main() {
  group('sketch curve colour matches Viewport2D', () {
    // The four tones the 2D painter uses.
    const white = 0xFFFFFFFF;
    const violet = 0xFF9A8CF5;
    const yellow = 0xFFE8C84A;

    test('a projection is yellow, editing or not', () {
      expect(
          sketchGeoColor(
              projection: true, editing: true, fullyConstrained: true),
          yellow);
      expect(
          sketchGeoColor(
              projection: true, editing: false, fullyConstrained: false),
          yellow);
    });

    test('under-constrained geometry is blue-violet WHILE editing', () {
      expect(
          sketchGeoColor(
              projection: false, editing: true, fullyConstrained: false),
          violet);
    });

    test('fully constrained geometry is white while editing', () {
      expect(
          sketchGeoColor(
              projection: false, editing: true, fullyConstrained: true),
          white);
    });

    test('outside the edited sketch everything is plain white', () {
      // DOF is an editing signal. Showing it on a sketch you are not editing
      // would be noise you cannot act on, so 2D does not, and neither does 3D.
      expect(
          sketchGeoColor(
              projection: false, editing: false, fullyConstrained: false),
          white);
      expect(
          sketchGeoColor(
              projection: false, editing: false, fullyConstrained: true),
          white);
    });

    test('projection wins over constraint state', () {
      expect(
          sketchGeoColor(
              projection: true, editing: true, fullyConstrained: false),
          isNot(violet));
    });
  });
}
