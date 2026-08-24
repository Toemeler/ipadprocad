// M232 — the DOF analysis, pinned DIFFERENTIALLY against the dense original.
//
// `analyzeSketch` returns three things and the UI reads every one of them:
//   * `dof`           — the gauge, the browser text, "fully constrained"
//   * `freePoints`    — gates dragging (a point not in here will not move)
//   * `looseCarriers` — the violet/white colouring of every entity
//
// OPTIMIZATION_PLAN §5 (Session 3) asks for all three to be pinned before the
// algorithm underneath them moves, because a rank computed differently is a
// sketch that looks wrong or refuses to drag — and neither failure throws.
//
// **This file used to hold hardcoded golden strings and that was the wrong
// instrument.** A golden recorded on one machine pins "this machine produced
// these digits". The claim being made is "the sparse path returns what the
// dense path returned", and no golden can test that: it retains no dense
// implementation to compare against. Build 437 proved the point the
// embarrassing way — the goldens went red on macOS arm64 + Flutter 3.47.1
// while the code was fine, because they were measuring the runtime.
//
// So every case below now runs through BOTH implementations, on the same
// machine, in the same process, on the same inputs, and requires the results
// to be equal. `denseReferenceForTests` selects the frozen copy of
// `_analyzeSketch` as it stood at `2921d3f` (see the end of `solver.dart`).
//
// Nothing here is a tolerance. `expect(a, b)` on the canonical string is exact
// equality, and that is deliberate: bit-identity is the strongest claim on
// this branch and the reason S3 never has to argue clauses (a)/(b)/(c) of the
// integrator's rule. Weakening it to `closeTo` to get a green build would
// trade that claim away and hide the divergence the test exists to find.
//
// The cases reach every branch the analysis has:
//   - every CType that contributes residuals
//   - each carrier kind (line, circle, arc, plain polyline per edge, spline)
//   - projections, which enter through _withProjectionPins and not through cs
//   - the rank edge cases: no constraints, over-constrained, degenerate, empty
//   - the perf ladder's own fixture at five sizes, which is the system
//     PERFORMANCE_PROFILE §5.5 measured
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);
Geo circle(double cx, double cy, double r) => Geo(Geo.circle, [cx, cy, r]);
Geo arc(double cx, double cy, double r, double a0, double a1) =>
    Geo(Geo.arc, [cx, cy, r, a0, a1]);
Geo rect(double x, double y, double w, double h) => Geo(Geo.polyline, [
      1, 4, // closed, 4 vertices
      x, y, x + w, y, x + w, y + h, x, y + h,
    ]);
Geo open3(double x, double y) => Geo(Geo.polyline, [
      0, 3, // open, 3 vertices
      x, y, x + 10, y + 4, x + 20, y - 3,
    ]);

Constraint fixPt(int ent, int pt, double x, double y) =>
    Constraint(CType.fix, pts: [PRef(ent, pt)], anchors: [x, y]);
Constraint coin(int e1, int p1, int e2, int p2) =>
    Constraint(CType.coincident, pts: [PRef(e1, p1), PRef(e2, p2)]);

/// Everything `SketchAnalysis` exposes, flattened and ordered, so that one
/// string equality covers dof, the movable set and the carrier set at once.
String sig(SketchAnalysis a) {
  String pairs(Set<(int, int)> s) {
    final l = s.toList()
      ..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2);
    return l.map((p) => '${p.$1}.${p.$2}').join(',');
  }

  return 'dof=${a.dof} free=[${pairs(a.freePoints)}] '
      'loose=[${pairs(a.looseCarriers)}]';
}

