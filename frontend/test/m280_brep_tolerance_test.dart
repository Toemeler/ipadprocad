// M280 — the tolerance that filled in the cut-outs.
//
// "It doesn't work correctly. The holes aren't there."
//
// The 3MF read fine after M278 and the converter produced a body — a SOLID
// bookmark, with every decorative line present as an edge and not one of its
// 37 cut-outs open.
//
// The mesh is not at fault, and that was worth establishing before touching
// anything: its Euler characteristic is -72, so its genus is 37 and the holes
// are demonstrably in the file. Measured from it:
//
//   bounding box     106.9 x 127.4 x 2.0 mm,  diagonal 166.3
//   default tolerance   0.002 * 166.3                 = 0.333 mm
//   the part's thickness                                2.0 mm
//   its NARROWEST slit                                  0.756 mm
//
// A surface-fit tolerance of a third of a millimetre is a sixth of everything
// that part is made of and nearly half the width of its thinnest opening. The
// diagonal says how BIG a model is and nothing about how FINE it is, and on a
// plate the two are unrelated — the diagonal grows with the sheet while the
// features stay the size of the features.
//
// So the tolerance is bounded by the model's own thinnest dimension too. These
// tests pin the rule and, as much as it matters, its DIRECTION: it may only
// ever lower the tolerance, because a rule that could raise one would blur
// features on a model that was converting perfectly well.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/mesh_io.dart';

/// A soup whose bounding box is exactly [dx] x [dy] x [dz]. One triangle is
/// enough: only the bounds are read.
MeshSoup _box(double dx, double dy, double dz) => MeshSoup(
      vertices: Float64List.fromList([0, 0, 0, dx, dy, 0, dx, dy, dz]),
      triangles: Int32List.fromList([0, 1, 2]),
      format: 'stl',
    );

double _diag(double dx, double dy, double dz) =>
    math.sqrt(dx * dx + dy * dy + dz * dz);

/// The tolerance in MILLIMETRES, which is the number the reasoning is about.
double _tolMm(MeshSoup s) {
  final b = s.bounds!;
  return brepTolFractionFor(s) *
      _diag(b[3] - b[0], b[4] - b[1], b[5] - b[2]);
}

void main() {
  group('the reported bookmark', () {
    // 106.86 x 127.40 x 2.00, the file's own bounding box.
    final s = _box(106.86, 127.40, 2.00);

    test('the old default was a third of a millimetre', () {
      final b = s.bounds!;
      final diag = _diag(b[3] - b[0], b[4] - b[1], b[5] - b[2]);
      expect(kBrepTolFractionDefault * diag, closeTo(0.333, 0.005));
    });

    test('the new one is a tenth, and fits inside the narrowest slit', () {
      // The narrowest slit in that file is 0.756 mm. A tolerance has to be a
      // small part of the thing it must not blur away, not half of it.
      expect(_tolMm(s), closeTo(0.100, 1e-9));
      expect(_tolMm(s), lessThan(0.756 / 5));
    });
  });

  group('the rule', () {
    test('it never RAISES the tolerance', () {
      // The direction that matters. A rule that could raise one would blur
      // features on a model that was converting perfectly well, which is a
      // regression traded for a fix.
      for (final (dx, dy, dz) in [
        (200.0, 150.0, 100.0), // a chunky bracket
        (4.0, 4.0, 20.0), // a pin
        (106.9, 127.4, 2.0), // the bookmark
        (1000.0, 1000.0, 1000.0),
        (0.5, 0.5, 0.5),
      ]) {
        final s = _box(dx, dy, dz);
        expect(brepTolFractionFor(s),
            lessThanOrEqualTo(kBrepTolFractionDefault + 1e-15),
            reason: '$dx x $dy x $dz');
      }
    });

    test('a chunky part is left exactly as it was', () {
      // The clamp must bite only on plate-like models — the class that was
      // failing — or it is a change to every import instead of a fix to one.
      final s = _box(200, 150, 100);
      expect(brepTolFractionFor(s), kBrepTolFractionDefault);
    });

    test('a thin plate is clamped by its THICKNESS, not by its diagonal', () {
      // The same plate on a bigger sheet: the diagonal doubles, the features
      // do not, and the tolerance must not follow the diagonal.
      final small = _box(50, 50, 2);
      final large = _box(400, 400, 2);
      expect(_tolMm(small), closeTo(_tolMm(large), 1e-12));
      expect(_tolMm(small), closeTo(kBrepTolThinFraction * 2.0, 1e-12));
    });

    test('a surface with no thickness keeps the built-in default', () {
      // Zero is "leave it alone". A flat mesh has no thinnest feature to
      // protect, the converter will not close it into a solid anyway, and
      // clamping against a zero would drive the tolerance to nothing.
      expect(brepTolFractionFor(_box(100, 100, 0)), 0);
    });

    test('an empty mesh answers 0 rather than a NaN', () {
      final empty = MeshSoup(
          vertices: Float64List(0),
          triangles: Int32List(0),
          format: 'stl');
      expect(brepTolFractionFor(empty), 0);
    });

    test('a very thin sheet is floored, not driven to zero', () {
      // Below the floor the fit chases the mesh's own round-off and no two
      // surfaces agree with each other any more. Foil is a real thing to
      // import; a tolerance of 1e-9 mm is not a real thing to fit at.
      final foil = _box(300, 300, 0.0001);
      expect(brepTolFractionFor(foil), kBrepTolFractionFloor);
    });
  });
}
