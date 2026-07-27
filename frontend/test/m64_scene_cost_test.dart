// M64 — the 3D scene must not get more expensive the longer you use it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

void main() {
  group('scene triangle budget', () {
    test('under budget the screen-space target is untouched', () {
      expect(budgetedLinDeflection(0.01, 1000), 0.01);
      expect(budgetedLinDeflection(0.01, kSceneTriangleBudget), 0.01);
    });

    test('over budget the target is relaxed proportionally', () {
      final t = budgetedLinDeflection(0.01, kSceneTriangleBudget * 3);
      expect(t, closeTo(0.03, 1e-12));
      expect(t, greaterThan(0.01), reason: 'must only ever get COARSER');
    });

    test('relaxing stops the ratchet: the pair refuses to refine further', () {
      // a mesh already built at the relaxed target must not ask for more
      const current = 0.03;
      final target = budgetedLinDeflection(0.01, kSceneTriangleBudget * 3);
      expect(meshNeedsRefine(current, target), isFalse,
          reason: 'budget + refine-only-finer must settle, not oscillate');
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
