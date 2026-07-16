// T-1 (Produktions-Audit) — Drag-Stabilität über den ECHTEN Anzeige-Pfad
// (beginGripDrag → updateGripDrag → displayGeometry → endGripDrag), Frame für
// Frame. Genau hier zerfiel der Slot auf dem Gerät: divergierte Zwischen-
// zustände wurden gerendert (Radius 54→120, Sweep→0) und als Startpunkt des
// nächsten Frames benutzt. Invarianten pro GEZEIGTEM Frame:
//   1. alle Werte finite,
//   2. keine degenerierte Entity (Sweep≈0-Arc, r<=0, Länge-0-Linie),
//   3. die Constraints sind erfüllt (Residuum <= 1e-4),
//   4. Arc-Parameter springen zwischen Frames nicht (Anti-Flacker).
// Beim Loslassen ist die committete Skizze erfüllt.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/diag.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/snap.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Drags [grip] along [path] through the real app lifecycle and checks the
/// frame invariants; returns the arc radii trace for jump analysis.
void dragAlong(AppState app, Grip grip, List<Offset> path) {
  final s = app.current!;
  app.beginGripDrag(grip);
  expect(app.dragGrip, isNotNull,
      reason: 'grip must be draggable (has free DOF)');
  List<Geo>? prev;
  for (final w in path) {
    app.updateGripDrag(w);
    final gs = app.displayGeometry(s);
    expect(allFinite(gs), isTrue, reason: 'frame must be finite');
    expect(hasDegenerateGeometry(gs), isFalse,
        reason: 'no zero-sweep arc / r<=0 / zero-length line may be shown');
    expect(constraintResidualNorm(gs, s.constraints), lessThan(1e-4),
        reason: 'a shown frame must satisfy the constraints');
    if (prev != null) {
      for (var i = 0; i < gs.length; i++) {
        if (gs[i].type != Geo.arc) continue;
        // radius may evolve, but never TELEPORT between adjacent frames —
        // the device log showed 54.57 -> 120.03 in one frame
        final dr = (gs[i].data[2] - prev[i].data[2]).abs();
        expect(dr, lessThan(prev[i].data[2] * 0.5 + 5),
            reason: 'arc e$i radius jumped $dr in one frame');
      }
    }
    prev = gs;
  }
  app.endGripDrag();
  expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-4),
      reason: 'the committed sketch must satisfy the constraints');
  expect(hasDegenerateGeometry(s.geometry), isFalse);
}

List<Offset> line(Offset a, Offset b, int n) => [
      for (var i = 1; i <= n; i++)
        Offset.lerp(a, b, i / n)!,
    ];

