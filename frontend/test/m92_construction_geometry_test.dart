// M92 — construction geometry and full constraint sets for the shape tools.
//
// The DOF arithmetic is the point here, because this is the area where an
// extra, redundant constraint row makes the LM normal equations singular and
// libslvs declare the sketch inconsistent (see the slot comments in
// app_state.dart). Every claim below is measured against the app's own
// residual counter rather than asserted.
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/solver.dart';
import 'package:prototype/tools.dart';

int _params(List<Geo> gs) {
  var n = 0;
  for (final g in gs) {
    switch (g.type) {
      case Geo.line:
        n += 4;
        break;
      case Geo.circle:
        n += 3;
        break;
      case Geo.arc:
        n += 5;
        break;
      default:
        n += g.data.length;
    }
  }
  return n;
}

int _equations(List<Geo> gs, List<Constraint> cs) {
  var n = 0;
  for (final c in cs) {
    n += residualCount(gs, c);
  }
  return n;
}

void main() {
  group('M114 arc slot', _arcSlotTests);

  group('polygon geometry', () {
    test('is n separate lines plus a construction circle', () {
      for (final n in [3, 5, 6, 8]) {
        final gs = buildToolGeometry(
            Tool.polygon, [Offset.zero, const Offset(20, 0)],
            params: {'sides': n.toDouble()})!;
        expect(gs, hasLength(n + 1), reason: '$n sides');
        for (var i = 0; i < n; i++) {
          expect(gs[i].type, Geo.line);
          expect(gs[i].isConstruction, isFalse);
        }
        expect(gs.last.type, Geo.circle);
        expect(gs.last.isConstruction, isTrue,
            reason: 'the circumscribed circle is construction geometry');
      }
    });

    test('the construction circle carries the centre and the vertices', () {
      final gs = buildToolGeometry(
          Tool.polygon, [const Offset(5, 7), const Offset(5, 27)],
          params: {'sides': 6.0})!;
      final c = gs.last;
      expect(c.data[0], closeTo(5, 1e-9));
      expect(c.data[1], closeTo(7, 1e-9));
      expect(c.data[2], closeTo(20, 1e-9));
      // Every vertex really is on it, so the constraint is satisfied at birth
      // and the solver has nothing to pull.
      for (var i = 0; i < 6; i++) {
        final p = Offset(gs[i].data[0], gs[i].data[1]);
        expect((p - const Offset(5, 7)).distance, closeTo(20, 1e-9));
      }
    });

    test('the edges close the loop', () {
      final gs = buildToolGeometry(
          Tool.polygon, [Offset.zero, const Offset(10, 0)],
          params: {'sides': 5.0})!;
      for (var i = 0; i < 5; i++) {
        final end = Offset(gs[i].data[2], gs[i].data[3]);
        final nextStart =
            Offset(gs[(i + 1) % 5].data[0], gs[(i + 1) % 5].data[1]);
        expect((end - nextStart).distance, lessThan(1e-9));
      }
    });
  });

  group('polygon constraint arithmetic', () {
    /// The set _commitTool adds: 2n corner coincidents, n-1 equal edges,
    /// n vertices coincident ON the circle.
    List<Constraint> _polySet(int n) => [
          for (var k = 0; k < n; k++)
            Constraint(CType.coincident,
                pts: [PRef(k, 1), PRef((k + 1) % n, 0)]),
          for (var k = 0; k < n - 1; k++)
            Constraint(CType.equal, ents: [k, k + 1]),
          for (var k = 0; k < n; k++)
            Constraint(CType.coincident, pts: [PRef(k, 0)], ents: [n]),
        ];

    test('point-on-curve is plain coincident, as in Inventor', () {
      final gs = buildToolGeometry(
          Tool.polygon, [Offset.zero, const Offset(10, 0)],
          params: {'sides': 6.0})!;
      // ONE point, ONE entity -> one equation, |q - centre| - r.
      final c = Constraint(CType.coincident, pts: [PRef(0, 0)], ents: [6]);
      expect(residualCount(gs, c), 1);
    });

    test('leaves exactly the polygon 4 DOF (centre, radius, rotation)', () {
      for (final n in [3, 4, 5, 6, 8, 12]) {
        final gs = buildToolGeometry(
            Tool.polygon, [Offset.zero, const Offset(20, 0)],
            params: {'sides': n.toDouble()})!;
        final eq = _equations(gs, _polySet(n));
        expect(_params(gs), 4 * n + 3, reason: '$n sides: parameters');
        expect(eq, 4 * n - 1, reason: '$n sides: equations');
        expect(_params(gs) - eq, 4, reason: '$n sides: DOF');
      }
    });

    test('a full n equal-edge constraints would OVERdetermine it', () {
      // The redundant row this deliberately avoids: with every vertex on one
      // circle, the n-th equal chord is implied by the other n-1.
      final n = 6;
      final gs = buildToolGeometry(
          Tool.polygon, [Offset.zero, const Offset(20, 0)],
          params: {'sides': n.toDouble()})!;
      final withExtra = [
        ..._polySet(n),
        Constraint(CType.equal, ents: [n - 1, 0]),
      ];
      expect(_params(gs) - _equations(gs, withExtra), 3,
          reason: 'one fewer DOF than the shape really has = redundant row');
    });

    test('dimensioning the centre and one side direction fully constrains it',
        () {
      final n = 6;
      final gs = buildToolGeometry(
          Tool.polygon, [Offset.zero, const Offset(20, 0)],
          params: {'sides': n.toDouble()})!;
      final cs = [
        ..._polySet(n),
        // "dimension the middle point": pin the circle centre (2 equations)
        Constraint(CType.fix, pts: [PRef(n, 0)]),
        // "make a side vertical": 1 equation
        Constraint(CType.vertical, ents: [0]),
        // and its size — 'dist' between the edge's two endpoints, which is
        // what the Dimension tool produces for a side.
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 20),
      ];
      expect(_params(gs) - _equations(gs, cs), 0,
          reason: 'centre + one side direction + one size = fully constrained');
      // And WITHOUT the size dimension exactly one DOF is left — the scale —
      // so nothing is over- or under-counted along the way.
      expect(_params(gs) - _equations(gs, cs.sublist(0, cs.length - 1)), 1);
    });
  });

  group('centre rectangles carry diagonals', () {
    test('two-point centre rectangle emits 4 lines + 2 construction diagonals',
        () {
      final gs = buildToolGeometry(
          Tool.rect2PC, [Offset.zero, const Offset(10, 6)])!;
      expect(gs, hasLength(6));
      for (var i = 0; i < 4; i++) {
        expect(gs[i].isConstruction, isFalse);
      }
      expect(gs[4].isConstruction, isTrue);
      expect(gs[5].isConstruction, isTrue);
    });

    test('the three-point centre rectangle too', () {
      final gs = buildToolGeometry(Tool.rect3PC,
          [Offset.zero, const Offset(10, 0), const Offset(0, 6)])!;
      expect(gs, hasLength(6));
      expect(gs[4].isConstruction, isTrue);
      expect(gs[5].isConstruction, isTrue);
    });

    test('the corner rectangles are UNCHANGED — no diagonals', () {
      expect(
          buildToolGeometry(
              Tool.rectTwoPoint, [Offset.zero, const Offset(10, 6)])!,
          hasLength(4));
    });

    test('the diagonals cross at the centre the user started from', () {
      final gs = buildToolGeometry(
          Tool.rect2PC, [const Offset(3, 4), const Offset(13, 10)])!;
      final d0a = Offset(gs[4].data[0], gs[4].data[1]);
      final d0b = Offset(gs[4].data[2], gs[4].data[3]);
      final mid = (d0a + d0b) / 2;
      expect((mid - const Offset(3, 4)).distance, lessThan(1e-9));
    });

    test('the diagonals add no degrees of freedom', () {
      final gs = buildToolGeometry(
          Tool.rect2PC, [Offset.zero, const Offset(10, 6)])!;
      // 8 parameters for two lines, 8 equations from four coincidents.
      final pins = [
        Constraint(CType.coincident, pts: [PRef(4, 0), PRef(0, 0)]),
        Constraint(CType.coincident, pts: [PRef(4, 1), PRef(2, 0)]),
        Constraint(CType.coincident, pts: [PRef(5, 0), PRef(1, 0)]),
        Constraint(CType.coincident, pts: [PRef(5, 1), PRef(3, 0)]),
      ];
      expect(_equations(gs, pins), 8);
    });
  });

  group('the linear slot axis is still there', () {
    test('and is construction geometry', () {
      final gs = buildToolGeometry(Tool.slotCC,
          [Offset.zero, const Offset(20, 0), const Offset(0, 5)])!;
      expect(gs, hasLength(5));
      expect(gs.last.type, Geo.line);
      expect(gs.last.isConstruction, isTrue);
      // Between the two arc centres, as Inventor draws it.
      expect(gs.last.data[0], closeTo(0, 1e-9));
      expect(gs.last.data[2], closeTo(20, 1e-9));
    });
  });

  test('polygon still extrudes: the loop is closed and planar', () {
    final gs = buildToolGeometry(
        Tool.polygon, [Offset.zero, const Offset(20, 0)],
        params: {'sides': 7.0})!;
    final edges = gs.where((g) => !g.isConstruction).toList();
    expect(edges, hasLength(7));
    var perimeter = 0.0;
    for (final e in edges) {
      perimeter +=
          (Offset(e.data[2], e.data[3]) - Offset(e.data[0], e.data[1])).distance;
    }
    // 7 chords of a circle of radius 20.
    expect(perimeter, closeTo(7 * 2 * 20 * math.sin(math.pi / 7), 1e-6));
  });
}

