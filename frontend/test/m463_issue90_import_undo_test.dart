// M463 (#90) — "a lot of different things went wrong".
//
// A STEP motor (Import1), a gear drawn on the motor's bottom face (Sketch1,
// Extrusion1 + Extrusion2 on Solid2) and a boss joined onto the motor
// (Extrusion3 on Solid1). The assistant deleted the gear; the user pressed
// Ctrl+Z; the gear came back and the motor did not:
//
//   * Import1 "no solid and no error" — the undo restore disposed every
//     solid and rebuilt from JSON, and an imported B-Rep is not in the JSON.
//     Extrusion3 went sick on the empty body.
//   * Sketch1 then lost the motor face it was anchored to, matched the bottom
//     of its OWN 1 mm extrusion instead, and walked 1 mm down on every
//     rebuild, y=0 to y=-16: the gear became a 25 mm pillar.
//   * Import1 was made first, so its seq was 0, and the load read 0 as
//     "absent" and renumbered it past every sketch — same seq as Extrusion3.
//   * Dragging End of Part above an import disposed its body for good.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

KernelSolid _stub(double v) => KernelSolid(
    OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
        Int32List.fromList(const [0]), Float64List(0)),
    v,
    null);

class _Kernel implements PartKernel {
  int stepReads = 0;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => '';

  @override
  List<KernelSolid> importStepSolids(String path) {
    stepReads++;
    return [_stub(42)];
  }

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      _stub(height);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      _stub(a.volume + b.volume);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// A part holding Import1 (from imports/motor.stp, which exists in the
/// document) and one ordinary extrusion on its own body.
Future<(AppState, _Kernel)> _app() async {
  final k = _Kernel();
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m463_');
  await app.createNamedPart('P');
  final stp = File('${app.stageDirForTest('P').path}/imports/motor.stp');
  stp.createSync(recursive: true);
  stp.writeAsStringSync('ISO-10303-21;');
  final p = app.currentPart!;
  p.appendFeature(ExtrudeFeature(
    name: 'Import1',
    bodyName: p.nextSolidName(),
    sketchName: '',
    profiles: const [],
    output: 'new',
  )
    ..imported = true
    ..importPath = 'imports/motor.stp'
    ..importIndex = 0
    ..solid = _stub(42)
    ..seq = p.nextSeq());
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
  p.appendFeature(ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: p.nextSolidName(),
      sketchName: p.childSketches.last.model.name,
      profiles: [ProfileSel(10, 5, 200)])
    ..output = 'new'
    ..seq = p.nextSeq());
  recomputeAllFeatures(p, k);
  return (app, k);
}

