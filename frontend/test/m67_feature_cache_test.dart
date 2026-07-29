// M67 — an unchanged feature must not be rebuilt.
//
// The device log (build 9ef0425) showed Extrusion1 dropping from 50 548
// triangles back to 4 304 and re-refining four times just because a SECOND
// extrude was started. Each of those re-tessellations cost 0.4-2.6 s on the
// UI thread, and none of them was necessary.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

class CountingKernel implements PartKernel {
  int extrudes = 0;
  int fusions = 0;

  @override
  bool get available => true;
  @override
  String get info => 'counting';
  @override
  String get lastError => 'counting failure';

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return KernelSolid(
        OcctMeshData(
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
            Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
            Int32List.fromList(const [0, 1, 2]),
            Int32List.fromList(const [0, 3]),
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
        height,
        null);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    fusions++;
    return KernelSolid(a.mesh, a.volume + b.volume, null);
  }

  @override
  noSuchMethod(Invocation i) => null;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m67_');
  return app;
}

void addRect(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

Future<PartModel> onePart(AppState app) async {
  await app.createNamedPart('Part1');
  app.startPartSketch();
  app.planePicked('xy');
  addRect(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: '5 mm');
  await app.applyExtrude();
  return app.currentPart!;
}

void main() {
  test('an unchanged feature is not re-executed', () async {
    final app = makeApp();
    final k = CountingKernel();
    app.partKernel = k;
    final part = await onePart(app);
    expect(part.features.length, 1);
    final built = k.extrudes;
    final solid = part.features.single.solid;
    expect(built, greaterThan(0));

    recomputeAllFeatures(part, k);
    recomputeAllFeatures(part, k);
    expect(k.extrudes, built, reason: 'nothing changed, so nothing to rebuild');
    expect(identical(part.features.single.solid, solid), isTrue,
        reason: 'the SAME solid must survive, keeping its refined mesh');
  });

  test('changing a parameter rebuilds that feature', () async {
    final app = makeApp();
    final k = CountingKernel();
    app.partKernel = k;
    final part = await onePart(app);
    final built = k.extrudes;

    (part.features.single as ExtrudeFeature).distanceA = 9;
    recomputeAllFeatures(part, k);
    expect(k.extrudes, built + 1);
  });

  test('editing the SKETCH rebuilds the feature built on it', () async {
    final app = makeApp();
    final k = CountingKernel();
    app.partKernel = k;
    final part = await onePart(app);
    final built = k.extrudes;

    final cs = part.childSketches.single;
    cs.model.engine.addLine(30, 30, 40, 30);
    cs.model.refresh();
    recomputeAllFeatures(part, k);
    expect(k.extrudes, built + 1,
        reason: 'the profile source changed, so the solid is stale');
  });

  test('force rebuilds everything (load / undo hand over new handles)',
      () async {
    final app = makeApp();
    final k = CountingKernel();
    app.partKernel = k;
    final part = await onePart(app);
    final built = k.extrudes;

    recomputeAllFeatures(part, k, force: true);
    expect(k.extrudes, built + 1);
  });

  test('the signature is stable and covers the inputs that matter', () async {
    final app = makeApp();
    app.partKernel = CountingKernel();
    final part = await onePart(app);
    final f = part.features.single as ExtrudeFeature;

    final a = featureInputSig(part, f);
    expect(featureInputSig(part, f), a, reason: 'must be deterministic');

    f.distanceA = 7;
    expect(featureInputSig(part, f), isNot(a));
    f.distanceA = 5;
    expect(featureInputSig(part, f), a, reason: 'and reversible');

    f.taperDeg = 3;
    expect(featureInputSig(part, f), isNot(a));
    f.taperDeg = 0;
    f.visible = false;
    expect(featureInputSig(part, f), isNot(a));
  });
}
