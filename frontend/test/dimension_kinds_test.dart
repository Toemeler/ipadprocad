// Tests for the M21 dimension system: the new dimension kinds
//   'pline' (perpendicular point-to-line distance)
//   'ang3'  (3-point angle, middle pick = vertex)
// and the center-based distance combos, driven through measureDim and the
// Dart LM solver (solveConstraints falls back to LM automatically when the
// native shim is not linked, which is the case on the host test runner).

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);
Geo circle(double cx, double cy, double r) => Geo(Geo.circle, [cx, cy, r]);

void main() {
  group('measureDim', () {
    test('pline measures the perpendicular distance to the infinite line',
        () {
      final gs = [line(0, 0, 100, 0), circle(30, 7, 5)];
      final c = Constraint(CType.dimension,
          pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
          dimKind: 'pline',
          textPos: Offset.zero);
      expect(measureDim(gs, c), closeTo(7, 1e-9));
      // foot outside the segment still measures against the infinite line
      final gs2 = [line(0, 0, 10, 0), circle(500, 7, 5)];
      expect(measureDim(gs2, c..textPos = Offset.zero), closeTo(7, 1e-9));
    });

    test('ang3 measures the angle at the middle (vertex) pick', () {
      final gs = [line(10, 0, 0, 0), line(0, 0, 0, 10)];
      // rays: end of line0 -> shared corner -> end of line1  = 90 deg
      final c = Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1), PRef(1, 1)],
          dimKind: 'ang3',
          textPos: Offset.zero);
      expect(measureDim(gs, c), closeTo(90, 1e-9));
    });

    test('center-to-center distance reuses the plain dist kind', () {
      final gs = [circle(0, 0, 5), circle(30, 40, 5)];
      final c = Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(1, 0)], dimKind: 'dist', textPos: Offset.zero);
      expect(measureDim(gs, c), closeTo(50, 1e-9));
    });
  });

  group('LM solver drives the new kinds', () {
    test('pline moves a circle center to the driven distance, same side', () {
      final gs = [line(0, 0, 100, 0), circle(30, 7, 5)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [0, 0, 100, 0]),
        Constraint(CType.dimension,
            pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
            dimKind: 'pline',
            textPos: Offset.zero)
          ..value = 12,
      ];
      solveConstraints(gs, cs);
      expect(gs[1].data[1], closeTo(12, 1e-3)); // moved up to 12
      expect(gs[1].data[1], greaterThan(0)); //     not mirrored below
    });

    test('pline keeps a below-the-line point below', () {
      final gs = [line(0, 0, 100, 0), circle(30, -3, 5)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [0, 0, 100, 0]),
        Constraint(CType.dimension,
            pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
            dimKind: 'pline',
            textPos: Offset.zero)
          ..value = 5,
      ];
      solveConstraints(gs, cs);
      expect(gs[1].data[1], closeTo(-5, 1e-3));
    });

    test('ang3 drives the angle between two joined lines', () {
      final gs = [line(10, 0, 0, 0), line(0, 0, 3, 10)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [10, 0, 0, 0]),
        Constraint(CType.coincident, pts: [PRef(0, 1), PRef(1, 0)]),
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1), PRef(1, 1)],
            dimKind: 'ang3',
            textPos: Offset.zero)
          ..value = 90,
      ];
      solveConstraints(gs, cs);
      final c2 = Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1), PRef(1, 1)],
          dimKind: 'ang3',
          textPos: Offset.zero);
      expect(measureDim(gs, c2), closeTo(90, 1e-2));
    });

    test('center-to-center distance drives the second circle', () {
      final gs = [circle(0, 0, 5), circle(30, 40, 5)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [0, 0, 5]),
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(1, 0)], dimKind: 'dist', textPos: Offset.zero)
          ..value = 100,
      ];
      solveConstraints(gs, cs);
      final d = Offset(gs[1].data[0], gs[1].data[1]).distance;
      expect(d, closeTo(100, 1e-3));
    });
  });

  group('over-constraint detection knows the new kinds', () {
    test('a second pline on a fully pinned point is redundant', () {
      final gs = [line(0, 0, 100, 0), circle(30, 7, 5)];
      final cs = [
        Constraint(CType.fix, ents: [0], anchors: [0, 0, 100, 0]),
        Constraint(CType.fix, pts: [PRef(1, 0)], anchors: [30, 7]),
      ];
      final extra = Constraint(CType.dimension,
          pts: [PRef(1, 0), PRef(0, 0), PRef(0, 1)],
          dimKind: 'pline',
          textPos: Offset.zero)
        ..value = 7;
      expect(wouldOverconstrain(gs, cs, extra), isTrue);
    });
  });
}
