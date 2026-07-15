// M35 — Pattern panel (Inventor): Rechteckige Anordnung / Runde Anordnung /
// Spiegeln. (a) der Dialog-Flow (Session, Picks, Preview); (b) das Commit
// erzeugt Kopien + assoziative Constraints (CType.pattern bzw. symmetric);
// (c) der Solver hält die Kopien am Muster (Quelle editieren -> Kopien
// folgen); (d) Fitted vs. Abstand-zwischen-Elementen; (e) Self Symmetric
// verlängert EINEN Spline symmetrisch über die Spiegelachse.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  group('rectangular pattern', () {
    test('commit creates count1*count2-1 copies + pattern constraints', () {
      final app = makeApp();
      final s = app.current!;
      // a circle to pattern + a horizontal direction line
      s.engine.addCircle(0, 0, 3);
      s.engine.addLine(0, -10, 20, -10);
      s.refresh();
      app.selectTool(Tool.patRect);
      expect(app.pattern, isNotNull);
      final ps = app.pattern!;
      // picks through the dialog routing
      app.toolClick(const Offset(0, 3)); // circle rim -> geometry
      expect(ps.geo, contains(0));
      ps.active = PatField.dir1;
      app.toolClick(const Offset(10, -10)); // the line
      expect(ps.dir1Ent, 1);
      ps.count1 = 3;
      ps.spacing1 = 30;
      ps.fitted = true; // 30 total span -> step 15
      expect(app.patternPreview(), hasLength(2));
      expect(app.commitPattern(), isTrue);
      expect(s.geometry, hasLength(4)); // circle + line + 2 copies
      final pats =
          s.constraints.where((c) => c.type == CType.pattern).toList();
      expect(pats, hasLength(2));
      expect(s.geometry[2].data[0], closeTo(15, 1e-6));
      expect(s.geometry[3].data[0], closeTo(30, 1e-6));
      expect(s.geometry[2].data[2], closeTo(3, 1e-6)); // radius copied
      expect(app.pattern, isNull); // OK closes the dialog
      expect(app.tool, Tool.none);
    });

    test('fitted off: spacing is BETWEEN elements', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.engine.addLine(0, -10, 20, -10);
      s.refresh();
      app.selectTool(Tool.patRect);
      final ps = app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..count1 = 3
        ..spacing1 = 30
        ..fitted = false; // step 30 -> copies at 30, 60
      expect(app.commitPattern(), isTrue);
      expect(s.geometry[2].data[0], closeTo(30, 1e-6));
      expect(s.geometry[3].data[0], closeTo(60, 1e-6));
      expect(ps.kind, Tool.patRect);
    });

    test('two directions + flip', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 1);
      s.engine.addLine(0, -10, 10, -10); // +x
      s.engine.addLine(-10, 0, -10, 10); // +y
      s.refresh();
      app.selectTool(Tool.patRect);
      app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..dir2Ent = 2
        ..count1 = 2
        ..count2 = 2
        ..spacing1 = 10
        ..spacing2 = 8
        ..flip2 = true // -y
        ..fitted = false;
      expect(app.commitPattern(), isTrue);
      // 4 instances -> 3 copies: (+10,0), (0,-8), (+10,-8)
      final centers = [
        for (var i = 3; i < s.geometry.length; i++)
          Offset(s.geometry[i].data[0], s.geometry[i].data[1])
      ];
      expect(centers, hasLength(3));
      expect(
          centers.any((c) =>
              (c - const Offset(10, 0)).distance < 1e-6),
          isTrue);
      expect(
          centers.any((c) =>
              (c - const Offset(0, -8)).distance < 1e-6),
          isTrue);
      expect(
          centers.any((c) =>
              (c - const Offset(10, -8)).distance < 1e-6),
          isTrue);
    });

    test('associative: editing the SOURCE drives the copies via the solver',
        () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 5, 0);
      s.engine.addLine(0, -10, 20, -10);
      s.refresh();
      app.selectTool(Tool.patRect);
      app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..count1 = 2
        ..spacing1 = 12
        ..fitted = false;
      expect(app.commitPattern(), isTrue);
      final gs = List<Geo>.from(s.geometry);
      // drag the source line's end up — the copy's end must follow at +12 in x
      gs[0] = gs[0].withData([0, 0, 5, 7]);
      solveConstraints(gs, s.constraints,
          dragged: const {(0, 1)}, iterations: 150);
      expect(gs[2].data[2], closeTo(gs[0].data[2] + 12, 1e-3));
      expect(gs[2].data[3], closeTo(gs[0].data[3], 1e-3));
    });

    test('non-associative copies carry NO constraints', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.engine.addLine(0, -10, 10, -10);
      s.refresh();
      app.selectTool(Tool.patRect);
      app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..count1 = 3
        ..associative = false;
      final before = s.constraints.length;
      expect(app.commitPattern(), isTrue);
      expect(s.constraints.length, before);
    });

    test('pattern adds no net DOF (copy fully slaved)', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, 0, 5, 0);
      s.engine.addLine(0, -10, 20, -10);
      s.refresh();
      final dof0 = analyzeSketch(s.geometry, s.constraints).dof;
      app.selectTool(Tool.patRect);
      app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..count1 = 3;
      expect(app.commitPattern(), isTrue);
      expect(analyzeSketch(s.geometry, s.constraints).dof, dof0);
    });

    test('validation toasts instead of committing', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.refresh();
      app.selectTool(Tool.patRect);
      expect(app.commitPattern(), isFalse); // no geometry
      app.pattern!.geo.add(0);
      expect(app.commitPattern(), isFalse); // no direction line
      expect(s.geometry, hasLength(1));
    });
  });

  group('circular pattern', () {
    test('N around the projected center point over 360° fitted', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(10, 0, 2);
      s.refresh();
      app.selectTool(Tool.patCirc);
      final ps = app.pattern!;
      app.toolClick(const Offset(10, 2)); // pick the circle
      expect(ps.geo, contains(0));
      ps.active = PatField.axis;
      app.toolClick(Offset.zero); // the projected CP at the origin
      expect(ps.axisPt, const PRef(kProjCenter, 0));
      ps.countC = 4;
      ps.angleC = 360;
      ps.fitted = true; // step 90°
      expect(app.patternPreview(), hasLength(3));
      expect(app.commitPattern(), isTrue);
      expect(s.geometry, hasLength(4));
      expect(s.geometry[1].data[0], closeTo(0, 1e-6));
      expect(s.geometry[1].data[1], closeTo(10, 1e-6));
      expect(s.geometry[2].data[0], closeTo(-10, 1e-6));
      expect(s.geometry[3].data[1], closeTo(-10, 1e-6));
      expect(s.constraints.where((c) => c.type == CType.pattern),
          hasLength(3));
    });

    test('arc copies rotate their sweep angles', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addArc(10, 0, 3, 0, math.pi / 2);
      s.refresh();
      app.selectTool(Tool.patCirc);
      app.pattern!
        ..geo.add(0)
        ..axisPt = const PRef(kProjCenter, 0)
        ..countC = 2
        ..angleC = 360
        ..fitted = true; // one copy at 180°
      expect(app.commitPattern(), isTrue);
      final c = s.geometry[1];
      expect(c.data[0], closeTo(-10, 1e-6));
      expect(c.data[1], closeTo(0, 1e-6));
      // the residuals hold when the SOURCE radius changes
      final gs = List<Geo>.from(s.geometry);
      gs[0] = gs[0].withData([10, 0, 5, 0, math.pi / 2]);
      solveConstraints(gs, s.constraints,
          dragged: const {(0, 1)}, iterations: 150);
      expect(gs[1].data[2], closeTo(gs[0].data[2], 1e-3),
          reason: 'copy radius follows the source');
    });

    test('flip reverses the rotation direction', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(10, 0, 1);
      s.refresh();
      app.selectTool(Tool.patCirc);
      app.pattern!
        ..geo.add(0)
        ..axisPt = const PRef(kProjCenter, 0)
        ..countC = 4
        ..angleC = 90
        ..fitted = true // step 30° over 90 span
        ..flipC = true;
      expect(app.commitPattern(), isTrue);
      // first copy at -30°: y must be NEGATIVE
      expect(s.geometry[1].data[1], lessThan(0));
    });
  });

  group('mirror', () {
    test('mirrored line gets symmetric constraints and follows the source',
        () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(2, 1, 8, 4);
      s.engine.addLine(0, -20, 0, 20); // mirror line = Y axis
      s.refresh();
      app.selectTool(Tool.mirror);
      final ps = app.pattern!;
      app.toolClick(const Offset(5, 2.5)); // pick the line
      expect(ps.geo, contains(0));
      ps.active = PatField.mirrorLine;
      app.toolClick(const Offset(0, 10));
      expect(ps.mirrorEnt, 1);
      expect(app.commitPattern(), isTrue);
      expect(s.geometry, hasLength(3));
      expect(s.geometry[2].data[0], closeTo(-2, 1e-6));
      expect(s.geometry[2].data[2], closeTo(-8, 1e-6));
      final sym =
          s.constraints.where((c) => c.type == CType.symmetric).toList();
      expect(sym, hasLength(2));
      // associativity: drag the source end, the mirror follows. Ground the
      // axis first (otherwise the solver is free to rotate IT instead —
      // legitimate, but not what this test measures).
      s.constraints.add(Constraint(CType.fix,
          ents: [1], anchors: List<double>.from(s.geometry[1].data)));
      final gs = List<Geo>.from(s.geometry);
      gs[0] = gs[0].withData([2, 1, 8, 9]);
      solveConstraints(gs, s.constraints,
          dragged: const {(0, 1)}, iterations: 150);
      expect(gs[2].data[2], closeTo(-gs[0].data[2], 1e-3));
      expect(gs[2].data[3], closeTo(gs[0].data[3], 1e-3));
    });

    test('mirrored circle: symmetric center + equal radius', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(6, 3, 2.5);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      app.selectTool(Tool.mirror);
      app.pattern!
        ..geo.add(0)
        ..mirrorEnt = 1;
      expect(app.commitPattern(), isTrue);
      expect(s.geometry[2].data[0], closeTo(-6, 1e-6));
      expect(s.geometry[2].data[2], closeTo(2.5, 1e-6));
      expect(s.constraints.where((c) => c.type == CType.equal), hasLength(1));
    });

    test('the mirror line itself cannot be in the selection', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      app.selectTool(Tool.mirror);
      final ps = app.pattern!;
      app.toolClick(const Offset(0, 5)); // select the line as geometry
      expect(ps.geo, contains(0));
      ps.active = PatField.mirrorLine;
      app.toolClick(const Offset(0, 5)); // and try it as the mirror line
      expect(ps.mirrorEnt, isNull);
    });

    test('Apply keeps the dialog open and clears the picks (Inventor)', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addLine(2, 1, 8, 4);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      app.selectTool(Tool.mirror);
      app.pattern!
        ..geo.add(0)
        ..mirrorEnt = 1;
      expect(app.commitPattern(keepOpen: true), isTrue);
      expect(app.pattern, isNotNull);
      expect(app.pattern!.geo, isEmpty);
      expect(app.tool, Tool.mirror);
    });

    test('self-symmetric extends ONE spline over the mirror line', () {
      final app = makeApp();
      final s = app.current!;
      // fit spline ending ON the y axis
      s.engine.addPolyline([-12, 2, -6, 8, 0, 5]);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.geometry[0] = s.geometry[0].asSpline(Geo.splineFit);
      app.selectTool(Tool.mirror);
      app.pattern!
        ..geo.add(0)
        ..mirrorEnt = 1
        ..selfSym = true;
      expect(app.commitPattern(), isTrue);
      expect(s.geometry, hasLength(2), reason: 'NO copy — one spline');
      final g = s.geometry[0];
      expect(g.data[1].toInt(), 5); // 3 -> 2n-1 = 5 defining points
      expect(g.spline, Geo.splineFit, reason: 'tag survives the rebuild');
      expect(Offset(g.data[2 + 8], g.data[3 + 8]).dx, closeTo(12, 1e-6));
      // symmetric pairs + middle pinned on the line
      expect(s.constraints.where((c) => c.type == CType.symmetric),
          hasLength(2));
      expect(
          s.constraints.where((c) =>
              c.type == CType.coincident &&
              c.pts.length == 1 &&
              c.ents.isNotEmpty),
          hasLength(1));
    });

    test('self-symmetric refuses a spline that misses the line', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addPolyline([-30, 2, -20, 8, -12, 5]);
      s.engine.addLine(0, -20, 0, 20);
      s.refresh();
      s.geometry[0] = s.geometry[0].asSpline(Geo.splineFit);
      app.selectTool(Tool.mirror);
      app.pattern!
        ..geo.add(0)
        ..mirrorEnt = 1
        ..selfSym = true;
      expect(app.commitPattern(), isFalse);
      expect(s.geometry[0].data[1].toInt(), 3, reason: 'untouched');
    });
  });

  group('session lifecycle', () {
    test('Esc cancels the dialog without touching the sketch', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.refresh();
      app.selectTool(Tool.patRect);
      app.pattern!.geo.add(0);
      app.cancelTool();
      expect(app.pattern, isNull);
      expect(app.tool, Tool.none);
      expect(s.geometry, hasLength(1));
    });

    test('the current selection seeds the Geometry pick set', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.refresh();
      app.selection.add(0);
      app.selectTool(Tool.mirror);
      expect(app.pattern!.geo, contains(0));
      expect(app.selection, isEmpty);
    });

    test('pattern constraints survive the sidecar round-trip', () {
      final c = Constraint(CType.pattern,
          ents: [0, 2], anchors: [patKindRotate, 1, 2, math.pi / 3]);
      final back = decodeConstraints(encodeConstraints([c]));
      expect(back, hasLength(1));
      expect(back[0].type, CType.pattern);
      expect(back[0].ents, [0, 2]);
      expect(back[0].anchors[3], closeTo(math.pi / 3, 1e-12));
    });

    test('deleting the source removes the pattern constraint (remap)', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addCircle(0, 0, 2);
      s.engine.addLine(0, -10, 10, -10);
      s.refresh();
      app.selectTool(Tool.patRect);
      app.pattern!
        ..geo.add(0)
        ..dir1Ent = 1
        ..count1 = 2;
      expect(app.commitPattern(), isTrue);
      final remapped = remapAfterRemove(s.constraints, 0);
      expect(remapped.where((c) => c.type == CType.pattern), isEmpty);
    });
  });
}
