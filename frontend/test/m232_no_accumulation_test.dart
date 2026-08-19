// M232 — the integrator's clause (c): a change must not accumulate under
// repetition.
//
// CROSS-SESSION, "2026-08-19 — INTEGRATOR — ruling on S4-2", narrows plan §1's
// "bit-identical" to a three-part test for any change that ALTERS a numerical
// result: (a) the residual is no worse, (b) the difference is inside the
// tolerance the code declares for that data path, (c) it does not accumulate
// under repetition. Each proven by test.
//
// **S3 does not alter a numerical result.** The sparse elimination performs
// exactly the operations the dense form performed on nonzeros, in the same
// order, and skips only additions of exact zero — which are the identity in
// IEEE 754. So S3 sits in the ruling's first branch, "bit-identical wherever
// the prior behaviour was well-defined", and (a)/(b)/(c) formally do not
// apply to it.
//
// This file exists anyway, for two reasons.
//
// First, "formally does not apply" is an argument, and the integrator asked
// for tests. A single-call golden (m232_analyze_pin_test, m232_lm_pin_test)
// proves one call is identical; determinism then proves any SEQUENCE of calls
// is identical. That is a proof rather than a test, and proofs about floating
// point are exactly the kind that turn out to have an unconsidered case.
//
// Second, S3 is the change with the most to lose from drift. The DOF analysis
// gates whether dragging works at all (`freePoints`) and drives the colouring
// users read to know whether a sketch is finished. A drift that appeared only
// after fifty drags would be invisible to every other test here.
//
// So: N successive drags along a path, each one a real solve followed by a
// real analysis, with the FINAL committed geometry pinned digit for digit and
// the final residual pinned beside it. Geometry is the stronger of the two —
// the residual is a function of the geometry and the constraints, so
// bit-identical geometry implies a bit-identical residual — but both are
// recorded because the integrator's clause (a) is stated in terms of the
// residual and it should be readable without re-deriving it.
//
// The goldens were recorded by running this file against `solver.dart` as it
// stands on `claude/perf-opt` (commit 2921d3f) — the dense implementation,
// before any S3 change.
import 'package:flutter_test/flutter_test.dart';
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
({String geo, String analysis, double residual}) dragPath(int steps) {
  final gs = sketchFixture(12);
  final cs = constraintFixture(12);
  SketchAnalysis? last;
  for (var i = 0; i < steps; i++) {
    // a deterministic path: small, non-axis-aligned, never repeating a point
    final d = List<double>.of(gs[1].data);
    d[0] += 0.37;
    d[1] -= 0.21;
    gs[1] = gs[1].withData(d);
    solveConstraints(gs, cs, dragged: {(1, 0)}, iterations: 80);
    last = analyzeSketch(gs, cs);
  }
  return (
    geo: geoDigits(gs),
    analysis: analysisDigits(last!),
    residual: constraintResidualNorm(gs, cs),
  );
}

void main() {
  group('clause (c): nothing accumulates over a long drag', () {
    test('100 successive drag+analyse cycles land digit for digit', () {
      final r = dragPath(100);
      expect(r.geo, _gold100Geo,
          reason: 'after 100 drags the committed geometry differs from what '
              'the dense implementation produced — that is drift, and it is '
              'exactly what clause (c) exists to catch');
      expect(r.analysis, _gold100Analysis,
          reason: 'the DOF analysis diverged over the sequence: dragging or '
              'the colouring would be wrong on a long editing session and on '
              'nothing shorter');
      expect(r.residual.toString(), _gold100Residual,
          reason: 'clause (a), measured at the end of the sequence');
    });

    test('the gap does not grow with N — 10, 50 and 100 all land exactly', () {
      // If a difference existed and accumulated, it would show as a gap that
      // widens with N. Pinning three lengths against the dense implementation
      // makes a growing gap fail at the longest N first, and a constant
      // offset fail at all three.
      expect(dragPath(10).geo, _gold10Geo);
      expect(dragPath(50).geo, _gold50Geo);
      // 100 is covered above; asserted here too so one test carries the shape
      expect(dragPath(100).geo, _gold100Geo);
    });

    test('the sequence is reproducible in-process', () {
      // Guards the goldens themselves: if `dragPath` were not deterministic,
      // the pins above would be measuring noise and would eventually flake.
      final a = dragPath(25), b = dragPath(25);
      expect(a.geo, b.geo);
      expect(a.analysis, b.analysis);
      expect(a.residual, b.residual);
    });
  });
}

