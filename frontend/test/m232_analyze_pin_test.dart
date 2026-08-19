// M232 — the DOF analysis, pinned exactly, BEFORE its algorithm was changed.
//
// `analyzeSketch` returns three things and the UI reads every one of them:
//   * `dof`           — the gauge, the browser text, "fully constrained"
//   * `freePoints`    — gates dragging (a point not in here will not move)
//   * `looseCarriers` — the violet/white colouring of every entity
//
// OPTIMIZATION_PLAN §5 (Session 3) asks for all three to be pinned across a
// range of fixtures before the algorithm underneath them moves, because a rank
// computed differently is a sketch that looks wrong or refuses to drag — and
// neither failure throws. This file is that pin.
//
// It is deliberately a GOLDEN test, not a set of hand-reasoned expectations:
// the point is not that these numbers are right (M26 and the other DOF tests
// argue that), it is that they are UNCHANGED. Each case is reduced to one
// canonical string covering all three fields, so a single character of drift
// anywhere fails the case that produced it.
//
// The cases are chosen to reach every branch the analysis has:
//   - every CType that contributes residuals
//   - each carrier kind (line, circle, arc, plain polyline per edge, spline)
//   - projections, which enter through _withProjectionPins and not through cs
//   - the rank edge cases: no constraints, over-constrained, degenerate,
//     empty sketch
//   - the perf ladder's own fixture at four sizes, which is the system
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

