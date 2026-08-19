// M232 — the memo in front of the DOF analysis, and the one way it can be
// wrong.
//
// `SketchAnalysisCache` reuses a previous `analyzeSketch` result when the
// inputs are value-for-value the ones behind it. That is sound because the
// analysis is a pure function of (geometry, constraints) — but only as far as
// the KEY is faithful. A field left out of the key is a stale answer: a sketch
// painted with the previous sketch's colouring, or one that refuses to drag a
// point that has become free. Nothing throws.
//
// So the first group below is not a performance test. It is the safety test,
// and it works by MUTATION: take a base sketch, change exactly one field, and
// require the key to notice. Every field of `Geo` and every field of
// `Constraint` is covered, including the ones that cannot affect the analysis
// — the key carries those deliberately, and a test that skipped them would
// invite someone to "tidy" them out later.
//
// OPTIMIZATION_PLAN §5 (S3) prediction P4 registers the other half in advance:
// the hit rate during a drag must be ZERO. A hit there would not be a win, it
// would be the proof that the key had missed something that moved. The last
// group asserts exactly that.
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

List<Geo> baseGeo() => [
      Geo(Geo.line, [0, 0, 50, 0]),
      Geo(Geo.circle, [10, 10, 4]),
    ];

List<Constraint> baseCons() => [
      Constraint(CType.fix,
          pts: [const PRef(0, 0)], anchors: [0.0, 0.0]),
      Constraint(CType.dimension,
          ents: [1], dimKind: 'rad', value: 4.0, paramName: 'd0'),
    ];