ExtrudeFeature _import(AppState app) =>
    app.currentPart!.features.firstWhere((f) => f.name == 'Import1')
        as ExtrudeFeature;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#90 — an undo keeps the imported body', () {
    test('undoing a delete of ANOTHER feature leaves the import intact',
        () async {
      final (app, k) = await _app();
      final body = _import(app).solid;
      expect(body, isNotNull);

      final p = app.currentPart!;
      await app
          .deleteFeature(p.features.firstWhere((f) => f.name == 'Extrusion1'));
      await app.undoPart();

      expect(p.features.map((f) => f.name), contains('Extrusion1'));
      final imp = _import(app);
      expect(imp.solid, isNotNull, reason: 'the motor must survive Ctrl+Z');
      expect(identical(imp.solid, body), isTrue,
          reason: 'the live B-Rep is handed over, not re-read');
      expect(imp.computeError, isNull);
      expect(k.stepReads, 0);

      await app.redoPart();
      expect(_import(app).solid, isNotNull, reason: 'and Ctrl+Shift+Z');
    });

    test('undoing the delete of the import itself re-reads its file', () async {
      final (app, k) = await _app();
      await app.deleteFeature(_import(app));
      expect(
          app.currentPart!.features.any((f) => f.name == 'Import1'), isFalse);

      await app.undoPart();
      final imp = _import(app);
      expect(imp.solid, isNotNull);
      expect(imp.computeError, isNull);
      expect(k.stepReads, 1);
    });
  });

  group('#90 — End of Part parks an imported body instead of disposing it', () {
    test('rolled back and forward, the import still has its solid', () async {
      final (app, k) = await _app();
      final p = app.currentPart!;
      final imp = _import(app);
      final body = imp.solid;

      imp.rolledBack = true;
      p.eopAfter = 0; // above everything
      recomputeAllFeatures(p, k, force: true);
      expect(imp.solid, isNull, reason: 'M128: a rolled-back row holds none');

      p.eopAfter = kEopAtEnd;
      recomputeAllFeatures(p, k, force: true);
      expect(identical(imp.solid, body), isTrue);
      expect(imp.computeError, isNull);
      expect(k.stepReads, 0);
    });

    test('an import with no solid says so instead of staying silent', () async {
      final (app, k) = await _app();
      final imp = _import(app);
      imp.disposeSolid();
      recomputeAllFeatures(app.currentPart!, k, force: true);
      expect(imp.computeError, isNotNull);
    });
  });

  group('#90 — a sketch never follows a face built from itself', () {
    // One planar face, normal -Y, 1 mm below the sketch: exactly what the
    // bottom of Sketch1's own 1 mm extrusion looked like to the matcher.
    KernelSolid faceBelow() {
      const a = 6.1319; // a right triangle of area ~18.8
      final pos = Float64List.fromList(
          [-a / 3, -1, -a / 3, 2 * a / 3, -1, -a / 3, -a / 3, -1, 2 * a / 3]);
      final info = Float64List(15)
        ..[0] = 0 // plane
        ..[5] = -1; // normal -Y
      return KernelSolid(
          OcctMeshData(pos, Float64List(9), Int32List.fromList([0, 1, 2]),
              Int32List.fromList(const [0]), Float64List(0),
              triFaces: Int32List.fromList([0]), faceInfos: info),
          1,
          null);
    }

    (PartModel, ChildSketch) part() {
      final p = PartModel('P');
      final s = ChildSketch(
          SketchModel('Sketch1'),
          'face',
          PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 0, 1),
              const Vec3(0, -1, 0), const Vec3(0, 0, 0)),
          true,
          false,
          0,
          SketchFaceSel.of(
              FaceRec(0, const Vec3(0, 0, 0), const Vec3(0, -1, 0), 18.8)));
      p.childSketches.add(s);
      return (p, s);
    }

    ExtrudeFeature ext(String name, String sketch) => ExtrudeFeature(
        name: name, bodyName: 'Solid2', sketchName: sketch, profiles: const [])
      ..solid = faceBelow();

    test("the sketch's own extrusion is not a face to follow", () {
      final (p, s) = part();
      p.features.add(ext('Extrusion1', 'Sketch1'));
      expect(reanchorFaceSketches(p), 0);
      expect(s.face!.origin.y, 0);
    });

    test('the same face on a feature BEFORE the consumer is followed', () {
      final (p, s) = part();
      p.features
        ..add(ext('Base', ''))
        ..add(ExtrudeFeature(
            name: 'Extrusion1',
            bodyName: 'Solid2',
            sketchName: 'Sketch1',
            profiles: const []));
      expect(reanchorFaceSketches(p), 1);
      expect(s.face!.origin.y, closeTo(-1, 1e-9));
    });
  });

  group('#90 — seq 0 is a position, not "absent"', () {
    test('the first feature keeps seq 0 across save and load', () {
      final p = PartModel('P');
      p.appendFeature(ExtrudeFeature(
          name: 'Import1',
          bodyName: 'Solid1',
          sketchName: '',
          profiles: const [])
        ..imported = true
        ..seq = p.nextSeq());
      p.appendFeature(ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid2',
          sketchName: 'Sketch1',
          profiles: const [])
        ..seq = p.nextSeq());
      // The undo restore attaches the sketches BEFORE loadJson, so the
      // migration saw Sketch2 at seq 4 and moved Import1 to 5.
      final q = PartModel('P')
        ..childSketches.add(ChildSketch(SketchModel('Sketch2'), 'xy'))
        ..childSketches.last.seq = 4;
      final j = p.toJson();
      j['sketches'] = [
        {'name': 'Sketch2', 'seq': 4}
      ];
      q.loadJson(j);
      expect(q.features.map((f) => f.seq).toList(), [0, 1]);
    });

    test('a pre-M91 feature with no seq at all is still numbered', () {
      final p = PartModel('P');
      p.appendFeature(ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: '',
          profiles: const []));
      final j = p.toJson();
      for (final f in j['features'] as List) {
        (f as Map).remove('seq');
      }
      j.remove('seqNext');
      final q = PartModel('P')..loadJson(j);
      expect(q.seqNext, greaterThan(q.features.single.seq));
    });
  });
}
