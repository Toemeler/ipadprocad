// M32 — Project Geometry (Inventor): Linien anderer Layer sowie die X/Y-
// Achse werden als GELBE, gepinnte Referenzgeometrie in den Editier-Layer
// projiziert; Projektionen folgen ihrer Quelle laufend und sind im Ziel-
// Layer nicht verschiebbar. Außerdem: Show Constraints / DOF default AUS.
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
  // source geometry on layer A, editing happens on layer B
  s.engine.setCurrentLayer('A');
  s.engine.addLine(0, 0, 40, 30); //  e0: the projection source
  s.engine.addCircle(80, 0, 10); //   e1: circles are NOT projectable
  s.refresh();
  s.layers
    ..clear()
    ..addAll(['A', 'B']);
  app.editingLayer = 'B';
  app.tool = Tool.project;
  return app;
}

void main() {
  test('defaults: Show Constraints and DOF glyphs start OFF', () {
    final app = AppState();
    expect(app.showConstraints, isFalse);
    expect(app.showDof, isFalse);
  });

  test('projecting a line from another layer creates a tagged copy on the '
      'editing layer', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15)); // on the source line
    final s = app.current!;
    expect(s.geometry, hasLength(3));
    final p = s.geometry[2];
    expect(p.type, Geo.line);
    expect(p.layer, 'B');
    expect(p.proj, 0, reason: 'tagged with its source entity');
    expect(p.data, s.geometry[0].data);
  });

  test('the projection TRACKS its source through the solver', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15));
    final s = app.current!;
    // drive the SOURCE with a dimension — the projection must follow
    s.constraints.addAll([
      Constraint(CType.fix, pts: [PRef(0, 0)], anchors: [0, 0]),
      Constraint(CType.horizontal, ents: [0]),
      Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 60),
    ]);
    final gs = List<Geo>.from(s.geometry);
    solveConstraints(gs, s.constraints);
    for (var k = 0; k < 4; k++) {
      expect(gs[0].data[k], closeTo(const [0, 0, 60, 0][k], 1e-6));
      expect(gs[2].data[k], closeTo(gs[0].data[k], 1e-9),
          reason: 'laufend aktualisiert: projection mirrors the source');
    }
    expect(gs[2].proj, 0, reason: 'tag survives the solve (withData)');
  });

  test('projections are PINNED: never draggable, dimensions against them '
      'drive the other geometry', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15));
    final s = app.current!;
    final a = analyzeSketch(s.geometry, s.constraints);
    expect(a.freePoints.contains((2, 0)), isFalse);
    expect(a.freePoints.contains((2, 1)), isFalse,
        reason: 'the drag block runs on freePoints — pinned means immovable');
    // a new line on B dimensioned against the projection: the LINE moves
    s.engine.setCurrentLayer('B');
    s.engine.addLine(100, 0, 100, 50);
    s.refresh(tagSource: List.of(s.geometry)
      ..add(Geo(Geo.line, const [100, 0, 100, 50], layer: 'B')));
    s.constraints.add(Constraint(CType.dimension,
        pts: [PRef(3, 0), PRef(2, 0)], dimKind: 'dist', value: 10));
    final gs = List<Geo>.from(s.geometry);
    solveConstraints(gs, s.constraints);
    for (var k = 0; k < 4; k++) {
      expect(gs[2].data[k], closeTo(gs[0].data[k], 1e-6),
          reason: 'projection did not budge');
    }
    final d = (Offset(gs[3].data[0], gs[3].data[1]) -
            Offset(gs[2].data[0], gs[2].data[1]))
        .distance;
    expect(d, closeTo(10, 1e-3), reason: 'the free line moved instead');
  });

  test('X axis projection: tap near y=0 with no entity hit', () {
    final app = makeApp();
    app.toolClick(const Offset(-150, 2)); // empty space near the X axis
    final s = app.current!;
    final p = s.geometry.last;
    expect(p.proj, Geo.projAxisX);
    expect(p.data, [-kProjAxisSpan, 0, kProjAxisSpan, 0]);
    expect(p.layer, 'B');
  });

  test('rejections: same layer, duplicate (circles project since M33)', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15)); //  project the line (ok)
    expect(app.current!.geometry, hasLength(3));
    app.toolClick(const Offset(20, 15)); //  source again -> duplicate
    expect(app.current!.geometry, hasLength(3));
    // picking the projection itself (same layer) must not chain-project:
    // it lies exactly on the source, so the duplicate guard covers it
  });

  test('deleting the source layer freezes the projection (projBroken)', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15));
    final s = app.current!;
    final coords = List<double>.of(s.geometry[2].data);
    app.editingLayer = null; // leave edit mode, then delete layer A
    app.deleteLayer('A');
    // e0 (line) and e1 (circle) are gone; the projection is now e0
    final p = s.geometry.singleWhere((g) => g.isProjection);
    expect(p.proj, Geo.projBroken);
    expect(p.data, coords, reason: 'frozen in place, Inventor-style');
    // ...and a solve leaves it alone
    final gs = List<Geo>.from(s.geometry);
    solveConstraints(gs, s.constraints);
    expect(gs.singleWhere((g) => g.isProjection).data, coords);
  });

  test('modify tools refuse projected geometry', () {
    final app = makeApp();
    app.toolClick(const Offset(20, 15));
    app.tool = Tool.trim;
    app.toolClick(const Offset(20, 15)); // picks the projection (layer B)
    expect(app.current!.geometry, hasLength(3),
        reason: 'trim must not cut a projection');
    expect(app.current!.geometry[2].isProjection, isTrue);
  });
}
