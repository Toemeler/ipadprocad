// Every edit saves the part, and every save drew the gallery still again --
// also when nothing it shows had changed: a sketch edit in a heavy part
// (a 120-hole plate) spent ~110 ms of its ~200 ms redrawing the identical
// picture. The still is now drawn only when the bodies, their visibility or
// their paint changed since the one on disk.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

class _Kernel implements PartKernel {
  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid stub(double v) => KernelSolid(
      OcctMeshData(
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList(const [0, 1, 2]),
          Int32List.fromList(const [0]),
          Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) =>
      stub(height);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      stub(a.volume + b.volume);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = AppState.stillEngines;
  tearDown(() => AppState.stillEngines = original);

  test('a save that changes nothing on screen does not redraw the still',
      () async {
    var renders = 0;
    AppState.stillEngines = [
      (
        name: 'counting',
        render: ({
          required Map<String, dynamic> scene,
          required Map<String, dynamic> camera,
          required int width,
          required int height,
        }) async {
          renders++;
          return Uint8List.fromList([renders, renders, renders]);
        },
      ),
    ];
    final k = _Kernel();
    final app = AppState()..partKernel = k;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m492_');
    await app.createNamedPart('P');
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
        name: 'Extrusion1',
        bodyName: 'Solid1',
        sketchName: p.childSketches.last.model.name,
        profiles: [ProfileSel(10, 5, 200)],
        distanceA: 4)
      ..output = 'new'
      ..seq = p.nextSeq();
    p.appendFeature(f);
    recomputeAllFeatures(p, k);

    Future<List<int>?> save() async {
      p.dirty = true;
      await app.savePart('P');
      return readDocEntry(app.library['P']!.path, kPreviewEntry);
    }

    final first = await save();
    final drawn = renders;
    expect(drawn, greaterThan(0));
    expect(await save(), first);
    expect(await save(), first);
    expect(renders, drawn, reason: 'the same body: the still on disk is it');

    // Anything the still shows changes it: the body ...
    f.distanceA = 6;
    recomputeAllFeatures(p, k);
    expect(await save(), isNot(first));
    expect(renders, drawn + 1);
    // ... its paint ...
    p.bodyMaterials['Solid1'] = 'brass';
    await save();
    expect(renders, drawn + 2);
    // ... and whether it is shown at all.
    f.visible = false;
    await save();
    expect(readDocEntry(app.library['P']!.path, kPreviewEntry), isNull);
    f.visible = true;
    await save();
    expect(renders, drawn + 3);
  });
}