/// The cases. Kept as builders so the golden table below reads as a list of
/// (name, expected) with nothing computed in it.
final cases = <String, (List<Geo>, List<Constraint>)>{
  'empty': (<Geo>[], <Constraint>[]),

  'single line, no constraints': ([line(0, 0, 50, 0)], <Constraint>[]),

  'line: fixed start + horizontal (free length)': (
    [line(0, 0, 50, 0)],
    [fixPt(0, 0, 0, 0), Constraint(CType.horizontal, ents: [0])],
  ),

  'line: length dimension only': (
    [line(0, 0, 50, 0)],
    [
      Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 50)
    ],
  ),

  'line fully ground': (
    [line(0, 0, 50, 0)],
    [fixPt(0, 0, 0, 0), fixPt(0, 1, 50, 0)],
  ),

  'two lines: parallel': (
    [line(0, 0, 50, 0), line(0, 10, 50, 12)],
    [Constraint(CType.parallel, ents: [0, 1])],
  ),

  'two lines: perpendicular + coincident corner': (
    [line(0, 0, 50, 0), line(50, 0, 50, 40)],
    [Constraint(CType.perpendicular, ents: [0, 1]), coin(0, 1, 1, 0)],
  ),

  'two lines: collinear': (
    [line(0, 0, 50, 0), line(60, 1, 90, 2)],
    [Constraint(CType.collinear, ents: [0, 1])],
  ),

  'two lines: vertical + equal': (
    [line(0, 0, 0, 50), line(20, 0, 21, 30)],
    [Constraint(CType.vertical, ents: [0]), Constraint(CType.equal, ents: [0, 1])],
  ),

  'symmetric about a line': (
    [line(0, -50, 0, 50), circle(-20, 0, 5), circle(22, 1, 5)],
    [
      Constraint(CType.symmetric,
          ents: [0], pts: [const PRef(1, 0), const PRef(2, 0)])
    ],
  ),

  'midpoint': (
    [line(0, 0, 60, 0), circle(31, 0, 3)],
    [
      Constraint(CType.midpoint, ents: [0], pts: [const PRef(1, 0)]),
      fixPt(0, 0, 0, 0),
      fixPt(0, 1, 60, 0),
    ],
  ),

  'two circles: concentric + equal': (
    [circle(0, 0, 10), circle(1, 1, 4)],
    [
      Constraint(CType.concentric, ents: [0, 1]),
      Constraint(CType.equal, ents: [0, 1]),
    ],
  ),

  'circle: radius dimension + fixed centre': (
    [circle(0, 0, 10)],
    [
      fixPt(0, 0, 0, 0),
      Constraint(CType.dimension, ents: [0], dimKind: 'rad', value: 10),
    ],
  ),

  'line tangent to circle': (
    [circle(0, 0, 10), line(-30, 10, 30, 10)],
    [Constraint(CType.tangent, ents: [0, 1])],
  ),

  'arc + line smooth (G1)': (
    [arc(0, 0, 10, 0, 1.5707963267948966), line(0, 10, -40, 10)],
    [
      coin(0, 2, 1, 0),
      Constraint(CType.smooth, ents: [0, 1]),
    ],
  ),

  'arc alone': ([arc(0, 0, 10, 0, 2.0)], <Constraint>[]),

  'rectangle, unconstrained (per-edge carriers)': (
    [rect(0, 0, 40, 30)],
    <Constraint>[],
  ),

  'rectangle, one corner ground + two directions': (
    [rect(0, 0, 40, 30)],
    [
      fixPt(0, 0, 0, 0),
      Constraint(CType.horizontal, pts: [const PRef(0, 0), const PRef(0, 1)]),
      Constraint(CType.vertical, pts: [const PRef(0, 1), const PRef(0, 2)]),
    ],
  ),

  'open polyline': ([open3(0, 0)], <Constraint>[]),

  'spline-tagged polyline': (
    [open3(0, 0).asSpline(Geo.splineCv)],
    <Constraint>[],
  ),

  'point on circle (coincident, one pt)': (
    [circle(0, 0, 10), circle(10, 0, 0.5)],
    [
      Constraint(CType.coincident, ents: [0], pts: [const PRef(1, 0)]),
    ],
  ),

  'point on polyline carrier': (
    [rect(0, 0, 40, 30), circle(20, 0, 0.5)],
    [
      Constraint(CType.coincident, ents: [0], pts: [const PRef(1, 0)]),
    ],
  ),

  'projection: a projected line pins itself': (
    [line(0, 0, 50, 0), line(0, 20, 50, 20).withProj(Geo.projSolid)],
    <Constraint>[],
  ),

  'projection: a projected circle pins its radius too': (
    [circle(0, 0, 10).withProj(Geo.projSolid)],
    <Constraint>[],
  ),

  'pattern constraint (rect copy)': (
    [line(0, 0, 10, 0), line(20, 0, 30, 0)],
    [
      Constraint(CType.pattern, ents: [0, 1], anchors: [0, 20, 0]),
      fixPt(0, 0, 0, 0),
      fixPt(0, 1, 10, 0),
    ],
  ),

  'over-constrained: two identical fixes': (
    [line(0, 0, 50, 0)],
    [fixPt(0, 0, 0, 0), fixPt(0, 0, 0, 0), fixPt(0, 1, 50, 0)],
  ),

  'redundant horizontals on one line': (
    [line(0, 0, 50, 0)],
    [
      Constraint(CType.horizontal, ents: [0]),
      Constraint(CType.horizontal, ents: [0]),
      fixPt(0, 0, 0, 0),
    ],
  ),

  'degenerate: zero-length line': (
    [line(10, 10, 10, 10)],
    [fixPt(0, 0, 10, 10)],
  ),

  'degenerate: zero-radius circle': ([circle(0, 0, 0)], <Constraint>[]),

  'mixed sketch, partially constrained': (
    [
      line(0, 0, 40, 0),
      line(40, 0, 40, 30),
      circle(20, 15, 6),
      arc(0, 30, 8, 0, 1.2),
      rect(60, 0, 20, 20),
    ],
    [
      fixPt(0, 0, 0, 0),
      Constraint(CType.horizontal, ents: [0]),
      coin(0, 1, 1, 0),
      Constraint(CType.perpendicular, ents: [0, 1]),
      Constraint(CType.dimension, ents: [2], dimKind: 'rad', value: 6),
      Constraint(CType.equal, ents: [2, 3]),
    ],
  ),

  // The system PERFORMANCE_PROFILE §5.5 actually measured, at the bottom of
  // its ladder. These are the cases that would catch a rank change on a large
  // COUPLED system, which the small cases above cannot.
  'perf fixture n=8': (sketchFixture(4), constraintFixture(4)),
  'perf fixture n=16': (sketchFixture(8), constraintFixture(8)),
  'perf fixture n=32': (sketchFixture(16), constraintFixture(16)),
  'perf fixture n=64': (sketchFixture(32), constraintFixture(32)),
  'perf fixture n=128': (sketchFixture(64), constraintFixture(64)),
};

