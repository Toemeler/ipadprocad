// T-3 (Produktions-Audit) — Operationen in KOMBINATION. Der Geräte-Fehler war
// keine Einzeloperation: ein Chamfer auf einer Rechteck-Ecke hinterließ ein
// unerfüllbares System, dessen Gesamt-Solve den zuvor gebauten Slot gleich
// mit zerlegte. Diese Tests bauen die Geräte-Session nach und nageln fest:
//   * jede Operation lässt den REST der Skizze unangetastet,
//   * nach jeder Operation ist die GANZE Skizze erfüllt (Residuum ~0),
//   * eine unmögliche Operation wird abgelehnt und ändert NICHTS.

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/diag.dart';
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

List<List<double>> snap(List<Geo> gs, Iterable<int> idx) =>
    [for (final i in idx) List<double>.from(gs[i].data)];

void expectUnchanged(List<List<double>> before, List<Geo> gs,
    Iterable<int> idx, String what) {
  var k = 0;
  for (final i in idx) {
    for (var j = 0; j < before[k].length; j++) {
      expect(gs[i].data[j], closeTo(before[k][j], 1e-9),
          reason: '$what: entity $i param $j moved');
    }
    k++;
  }
}

void main() {
  test('the device session: rect + slot + circle, then two chamfers', () {
    final app = makeApp();
    final s = app.current!;
    // rectangle (device: 4 lines with h/v + corners)
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(160, 80));
    // linear slot next to it (device: slotOverall — same 4-entity result)
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(90, 10));
    app.toolClick(const Offset(150, 10));
    app.toolClick(const Offset(120, 18)); // r = 8
    // a circle attached to a rectangle corner (device: entity e4)
    s.engine.addCircle(60, 40, 12);
    s.refresh();
    s.constraints.add(Constraint(CType.coincident,
        pts: [const PRef(8, 0), const PRef(1, 1)]));
    expect(solveConstraints(List<Geo>.from(s.geometry), s.constraints), isTrue);

    final slotIdx = [4, 5, 6, 7];
    final slotBefore = snap(s.geometry, slotIdx);

    // chamfer corner 1 (between rect edges e2/e3) — the op that used to
    // scramble everything
    app.tool = Tool.chamfer;
    app.filletSess = FilletSession(Tool.chamfer, d1: 5, d2: 5);
    app.toolClick(const Offset(104, 40)); // on e0 near corner (0,0)
    app.toolClick(const Offset(100, 44)); // on e3 near corner (0,0)
    expect(s.geometry, hasLength(10), reason: 'chamfer line added');
    // whole sketch satisfied, nothing degenerate
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    expect(hasDegenerateGeometry(s.geometry), isFalse);
    // the SLOT did not move a hair
    expectUnchanged(slotBefore, s.geometry, slotIdx, 'after chamfer 1');

    // chamfer corner 2
    app.toolClick(const Offset(156, 40));
    app.toolClick(const Offset(160, 44));
    expect(s.geometry, hasLength(11));
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    expectUnchanged(slotBefore, s.geometry, slotIdx, 'after chamfer 2');

    // both chamfers carry x/y setback dims of 5
    final dims = s.constraints
        .where((c) => c.type == CType.dimension)
        .toList();
    expect(dims, hasLength(4)); // 2 chamfers × (distx + disty)
    for (final d in dims) {
      expect({'distx', 'disty'}, contains(d.dimKind));
      expect(d.value, closeTo(5, 1e-6));
    }
  });

  test('fillet after a slot leaves the slot untouched and satisfied', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(160, 80));
    app.tool = Tool.slotCC;
    app.toolClick(const Offset(90, 10));
    app.toolClick(const Offset(150, 10));
    app.toolClick(const Offset(120, 18));
    final slotIdx = [4, 5, 6, 7];
    final slotBefore = snap(s.geometry, slotIdx);
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 6);
    app.toolClick(const Offset(156, 80));
    app.toolClick(const Offset(160, 76));
    expect(s.geometry, hasLength(9));
    expect(s.geometry.last.type, Geo.arc);
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    expectUnchanged(slotBefore, s.geometry, slotIdx, 'after fillet');
  });

  test('an over-large fillet on a FREE rectangle is allowed (edges grow)', () {
    // documents intended behaviour: without dimensions the edges may resize,
    // so a big radius is satisfiable — Inventor allows it too
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(120, 50));
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 500);
    app.toolClick(const Offset(118, 50));
    app.toolClick(const Offset(120, 48));
    expect(s.geometry, hasLength(5));
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
  });

  test('a chamfer on a FIXED corner is refused and changes NOTHING', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(120, 50));
    // pin BOTH corner points the chamfer would trim apart: the seams + the
    // x/y dims then contradict the fixes — unsatisfiable by construction
    s.constraints.add(Constraint(CType.fix,
        pts: [const PRef(1, 1)], anchors: [120, 50]));
    s.constraints.add(Constraint(CType.fix,
        pts: [const PRef(2, 0)], anchors: [120, 50]));
    final all = [0, 1, 2, 3];
    final before = snap(s.geometry, all);
    final consBefore = s.constraints.length;
    app.tool = Tool.chamfer;
    app.filletSess = FilletSession(Tool.chamfer, d1: 5, d2: 5);
    app.toolClick(const Offset(118, 50));
    app.toolClick(const Offset(120, 48));
    expect(s.geometry, hasLength(4), reason: 'nothing added');
    expect(s.constraints.length, consBefore, reason: 'nothing constrained');
    expectUnchanged(before, s.geometry, all, 'after refused chamfer');
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6),
        reason: 'the sketch is still the valid pre-op state');
  });

  test('every fillet is dimensioned; editing one drives only that one', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(160, 80));
    app.tool = Tool.fillet;
    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.toolClick(const Offset(156, 80));
    app.toolClick(const Offset(160, 76));
    app.toolClick(const Offset(104, 40));
    app.toolClick(const Offset(100, 44));
    expect(s.geometry, hasLength(6));
    final rads = s.constraints
        .where((c) => c.type == CType.dimension && c.dimKind == 'rad')
        .toList();
    expect(rads, hasLength(2), reason: 'one R-dim per fillet (user spec)');
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    // editing the FIRST fillet's dimension moves only e4
    final dimOfE4 = rads.firstWhere((d) => d.ents.contains(4));
    app.setDimensionValue(dimOfE4, 7);
    expect(s.geometry[4].data[2], closeTo(7, 1e-4));
    expect(s.geometry[5].data[2], closeTo(5, 1e-4));
  });

  test('trim keeps the whole sketch satisfied or refuses', () {
    final app = makeApp();
    final s = app.current!;
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(100, 40));
    app.toolClick(const Offset(130, 60));
    s.engine.addLine(90, 50, 140, 50); // a cutter through the rectangle
    s.refresh();
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(115, 50)); // trim the middle span of the cutter
    expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-6));
    expect(hasDegenerateGeometry(s.geometry), isFalse);
    expect(allFinite(s.geometry), isTrue);
  });
}
