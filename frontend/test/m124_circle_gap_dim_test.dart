// M124 — dimensioning between two circles.
//
// Two gaps, one cause. Picking two circles gave a CENTRE-TO-CENTRE distance,
// which for a concentric pair is identically 0: it measures nothing and cannot
// drive anything. And Offset wired lines (parallel + a pline distance) and arcs
// (concentric) to their sources but left a CIRCLE copy completely loose — no
// constraint, no dimension, so the offset circle drifted on the first drag and
// there was no value to type into.
//
// Both now go through the radial gap |R2 - R1| — the annulus width, which is
// exactly the distance an Offset moved the circle.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

List<Constraint> gapDims(List<Constraint> cs) =>
    [for (final c in cs) if (c.dimKind == 'gap') c];

void main() {
  group('M124 gap measurement', () {
    test('measures the radial gap, whichever circle is picked first', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]), // d20
        Geo(Geo.circle, [0, 0, 12]), // d24 -> gap 2
      ];
      final a = Constraint(CType.dimension, dimKind: 'gap', ents: [0, 1]);
      final b = Constraint(CType.dimension, dimKind: 'gap', ents: [1, 0]);
      expect(measureDim(gs, a), closeTo(2, 1e-9));
      expect(measureDim(gs, b), closeTo(2, 1e-9),
          reason: 'pick order must not change the measured width');
    });

    test('contributes exactly one equation and removes one DOF', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.circle, [0, 0, 12]),
      ];
      final c = Constraint(CType.dimension,
          dimKind: 'gap', ents: [0, 1], value: 2);
      expect(residualCount(gs, c), 1);

      final base = <Constraint>[
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [0, 0]),
        Constraint(CType.dimension, dimKind: 'dia', ents: [0], value: 20),
      ];
      final before = analyzeSketch(gs, base).dof;
      final after = analyzeSketch(gs, [...base, c]).dof;
      expect(after, before - 1, reason: 'the gap pins the outer radius');
    });
  });

  group('M124 the gap actually drives', () {
    test('setting the gap to 2 resizes the outer circle, not the inner', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.circle, [0, 0, 15]), // starts 5 away
      ];
      final cs = <Constraint>[
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [0, 0]),
        Constraint(CType.dimension, dimKind: 'dia', ents: [0], value: 20),
        Constraint(CType.dimension, dimKind: 'gap', ents: [0, 1], value: 2),
      ];
      expect(solveConstraints(gs, cs), isTrue);
      expect(gs[0].data[2], closeTo(10, 1e-6), reason: 'inner d20 held');
      expect(gs[1].data[2], closeTo(12, 1e-6), reason: 'outer pulled to r12');
      expect(measureDim(gs, cs.last), closeTo(2, 1e-6));
    });

    test('the inner circle growing carries the outer one along', () {
      // Ø20 + 2 gap; drive the inner to Ø30 and the outer must follow to r17.
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.circle, [0, 0, 12]),
      ];
      final cs = <Constraint>[
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0, 0]),
        Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [0, 0]),
        Constraint(CType.dimension, dimKind: 'dia', ents: [0], value: 30),
        Constraint(CType.dimension, dimKind: 'gap', ents: [0, 1], value: 2),
      ];
      expect(solveConstraints(gs, cs), isTrue);
      expect(gs[0].data[2], closeTo(15, 1e-6));
      expect(gs[1].data[2], closeTo(17, 1e-6),
          reason: 'the gap is a relationship, not a fixed radius');
    });
  });

  group('M124 the dimension tool picks it', () {
    test('two CONCENTRIC circles give a gap, not a zero centre distance', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.circle, [0, 0, 12]),
      ]);
      app.selectTool(Tool.dimension);
      // Seed the pick set directly: this test is about WHICH dimension the
      // pair yields, not about hit-test tolerances.
      app.conEnts.addAll([0, 1]);
      app.toolClick(const Offset(20, 20)); // place the text
      expect(app.pendingDim, isNotNull, reason: 'the value dialog opened');
      expect(app.pendingDim!.dimKind, 'gap');
      app.confirmDimension(null); // accept the measured value

      final dims = gapDims(s.constraints);
      expect(dims, hasLength(1), reason: 'a gap dimension was placed');
      expect(dims[0].value, closeTo(2, 1e-6));
    });

    test('two circles with DIFFERENT centres still give centre-to-centre', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.addAll([
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.circle, [50, 0, 12]),
      ]);
      app.selectTool(Tool.dimension);
      app.conEnts.addAll([0, 1]);
      app.toolClick(const Offset(25, 30));
      expect(app.pendingDim, isNotNull);
      app.confirmDimension(null);

      expect(gapDims(s.constraints), isEmpty,
          reason: 'Inventor gives centre-to-centre when it is meaningful');
      final dims = [
        for (final c in s.constraints)
          if (c.type == CType.dimension) c
      ];
      expect(dims, hasLength(1));
      expect(dims[0].value, closeTo(50, 1e-6));
    });
  });

  group('M124 offsetting a circle', () {
    test('leaves a concentric constraint and a driving gap dimension', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.add(Geo(Geo.circle, [0, 0, 10]));
      app.selectTool(Tool.moffset);
      app.modEntity = 0; // the picked circle
      app.toolClick(const Offset(13, 0)); // offset outwards ~3

      expect(s.geometry, hasLength(2), reason: 'a copy was made');
      expect(
          s.constraints.where((c) => c.type == CType.concentric).length, 1,
          reason: 'the copy is tied to its source');
      final dims = gapDims(s.constraints);
      expect(dims, hasLength(1), reason: 'the offset distance is dimensioned');
      expect(dims[0].paramName, isNotNull,
          reason: 'and it is the editable driver, so a value can be typed');
      expect(dims[0].value, closeTo(3, 1e-6),
          reason: 'the distance the offset actually moved, not a run length');
    });

    test('editing that dimension to 2 moves the copy to exactly 2', () {
      final app = makeApp();
      final s = app.current!;
      s.geometry.add(Geo(Geo.circle, [0, 0, 10]));
      app.selectTool(Tool.moffset);
      app.modEntity = 0;
      app.toolClick(const Offset(13, 0));

      final dim = gapDims(s.constraints).single;
      s.constraints.add(Constraint(CType.dimension,
          dimKind: 'dia', ents: [0], value: 20));
      dim.value = 2;
      expect(solveConstraints(s.geometry, s.constraints), isTrue);
      expect(measureDim(s.geometry, dim), closeTo(2, 1e-6));
      expect(s.geometry[1].data[2], closeTo(12, 1e-6),
          reason: 'Ø20 source + 2 gap -> the copy sits at r12');
    });
  });
}
