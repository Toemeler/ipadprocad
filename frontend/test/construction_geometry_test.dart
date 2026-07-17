// M40 — CONSTRUCTION GEOMETRY (Inventor's Format > Construction linetype).
// Contract: a construction entity IS a normal entity for the solver, snapping,
// constraints, dimensions, trims, drags and the undo journal — the style is
// pure rendering (thin + finely dashed) that rides the styles.json sidecar.
// Slots create their axis (between the cap centers) as construction geometry
// automatically, bound coincident to the centers, without changing the slot's
// 5 DOF or introducing redundancy.

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
  test('toggle selected line -> construction -> back to normal', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(50, 0));
    app.selection.add(0);
    app.toggleConstructionSelected();
    expect(s.geometry[0].isConstruction, isTrue);
    expect(s.geometry[0].style, Geo.styleConstruction);
    app.selection.add(0);
    app.toggleConstructionSelected();
    expect(s.geometry[0].style, Geo.styleNormal, reason: 'toggles back');
  });

  test('mixed selection converts everything TO construction first', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(50, 0));
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 10));
    app.toolClick(const Offset(50, 10));
    app.selection.add(0);
    app.toggleConstructionSelected(); // e0 construction, e1 normal
    app.selection.addAll([0, 1]);
    app.toggleConstructionSelected(); // Inventor: mixed -> ALL construction
    expect(s.geometry[0].isConstruction, isTrue);
    expect(s.geometry[1].isConstruction, isTrue);
    app.selection.addAll([0, 1]);
    app.toggleConstructionSelected(); // uniform -> back to normal
    expect(s.geometry.every((g) => g.style == Geo.styleNormal), isTrue);
  });

  test('construction lines constrain and dimension exactly like normal', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(60, 5));
    app.selection.add(0);
    app.toggleConstructionSelected();
    // a driving dimension ON the construction line
    final dim = Constraint(CType.dimension,
        pts: [const PRef(0, 0), const PRef(0, 1)], dimKind: 'dist', value: 60);
    s.constraints.add(dim);
    app.setDimensionValue(dim, 80);
    final g = s.geometry[0];
    final len = (getPt(g, 1) - getPt(g, 0)).distance;
    expect(len, closeTo(80, 1e-6),
        reason: 'dimension drives the construction line like any line');
    expect(g.isConstruction, isTrue, reason: 'solve preserved the style');
  });

  test('linear slot gets an automatic construction axis, rank-clean', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(140, 40));
    app.toolClick(const Offset(120, 46)); // r = 6
    expect(s.geometry, hasLength(5));
    final axis = s.geometry[4];
    expect(axis.type, Geo.line);
    expect(axis.isConstruction, isTrue);
    // axis endpoints ON the cap centers, and bound there
    expect((getPt(axis, 0) - getPt(s.geometry[2], 0)).distance, lessThan(1e-6));
    expect((getPt(axis, 1) - getPt(s.geometry[3], 0)).distance, lessThan(1e-6));
    final axisBinds = s.constraints.where((c) =>
        c.type == CType.coincident &&
        c.pts.length == 2 &&
        c.pts.any((p) => p.ent == 4));
    expect(axisBinds, hasLength(2));
    // slot DOF unchanged, zero redundancy — the axis is fully pinned
    final (rank, eqs, params) = debugRank(s.geometry, s.constraints);
    expect(eqs - rank, 0, reason: 'axis binds must not go redundant');
    expect(params - rank, 5, reason: 'slot keeps its 5 DOF');
  });

  test('dragging the slot axis moves the whole slot coherently', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(140, 40));
    app.toolClick(const Offset(120, 46));
    final gs = List<Geo>.from(s.geometry);
    // drag the axis start (= cap1 center region) by +10,+5
    gs[4] = setPt(gs[4], 0, const Offset(110, 45));
    final ok = solveConstraints(gs, s.constraints,
        dragged: const {(4, 0)}, iterations: 200);
    expect(ok, isTrue);
    // axis start still ON cap1 center; slot still a slot (caps equal radius)
    expect((getPt(gs[4], 0) - getPt(gs[2], 0)).distance, lessThan(1e-6));
    expect(gs[2].data[2], closeTo(gs[3].data[2], 1e-6));
    expect(gs[4].isConstruction, isTrue);
  });

  test('style survives trim, the sidecar scheme, and the undo journal', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 50));
    app.toolClick(const Offset(100, 50));
    app.selectTool(Tool.line);
    app.toolClick(const Offset(50, 0));
    app.toolClick(const Offset(50, 100));
    app.selection.add(0);
    app.toggleConstructionSelected();
    // trim the construction line at the crossing: the surviving piece keeps
    // the construction style (withData preserves tags)
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(80, 50));
    // trim appends the surviving piece, so find it by style, not by index
    final cons = s.geometry.where((g) => g.isConstruction).toList();
    expect(cons, hasLength(1),
        reason: 'trim piece inherits the construction style');
    expect(cons[0].type, Geo.line);
    // undo/redo round-trips the style (UndoSnap compares/carries g.style)
    app.undo(); // un-trim
    app.undo(); // un-toggle
    expect(s.geometry.every((g) => g.style == Geo.styleNormal), isTrue);
    app.redo();
    expect(s.geometry.where((g) => g.isConstruction), hasLength(1));
    app.redo();
    expect(s.geometry.where((g) => g.isConstruction), hasLength(1));
    expect(s.geometry.length, 2);
  });
}