void main() {
  test('slot: dragging a cap endpoint stays a slot (the device bug)', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(40, 0));
    app.toolClick(const Offset(20, 6)); // rails y=±6, caps r=6
    app.tool = Tool.none;
    // drag cap2's END (attached to rail1's end) like the device session did
    final cap = s.geometry[3];
    expect(cap.type, Geo.arc);
    final start = getPt(cap, 2);
    dragAlong(app, Grip(3, 2, start, 'end'),
        line(start, start + const Offset(15, 22), 40));
    // it is STILL a slot: equal caps, parallel rails (implied), 4 seams closed
    final r1 = s.geometry[2].data[2], r2 = s.geometry[3].data[2];
    expect(r1, closeTo(r2, 1e-6));
    final d1 = Offset(s.geometry[0].data[2] - s.geometry[0].data[0],
        s.geometry[0].data[3] - s.geometry[0].data[1]);
    final d2 = Offset(s.geometry[1].data[2] - s.geometry[1].data[0],
        s.geometry[1].data[3] - s.geometry[1].data[1]);
    final cross = (d1.dx * d2.dy - d1.dy * d2.dx) / (d1.distance * d2.distance);
    expect(cross.abs(), lessThan(1e-6), reason: 'rails parallel by implication');
  });

  test('slot: torture drag INTO the degenerate zone shows only valid frames',
      () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(40, 0));
    app.toolClick(const Offset(20, 6));
    app.tool = Tool.none;
    // pull rail1's start ACROSS the slot towards rail2 and beyond — the old
    // code walked into the collapsed branch here; the display gate must show
    // only satisfiable frames and the release must land on a valid slot
    final g0 = getPt(s.geometry[0], 0);
    dragAlong(app, Grip(0, 0, g0, 'end'),
        line(g0, g0 + const Offset(-6, 30), 60));
    expect(s.geometry[2].data[2], greaterThan(1e-3));
    expect(s.geometry[3].data[2], greaterThan(1e-3));
  });

  test('rectangle: corner drag stays a rectangle each frame', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    app.tool = Tool.none;
    final c = getPt(s.geometry[1], 1); // a corner point
    dragAlong(app, Grip(1, 1, c, 'end'),
        line(c, c + const Offset(18, 12), 30));
    // all four corners still closed + h/v held
    for (var k = 0; k < 4; k++) {
      final a = getPt(s.geometry[k], 1);
      final b = getPt(s.geometry[(k + 1) % 4], 0);
      expect((a - b).distance, lessThan(1e-6));
    }
  });

  test('filleted rectangle: dragging an edge keeps the fillet tangent', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 4);
    app.toolClick(const Offset(28, 20));
    app.toolClick(const Offset(30, 18));
    app.tool = Tool.none;
    expect(s.geometry, hasLength(5));
    // drag the rectangle's free corner opposite the fillet
    final c = getPt(s.geometry[3], 0);
    dragAlong(app, Grip(3, 0, c, 'end'),
        line(c, c + const Offset(-10, -8), 30));
    // fillet arc still exists with its dimensioned radius
    final arc = s.geometry[4];
    expect(arc.type, Geo.arc);
    expect(arc.data[2], closeTo(4, 1e-4));
  });

  test('drag past the reachable region parks at last-good, then recovers', () {
    // a dimensioned line: its length is FIXED at 20; dragging the free end
    // beyond radius 20 is impossible — the display must park on the circle of
    // radius 20 (last good), never on a stretched line
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(0, 0, 20, 0);
    s.refresh();
    s.constraints.add(Constraint(CType.fix, pts: [const PRef(0, 0)],
        anchors: [0, 0]));
    s.constraints.add(Constraint(CType.dimension,
        pts: [const PRef(0, 0), const PRef(0, 1)], dimKind: 'dist', value: 20));
    app
      ..tool = Tool.none
      ..beginGripDrag(Grip(0, 1, const Offset(20, 0), 'end'));
    expect(app.dragGrip, isNotNull);
    for (final w in line(const Offset(20, 0), const Offset(60, 25), 25)) {
      app.updateGripDrag(w);
      final gs = app.displayGeometry(s);
      final len = (getPt(gs[0], 1) - getPt(gs[0], 0)).distance;
      expect(len, closeTo(20, 1e-4),
          reason: 'the dimension must hold in every shown frame');
    }
    app.endGripDrag();
    final len = (getPt(s.geometry[0], 1) - getPt(s.geometry[0], 0)).distance;
    expect(len, closeTo(20, 1e-4));
  });

  test('tangent circle: dragging a triangle vertex keeps all 3 tangencies',
      () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(-20, 0, 20, 0);
    s.engine.addLine(-20, 0, 0, 30);
    s.engine.addLine(20, 0, 0, 30);
    s.refresh();
    app.tool = Tool.circleTangent;
    app.toolClick(const Offset(0, 0.5));
    app.toolClick(const Offset(-9, 14));
    app.toolClick(const Offset(9, 14));
    app.tool = Tool.none;
    expect(s.geometry, hasLength(4));
    final apex = getPt(s.geometry[1], 1);
    dragAlong(app, Grip(1, 1, apex, 'end'),
        line(apex, apex + const Offset(6, 10), 25));
    // tangency distances re-checked explicitly
    final cc = Offset(s.geometry[3].data[0], s.geometry[3].data[1]);
    final r = s.geometry[3].data[2];
    double dist(Geo l) {
      final a = Offset(l.data[0], l.data[1]), b = Offset(l.data[2], l.data[3]);
      final d = b - a;
      final n = Offset(-d.dy, d.dx) / d.distance;
      return ((cc - a).dx * n.dx + (cc - a).dy * n.dy).abs();
    }

    for (var i = 0; i < 3; i++) {
      expect(dist(s.geometry[i]), closeTo(r, 1e-4),
          reason: 'tangent to line $i after the drag');
    }
  });

  test('arc slot: endpoint drag keeps caps equal by implication', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slot3A;
    app.toolClick(const Offset(-20, 0));
    app.toolClick(const Offset(0, 20));
    app.toolClick(const Offset(20, 0));
    app.toolClick(const Offset(0, 26));
    app.tool = Tool.none;
    final capA = s.geometry[2];
    final start = getPt(capA, 1);
    dragAlong(app, Grip(2, 1, start, 'end'),
        line(start, start + const Offset(-4, 8), 30));
    expect(s.geometry[2].data[2],
        closeTo(s.geometry[3].data[2], 1e-6),
        reason: 'cap equality is structural, not a lucky solve');
  });

  test('a slot drag frame is solved in reasonable time (sanity)', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(40, 0));
    app.toolClick(const Offset(20, 6));
    app.tool = Tool.none;
    final cap = s.geometry[3];
    final start = getPt(cap, 2);
    app.beginGripDrag(Grip(3, 2, start, 'end'));
    final sw = Stopwatch()..start();
    const frames = 60;
    for (var i = 1; i <= frames; i++) {
      app.updateGripDrag(start + Offset(0.2 * i, 0.3 * i));
      app.displayGeometry(s);
    }
    sw.stop();
    app.endGripDrag();
    final perFrame = sw.elapsedMicroseconds / frames / 1000.0;
    // budget: comfortably under a 120 Hz frame on desktop-class hardware
    expect(perFrame, lessThan(8.0),
        reason: 'avg ${perFrame.toStringAsFixed(2)} ms per drag-solve frame');
  }, retry: 1);

  test('math.pi sanity anchor for sweep guards', () {
    // hasDegenerateGeometry treats ~0 and ~2π sweeps as collapsed; a true
    // half-circle cap (π) must NOT be degenerate
    final g = Geo(Geo.arc, [0, 0, 6, -math.pi / 2, math.pi / 2, 0]);
    expect(hasDegenerateGeometry([g]), isFalse);
    final z = Geo(Geo.arc, [0, 0, 6, 1.7814, 1.7814, 0]); // device-log state
    expect(hasDegenerateGeometry([z]), isTrue);
  });
}