// Recorded against claude/perf-opt @ 2921d3f — the DENSE implementation.
const _gold10Geo = r'2:60.0,0.0,4.0;2:55.661524227066295,27.899999999999988,4.0;2:30.000000000000007,51.96152422706631,4.0;2:3.67394039744206e-15,60.0,4.0;2:-29.999999999999986,51.96152422706632,4.0;2:-51.96152422706632,29.999999999999996,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-51.96152422706633,-29.999999999999982,4.0;2:-30.00000000000003,-51.961524227066306,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:30.000000000000007,-51.96152422706631,4.0;2:51.961524227066306,-30.00000000000003,4.0;1:60.0,0.0,55.66152422687745,27.900000000107173;1:55.66152422687745,27.900000000107173,30.000000000000007,51.96152422706631;1:30.000000000000007,51.96152422706631,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-29.999999999999986,51.96152422706632;1:-29.999999999999986,51.96152422706632,-51.96152422706632,29.999999999999996;1:-51.96152422706632,29.999999999999996,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-51.96152422706633,-29.999999999999982;1:-51.96152422706633,-29.999999999999982,-30.00000000000003,-51.961524227066306;1:-30.00000000000003,-51.961524227066306,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,30.000000000000007,-51.96152422706631;1:30.000000000000007,-51.96152422706631,51.961524227066306,-30.00000000000003;1:51.961524227066306,-30.00000000000003,60.0,0.0';
const _gold50Geo = r'2:60.0,0.0,4.0;2:70.46152422706632,19.499999999999954,4.0;2:30.000000000000007,51.96152422706631,4.0;2:3.67394039744206e-15,60.0,4.0;2:-29.999999999999986,51.96152422706632,4.0;2:-51.96152422706632,29.999999999999996,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-51.96152422706633,-29.999999999999982,4.0;2:-30.00000000000003,-51.961524227066306,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:30.000000000000007,-51.96152422706631,4.0;2:51.961524227066306,-30.00000000000003,4.0;1:60.0,0.0,70.46152422687747,19.50000000010714;1:70.46152422687747,19.50000000010714,30.000000000000007,51.96152422706631;1:30.000000000000007,51.96152422706631,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-29.999999999999986,51.96152422706632;1:-29.999999999999986,51.96152422706632,-51.96152422706632,29.999999999999996;1:-51.96152422706632,29.999999999999996,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-51.96152422706633,-29.999999999999982;1:-51.96152422706633,-29.999999999999982,-30.00000000000003,-51.961524227066306;1:-30.00000000000003,-51.961524227066306,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,30.000000000000007,-51.96152422706631;1:30.000000000000007,-51.96152422706631,51.961524227066306,-30.00000000000003;1:51.961524227066306,-30.00000000000003,60.0,0.0';
const _gold100Geo = r'2:60.0,0.0,4.0;2:88.96152422706655,8.999999999999911,4.0;2:30.000000000000007,51.96152422706631,4.0;2:3.67394039744206e-15,60.0,4.0;2:-29.999999999999986,51.96152422706632,4.0;2:-51.96152422706632,29.999999999999996,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-51.96152422706633,-29.999999999999982,4.0;2:-30.00000000000003,-51.961524227066306,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:30.000000000000007,-51.96152422706631,4.0;2:51.961524227066306,-30.00000000000003,4.0;1:60.0,0.0,88.9615242268777,9.000000000107097;1:88.9615242268777,9.000000000107097,30.000000000000007,51.96152422706631;1:30.000000000000007,51.96152422706631,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-29.999999999999986,51.96152422706632;1:-29.999999999999986,51.96152422706632,-51.96152422706632,29.999999999999996;1:-51.96152422706632,29.999999999999996,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-51.96152422706633,-29.999999999999982;1:-51.96152422706633,-29.999999999999982,-30.00000000000003,-51.961524227066306;1:-30.00000000000003,-51.961524227066306,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,30.000000000000007,-51.96152422706631;1:30.000000000000007,-51.96152422706631,51.961524227066306,-30.00000000000003;1:51.961524227066306,-30.00000000000003,60.0,0.0';
const _gold100Analysis = r'dof=22 free=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.1,13.0,13.1,14.0,14.1,15.0,15.1,16.0,16.1,17.0,17.1,18.0,18.1,19.0,19.1,20.0,20.1,21.0,21.1,22.0,22.1,23.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0]';
const _gold100Residual = r'3.070905054045597e-10';
