// M232 — the Levenberg–Marquardt fallback, pinned DIFFERENTIALLY against the
// dense original.
//
// A harsher pin than the DOF one, and it has to be. `analyzeSketch` reports;
// `_lm` MOVES GEOMETRY. A change that shifts a coordinate in the fifteenth
// decimal is not visible in any assertion about dof or colouring, but it is a
// different sketch, it is what the user's part is built on, and after eighty
// iterations of a damped least-squares loop a difference that small is not
// guaranteed to stay small — the λ schedule branches on `e2 < err`, so one
// flipped comparison takes the whole run down another path.
//
// **This file used to hold hardcoded goldens, and build 437 showed why that
// was wrong**: they were red on macOS arm64 + Flutter 3.47.1 with the code
// working perfectly, because a golden pins the machine that recorded it, not
// the equality of two code paths. Every case now runs the SAME solve twice in
// one process — once with `denseReferenceForTests`, once without — from
// identical starting geometry, and requires the committed parameter vector to
// match digit for digit.
//
// No tolerances. `expect` on the joined `toString` of every double is exact,
// and `toString` round-trips a double in Dart, so this compares bit patterns
// in readable form.
//
// The cases cover all three LM entry paths in `_solveConstraintsInner`:
//   * `lm`         — no drag, libslvs declined
//   * `lm-frozen`  — a drag the constraints CAN honour
//   * `lm-relaxed` — a drag they cannot, so the freeze is dropped and a second
//                    full run happens (the worst case in the 2D pipeline, per
//                    PERFORMANCE_PROFILE §5.4)
// and the unsatisfiable system the profile measures as
// `solve.overConstrained`.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

/// Every number in the sketch, exactly. `toString` round-trips a double in
/// Dart, so this is the bit pattern in readable form — not an approximation
/// of it.
String geoSig(List<Geo> gs) =>
    gs.map((g) => '${g.type}:${g.data.join(",")}').join(';');

/// A short, human-checkable digest for the golden table, plus the full string
/// behind it so a failure can be read rather than guessed at.
T _withDense<T>(T Function() body) {
  denseReferenceForTests = true;
  try {
    return body();
  } finally {
    denseReferenceForTests = false;
  }
}

/// Builds a fresh case, solves it, and returns everything observable: the
/// committed numbers and the boolean the caller uses to decide whether to keep
/// the configuration at all.
({String geo, bool ok}) run(
    (List<Geo>, List<Constraint>) Function() build,
    {Set<(int, int)> dragged = const {}}) {
  final (gs, cs) = build();
  final ok = solveConstraints(gs, cs, dragged: dragged, iterations: 80);
  return (geo: geoSig(gs), ok: ok);
}

void main() {
  tearDown(() => denseReferenceForTests = false);

  group('sparse and dense LM land on the same numbers (M232 differential pin)',
      () {
    void differential(
      String name,
      (List<Geo>, List<Constraint>) Function() build, {
      Set<(int, int)> dragged = const {},
    }) {
      test(name, () {
        final sparse = run(build, dragged: dragged);
        final dense = _withDense(() => run(build, dragged: dragged));
        expect(sparse.ok, dense.ok,
            reason: 'the two paths disagree about whether the solve SUCCEEDED '
                'for "$name" — that decides whether the caller keeps the '
                'configuration, so it matters as much as the numbers');
        expect(sparse.geo, dense.geo,
            reason: 'the row-major normal equations moved the geometry away '
                'from where the pair form put it, for "$name". Per the '
                'integrator, a real difference here outweighs everything else '
                'on this branch — report it, do not tune it away.');
      });
    }

    // The profile's own over-constrained fixture: two conflicting fixes on one
    // point, 168 parameters, 124 residuals — the LOSING path, which §5.4
    // measures at 66.4 ms against a 0.271 ms fast-path solve.
    differential('solve.overConstrained — unsatisfiable, both LM passes', () {
      final gs = sketchFixture(24);
      final cs = constraintFixture(24)
        ..add(Constraint(CType.fix,
            ents: [1], pts: [const PRef(1, 0)], anchors: [999.0, 999.0]));
      return (gs, cs);
    });

    differential('an unsatisfied but SOLVABLE system', () {
      // Perturbed away from its solution so the LM actually has work to do.
      final gs = sketchFixture(12);
      for (var i = 0; i < gs.length; i++) {
        final d = List<double>.of(gs[i].data);
        d[0] += 3.5;
        d[1] -= 2.25;
        gs[i] = gs[i].withData(d);
      }
      return (gs, constraintFixture(12));
    });

    differential('a drag the constraints CAN honour (lm-frozen)',
        () => (sketchFixture(8), constraintFixture(8)),
        dragged: {(0, 0)});

    differential('a drag the constraints CANNOT honour (lm-relaxed)', () {
      // The dragged point is pinned by a `fix` too, so freezing it makes the
      // system unsatisfiable and the second, relaxed run must happen.
      final gs = sketchFixture(8);
      final d = List<double>.of(gs[0].data);
      d[0] += 40; // haul the fixed circle's centre far off its anchor
      d[1] += 40;
      gs[0] = gs[0].withData(d);
      return (gs, constraintFixture(8));
    }, dragged: {(0, 0)});

    differential('a tangency (branch capture on the LM path)', () {
      return (
        [
          Geo(Geo.circle, [0, 0, 10]),
          Geo(Geo.line, [-30, 12, 30, 11]),
        ],
        [
          Constraint(CType.tangent, ents: [0, 1]),
          Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0.0, 0.0]),
          Constraint(CType.dimension, ents: [0], dimKind: 'rad', value: 10.0),
        ]
      );
    });

    test('rank/redundancy reporting agrees (debugRank)', () {
      // debugRank shares the Jacobian builder with the analysis and is the
      // ground truth other tests assert redundancy against. Integers, so this
      // one WAS platform-stable and passed on CI — kept, and made differential
      // like the rest so it says something about the change rather than about
      // the machine.
      final sparse = debugRank(sketchFixture(12), constraintFixture(12));
      final dense =
          _withDense(() => debugRank(sketchFixture(12), constraintFixture(12)));
      expect('${sparse.$1}/${sparse.$2}/${sparse.$3}',
          '${dense.$1}/${dense.$2}/${dense.$3}');
      expect(sparse.$1, 62, reason: 'a semantic check that does not depend on '
          'the machine: 12 circles + 12 lines, fully ranked at 62');
    });
  });
}
