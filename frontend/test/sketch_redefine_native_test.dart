// The WC-Rolle model from bug-2026-10-10T112805. Requires the real OCCT
// library (PROTOTYPE_NATIVE_DIR); no mock solid can prove feature placement.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

Map<String, dynamic> fixture(String name) => jsonDecode(
        File('test/fixtures/sketch_redefine/$name.json').readAsStringSync())
    as Map<String, dynamic>;

AppState reportModel() {
  final app = AppState();
  final p = PartModel('WC-Rolle')..loadJson(fixture('part'));
  app.parts[p.name] = p;
  app.curTab = p.name;
  for (final meta in fixture('part')['sketches'] as List) {
    final row = fixture(meta['name'] as String);
    final s = SketchModel(row['name'] as String);
    s.layers.addAll((row['layers'] as List).cast<String>());
    for (final g in row['geometry'] as List) {
      final d =
          (g['data'] as List).cast<num>().map((n) => n.toDouble()).toList();
      s.engine.setCurrentLayer(g['layer'] as String);
      if (g['type'] == Geo.circle) {
        s.engine.addCircle(d[0], d[1], d[2]);
      } else {
        s.engine.addLine(d[0], d[1], d[2], d[3]);
      }
    }
    s.refresh();
    s.constraints.addAll([
      for (final c in row['constraints'] as List)
        Constraint.fromJson((c as Map).cast<String, dynamic>())
    ]);
    p.childSketches.add(ChildSketch(
        s,
        meta['plane'] as String,
        PlaneFrame.fromFrameJson(meta['frame'] as List?),
        meta['vis'] as bool,
        false,
        meta['seq'] as int,
        meta['faceRef'] == null
            ? null
            : SketchFaceSel.fromJson(
                (meta['faceRef'] as Map).cast<String, dynamic>())));
  }
  expect(recomputeAllFeatures(p, app.partKernel), isTrue);
  // The diagnostic bundle records isProjection but omits source indices.
  // Recover the two exact circular edges against the captured face frame.
  final cs = p.childSketches.last;
  final edges = partEdges(p, sketchFrameOf(cs));
  for (final i in [1, 2]) {
    final g = cs.model.geometry[i];
    final source = resolveProjectionSource(g.withProj(Geo.projSolid), edges);
    expect(source, isNotNull);
    cs.model.geometry[i] = g.withProj(Geo.projSolid, source!.index);
  }
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'Set PROTOTYPE_NATIVE_DIR to OCCT';

  test(
      'reported face sketch redefines to a parallel origin plane and keeps projections',
      () {
    final app = reportModel();
    final p = app.currentPart!;
    final cs = p.childSketches.last;
    app.startRedefineSketch(cs);
    app.planePicked('xz');
    expect(cs.faceRef, isNull);
    expect(cs.plane, 'xz');
    expect(
        cs.model.geometry.where((g) => g.proj == Geo.projSolid), hasLength(2));
    expect(cs.model.geometry[1].data[2], closeTo(60, 1e-6));
    expect(cs.model.geometry[2].data[2], closeTo(20, 1e-6));
    expect(cs.model.constraints, hasLength(9));
    expect(p.features.single.solid!.volume, closeTo(955044.1667, 0.1));
    app.dispose();
  }, skip: skip);

  test(
      'reported face sketch redefines to a perpendicular plane as ordinary geometry',
      () {
    final app = reportModel();
    final cs = app.currentPart!.childSketches.last;
    app.startRedefineSketch(cs);
    app.planePicked('xy');
    expect(cs.model.geometry.every((g) => !g.isProjection), isTrue);
    expect(cs.model.constraints, hasLength(9));
    expect(cs.model.geometry, hasLength(5));
    expect(cs.faceRef, isNull);
    app.dispose();
  }, skip: skip);

  test('consumed sketch moves its extrusion and undo restores the real solid',
      () async {
    final app = reportModel();
    final dir = Directory.systemTemp.createTempSync('redefine_native_');
    app.docsDirForTest = dir;
    final p = app.currentPart!;
    final cs = p.childSketches.first;
    final b = planeFrame('xz');
    // This work plane must precede the sketch's extrusion in the timeline.
    final w = WorkPlane('Support', -1, WorkPlaneKind.offset, 'Offset 20',
        offsetPlaneFrame(b, 20),
        base: b, offset: 20);
    p.workPlanes.add(w);
    app.startRedefineSketch(cs);
    app.planePicked(w.id);
    expect(p.features.single.computeError, isNull);
    double minY() {
      final pts = p.features.single.solid!.mesh.positions;
      var y = double.infinity;
      for (var i = 1; i < pts.length; i += 3) {
        if (pts[i] < y) y = pts[i];
      }
      return y;
    }

    expect(minY(), closeTo(20, 1e-6));
    await app.savePart(p.name);
    await app.undoPart();
    expect(cs.plane, 'xz');
    expect(cs.workPlaneId, isNull);
    expect(minY(), closeTo(0, 1e-6));
    await app.redoPart();
    expect(minY(), closeTo(20, 1e-6));
    app.dispose();
    p.dispose();
    await dir.delete(recursive: true);
  }, skip: skip);
}
