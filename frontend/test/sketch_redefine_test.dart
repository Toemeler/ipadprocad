import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

AppState appWithSketch() {
  final app = AppState();
  final p = PartModel('P');
  app.parts['P'] = p;
  app.curTab = 'P';
  final s = SketchModel('Sketch1')..layers.add('Layer 1');
  s.engine.setCurrentLayer('Layer 1');
  s.engine.addLine(1, 2, 11, 2);
  s.refresh();
  s.geometry[0] = s.geometry[0].withProj(Geo.projAxisX);
  s.constraints.add(Constraint(CType.horizontal, ents: [0]));
  p.childSketches.add(ChildSketch(s, 'xy', null, true, true, 0));
  return app;
}

WorkPlane workPlane(PartModel p, {String base = 'xy', int seq = 1}) {
  final b = planeFrame(base);
  final w = WorkPlane('Work Plane$seq', seq, WorkPlaneKind.offset, 'Offset',
      offsetPlaneFrame(b, 20),
      base: b, offset: 20);
  p.workPlanes.add(w);
  return w;
}

AppState projectedSketch() {
  final app = appWithSketch();
  final p = app.currentPart!;
  final s = p.childSketches.single.model;
  s.geometry[0] = s.geometry[0].withProj(Geo.projSolid, 0);
  s.engine.addCircle(1, 2, 1);
  s.refresh();
  s.constraints.add(
      Constraint(CType.coincident, pts: [const PRef(0, 0), const PRef(1, 0)]));
  p.features.add(ExtrudeFeature(
      name: 'Source', bodyName: 'B', sketchName: 'Other', profiles: const [])
    ..solid = KernelSolid(
        OcctMeshData(
            Float64List(0),
            Float64List(0),
            Int32List(0),
            Int32List.fromList([0, 2]),
            Float64List.fromList([1, 2, 0, 11, 2, 0])),
        1,
        null));
  return app;
}

