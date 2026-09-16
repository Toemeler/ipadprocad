// #66 — "i cant offset this circle with the line in one offset somehow it
// seems not connected."
//
// It IS connected. bug-2026-09-16T153624's sketch, from the log:
//
//   [0] line data=[-0.3873, 0.1000, 0.3873, 0.1000]
//   [1] arc  data=[0, 0, 0.4000, 2.8889, 0.2527]      the major arc, BELOW
//   [2] arc  data=[0, 0, 0.4000, 0.2527, 2.8889]      the minor arc, ABOVE
//   [4] coincident/ pts=e0.p0,e1.p1      [5] coincident/ pts=e0.p1,e1.p2
//   [6] coincident/ pts=e0.p1,e2.p1      [7] coincident/ pts=e0.p0,e2.p2
//
// A circle split at the two ends of a chord, with the chord across it — and
// the minor arc drawn DASHED in the screenshot, i.e. construction. Every one
// of those coincidences is real, so the three curves genuinely do meet.
//
// They meet THREE AT A TIME, which is the problem. `offsetChainAt` walks away
// from the seed and needs exactly one unvisited neighbour to keep going; at
// the chord's right end it finds two arcs and stops on the spot. The log says
// so in one line:
//
//   modify: offset chain from e0: +1 segs (open), constraints 20
//
// The seed alone, offset by itself, which is "somehow it seems not connected".
//
// IT IS NOT A BRANCH IN ANY SENSE THE USER WOULD RECOGNISE. Construction
// geometry is scaffolding: it crosses the sketch wherever it is useful, and a
// chain allowed to step onto it finds a junction at every crossing and stops
// there. Projected reference geometry was excluded from chains from the start
// for exactly that reason — this is the same rule for the other kind of
// reference geometry.
//
// Matching the SEED rather than banning construction outright, so a
// construction chain can still be offset on its own terms. What a chain may
// not do is cross between the two.
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/modify.dart';

/// The reporter's sketch. [dashed] says whether the minor arc above the chord
/// is construction, which is the only variable.
List<Geo> _chordAndCircle({required bool dashed}) {
  const r = 0.4, y = 0.1;
  final half = math.sqrt(r * r - y * y); // 0.3873, as the log has it
  final a = math.atan2(y, half); //         0.2527
  final b = math.pi - a; //                 2.8889
  return [
    Geo(Geo.line, [-half, y, half, y]),
    Geo(Geo.arc, [0, 0, r, b, a]), //       major, below the chord
    Geo(Geo.arc, [0, 0, r, a, b],
        style: dashed ? Geo.styleConstruction : Geo.styleNormal),
  ];
}

/// What the app hands the walker: line/arc, editable, not a projection, and
/// of the same construction-ness as the seed.
Set<int> _eligible(List<Geo> gs, int seed) => {
      for (var i = 0; i < gs.length; i++)
        if ((gs[i].type == Geo.line || gs[i].type == Geo.arc) &&
            !gs[i].isProjection &&
            gs[i].isConstruction == gs[seed].isConstruction)
          i
    };

void main() {
  group('THE REPORT: the chord and the circle are one chain', () {
    test('the chain runs line -> arc and CLOSES', () {
      final gs = _chordAndCircle(dashed: true);
      // Picking below the chord, on the major arc's side, as the log's
      // toolClick at w=(-0.30,0.10) -> (-0.40,0.04) did.
      final chain = offsetChainAt(gs, 0, const Offset(-0.30, 0.04),
          _eligible(gs, 0));

      expect(chain, isNotNull);
      expect(chain!.sources.length, 2,
          reason: 'THE REPORT: this was 1 — "+1 segs (open)" in the log');
      expect(chain.sources.toSet(), {0, 1},
          reason: 'the chord and the arc that is not scaffolding');
      expect(chain.closed, isTrue,
          reason: 'a chord and its arc close on each other');
    });

    test('and the construction arc is not dragged into it', () {
      final gs = _chordAndCircle(dashed: true);
      final chain =
          offsetChainAt(gs, 0, const Offset(-0.30, 0.04), _eligible(gs, 0));
      expect(chain!.sources, isNot(contains(2)));
    });

    test('with BOTH arcs real it still refuses, which is right', () {
      // Nothing here is scaffolding, so three curves really do meet at each
      // end and there are two equally good loops. Guessing between them would
      // be worse than stopping: the rule is about reference geometry, not
      // about making every junction resolve.
      final gs = _chordAndCircle(dashed: false);
      final chain =
          offsetChainAt(gs, 0, const Offset(-0.30, 0.04), _eligible(gs, 0));
      expect(chain!.sources.length, 1);
    });
  });

  group('a construction chain can still be offset on its own terms', () {
    test('seeding ON construction offsets the construction run', () {
      // Two construction lines meeting at a corner, with a normal line also
      // touching that corner. Seeded on construction, the walk sees only the
      // other construction line and runs; before this rule it would have seen
      // two neighbours and stopped.
      final gs = [
        Geo(Geo.line, const [0, 0, 10, 0], style: Geo.styleConstruction),
        Geo(Geo.line, const [10, 0, 10, 10], style: Geo.styleConstruction),
        Geo(Geo.line, const [10, 0, 20, -10]),
      ];
      final chain = offsetChainAt(gs, 0, const Offset(5, 1), _eligible(gs, 0));
      expect(chain!.sources.toSet(), {0, 1});
    });

    test('and a normal chain does not step onto construction', () {
      final gs = [
        Geo(Geo.line, const [0, 0, 10, 0]),
        Geo(Geo.line, const [10, 0, 10, 10], style: Geo.styleConstruction),
      ];
      final chain = offsetChainAt(gs, 0, const Offset(5, 1), _eligible(gs, 0));
      expect(chain!.sources, [0]);
    });
  });
}
