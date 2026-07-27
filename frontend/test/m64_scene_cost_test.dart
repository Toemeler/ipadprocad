// M64/M66 — the 3D scene must not get more expensive the longer you use it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

void main() {
  group('scene triangle budget', () {
    test('well under budget the screen-space target is untouched', () {
      expect(budgetedLinDeflection(0.01, 1000), 0.01);
      expect(budgetedLinDeflection(0.01, (kSceneTriangleBudget * 0.5).round()),
          0.01);
    });

    test('at or over budget refinement is refused outright', () {
      // M66: the M65 version scaled the target by sceneTris/budget, but that
      // ratio is ~1.0 exactly when the scene first crosses the line, so it
      // barely relaxed and the device still ran up to 78 976 triangles
      // (build 9ef0425 log). Now it is a hard stop.
      expect(budgetedLinDeflection(0.01, kSceneTriangleBudget),
          double.infinity);
      expect(budgetedLinDeflection(0.01, kSceneTriangleBudget * 3),
          double.infinity);
      expect(meshNeedsRefine(0.02, budgetedLinDeflection(0.01, 999999)),
          isFalse,
          reason: 'a refused target must not trigger a re-mesh');
    });

    test('the budget is tight enough to fire for a SINGLE gear', () {
      // one z=20 gear measured 50 548 triangles on device; the first guess of
      // 120 000 therefore never engaged at all
      expect(kSceneTriangleBudget, lessThan(50548));
    });

    test('the last stretch before the ceiling eases off', () {
      final near =
          budgetedLinDeflection(0.01, (kSceneTriangleBudget * 0.9).round());
      expect(near, greaterThan(0.01), reason: 'must only ever get COARSER');
      expect(near.isFinite, isTrue);
    });

    test('degenerate input is passed through unharmed', () {
      expect(budgetedLinDeflection(0.0, 999999), 0.0);
      expect(budgetedLinDeflection(0.01, 0), 0.01);
      expect(budgetedLinDeflection(0.01, 999999, budget: 0), 0.01);
    });
  });

  group('mesh logging cost', () {
    test('the heavy convention report is off by default', () {
      expect(meshDiagnostics, isFalse,
          reason: 'it measured ~50ms on a 34k-triangle gear, on the UI thread');
    });
  });
}
