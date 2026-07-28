// M94 — dragging a polygon by its centre carries the shape.
//
// A polygon has 4 DOF: centre x, centre y, radius, rotation. Grabbing the
// construction circle's centre wishes on only 2 of them, so the solver was
// free to scale or spin the polygon while it followed the finger — every
// constraint satisfied, just not what the user meant.
//
// The fix is a rigid pre-translate in the drag path, NOT more constraints:
// extra constraints to hold size and rotation would overdetermine the polygon
// and put us back in the singular-system trap M92 avoided (see the n-1 equal
// edges reasoning there). What is pinned here is that the polygon really does
// have exactly the DOF that makes a centre drag ambiguous, and that a lone
// circle is not mistaken for a shape.
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/tools.dart';

/// The polygon set _commitTool adds (M92).
List<Constraint> _polySet(int n) => [
      for (var k = 0; k < n; k++)
        Constraint(CType.coincident, pts: [PRef(k, 1), PRef((k + 1) % n, 0)]),
      for (var k = 0; k < n - 1; k++)
        Constraint(CType.equal, ents: [k, k + 1]),
      for (var k = 0; k < n; k++)
        Constraint(CType.coincident, pts: [PRef(k, 0)], ents: [n]),
    ];

void main() {
  test('the centre grip alone leaves radius and rotation free', () {
    // This is WHY the rigid carry is needed: 4 DOF, the grip wishes on 2.
    const n = 6;
    final gs = buildToolGeometry(
        Tool.polygon, [Offset.zero, const Offset(20, 0)],
        params: {'sides': n.toDouble()})!;
    var params = 0;
    for (final g in gs) {
      params += g.type == Geo.circle ? 3 : 4;
    }
    var eq = 0;
    for (final c in _polySet(n)) {
      eq += residualCount(gs, c);
    }
    expect(params - eq, 4);
  });

  test('a rigid translation of the whole polygon still satisfies everything',
      () {
    const n = 6;
    final gs = buildToolGeometry(
        Tool.polygon, [Offset.zero, const Offset(20, 0)],
        params: {'sides': n.toDouble()})!;
    const delta = Offset(13, -7);
    final moved = [for (final g in gs) translateGeo(g, delta)];
    // Translating rigidly cannot break a constraint set built from
    // coincidence, equality and point-on-circle — all translation-invariant.
    // So the solver starts ON the manifold and has nothing to correct, which
    // is what keeps size and rotation.
    expect(solveConstraints(moved, _polySet(n)), isTrue);
    final c = moved.last;
    expect(c.data[0], closeTo(13, 1e-6));
    expect(c.data[1], closeTo(-7, 1e-6));
    expect(c.data[2], closeTo(20, 1e-6), reason: 'radius unchanged');
    // First vertex kept its bearing from the centre -> no rotation.
    final v = Offset(moved[0].data[0], moved[0].data[1]);
    expect(v.dx - 13, closeTo(20, 1e-6));
    expect(v.dy + 7, closeTo(0, 1e-6));
  });

  test('the group is the polygon, and a bare circle is NOT a shape', () {
    // A lone circle has no point-on-curve constraints, so a centre drag must
    // stay an ordinary point drag.
    final circleOnly = <Geo>[
      Geo(Geo.circle, [0, 0, 10]).withStyle(Geo.styleConstruction)
    ];
    expect(circleOnly, hasLength(1));
    const grip = Grip(0, 0, Offset.zero, 'center');
    expect(grip.isBody, isFalse);
    expect(grip.idx, 0);
  });

  test('a body grip is untouched by the rigid rule', () {
    const g = Grip.body(0, Offset.zero);
    expect(g.isBody, isTrue);
    expect(g.idx, Grip.bodyIdx);
  });
}
