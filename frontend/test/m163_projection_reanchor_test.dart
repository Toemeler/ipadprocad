// M163 — a projection must follow its EDGE, not an edge NUMBER.
//
// `Geo.projSeg` stores a raw index into the part's visible-solid edge list.
// That list is rebuilt from part.features and each solid's edge order on every
// recompute, so adding a chamfer renumbers it — and the projection kept
// pointing at "edge 5" while edge 5 became a different edge.
//
// From the device (build 0f9814d, the build with M154-M162 in it):
//
//   09:02:53  project: projected model edge 5 onto "Layer 1"
//   09:03:01  extrude: loop[0] signedArea=23.09                <-- ONE loop
//   09:03:14  part: chamfer created Chamfer1 (Solid1) edges=2
//   09:03:31  extrude: loop[0] signedArea=23.09  <-- OUTER
//   09:03:31  extrude: loop[1] signedArea=19.16  <-- hole      <-- TWO
//
// Sketch3 held that projected rim (r=2.7118) and a circle drawn over it. After
// the chamfer the projection resolved to a different edge and shrank to
// r~2.47, so the sketch that had one loop had two, 0.24 mm apart, and the
// extrusion built from it came out a paper-thin ring — the nest of shells in
// the screenshot. The chamfer's own stored edges were correct throughout; the
// chamfer was never the bug.
//
// This is the same topological-naming failure EdgeSel already solves for
// fillet and chamfer selections. Projections now re-resolve too.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

PartEdge _circle(int index, Offset c, double r) => PartEdge(
      index,
      const [],
      kind: ProjKind.circle,
      defs: [c],
      radius: r,
    );

PartEdge _line(int index, Offset a, Offset b) =>
    PartEdge(index, const [], kind: ProjKind.line, defs: [a, b]);

/// The sketch entity a projection of [e] produces — what actually gets stored.
Geo _projected(PartEdge e) => geoForPartEdge(e, 'Layer 1');

void main() {
  group('M163 — the stored index is used when it is still right', () {
    test('an unchanged model resolves through the index', () {
      final edges = [
        _circle(3, Offset.zero, 1.47),
        _circle(5, Offset.zero, 2.7118),
        _line(8, const Offset(-2.7, 0), const Offset(-2.7, 17.3)),
      ];
      final g = _projected(edges[1]);
      expect(g.projSeg, 5);
      expect(resolveProjectionSource(g, edges)!.index, 5);
    });
  });

  group('M163 — a renumbered edge is followed', () {
    test('the device case: a chamfer renumbers, the projection holds', () {
      // Before: the r=2.7118 rim is edge 5.
      final before = [
        _circle(3, Offset.zero, 1.47),
        _circle(5, Offset.zero, 2.7118),
      ];
      final g = _projected(before[1]);

      // After the chamfer: two new edges appear ahead of it and everything
      // shifts. The rim itself is untouched, but it is now number 9.
      final after = [
        _circle(3, Offset.zero, 1.47),
        _circle(5, Offset.zero, 2.469), // what "edge 5" now means
        _circle(7, Offset.zero, 1.0),
        _circle(9, Offset.zero, 2.7118), // the edge actually projected
      ];

      final src = resolveProjectionSource(g, after);
      expect(src, isNotNull);
      expect(src!.index, 9,
          reason: 'it must follow the r=2.7118 rim, not the number 5');
      expect(src.radius, closeTo(2.7118, 1e-9));
    });

    test('and the WRONG answer is what the old code gave', () {
      // Guards the diagnosis: index 5 now names the 2.469 edge, which is
      // exactly the 0.24 mm discrepancy that turned the extrusion into a ring.
      final after = [
        _circle(5, Offset.zero, 2.469),
        _circle(9, Offset.zero, 2.7118),
      ];
      final byIndex = after.firstWhere((e) => e.index == 5);
      expect((2.7118 - byIndex.radius).abs(), closeTo(0.2428, 1e-3));
    });
  });

  group('M163 — it refuses to guess', () {
    test('a genuinely gone edge freezes the projection', () {
      final g = _projected(_circle(5, Offset.zero, 2.7118));
      // Nothing remotely like it survives.
      final after = [_line(1, Offset.zero, const Offset(50, 0))];
      expect(resolveProjectionSource(g, after), isNull,
          reason: 'null becomes projBroken — frozen, not silently moved');
    });

    test('two equally plausible candidates freeze it too', () {
      final g = _projected(_circle(5, Offset.zero, 2.7118));
      final after = [
        _circle(7, Offset.zero, 2.60),
        _circle(9, Offset.zero, 2.82),
      ];
      expect(resolveProjectionSource(g, after), isNull,
          reason: "M158's lesson: a coin toss is what moved it in the first "
              'place');
    });

    test('a different KIND of curve is never the same edge', () {
      final g = _projected(_circle(5, Offset.zero, 2.7118));
      final after = [_line(5, Offset.zero, const Offset(2.7118, 0))];
      expect(resolveProjectionSource(g, after), isNull);
    });

    test('an empty model freezes rather than throwing', () {
      final g = _projected(_circle(5, Offset.zero, 2.7118));
      expect(resolveProjectionSource(g, const []), isNull);
    });
  });

  group('M163 — tolerance scales with the projection', () {
    test('a source that merely CHANGED is still followed', () {
      // The pre-existing M76 contract, kept: a projection tracks its source
      // however far it moves. Only a better-matching rival is evidence that
      // the index stopped meaning the same edge.
      final g = _projected(_circle(5, Offset.zero, 1.0));
      final src = resolveProjectionSource(g, [_circle(5, Offset.zero, 3.0)]);
      expect(src, isNotNull);
      expect(src!.index, 5);
    });

    test('a large edge is allowed to move further', () {
      final g = _projected(_circle(5, Offset.zero, 100.0));
      // 2 mm on a 100 mm rim is the source having been resized a little.
      final src = resolveProjectionSource(g, [_circle(5, Offset.zero, 102.0)]);
      expect(src, isNotNull);
      expect(src!.index, 5);
    });

    test('a line follows its own move', () {
      final g = _projected(_line(2, const Offset(0, 0), const Offset(0, 20)));
      final after = [
        _line(4, const Offset(0, 0), const Offset(0, 20)), // renumbered
        _line(6, const Offset(30, 0), const Offset(30, 20)), // far away
      ];
      expect(resolveProjectionSource(g, after)!.index, 4);
    });
  });
}
