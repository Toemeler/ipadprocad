// M465 — a feature's stored RESULT (Inventor's model of a part).
//
// A part converted from Inventor carries the exact body Inventor built, and
// must show THAT until something in its tree changes — this kernel cannot
// reproduce every Inventor blend, so rebuilding on open would show a body
// Inventor never made. The contract:
//   * a valid result stands in for every feature before it on its body, which
//     are not computed at all;
//   * a converter writes the key '*', and the first fold adopts the real one;
//   * any edit upstream changes the key: the result is dropped for good and
//     the tree is rebuilt like any other;
//   * the result round-trips through the document.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

class _Kernel implements PartKernel {
  int extrudes = 0;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid stub(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return stub(height);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      stub(a.volume + b.volume);

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) =>
      stub(a.volume - b.volume);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<AppState> _app(int n, _Kernel k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m465_');
  await app.createNamedPart('P');
  for (var i = 1; i <= n; i++) {
    app.startPartSketch();
    app.planePicked('xy');
    final s = app.activeChild!;
    s.engine.setCurrentLayer(app.editingLayer!);
    s.engine.addLine(0, 0, 20, 0);
    s.engine.addLine(20, 0, 20, 10);
    s.engine.addLine(20, 10, 0, 10);
    s.engine.addLine(0, 10, 0, 0);
    s.refresh();
    app.finishPartSketch();
    final p = app.currentPart!;
    final f = ExtrudeFeature(
        name: 'Extrusion$i',
        bodyName: 'Solid1',
        sketchName: p.childSketches.last.model.name,
        profiles: [ProfileSel(10, 5, 200)],
        distanceA: i.toDouble());
    f.output = i == 1 ? 'new' : 'join';
    f.seq = p.nextSeq();
    p.appendFeature(f);
  }
  recomputeAllFeatures(app.currentPart!, app.partKernel);
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a valid stored result IS the body, and covers what came before', () async {
    final k = _Kernel();
    final app = await _app(3, k);
    final p = app.currentPart!;
    final last = p.features[2];
    last.resultCache = ResultCache(step: 'inventor/result.step', index: 0, sig: '*')
      ..solid = k.stub(999);
    final before = k.extrudes;

    recomputeAllFeatures(p, k, force: true);

    expect(k.extrudes, before, reason: 'nothing the result covers is computed');
    expect(last.solid!.volume, 999, reason: 'the stored result is the body');
    expect(p.features[0].solid, isNull);
    expect(p.features[1].solid, isNull);
    expect(p.features.every((f) => f.computeError == null), isTrue,
        reason: 'covered features are not failures');
    expect(last.resultCache!.sig, isNot('*'),
        reason: 'the first fold adopts its own key');

    // A second rebuild with nothing changed keeps using it.
    recomputeAllFeatures(p, k, force: true);
    expect(last.solid!.volume, 999);
    expect(last.resultCache, isNotNull);
  });

  test('an edit upstream drops the result for good and rebuilds', () async {
    final k = _Kernel();
    final app = await _app(3, k);
    final p = app.currentPart!;
    final last = p.features[2];
    last.resultCache = ResultCache(step: 's.step', index: 0, sig: '*')
      ..solid = k.stub(999);
    recomputeAllFeatures(p, k, force: true);
    expect(last.solid!.volume, 999);

    (p.features[1] as ExtrudeFeature).distanceA = 7;
    recomputeAllFeatures(p, k, force: true);

    expect(last.resultCache, isNull, reason: 'the result no longer describes the part');
    expect(last.solid!.volume, 1 + 7 + 3, reason: 'the tree is rebuilt here');
  });

  test('a result keyed to another tree is not used', () async {
    final k = _Kernel();
    final app = await _app(2, k);
    final p = app.currentPart!;
    p.features[1].resultCache = ResultCache(step: 's.step', index: 0, sig: 'not-this-tree')
      ..solid = k.stub(999);
    recomputeAllFeatures(p, k, force: true);
    expect(p.features[1].solid!.volume, 1 + 2);
    expect(p.features[1].resultCache, isNull);
  });

  test('the result round-trips through the document', () async {
    final k = _Kernel();
    final app = await _app(1, k);
    final f = app.currentPart!.features[0] as ExtrudeFeature;
    f.resultCache = ResultCache(step: 'inventor/result.step', index: 1, sig: 'abc');
    final j = f.toJson();
    expect(j['cache'], {'step': 'inventor/result.step', 'index': 1, 'sig': 'abc'});
    final back = PartFeature.fromJson(j)!;
    expect(back.resultCache!.step, 'inventor/result.step');
    expect(back.resultCache!.index, 1);
    expect(back.resultCache!.sig, 'abc');
    // absent stays absent: an ordinary part writes what it always wrote
    f.resultCache = null;
    expect(f.toJson().containsKey('cache'), isFalse);
  });
}
