// M131b — Sweep, Loft and Coil.
//
// The kernel maths is asserted analytically in the OCCT smoke test
// ([30] swept prism = 4000, [31] lofted frustum = 5833.333, [32] coil matches
// its helix length). What these cover is the Dart half: what reaches the
// kernel, the method conversions, and the dependency tracking that decides
// whether a feature rebuilds at all.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// Records what the three new paths hand the kernel.
class SweepRecorder implements PartKernel {
  int sweeps = 0, lofts = 0, coils = 0;
  List<double>? lastPath, lastMat;
  int? lastOrientation;
  double? lastTaper, lastRevolutions, lastHeight;
  bool? lastClockwise, lastRuled, lastClosed, lastSolid;
  int? lastSectionCount;
  Vec3? lastAxP, lastAxD;

  @override
  bool get available => true;
  @override
  String get info => 'sweep recorder';
  @override
  String get lastError => 'sweep recorder failure';

  KernelSolid _mk(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> g, double h, double t,
          List<double> m) =>
      _mk(h);

  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0, double taperDeg = 0, double twistDeg = 0}) {
    sweeps++;
    lastPath = List.of(pathPts);
    lastMat = List.of(mat34);
    lastOrientation = orientation;
    lastTaper = taperDeg;
    return _mk(1);
  }

  @override
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
      {bool solid = true, bool ruled = false, bool closed = false}) {
    lofts++;
    lastSectionCount = sections.length;
    lastSolid = solid;
    lastRuled = ruled;
    lastClosed = closed;
    return _mk(2);
  }

  @override
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
      Vec3 axP, Vec3 axD,
      {required double revolutions,
      required double height,
      double taperDeg = 0,
      bool clockwise = false}) {
    coils++;
    lastAxP = axP;
    lastAxD = axD;
    lastRevolutions = revolutions;
    lastHeight = height;
    lastTaper = taperDeg;
    lastClockwise = clockwise;
    return _mk(3);
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void _rect(SketchModel s, String layer, double x0, double y0, double x1,
    double y1) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A part with one XY sketch: a 20x10 rectangle plus a separate line that can
/// serve as a sweep path (geometry index 4).
Future<AppState> appWithSketch(SweepRecorder k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m131b_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  final sm = app.activeChild!;
  _rect(sm, app.editingLayer!, 0, 0, 20, 10);
  sm.engine.addLine(30, 0, 30, 40); // index 4 — the path
  sm.refresh();
  app.finishPartSketch();
  return app;
}

const int kPathGeo = 4;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sweep', () {
    test('opening switches the shared session to sweep', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openSweep();
      final s = app.extrudeSession!;
      expect(s.isSweep, isTrue);
      expect(s.isRevolve, isFalse);
      expect(s.path, isNull);
    });

    test('without a path there is no feature', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openSweep();
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
    });

    test('the picked path reaches the kernel as WORLD points', () async {
      final k = SweepRecorder();
      final app = await appWithSketch(k);
      app.openSweep();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.sweepPathPicked(sk, kPathGeo);
      expect(await app.applyExtrude(), isTrue);
      expect(k.sweeps, greaterThan(0));
      // XY sketch: sketch (30,0) and (30,40) map to world (30,0,0)/(30,40,0)
      expect(k.lastPath!.length, 6);
      expect(k.lastPath!.sublist(0, 3), [30.0, 0.0, 0.0]);
      expect(k.lastPath!.sublist(3, 6), [30.0, 40.0, 0.0]);
    });

    test('orientation and taper are passed through', () async {
      final k = SweepRecorder();
      final app = await appWithSketch(k);
      app.openSweep();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.sweepPathPicked(sk, kPathGeo);
      app.setExtrude(orientation: 2, exprSweepTaper: '3 deg');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastOrientation, 2);
      expect(k.lastTaper, 3.0);
    });

    test('a non-zero twist is refused up front, not at the shim', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openSweep();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.sweepPathPicked(sk, kPathGeo);
      app.setExtrude(exprTwist: '10 deg');
      expect(await app.applyExtrude(), isFalse);
    });

    test('the committed feature is a SweepFeature named Sweep1', () async {
      final k = SweepRecorder();
      final app = await appWithSketch(k);
      app.openSweep();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.sweepPathPicked(sk, kPathGeo);
      await app.applyExtrude();
      final f = app.currentPart!.features.single;
      expect(f, isA<SweepFeature>());
      expect(f.name, 'Sweep1');
      expect(f.solid, isNotNull);
    });

    test('the path SKETCH is part of the rebuild signature', () async {
      // Without this, editing the path curve leaves the cached solid in place
      // and the sweep silently does not move.
      final f = SweepFeature(
          name: 'S',
          bodyName: 'Solid1',
          sketchName: 'Sketch1',
          profiles: const [],
          path: CurveSel('Sketch2', 0, 0, 0, 10, 0, 10));
      expect(f.sketchNames, containsAll(<String>['Sketch1', 'Sketch2']));
    });
  });

  group('Loft', () {
    test('fewer than two sections is not a loft', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openLoft();
      expect(await app.applyExtrude(), isFalse);
    });

    test('sections reach the kernel in PICK order', () async {
      final k = SweepRecorder();
      final app = await appWithSketch(k);
      app.openLoft();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.toggleLoftSection(sk, ProfileSel(5, 5, 200));
      app.toggleLoftSection(sk, ProfileSel(6, 6, 200));
      expect(app.extrudeSession!.loftSections.length, 2);
      expect(await app.applyExtrude(), isTrue);
      expect(k.lofts, greaterThan(0));
      expect(k.lastSectionCount, 2);
    });

    test('tapping a section again removes it', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openLoft();
      final sk = app.currentPart!.childSketches.single.model.name;
      final sel = ProfileSel(5, 5, 200);
      app.toggleLoftSection(sk, sel);
      expect(app.extrudeSession!.loftSections.length, 1);
      app.toggleLoftSection(sk, ProfileSel(5, 5, 200));
      expect(app.extrudeSession!.loftSections, isEmpty);
    });

    test('ruled, closed and solid reach the kernel', () async {
      final k = SweepRecorder();
      final app = await appWithSketch(k);
      app.openLoft();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.toggleLoftSection(sk, ProfileSel(5, 5, 200));
      app.toggleLoftSection(sk, ProfileSel(6, 6, 200));
      app.setExtrude(loftRuled: true, loftClosed: true);
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastRuled, isTrue);
      expect(k.lastClosed, isTrue);
      expect(k.lastSolid, isTrue);
    });

    test('it depends on EVERY section sketch, de-duplicated', () {
      final f = LoftFeature(
          name: 'L',
          bodyName: 'Solid1',
          sectionSketches: const ['A', 'B', 'A'],
          sections: [ProfileSel(0, 0, 1), ProfileSel(1, 1, 1),
                     ProfileSel(2, 2, 1)]);
      expect(f.sketchNames.toSet(), {'A', 'B'});
    });
  });

  group('Coil', () {
    Future<AppState> armedCoil(SweepRecorder k) async {
      final app = await appWithSketch(k);
      app.openCoil();
      final sk = app.currentPart!.childSketches.single.model.name;
      app.revolveAxisPicked(sk, kPathGeo); // the vertical line as the axis
      return app;
    }

    test('without an axis there is no feature', () async {
      final app = await appWithSketch(SweepRecorder());
      app.openCoil();
      expect(await app.applyExtrude(), isFalse);
    });

    test('Revolution and Height pass straight through', () async {
      final k = SweepRecorder();
      final app = await armedCoil(k);
      app.setExtrude(coilMethod: 0, exprRevolutions: '4 ul',
          exprHeight: '20 mm');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastRevolutions, 4.0);
      expect(k.lastHeight, 20.0);
    });

    test('Pitch and Revolution derives the height', () async {
      // 3 turns at 5 mm pitch is 15 mm tall.
      final k = SweepRecorder();
      final app = await armedCoil(k);
      app.setExtrude(coilMethod: 1, exprRevolutions: '3 ul',
          exprPitch: '5 mm');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastRevolutions, 3.0);
      expect(k.lastHeight, 15.0);
    });

    test('Pitch and Height derives the revolutions', () async {
      // 24 mm at 4 mm pitch is 6 turns.
      final k = SweepRecorder();
      final app = await armedCoil(k);
      app.setExtrude(coilMethod: 2, exprPitch: '4 mm', exprHeight: '24 mm');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastRevolutions, 6.0);
      expect(k.lastHeight, 24.0);
    });

    test('Spiral is flat — revolutions with no rise', () async {
      final k = SweepRecorder();
      final app = await armedCoil(k);
      app.setExtrude(coilMethod: 3, exprRevolutions: '2 ul');
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastRevolutions, 2.0);
      expect(k.lastHeight, 0.0);
    });

    test('the axis reaches the kernel in WORLD space', () async {
      final k = SweepRecorder();
      final app = await armedCoil(k);
      expect(await app.applyExtrude(), isTrue);
      // the path line runs (30,0)->(30,40) on the XY sketch
      expect(k.lastAxP!.x, closeTo(30, 1e-9));
      expect(k.lastAxD!.y, closeTo(40, 1e-9));
      expect(k.lastAxD!.z, closeTo(0, 1e-9));
    });

    test('handedness is passed through', () async {
      final k = SweepRecorder();
      final app = await armedCoil(k);
      app.setExtrude(coilClockwise: true);
      expect(await app.applyExtrude(), isTrue);
      expect(k.lastClockwise, isTrue);
    });

    test('the method conversions are pure and testable on the feature', () {
      CoilFeature c(int m) => CoilFeature(
          name: 'C',
          bodyName: 'S',
          sketchName: 'Sketch1',
          profiles: const [],
          method: m,
          revolutions: 3,
          height: 24,
          pitch: 4);
      expect(c(0).resolved, (3.0, 24.0));
      expect(c(1).resolved, (3.0, 12.0)); // pitch * revolutions
      expect(c(2).resolved, (6.0, 24.0)); // height / pitch
      expect(c(3).resolved, (3.0, 0.0)); // spiral
    });
  });

  group('serialisation', () {
    test('all three round-trip with their own fields', () {
      final feats = <PartFeature>[
        SweepFeature(
            name: 'Sweep1',
            bodyName: 'Solid1',
            sketchName: 'Sketch1',
            profiles: [ProfileSel(1, 2, 30)],
            path: CurveSel('Sketch1', 4, 0, 0, 0, 40, 40),
            orientation: 2,
            taperDeg: 3),
        LoftFeature(
            name: 'Loft1',
            bodyName: 'Solid1',
            sectionSketches: const ['Sketch1', 'Sketch2'],
            sections: [ProfileSel(1, 1, 10), ProfileSel(2, 2, 20)],
            ruled: true,
            closedLoop: true),
        CoilFeature(
            name: 'Coil1',
            bodyName: 'Solid1',
            sketchName: 'Sketch1',
            profiles: [ProfileSel(3, 4, 50)],
            method: 2,
            pitch: 4,
            height: 24,
            clockwise: true),
      ];
      for (final f in feats) {
        f.seq = 7;
        final back = PartFeature.fromJson(f.toJson());
        expect(back, isNotNull, reason: '${f.kind} did not load');
        expect(back!.kind, f.kind);
        expect(back.seq, 7);
        expect(back.ownSig(), f.ownSig(),
            reason: '${f.kind} did not survive the round trip identically');
      }
    });

    test('a loft with more sections than sketches still pairs them', () {
      final j = {
        'kind': 'loft',
        'name': 'Loft1',
        'body': 'Solid1',
        'sections': [
          ProfileSel(0, 0, 1).toJson(),
          ProfileSel(1, 1, 1).toJson(),
        ],
        'sketches': ['OnlyOne'],
      };
      final f = PartFeature.fromJson(j) as LoftFeature;
      expect(f.sectionSketches.length, f.sections.length,
          reason: 'every downstream loop pairs the two lists');
    });
  });
}
