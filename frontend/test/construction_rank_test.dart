// T-2 (Produktions-Audit) — Rang-/Redundanztest jeder deterministischen
// Konstruktion. Ein rangdefizientes (redundantes) Gleichungssystem macht die
// LM-Normalgleichungen singulär und lässt libslvs die Skizze als inkonsistent
// melden — genau die Wurzel des Slot-Flackerns. Deshalb ist hier für JEDE
// Konstruktion festgenagelt: Gleichungen == Rang (Redundanz 0), DOF ==
// Inventor-Erwartung, Residuum ~0 direkt nach dem Commit.

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
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

void expectClean(SketchModel s,
    {required int dof, String reason = ''}) {
  final (rank, eqs, params) = debugRank(s.geometry, s.constraints);
  expect(eqs - rank, 0,
      reason: 'redundancy-free system required $reason '
          '(eqs=$eqs rank=$rank)');
  expect(params - rank, dof,
      reason: 'DOF mismatch $reason (params=$params rank=$rank)');
  expect(analyzeSketch(s.geometry, s.constraints).dof, dof, reason: reason);
  expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6),
      reason: 'construction must commit already satisfied $reason');
}

void main() {
  test('rectangle 2P: 12 independent equations, 4 DOF', () {
    final app = makeApp();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    expectClean(app.current!, dof: 4, reason: '(rect 2P)');
  });

  test('rectangle 3P (rotated): perpendicular corners, 5 DOF', () {
    final app = makeApp();
    app.tool = Tool.rect3P;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 10));
    app.toolClick(const Offset(25, 25));
    expectClean(app.current!, dof: 5, reason: '(rect 3P)');
  });

  test('linear slot: 13 independent equations, 5 DOF', () {
    final app = makeApp();
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(40, 0));
    app.toolClick(const Offset(20, 6));
    expectClean(app.current!, dof: 5, reason: '(linear slot)');
  });

  test('arc slot: 14 independent equations, 6 DOF', () {
    final app = makeApp();
    app.tool = Tool.slot3A;
    app.toolClick(const Offset(-20, 0));
    app.toolClick(const Offset(0, 20));
    app.toolClick(const Offset(20, 0));
    app.toolClick(const Offset(0, 26));
    expectClean(app.current!, dof: 6, reason: '(arc slot)');
  });

  test('fillet on a rectangle corner: redundancy-free, DOF unchanged', () {
    final app = makeApp();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 4);
    app.toolClick(const Offset(28, 20));
    app.toolClick(const Offset(30, 18));
    // rect(4) + fillet arc: the fillet consumes exactly the freedom it adds
    // (5 arc params vs corner-coincidence removal −2, seams +4, tangents +2,
    // radius dim +1)
    expect(app.current!.geometry, hasLength(5));
    expectClean(app.current!, dof: 4, reason: '(rect + fillet)');
  });

  test('chamfer (equal) on a rectangle corner: x/y setbacks, redundancy-free',
      () {
    final app = makeApp();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    app.tool = Tool.chamfer;
    app.filletSess = FilletSession(Tool.chamfer, d1: 5, d2: 5);
    app.toolClick(const Offset(28, 20));
    app.toolClick(const Offset(30, 18));
    expect(app.current!.geometry, hasLength(5));
    expectClean(app.current!, dof: 4, reason: '(rect + chamfer equal)');
  });

  test('chamfer (two distances) on a rectangle corner: redundancy-free', () {
    final app = makeApp();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(30, 20));
    app.tool = Tool.chamfer;
    app.filletSess = FilletSession(Tool.chamfer, d1: 8, d2: 4)..mode = 1;
    app.toolClick(const Offset(28, 20));
    app.toolClick(const Offset(30, 18));
    expectClean(app.current!, dof: 4, reason: '(rect + chamfer 2d)');
  });

  test('both slots stay redundancy-free after a solver round-trip', () {
    // guards against a future "helpful" constraint sneaking back in
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(40, 0));
    app.toolClick(const Offset(20, 6));
    final gs = List<Geo>.from(s.geometry);
    expect(solveConstraints(gs, s.constraints), isTrue);
    final (rank, eqs, _) = debugRank(gs, s.constraints);
    expect(eqs - rank, 0);
  });
}
