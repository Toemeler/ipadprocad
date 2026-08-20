// M232 — the integrator's clause (c): a change must not accumulate under
// repetition. Pinned DIFFERENTIALLY against the dense original.
//
// CROSS-SESSION's S4-2 ruling narrows plan §1's "bit-identical" to a
// three-part test for any change that ALTERS a numerical result: (a) the
// residual is no worse, (b) the difference is inside the tolerance the code
// declares for that data path, (c) it does not accumulate under repetition.
//
// **S3 does not alter a numerical result**, so it sits in the ruling's first
// branch and never reaches (a), (b) or (c): the sparse elimination performs
// exactly the operations the dense form performed on nonzeros, in the same
// order, and skips only additions of exact zero — the identity in IEEE 754,
// both signed zeros included.
//
// That is the claim. This file tests it over a LONG sequence, because S3 is
// the change with the most to lose from drift that only shows up late:
// `freePoints` gates whether a point can be dragged at all, `looseCarriers`
// drives the colouring users read, and a divergence that appeared only after
// fifty edits would be invisible to every other test on this branch. It is
// the failure mode plan §9 warns about — "a change that looks obviously
// correct, that all the tests pass, and that quietly alters geometry on one
// part in fifty".
//
// **It used to compare against hardcoded goldens, which could not do that
// job.** A golden recorded on one machine pins that machine's digits, so it
// went red on CI (build 437) with the code working. Both paths now run in the
// same process on the same inputs and are compared to each other: N
// successive drags, each a real solve followed by a real analysis, with the
// final committed geometry, the final analysis and the final residual all
// required to match exactly.
//
// **What this file detects, measured by mutation rather than assumed.** A
// one-ULP error injected into the sparse elimination turns it red. The same
// error injected into the LM's normal equations does NOT — and that is a
// property of the LM, not an oversight: the fixture reaches `_lm` (40 calls
// per 20 steps, 26 724 executions of the mutated line), but the loop iterates
// to convergence, so a last-bit difference in JtJ is damped out before the
// step commits. That is evidence FOR clause (c) — differences here do not
// accumulate, they disappear — but it means LM sensitivity lives in
// `m232_lm_pin_test`, which does catch that mutation, and not here.
//
// Geometry is the strongest of the three — the residual is a function of the
// geometry and the constraints, so identical geometry implies an identical
// residual — but the residual is compared too, because the integrator's
// clause (a) is stated in terms of it and should be readable here without
// re-deriving it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

String geoDigits(List<Geo> gs) =>
    gs.map((g) => '${g.type}:${g.data.join(",")}').join(';');

String analysisDigits(SketchAnalysis a) {
  String pairs(Set<(int, int)> s) {
    final l = s.toList()
      ..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2);
    return l.map((p) => '${p.$1}.${p.$2}').join(',');
  }

  return 'dof=${a.dof} free=[${pairs(a.freePoints)}] '
      'loose=[${pairs(a.looseCarriers)}]';
}

/// One drag step: shove a point, solve honouring it, then analyse — the exact
/// order the app uses, and the order that matters, because the analysis reads
/// the geometry the solve just wrote.
///
/// [overConstrained] adds a second, conflicting `fix` to the point being
/// dragged. That makes libslvs reject its own result, which is what forces
/// `_solveConstraintsInner` down the **Dart LM fallback** — twice per step, as
/// PERFORMANCE_PROFILE §5.4 describes. Without it this sequence never executes
/// `_lm` at all, and a comparison of it says nothing about the LM's normal
/// equations. That was measured: a one-ULP error injected into them passed a
/// version of this file that only used the plain fixture.
({String geo, String trail, String analysis, String rref, double residual})
    dragPath(
    int steps, {
  bool overConstrained = false,
}) {
  final gs = sketchFixture(12);
  final cs = constraintFixture(12);
  if (overConstrained) {
    cs.add(Constraint(CType.fix,
        ents: [1], pts: [const PRef(1, 0)], anchors: [999.0, 999.0]));
  }
  SketchAnalysis? last;
  // EVERY step, not just the last. Comparing only the endpoint hides a
  // transient divergence, because a converging solve pulls both paths back to
  // the same attractor — measured: a one-ULP error in the LM's normal
  // equations passed an endpoint-only version of this test and fails this one.
  final trail = StringBuffer();
  for (var i = 0; i < steps; i++) {
    // a deterministic path: small, non-axis-aligned, never repeating a point
    final d = List<double>.of(gs[1].data);
    d[0] += 0.37;
    d[1] -= 0.21;
    gs[1] = gs[1].withData(d);
    solveConstraints(gs, cs, dragged: {(1, 0)}, iterations: 80);
    last = analyzeSketch(gs, cs);
    trail
      ..write(i)
      ..write('>')
      ..write(geoDigits(gs))
      ..write('\n');
  }
  return (
    geo: geoDigits(gs),
    trail: trail.toString(),
    analysis: analysisDigits(last!),
    // the un-quantised one: SketchAnalysis rounds through four thresholds, so
    // on its own it cannot see a sub-threshold difference
    rref: debugReducedSignature(gs, cs),
    residual: constraintResidualNorm(gs, cs),
  );
}

