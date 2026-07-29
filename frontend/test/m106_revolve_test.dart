// M106 — Revolve: the shared session, the axis pick, validation and commit.
//
// End to end through AppState with a recording fake kernel, so what actually
// reaches the kernel (sweep angle, axis, placement) is asserted rather than
// assumed. This is the milestone that shipped without tests; it has them now.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// Records what the revolve path hands the kernel.
class RecordingKernel implements PartKernel {
  bool fail = false;
  int revolves = 0;
  double? lastAngle, lastAxPx, lastAxPy, lastAxDx, lastAxDy;
  List<double>? lastMat;
  List<List<List<Offset>>>? lastGroups;

  @override
  bool get available => true;
  @override
  String get info => 'recording';
  @override
  String get lastError => 'recording failure';

  KernelSolid _stub(double v) => KernelSolid(
      OcctMeshData(
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList(const [0, 1, 2]),
          Int32List.fromList(const [0, 3]),
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      v,
      null);

  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
      double axPx, double axPy, double axDx, double axDy, List<double> mat34) {
    if (fail) return null;
    revolves++;
    lastGroups = groups;
    lastAngle = angleDeg;
    lastAxPx = axPx;
    lastAxPy = axPy;
    lastAxDx = axDx;
    lastAxDy = axDy;
    lastMat = mat34;
    return _stub(angleDeg);
  }

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      fail ? null : _stub(height);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m106_');
  return app;
}

void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A part with one XY sketch holding a rectangle from (5,0) to (15,10).
/// Its LAST line — index 3 — is the left edge (5,10)->(5,0), a vertical line
/// the profile only touches, which is a legal axis (a shaft revolved about
/// its own edge).
Future<AppState> partWithRect(RecordingKernel k) async {
  final app = makeApp();
  app.partKernel = k;
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 5, 0, 15, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  return app;
}