// ---------------------------------------------------------------------------
// M114 — the arc slot finally has construction geometry.
void _arcSlotTests() {
  test('emits four rails/caps plus two construction radii', () {
    final gs = buildToolGeometry(Tool.slot3A, [
      const Offset(0, 0),
      const Offset(0, 40),
      const Offset(40, 0),
      const Offset(0, 34),
    ]);
    expect(gs, isNotNull);
    expect(gs!, hasLength(6));
    for (var i = 0; i < 4; i++) {
      expect(gs[i].isConstruction, isFalse, reason: 'entity $i is real');
    }
    expect(gs[4].isConstruction, isTrue);
    expect(gs[5].isConstruction, isTrue);
    expect(gs[4].type, Geo.line, reason: 'lines, not an arc — see the comment');
    expect(gs[5].type, Geo.line);
  });

  test('each radius starts at the shared rail centre', () {
    final gs = buildToolGeometry(Tool.slot3A, [
      const Offset(0, 0),
      const Offset(0, 40),
      const Offset(40, 0),
      const Offset(0, 34),
    ])!;
    final centre = Offset(gs[0].data[0], gs[0].data[1]);
    for (final r in [gs[4], gs[5]]) {
      expect((Offset(r.data[0], r.data[1]) - centre).distance, lessThan(1e-9));
    }
  });

  test('the four pins add no degrees of freedom', () {
    final gs = buildToolGeometry(Tool.slot3A, [
      const Offset(0, 0),
      const Offset(0, 40),
      const Offset(40, 0),
      const Offset(0, 34),
    ])!;
    // Two lines = 8 parameters; four coincidents = 8 equations.
    final pins = [
      Constraint(CType.coincident, pts: [PRef(4, 0), PRef(0, 0)]),
      Constraint(CType.coincident, pts: [PRef(4, 1), PRef(2, 0)]),
      Constraint(CType.coincident, pts: [PRef(5, 0), PRef(0, 0)]),
      Constraint(CType.coincident, pts: [PRef(5, 1), PRef(3, 0)]),
    ];
    expect(_equations(gs, pins), 8);
  });

  test('the LINEAR slot is unchanged — still five entities', () {
    expect(
        buildToolGeometry(Tool.slotCC,
            [Offset.zero, const Offset(20, 0), const Offset(0, 5)])!,
        hasLength(5));
  });
}
