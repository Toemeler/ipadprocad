// PERMANENTE Regression aus der Geräte-Session vom 2026-07-16 (M38):
// Rechteck mit Ecke AUF dem Center Point, Slot, vier Cap-Drags (darunter der
// große Center-Zug, der den Slot damals in den gekreuzten "Teardrop" faltete),
// danach die r=5-Fillets, deren dritter auf dem Gerät abgelehnt wurde.
// Festgenagelt wird das NEUE Verhalten:
//   * die Rechteck-Ecke auf (0,0) bindet an den projizierten Center Point,
//   * der Tangenten-AST ist persistent (tanBranch) — der Slot kann durch
//     Ziehen NICHT mehr auf den gekreuzten Ast wechseln, der Drag parkt,
//   * endGripDrag SETTLED auf Maschinengenauigkeit (Seams < 1e-9), darum
//     bleibt der native Pfad nutzbar und
//   * der zuvor abgelehnte r=5-Fillet gelingt.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
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

void drag(AppState app, int ent, int idx, String kind, Offset to,
    {int frames = 40}) {
  final s = app.current!;
  final from = kind == 'center'
      ? Offset(s.geometry[ent].data[0], s.geometry[ent].data[1])
      : getPt(s.geometry[ent], idx);
  app.beginGripDrag(Grip(ent, idx, from, kind));
  if (app.dragGrip == null) return;
  for (var i = 1; i <= frames; i++) {
    app.updateGripDrag(Offset.lerp(from, to, i / frames)!);
    app.displayGeometry(s);
  }
  app.endGripDrag();
}

void main() {
  test('device session M38: CP-bind, no branch-cross, settle, fillet ok', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0)); // corner exactly on the Center Point
    app.toolClick(const Offset(351.124, 190.457));
    // the corner binds to the projected center point (the regressed feature)
    expect(
        s.constraints.any((c) =>
            c.type == CType.coincident &&
            c.pts.any((p) => p.ent == kProjCenter)),
        isTrue,
        reason: 'a corner drawn on (0,0) grounds to the Center Point');
    expect(analyzeSketch(s.geometry, s.constraints).dof, 2,
        reason: 'grounded rectangle keeps only w + h');

    app.tool = Tool.slotCP;
    app.toolClick(const Offset(-547.60, 257.75));
    app.toolClick(const Offset(-197.10, 198.64));
    app.toolClick(const Offset(-197.10, 257.61));
    app.tool = Tool.none;
    // every slot tangency captured its branch at creation
    final slotTans =
        s.constraints.where((c) => c.type == CType.tangent).toList();
    expect(slotTans, hasLength(4));
    for (final c in slotTans) {
      expect(c.tanBranch, isNotNull, reason: 'branch persisted after commit');
    }
    final branches = [for (final c in slotTans) c.tanBranch];

    // the four device drags, incl. the big center move that used to cross
    drag(app, 7, 0, 'center', const Offset(-164.776, 175.489));
    drag(app, 7, 2, 'end', const Offset(-140.057, 299.282));
    drag(app, 7, 0, 'center', const Offset(80.118, 308.755));
    drag(app, 7, 1, 'end', const Offset(48.837, 70.464));

    // branches NEVER flipped
    for (var i = 0; i < 4; i++) {
      expect(slotTans[i].tanBranch, branches[i],
          reason: 'a tangency cannot change branch by dragging');
    }
    // the slot is still an open slot, not the crossed teardrop: the two rail
    // endpoints across each cap sit a full cap-chord apart, caps stay real
    final g4 = s.geometry[4], g5 = s.geometry[5];
    final capChord = (getPt(g4, 1) - getPt(g5, 0)).distance;
    expect(capChord, greaterThan(20),
        reason: 'device teardrop had the rails meeting in a point');
    expect(s.geometry[6].data[2], greaterThan(10));
    expect(s.geometry[7].data[2], greaterThan(10));
    expect(s.geometry[6].data[2], closeTo(s.geometry[7].data[2], 1e-6));
    // endGripDrag settles the committed sketch far below the 1e-6 shared-
    // endpoint tolerance (device drift used to exceed it and pushed every
    // later solve off the native path); LM's stopping rule leaves ~1e-8
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-7));

    // the fillets of the session — including the r=5 at e1/e0 that the
    // device rejected
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.toolClick(const Offset(310.63, 190.46));
    app.toolClick(const Offset(351.12, 159.74));
    app.toolClick(const Offset(46.71, 190.46));
    app.toolClick(const Offset(0, 164.77));
    app.toolClick(const Offset(351.12, 23.88));
    app.toolClick(const Offset(330.26, 0));
    // rect(4) + slot incl. its M40 construction axis(5) + 3 fillet arcs
    expect(s.geometry, hasLength(12),
        reason: 'all three fillets succeed, incl. the once-rejected corner');
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    // every fillet carries its own radius dimension
    final rads = s.constraints
        .where((c) => c.type == CType.dimension && c.dimKind == 'rad');
    expect(rads, hasLength(3));
  });

  test('tanBranch survives the sidecar round-trip', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(140, 40));
    app.toolClick(const Offset(120, 46));
    final json = encodeConstraints(s.constraints);
    final back = decodeConstraints(json);
    final tans = back.where((c) => c.type == CType.tangent).toList();
    expect(tans, hasLength(4));
    for (var i = 0; i < 4; i++) {
      expect(tans[i].tanBranch, isNotNull);
    }
  });

  test('trim by a circle binds the cut point onto the circle (native)', () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(0, 50, 200, 50);
    s.engine.addCircle(100, 50, 20); // cutter
    s.refresh();
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(100, 50)); // remove the span inside the circle
    // two pieces remain; each new endpoint is bound onto the circle
    final onCurve = s.constraints.where((c) =>
        c.type == CType.coincident &&
        c.pts.length == 1 &&
        c.ents.isNotEmpty &&
        s.geometry[c.ents[0]].type == Geo.circle);
    expect(onCurve, hasLength(2));
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    // and it DRIVES: growing the circle pushes the trimmed ends outward
    final gs = List<Geo>.from(s.geometry);
    final ci = gs.indexWhere((g) => g.type == Geo.circle);
    gs[ci] = gs[ci].withData([100, 50, 30]);
    expect(
        solveConstraints(gs, s.constraints,
            dragged: {(ci, 1)}, iterations: 120),
        isTrue);
    for (final g in gs.where((g) => g.type == Geo.line)) {
      for (final p in [
        Offset(g.data[0], g.data[1]),
        Offset(g.data[2], g.data[3])
      ]) {
        final d = (p - const Offset(100, 50)).distance;
        expect(d, greaterThan(29.9),
            reason: 'trimmed ends follow the circle outward');
      }
    }
  });

  test('coincident tool: 2nd pick on a stacked point picks the OTHER entity',
      () {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(0, 0, 50, 0);
    s.engine.addLine(50, 0, 50, 40); // endpoint stacked on line0.p1
    s.refresh();
    app.selectTool(Tool.cCoincident);
    app.toolClick(const Offset(50, 0)); // first pick: nearest stacked point
    app.toolClick(const Offset(50, 0)); // second pick: MUST be the other one
    final coins =
        s.constraints.where((c) => c.type == CType.coincident).toList();
    expect(coins, hasLength(1),
        reason: 'the constraint was created, not rejected as e.p==e.p');
    final c = coins.first;
    expect(c.pts, hasLength(2));
    expect(c.pts[0].ent != c.pts[1].ent || c.pts[0].pt != c.pts[1].pt, isTrue);
  });
}