const int kAxisLine = 3; // the (5,10)->(5,0) edge

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opening', () {
    test('openRevolve switches the shared session to revolve defaults',
        () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      final s = app.extrudeSession!;
      expect(s.kind, 'revolve');
      expect(s.isRevolve, isTrue);
      expect(s.full, isTrue, reason: 'Inventor opens Revolve on a full turn');
      expect(s.exprA, '360.00 deg');
      expect(s.axisPicked, isFalse);
      expect(s.profiles.length, 1, reason: 'the single profile pre-selects');
    });

    test('Extrude and Revolve cannot both be open', () async {
      final app = await partWithRect(RecordingKernel());
      app.openExtrude();
      expect(app.extrudeSession!.isRevolve, isFalse);
      app.openRevolve();
      expect(app.extrudeSession!.isRevolve, isTrue,
          reason: 'one session object, switched in place');
    });
  });

  group('axis pick', () {
    test('a sketch line becomes a point + direction in sketch coords',
        () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      final s = app.extrudeSession!;
      expect(s.axisPicked, isTrue);
      expect(s.axPx, 5);
      expect(s.axPy, 10);
      expect(s.axDx, 0, reason: 'a vertical line has no x component');
      expect(s.axDy, -10);
      expect(app.pickingRevolveAxis, isFalse, reason: 'the pick disarms');
    });

    test('an out-of-range index is refused, not stored', () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, 99);
      expect(app.extrudeSession!.axisPicked, isFalse);
    });

    test('an unknown sketch is refused', () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      app.revolveAxisPicked('NoSuchSketch', 0);
      expect(app.extrudeSession!.axisPicked, isFalse);
    });
  });

  group('validation', () {
    test('no axis means no feature', () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
    });

    test('an angle over 360 is refused', () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      app.setExtrude(full: false, exprA: '400 deg');
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
    });

    test('asymmetric A + B cannot exceed a full turn', () async {
      final app = await partWithRect(RecordingKernel());
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      app.setExtrude(
          full: false,
          exprA: '300 deg',
          exprB: '100 deg',
          direction: ExtrudeDirection.asymmetric);
      expect(await app.applyExtrude(), isFalse);
    });
  });

  group('what reaches the kernel', () {
    Future<(AppState, RecordingKernel)> armed() async {
      final k = RecordingKernel();
      final app = await partWithRect(k);
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      return (app, k);
    }

    test('Full sends exactly 360 and the picked axis', () async {
      final (app, k) = await armed();
      expect(await app.applyExtrude(), isTrue);
      expect(k.revolves, greaterThan(0));
      expect(k.lastAngle, 360);
      expect(k.lastAxPx, 5);
      expect(k.lastAxPy, 10);
      expect(k.lastAxDx, 0);
      expect(k.lastAxDy, -10);
    });

    test('Full overrides a typed angle', () async {
      final (app, k) = await armed();
      app.setExtrude(exprA: '90 deg'); // full is still on
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastAngle, 360);
    });

    test('a partial turn sends the typed angle', () async {
      final (app, k) = await armed();
      app.setExtrude(full: false, exprA: '90 deg');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastAngle, 90);
    });

    test('symmetric sweeps Angle A, starting half a turn back', () async {
      final (app, k) = await armed();
      app.setExtrude(
          full: false,
          exprA: '90 deg',
          direction: ExtrudeDirection.symmetric);
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastAngle, 90);
      // the -45 deg start offset rides in the placement, so the matrix must
      // NOT be the plain frame transform
      expect(k.lastMat, isNot(planeFrame('xy').mat34(0)));
      expect(k.lastMat,
          planeFrame('xy').mat34Rotated(5, 10, 0, -10, -45));
    });

    test('a full turn needs no rotation in the placement', () async {
      final (app, k) = await armed();
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastMat, planeFrame('xy').mat34(0));
    });

    test('asymmetric sums A and B and starts at -B', () async {
      final (app, k) = await armed();
      app.setExtrude(
          full: false,
          exprA: '90 deg',
          exprB: '30 deg',
          direction: ExtrudeDirection.asymmetric);
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastAngle, 120);
      expect(k.lastMat,
          planeFrame('xy').mat34Rotated(5, 10, 0, -10, -30));
    });
  });

  group('commit', () {
    test('the committed feature is a RevolveFeature named Revolution1',
        () async {
      final k = RecordingKernel();
      final app = await partWithRect(k);
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      expect(await app.applyExtrude(), isTrue);
      final f = app.currentPart!.features.single;
      expect(f, isA<RevolveFeature>());
      expect(f.name, 'Revolution1');
      expect(f.kind, 'revolve');
      expect((f as RevolveFeature).full, isTrue);
      expect(f.axPx, 5);
      expect(f.solid, isNotNull);
    });

    test('editFeature reopens the revolve panel, not the extrude one',
        () async {
      final k = RecordingKernel();
      final app = await partWithRect(k);
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      await app.applyExtrude();
      final f = app.currentPart!.features.single;
      app.editFeature(f);
      final s = app.extrudeSession!;
      expect(s.isRevolve, isTrue);
      expect(s.editing, same(f));
      expect(s.axisPicked, isTrue, reason: 'the stored axis comes back');
      expect(s.axPx, 5);
    });

    test('editing REPLACES the feature instead of adding a second', () async {
      final k = RecordingKernel();
      final app = await partWithRect(k);
      app.openRevolve();
      final name = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(name, kAxisLine);
      await app.applyExtrude();
      expect(app.currentPart!.features.length, 1);
      final seq = app.currentPart!.features.single.seq;

      app.editFeature(app.currentPart!.features.single);
      app.setExtrude(full: false, exprA: '120 deg');
      expect(await app.applyExtrude(), isTrue);

      expect(app.currentPart!.features.length, 1,
          reason: 'an edit must not duplicate the feature');
      final f = app.currentPart!.features.single as RevolveFeature;
      expect(f.name, 'Revolution1', reason: 'the name is kept');
      expect(f.seq, seq, reason: 'and its place on the timeline');
      expect(f.angleA, 120);
      expect(k.lastAngle, 120);
    });
  });
}