/// Recorded from the implementation as it stood at the head of
/// `claude/perf-opt` (commit 4890f06), before Session 3 touched it.
const golden = <String, String>{
  'empty': r'dof=0 free=[] loose=[]',
  'single line, no constraints': r'dof=4 free=[0.0,0.1] loose=[0.0]',
  'line: fixed start + horizontal (free length)': r'dof=1 free=[0.1] loose=[]',
  'line: length dimension only': r'dof=3 free=[0.0,0.1] loose=[0.0]',
  'line fully ground': r'dof=0 free=[] loose=[]',
  'two lines: parallel': r'dof=7 free=[0.0,0.1,1.0,1.1] loose=[0.0,1.0]',
  'two lines: perpendicular + coincident corner': r'dof=5 free=[0.0,0.1,1.0,1.1] loose=[0.0,1.0]',
  'two lines: collinear': r'dof=6 free=[0.0,0.1,1.0,1.1] loose=[0.0,1.0]',
  'two lines: vertical + equal': r'dof=6 free=[0.0,0.1,1.0,1.1] loose=[0.0,1.0]',
  'symmetric about a line': r'dof=8 free=[0.0,0.1,1.0,2.0] loose=[0.0,1.0,2.0]',
  'midpoint': r'dof=1 free=[] loose=[1.0]',
  'two circles: concentric + equal': r'dof=3 free=[0.0,1.0] loose=[0.0,1.0]',
  'circle: radius dimension + fixed centre': r'dof=0 free=[] loose=[]',
  'line tangent to circle': r'dof=6 free=[0.0,1.0,1.1] loose=[0.0,1.0]',
  'arc + line smooth (G1)': r'dof=6 free=[0.0,0.1,0.2,1.0,1.1] loose=[0.0,1.0]',
  'arc alone': r'dof=5 free=[0.0,0.1,0.2] loose=[0.0]',
  'rectangle, unconstrained (per-edge carriers)': r'dof=8 free=[0.0,0.1,0.2,0.3] loose=[0.0,0.1,0.2,0.3]',
  'rectangle, one corner ground + two directions': r'dof=4 free=[0.1,0.2,0.3] loose=[0.1,0.2,0.3]',
  'open polyline': r'dof=6 free=[0.0,0.1,0.2] loose=[0.0,0.1]',
  'spline-tagged polyline': r'dof=6 free=[0.0,0.1,0.2] loose=[0.0]',
  'point on circle (coincident, one pt)': r'dof=5 free=[0.0,1.0] loose=[0.0,1.0]',
  'point on polyline carrier': r'dof=10 free=[0.0,0.1,0.2,0.3,1.0] loose=[0.0,0.1,0.2,0.3,1.0]',
  'projection: a projected line pins itself': r'dof=4 free=[0.0,0.1] loose=[0.0]',
  'projection: a projected circle pins its radius too': r'dof=0 free=[] loose=[]',
  'pattern constraint (rect copy)': r'dof=0 free=[] loose=[]',
  'over-constrained: two identical fixes': r'dof=0 free=[] loose=[]',
  'redundant horizontals on one line': r'dof=1 free=[0.1] loose=[]',
  'degenerate: zero-length line': r'dof=2 free=[0.1] loose=[0.0]',
  'degenerate: zero-radius circle': r'dof=3 free=[0.0] loose=[0.0]',
  'mixed sketch, partially constrained': r'dof=16 free=[0.1,1.0,1.1,2.0,3.0,3.1,3.2,4.0,4.1,4.2,4.3] loose=[1.0,2.0,3.0,4.0,4.1,4.2,4.3]',
  'perf fixture n=8': r'dof=6 free=[1.0,2.0,3.0,4.1,5.0,5.1,6.0,6.1,7.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0]',
  'perf fixture n=16': r'dof=14 free=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.1,9.0,9.1,10.0,10.1,11.0,11.1,12.0,12.1,13.0,13.1,14.0,14.1,15.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0]',
  'perf fixture n=32': r'dof=30 free=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.1,17.0,17.1,18.0,18.1,19.0,19.1,20.0,20.1,21.0,21.1,22.0,22.1,23.0,23.1,24.0,24.1,25.0,25.1,26.0,26.1,27.0,27.1,28.0,28.1,29.0,29.1,30.0,30.1,31.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0,24.0,25.0,26.0,27.0,28.0,29.0,30.0,31.0]',
  'perf fixture n=64': r'dof=62 free=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0,24.0,25.0,26.0,27.0,28.0,29.0,30.0,31.0,32.1,33.0,33.1,34.0,34.1,35.0,35.1,36.0,36.1,37.0,37.1,38.0,38.1,39.0,39.1,40.0,40.1,41.0,41.1,42.0,42.1,43.0,43.1,44.0,44.1,45.0,45.1,46.0,46.1,47.0,47.1,48.0,48.1,49.0,49.1,50.0,50.1,51.0,51.1,52.0,52.1,53.0,53.1,54.0,54.1,55.0,55.1,56.0,56.1,57.0,57.1,58.0,58.1,59.0,59.1,60.0,60.1,61.0,61.1,62.0,62.1,63.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0,24.0,25.0,26.0,27.0,28.0,29.0,30.0,31.0,32.0,33.0,34.0,35.0,36.0,37.0,38.0,39.0,40.0,41.0,42.0,43.0,44.0,45.0,46.0,47.0,48.0,49.0,50.0,51.0,52.0,53.0,54.0,55.0,56.0,57.0,58.0,59.0,60.0,61.0,62.0,63.0]',
  'perf fixture n=128': r'dof=126 free=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0,24.0,25.0,26.0,27.0,28.0,29.0,30.0,31.0,32.0,33.0,34.0,35.0,36.0,37.0,38.0,39.0,40.0,41.0,42.0,43.0,44.0,45.0,46.0,47.0,48.0,49.0,50.0,51.0,52.0,53.0,54.0,55.0,56.0,57.0,58.0,59.0,60.0,61.0,62.0,63.0,64.1,65.0,65.1,66.0,66.1,67.0,67.1,68.0,68.1,69.0,69.1,70.0,70.1,71.0,71.1,72.0,72.1,73.0,73.1,74.0,74.1,75.0,75.1,76.0,76.1,77.0,77.1,78.0,78.1,79.0,79.1,80.0,80.1,81.0,81.1,82.0,82.1,83.0,83.1,84.0,84.1,85.0,85.1,86.0,86.1,87.0,87.1,88.0,88.1,89.0,89.1,90.0,90.1,91.0,91.1,92.0,92.1,93.0,93.1,94.0,94.1,95.0,95.1,96.0,96.1,97.0,97.1,98.0,98.1,99.0,99.1,100.0,100.1,101.0,101.1,102.0,102.1,103.0,103.1,104.0,104.1,105.0,105.1,106.0,106.1,107.0,107.1,108.0,108.1,109.0,109.1,110.0,110.1,111.0,111.1,112.0,112.1,113.0,113.1,114.0,114.1,115.0,115.1,116.0,116.1,117.0,117.1,118.0,118.1,119.0,119.1,120.0,120.1,121.0,121.1,122.0,122.1,123.0,123.1,124.0,124.1,125.0,125.1,126.0,126.1,127.0] loose=[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0,20.0,21.0,22.0,23.0,24.0,25.0,26.0,27.0,28.0,29.0,30.0,31.0,32.0,33.0,34.0,35.0,36.0,37.0,38.0,39.0,40.0,41.0,42.0,43.0,44.0,45.0,46.0,47.0,48.0,49.0,50.0,51.0,52.0,53.0,54.0,55.0,56.0,57.0,58.0,59.0,60.0,61.0,62.0,63.0,64.0,65.0,66.0,67.0,68.0,69.0,70.0,71.0,72.0,73.0,74.0,75.0,76.0,77.0,78.0,79.0,80.0,81.0,82.0,83.0,84.0,85.0,86.0,87.0,88.0,89.0,90.0,91.0,92.0,93.0,94.0,95.0,96.0,97.0,98.0,99.0,100.0,101.0,102.0,103.0,104.0,105.0,106.0,107.0,108.0,109.0,110.0,111.0,112.0,113.0,114.0,115.0,116.0,117.0,118.0,119.0,120.0,121.0,122.0,123.0,124.0,125.0,126.0,127.0]',
};

void main() {
  group('analyzeSketch is unchanged (M232 pin)', () {
    cases.forEach((name, fx) {
      test(name, () {
        final want = golden[name];
        expect(want, isNotNull, reason: 'no golden recorded for "$name"');
        expect(sig(analyzeSketch(fx.$1, fx.$2)), want,
            reason: 'the DOF analysis changed for "$name" — dof, the movable '
                'set or the carrier colouring is no longer what it was');
      });
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