PlaneFrame shiftedParallelFrame() => PlaneFrame('face', const Vec3(1, 0, 0),
    const Vec3(0, 1, 0), const Vec3(0, 0, 1), const Vec3(5, 0, 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancel restores visibility and leaves the drawing and journal alone',
      () {
    final app = appWithSketch();
    final p = app.currentPart!;
    p.vis['xz'] = true;
    final before = Map.of(p.vis);
    app.startRedefineSketch(p.childSketches.single);
    expect(app.pickPlane, isTrue);
    expect(p.vis['xy'], isTrue);
    app.escape3D();
    expect(p.vis, before);
    expect(app.pickPlane, isFalse);
    expect(app.canUndoPart, isFalse);
    expect(p.childSketches.single.plane, 'xy');
  });

  test('parallel work plane keeps links, constraints, identity and timeline',
      () {
    final app = appWithSketch();
    final p = app.currentPart!;
    final cs = p.childSketches.single;
    final w = workPlane(p);
    app.startRedefineSketch(cs);
    app.startSketchOnWorkPlane(w, alreadyArmed: true);
    expect(p.childSketches.single, same(cs));
    expect(cs.model.geometry.single.proj, Geo.projAxisX);
    expect(cs.model.constraints, hasLength(1));
    expect(cs.shared, isTrue);
    expect(cs.seq, 0);
    expect(cs.workPlaneId, w.id);
    expect(cs.faceRef, isNull);
    expect(sketchFrameOf(cs).origin, w.frame.origin);
    expect(app.activeChild, isNull);
    expect(app.pickPlane, isFalse);
    expect(app.canUndoPart, isTrue);
    final row = (p.toJson()['sketches'] as List).single as Map;
    expect(row['workPlane'], w.id);
    expect(row['frame'], w.frame.frameJson());
  });

  test(
      'nonparallel support frees projections without deleting user constraints',
      () {
    final app = appWithSketch();
    final cs = app.currentPart!.childSketches.single;
    final data = List.of(cs.model.geometry.single.data);
    app.startRedefineSketch(cs);
    app.planePicked('xz');
    expect(cs.plane, 'xz');
    expect(cs.face, isNull);
    expect(cs.model.geometry.single.proj, Geo.projNone);
    expect(cs.model.geometry.single.projSeg, -1);
    expect(cs.model.geometry.single.data, data);
    expect(cs.model.constraints.single.type, CType.horizontal);
  });

  test('face support is replaced and cleared when returning to an origin plane',
      () {
    final app = appWithSketch();
    final cs = app.currentPart!.childSketches.single;
    final frame = offsetPlaneFrame(planeFrame('xy'), 30);
    final ref = SketchFaceSel(0, 0, 30, 0, 0, 1, 100);
    app.startRedefineSketch(cs);
    app.facePicked(frame, ref);
    expect(cs.faceRef, same(ref));
    expect(cs.plane, 'face');
    app.startRedefineSketch(cs);
    app.planePicked('xy');
    expect(cs.faceRef, isNull);
    expect(cs.face, isNull);
    expect(cs.workPlaneId, isNull);
    expect(cs.plane, 'xy');
  });

  test('undo and redo restore support metadata and released projection pins',
      () async {
    final app = appWithSketch();
    final dir = Directory.systemTemp.createTempSync('redefine_');
    app.docsDirForTest = dir;
    final p = app.currentPart!;
    final cs = p.childSketches.single;
    final w = workPlane(p, base: 'xz');
    app.startRedefineSketch(cs);
    app.planePicked(w.id);
    await app.savePart('P');
    await app.undoPart();
    expect(cs.plane, 'xy');
    expect(cs.face, isNull);
    expect(cs.workPlaneId, isNull);
    expect(cs.model.geometry.single.proj, Geo.projAxisX);
    await app.redoPart();
    expect(cs.plane, kWorkPlaneKey);
    expect(cs.workPlaneId, w.id);
    expect(cs.face!.frameJson(), w.frame.frameJson());
    expect(cs.model.geometry.single.proj, Geo.projNone);
    await app.savePart('P');
    final reopened = AppState()..docsDirForTest = dir;
    await reopened.openPart('P');
    final loaded = reopened.currentPart!.childSketches.single;
    expect(loaded.workPlaneId, w.id);
    expect(loaded.face!.frameJson(), w.frame.frameJson());
    expect(loaded.model.geometry.single.proj, Geo.projNone);
    reopened.currentPart!.dispose();
    p.dispose();
    reopened.dispose();
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a downstream work plane cannot create a circular dependency', () {
    final app = appWithSketch();
    final p = app.currentPart!;
    p.features.add(ExtrudeFeature(
        name: 'E', bodyName: 'B', sketchName: 'Sketch1', profiles: const [])
      ..seq = 1);
    final w = workPlane(p, seq: 2);
    app.startRedefineSketch(p.childSketches.single);
    app.planePicked(w.id);
    expect(app.pickPlane, isTrue);
    expect(p.childSketches.single.plane, 'xy');
    expect(app.canUndoPart, isFalse);
    app.cancelPlanePick();
  });

  test('parallel opposite normals reproject the SAME model edge', () {
    final app = appWithSketch();
    final p = app.currentPart!;
    final cs = p.childSketches.single;
    // Different lengths make an accidental switch to the other edge visible.
    p.features.add(ExtrudeFeature(
        name: 'Source', bodyName: 'B', sketchName: 'Other', profiles: const [])
      ..solid = KernelSolid(
          OcctMeshData(
              Float64List(0),
              Float64List(0),
              Int32List(0),
              Int32List.fromList([0, 2, 4]),
              Float64List.fromList([1, 2, 0, 11, 2, 0, 1, -2, 0, 21, -2, 0])),
          1,
          null));
    cs.model.geometry[0] = cs.model.geometry[0].withProj(Geo.projSolid, 0);
    final target = PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, -1, 0),
        const Vec3(0, 0, -1), const Vec3(5, 0, 20));
    app.startRedefineSketch(cs);
    app.facePicked(target);
    final g = cs.model.geometry.single;
    expect(g.proj, Geo.projSolid);
    expect(g.projSeg, 0);
    expect(g.data, [-4, -2, 6, -2]);
    expect(cs.model.engine.allGeometry().single.data, g.data);
  });

  test('switching away cancels pending redefine and restores pick planes', () {
    final app = appWithSketch();
    final p = app.currentPart!;
    final vis = Map.of(p.vis);
    app.startRedefineSketch(p.childSketches.single);
    app.goHome();
    expect(app.pickPlane, isFalse);
    expect(p.vis, vis);
    expect(p.childSketches.single.plane, 'xy');
  });

  test('switching commands gives the next plane pick to the new command', () {
    final app = appWithSketch();
    final p = app.currentPart!;
    app.startRedefineSketch(p.childSketches.single);
    app.startWorkPlane(WorkPlaneKind.offset);
    app.planePicked('xz');
    expect(p.childSketches.single.plane, 'xy');
    expect(p.workPlanes, hasLength(1));
  });

  test('a moved parallel projection carries constrained drawing geometry', () {
    final app = projectedSketch();
    final cs = app.currentPart!.childSketches.single;
    app.startRedefineSketch(cs);
    app.facePicked(shiftedParallelFrame());
    final gs = cs.model.geometry;
    expect(gs[0].data[0], closeTo(-4, 1e-7));
    expect(gs[1].data[0], closeTo(-4, 1e-7));
    expect(gs[1].data[1], closeTo(2, 1e-7));
    expect(gs[0].proj, Geo.projSolid);
    expect(cs.model.constraints, hasLength(2));
  });

  test('unsatisfiable parallel support leaves model and undo history intact',
      () {
    final app = projectedSketch();
    final cs = app.currentPart!.childSketches.single;
    cs.model.constraints
        .add(Constraint(CType.fix, pts: [const PRef(1, 0)], anchors: [1, 2]));
    app.startRedefineSketch(cs);
    app.facePicked(shiftedParallelFrame());
    expect(app.pickPlane, isTrue);
    expect(cs.plane, 'xy');
    expect(cs.model.geometry[0].data[0], 1);
    expect(cs.model.geometry[1].data[0], 1);
    expect(app.canUndoPart, isFalse);
    app.cancelPlanePick();
  });

  test('browser offers Redefine for free and consumed sketches', () {
    final app = appWithSketch();
    final p = app.currentPart!;
    List<String> menu() {
      final rows = buildBrowserRows(app, expanded: {kIdOrigin});
      final row = rows.firstWhere((r) => r.id == '${kIdSketch}Sketch1');
      return [
        for (final group in row.menu)
          for (final item in group) item.id
      ];
    }

    expect(menu(), contains('skRedefine'));
    p.features.add(ExtrudeFeature(
        name: 'E', bodyName: 'B', sketchName: 'Sketch1', profiles: const []));
    // Shared sketches keep their own browser row even when consumed.
    expect(menu(), contains('skRedefine'));
  });
}