void main() {
  group('the key notices every field (this is the safety test)', () {
    final gs = baseGeo(), cs = baseCons();
    final base = analysisKey(gs, cs);

    void differs(String what, List<Geo> g2, List<Constraint> c2) {
      expect(analysisKey(g2, c2), isNot(base),
          reason: '$what left the key unchanged — the cache would serve a '
              'stale analysis for it');
    }

    test('Geo.type', () {
      differs('type', [Geo(Geo.arc, [0, 0, 50, 0]), gs[1]], cs);
    });
    test('Geo.data', () {
      differs('data', [Geo(Geo.line, [0, 0, 50, 0.5]), gs[1]], cs);
    });
    test('Geo.data, smallest representable step', () {
      // a drag moves points by far more than this, but the key must not be
      // rounding: doubles go in through toString, which round-trips exactly
      const eps = 5e-324; // the smallest subnormal
      differs('a one-ULP move', [Geo(Geo.line, [eps, 0, 50, 0]), gs[1]], cs);
    });
    test('Geo.layer', () {
      differs('layer', [gs[0].onLayer('other'), gs[1]], cs);
    });
    test('Geo.spline', () {
      differs('spline tag', [gs[0], gs[1].asSpline(Geo.splineCv)], cs);
    });
    test('Geo.style', () {
      differs('style', [gs[0].withStyle(Geo.styleConstruction), gs[1]], cs);
    });
    test('Geo.proj', () {
      differs('projection source', [gs[0].withProj(Geo.projSolid), gs[1]], cs);
    });
    test('Geo.projSeg', () {
      differs('projection segment',
          [gs[0].withProj(Geo.projSolid, 2), gs[1].withProj(Geo.projSolid, 3)],
          cs);
    });
    test('entity count', () {
      differs('an added entity', [...gs, Geo(Geo.circle, [0, 0, 1])], cs);
    });
    test('entity ORDER', () {
      // indices are what constraints refer to, so a swap is a different sketch
      differs('a reordering', [gs[1], gs[0]], cs);
    });

    test('Constraint.type', () {
      differs('constraint type',
          gs, [Constraint(CType.horizontal, ents: [0]), cs[1]]);
    });
    test('Constraint.pts', () {
      differs('point refs', gs, [cs[0].withPts([const PRef(0, 1)]), cs[1]]);
    });
    test('Constraint.ents', () {
      differs('entity refs', gs, [
        cs[0],
        Constraint(CType.dimension,
            ents: [0], dimKind: 'rad', value: 4.0, paramName: 'd0')
      ]);
    });
    test('Constraint.value', () {
      final c = baseCons();
      c[1].value = 4.5; // mutable, and edited in place by the dimension tool
      differs('a dimension value', gs, c);
    });
    test('Constraint.dimKind', () {
      differs('dimension kind', gs, [
        cs[0],
        Constraint(CType.dimension,
            ents: [1], dimKind: 'dia', value: 4.0, paramName: 'd0')
      ]);
    });
    test('Constraint.anchors', () {
      differs('fix anchors', gs, [
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [1.0, 0.0]),
        cs[1]
      ]);
    });
    test('Constraint.driven', () {
      final c = baseCons();
      c[1].driven = true; // a driven dimension measures, it does not drive
      differs('the driven flag', gs, c);
    });
    test('Constraint.tanBranch', () {
      final c = baseCons();
      c[1].tanBranch = 1.0; // captured on the first solve after creation
      differs('the tangency branch', gs, c);
    });
    test('Constraint.paramName', () {
      final c = baseCons();
      c[1].paramName = 'd7';
      differs('a parameter name', gs, c);
    });
    test('Constraint.expr', () {
      final c = baseCons();
      c[1].expr = 'd0*2';
      differs('an expression', gs, c);
    });
    test('Constraint.textPos', () {
      final c = baseCons();
      c[1].textPos = const Offset(3, 4);
      differs('a label position', gs, c);
    });
    test('constraint count', () {
      differs('an added constraint',
          gs, [...cs, Constraint(CType.horizontal, ents: [0])]);
    });

    test('an identical sketch built twice gives an identical key', () {
      expect(analysisKey(baseGeo(), baseCons()), base);
    });
  });

  group('the memo returns what the analysis returns', () {
    test('a hit is the same answer as a fresh computation', () {
      final c = SketchAnalysisCache();
      for (final n in [8, 16, 32]) {
        final gs = sketchFixture(n ~/ 2), cs = constraintFixture(n ~/ 2);
        final fresh = analyzeSketch(gs, cs);
        final first = c.of(gs, cs);
        final second = c.of(gs, cs);
        expect(identical(first, second), isTrue, reason: 'the second call '
            'should have been served from the memo');
        expect(second.dof, fresh.dof);
        expect(second.freePoints, fresh.freePoints);
        expect(second.looseCarriers, fresh.looseCarriers);
      }
    });

    test('four sketches fit; the fifth evicts the oldest', () {
      // Sizes from 2 up, deliberately: `_analyzeSketch` returns a CONST
      // SketchAnalysis for a fully constrained sketch, and const instances are
      // canonicalised — so `identical` is true between two independent
      // computations of dof = 0 and cannot tell a hit from a miss there.
      // constraintFixture grounds the ring with one fix and one dimension,
      // leaving dof = entities - 2, so every size below has dof > 0.
      final c = SketchAnalysisCache();
      final fx = [
        for (var i = 2; i <= 6; i++) (sketchFixture(i), constraintFixture(i))
      ];
      final first = [for (final f in fx) c.of(f.$1, f.$2)];
      // the four most recent are still there
      for (var i = 1; i < 5; i++) {
        expect(identical(c.of(fx[i].$1, fx[i].$2), first[i]), isTrue,
            reason: 'sketch $i should still be memoised');
      }
      // the oldest was evicted by the fifth
      expect(identical(c.of(fx[0].$1, fx[0].$2), first[0]), isFalse,
          reason: 'sketch 0 should have been evicted');
    });

    test('clear() empties it', () {
      final c = SketchAnalysisCache();
      final gs = baseGeo(), cs = baseCons();
      final a = c.of(gs, cs);
      c.clear();
      expect(identical(c.of(gs, cs), a), isFalse);
    });
  });

  group('P4: a drag must never hit', () {
    test('every frame of a moving point is a miss', () {
      // The registered prediction. If this ever passes with a hit, the memo is
      // unsound and must be removed, not celebrated.
      final c = SketchAnalysisCache();
      final cs = baseCons();
      SketchAnalysis? prev;
      for (var frame = 0; frame < 30; frame++) {
        final gs = [
          Geo(Geo.line, [0, 0, 50, frame * 0.01]),
          Geo(Geo.circle, [10, 10, 4]),
        ];
        final a = c.of(gs, cs);
        if (prev != null) {
          expect(identical(a, prev), isFalse,
              reason: 'frame $frame was served from the memo, but the '
                  'geometry had moved');
        }
        prev = a;
      }
    });

    test('editing a dimension in place is a miss', () {
      final c = SketchAnalysisCache();
      final gs = baseGeo(), cs = baseCons();
      final a = c.of(gs, cs);
      cs[1].value = 9.0; // the same List, the same Constraint object
      expect(identical(c.of(gs, cs), a), isFalse,
          reason: 'the constraint list is mutated in place — an identity '
              'check would have missed this, which is why the key is a value '
              'snapshot');
    });

    test('mutating the geometry list in place is a miss', () {
      final c = SketchAnalysisCache();
      final gs = baseGeo(), cs = baseCons();
      final a = c.of(gs, cs);
      gs[0] = gs[0].withData([0, 0, 50, 7]);
      expect(identical(c.of(gs, cs), a), isFalse);
    });
  });
}