T _withDense<T>(T Function() body) {
  denseReferenceForTests = true;
  try {
    return body();
  } finally {
    denseReferenceForTests = false;
  }
}

void main() {
  tearDown(() => denseReferenceForTests = false);

  void compare(String label, int n, {bool overConstrained = false}) {
    final sparse = dragPath(n, overConstrained: overConstrained);
    final dense =
        _withDense(() => dragPath(n, overConstrained: overConstrained));
    expect(sparse.trail, dense.trail,
        reason: '$label: the two paths diverged at some point DURING the '
            'sequence even if they met again at the end — the endpoint is an '
            'attractor and hides exactly that');
    expect(sparse.rref, dense.rref,
        reason: '$label: the reduced matrix diverged over $n cycles — this is '
            'the un-quantised comparison and the one that catches a '
            'sub-threshold difference');
    expect(sparse.geo, dense.geo,
        reason: '$label: after $n drags the sparse path has committed '
            'different geometry from the dense original. Per the integrator '
            'that outweighs everything else on this branch — report it, do '
            'not loosen this assertion.');
    expect(sparse.analysis, dense.analysis,
        reason: '$label: the DOF analysis diverged over the sequence — '
            'dragging or the colouring would be wrong on a long editing '
            'session and on nothing shorter');
    expect(sparse.residual, dense.residual,
        reason: '$label: clause (a), measured at the end of the sequence');
  }

  group('clause (c): the two paths do not diverge over a long drag', () {
    test('100 cycles on the fast path agree exactly', () => compare('slvs', 100));

    test('100 cycles through the LM FALLBACK agree exactly', () {
      // The path §5.4 calls the worst case in the 2D pipeline, and the only
      // one that exercises the normal equations S3 rewrote.
      compare('lm', 100, overConstrained: true);
    });

    test('the gap does not grow with N — 10, 50 and 100, both paths', () {
      // A difference that accumulated would widen with N and so fail at the
      // longest N first; a constant offset fails at all three.
      for (final n in [10, 50, 100]) {
        compare('slvs', n);
        compare('lm', n, overConstrained: true);
      }
    });

    test('the residual is identical, not merely no worse', () {
      // Clause (a) asks for "no worse". S3 delivers something stronger, and
      // the distinction matters: "no worse" would also be satisfied by a path
      // that quietly moved the sketch somewhere else that happened to fit.
      final sparse = dragPath(50);
      final dense = _withDense(() => dragPath(50));
      expect(sparse.residual, dense.residual);
      expect(sparse.residual, lessThan(1e-6),
          reason: 'a sanity floor on the fixture: if this drifts up, the '
              'sequence is no longer exercising a converged system and the '
              'comparison above is measuring something else');
    });

    test('the sequence is reproducible in-process', () {
      // Guards the comparison itself: if dragPath were not deterministic,
      // every assertion above would be comparing noise to noise.
      final a = dragPath(25), b = dragPath(25);
      expect(a.geo, b.geo);
      expect(a.trail, b.trail);
      expect(a.rref, b.rref);
      expect(a.residual, b.residual);
    });
  });
}
