// M68 — outlines must always look right, and sketching must never stutter.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

void main() {
  group('edge discretisation is independent of the face budget', () {
    test('coarsening the faces must not be able to coarsen the outlines', () {
      // The shim now clamps the EDGE deflection to 5e-3 / 0.05 rad regardless
      // of what the faces get. This test pins the intent at the Dart end: the
      // face target is allowed to go coarse (that is the budget doing its
      // job), and the outline quality must not be derived from it.
      final coarse = budgetedLinDeflection(0.01, kSceneTriangleBudget * 2);
      expect(coarse, double.infinity,
          reason: 'faces are allowed to stop refining');
      // kCoarseLinDeflection is the FACE fallback; edges are pinned finer in
      // the shim, so this constant must never be treated as an outline bound.
      expect(kCoarseLinDeflection, greaterThan(5e-3),
          reason: 'if this ever drops below the shim edge clamp, the comment '
              'in occt_capi.cpp about outlines being finer is wrong');
    });
  });

  group('scene budget still behaves', () {
    test('a fresh solid at the coarse default still gets one refinement', () {
      expect(meshNeedsRefine(kCoarseLinDeflection, 0.02), isTrue);
    });

    test('and stops once the budget is reached', () {
      expect(meshNeedsRefine(0.02, budgetedLinDeflection(0.001, 999999)),
          isFalse);
    });
  });
}
