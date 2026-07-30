// M159 — one refinement pass must not be able to blow the whole budget.
//
// Device log (build 684d35e), a coil:
//   perf: remesh n=1 lin=1.80e-2 tris=1002412 in 9952ms
//   perf: remesh n=2 lin=6.17e-3 tris=1968422 in 21457ms
//   perf: remesh n=1 lin=1.24e-2 tris=605610 in 56183ms
//
// The budget is 40 000. It is also REACTIVE: budgetedLinDeflection reads the
// triangles already in the scene, and the coil's first mesh is only 7 536, so
// there is plenty of headroom and the full target gets requested. OCCT then
// returns a million triangles from that one call. The budget refuses to go
// further afterwards, which is correct and far too late — the 56 seconds are
// spent and a million-triangle mesh is on screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

void main() {
  group('M159 — a bounded refinement step', () {
    test('the reported coil jump is refused', () {
      // Its first mesh is the coarse default; the view wants 1.8e-2.
      const current = kCoarseLinDeflection; // 0.6
      const want = 1.80e-2;
      final step = steppedLinDeflection(current, want);
      expect(step, greaterThan(want),
          reason: 'the full jump is what produced 1 002 412 triangles');
      expect(step, closeTo(current / kMaxRefineStep, 1e-12));
    });

    test('it still converges on the target, in passes', () {
      var lin = kCoarseLinDeflection;
      const want = 1.80e-2;
      var passes = 0;
      while (meshNeedsRefine(lin, want) && passes < 50) {
        lin = steppedLinDeflection(lin, want);
        passes++;
      }
      // It lands where meshNeedsRefine stops asking — its hysteresis refuses
      // a last few per cent, which is the point of having one.
      expect(lin / want, closeTo(1.0, 0.1),
          reason: 'the target is reached to within the refine hysteresis');
      expect(passes, lessThan(10), reason: 'and quickly: halving each time');
    });

    test('each pass is at most one halving, so cost per pass is bounded', () {
      var lin = 0.6;
      for (var i = 0; i < 6; i++) {
        final next = steppedLinDeflection(lin, 1e-6);
        expect(next / lin, closeTo(1 / kMaxRefineStep, 1e-12),
            reason: 'never more than one step, however far away the target');
        lin = next;
      }
    });

    test('a modest refinement is untouched', () {
      // Already within one step: pass the target straight through.
      expect(steppedLinDeflection(0.02, 0.015), 0.015);
      expect(steppedLinDeflection(0.02, 0.01), 0.01);
    });

    test('a COARSENING request is never tightened', () {
      expect(steppedLinDeflection(0.01, 0.5), 0.5);
      expect(steppedLinDeflection(0.01, double.infinity), double.infinity);
    });

    test('a solid with no mesh yet takes the target as given', () {
      expect(steppedLinDeflection(0, 0.01), 0.01);
      expect(steppedLinDeflection(double.nan, 0.01), 0.01);
      expect(steppedLinDeflection(double.infinity, 0.01), 0.01);
    });

    test('the budget still stops the climb between passes', () {
      // Once the scene is at budget the request becomes infinite, and the step
      // clamp must not resurrect it into something finite and finer.
      final target = budgetedLinDeflection(1e-3, kSceneTriangleBudget);
      expect(target, double.infinity);
      expect(steppedLinDeflection(0.02, target), double.infinity);
      expect(meshNeedsRefine(0.02, double.infinity), isFalse);
    });
  });
}