/// Runs [body] with the frozen dense reduction selected, and restores the
/// flag whatever happens — a leaked `true` would silently put every later
/// test in this process on the slow path and quietly stop testing anything.
T withDenseReference<T>(T Function() body) {
  denseReferenceForTests = true;
  try {
    return body();
  } finally {
    denseReferenceForTests = false;
  }
}

void main() {
  tearDown(() => denseReferenceForTests = false);

  group('sparse and dense DOF analysis agree exactly (M232 differential pin)',
      () {
    cases.forEach((name, fx) {
      test(name, () {
        // (1) the REDUCED MATRIX, before anything is rounded into a
        // decision. `SketchAnalysis` is quantised — a DOF count and two sets
        // gated on 1e-7 / 1e-9 / 1e-6 / 1e-5 — so comparing only its output
        // cannot see a difference smaller than a threshold. Measured, not
        // assumed: an injected one-ULP error in the sparse elimination passes
        // the output comparison and fails this one.
        final sparseRref = debugReducedSignature(fx.$1, fx.$2);
        final denseRref =
            withDenseReference(() => debugReducedSignature(fx.$1, fx.$2));
        expect(sparseRref, denseRref,
            reason: 'the sparse reduction produced different NUMBERS from the '
                'frozen dense original for "$name". Per the integrator, a real '
                'difference here outweighs everything else on the branch — '
                'report it, do not tune it away.');

        // (2) and the analysis the UI actually reads, which is what a user
        // would see go wrong.
        final sparse = sig(analyzeSketch(fx.$1, fx.$2));
        final dense = withDenseReference(() => sig(analyzeSketch(fx.$1, fx.$2)));
        expect(sparse, dense,
            reason: 'dof, the movable set or the carrier colouring differs '
                'for "$name"');
      });
    });

    test('the dense reference is actually reached', () {
      // Guards the guard: if the flag were ignored, every comparison above
      // would be sparse-against-sparse and could never fail. The dense path
      // is knowably slower on the ladder's upper rungs, so a large fixture
      // separates them by wall time — the one property the two paths do NOT
      // share.
      final gs = sketchFixture(128), cs = constraintFixture(128);
      final t0 = Stopwatch()..start();
      analyzeSketch(gs, cs);
      t0.stop();
      final t1 = Stopwatch()..start();
      withDenseReference(() => analyzeSketch(gs, cs));
      t1.stop();
      expect(t1.elapsedMicroseconds, greaterThan(t0.elapsedMicroseconds),
          reason: 'the dense reference should be the slower of the two at 256 '
              'entities; if it is not, the flag is not selecting it and every '
              'differential assertion in this file is vacuous');
    });

    test('the analysis is a pure function of its inputs', () {
      // The cache added at the app_state call sites is sound ONLY if this
      // holds: two calls on equal inputs must give an equal answer.
      for (final fx in cases.values) {
        expect(sig(analyzeSketch(fx.$1, fx.$2)), sig(analyzeSketch(fx.$1, fx.$2)));
      }
    });

    test('analysis does not mutate the geometry it is given', () {
      // A sparse rewrite that packed/unpacked wrongly could write back into
      // the sketch. Nothing downstream would notice until a drag moved.
      for (final fx in cases.values) {
        final before = [
          for (final g in fx.$1) '${g.type}:${g.data.join(",")}'
        ];
        analyzeSketch(fx.$1, fx.$2);
        final after = [
          for (final g in fx.$1) '${g.type}:${g.data.join(",")}'
        ];
        expect(after, before);
      }
    });
  });
}
