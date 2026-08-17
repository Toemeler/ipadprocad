// M230 — a 3D panel must not outlive the model it points at.
//
// Found by looking rather than by a report, the same way M226's two were. Every
// 3D session holds references INTO a part: a sketch name, a body name, a frame
// lifted off a face, a list of placements. Four places in this file are moments
// when that part is about to be replaced or left behind — going home, closing a
// tab, deleting a part, restoring an undo snapshot — and all four cancelled
// `cancelExtrude()` alone.
//
// That was right when the extrude session was the only one. It has been quietly
// wrong since M136 added the fillet panel, and this session added four more
// (M212's patterns, M225's hole, M227's combine, M228's split). Open a hole in
// part A, go home, open part B: the panel came back, pointing at A's sketch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart' show WorkAxisMethod;

import 'm56_part_test.dart' show FakeKernel, addRectLines;

Future<AppState> _app() async {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m230_');
  return app;
}

/// A part with one built body and a sketch carrying a point.
Future<void> _buildPart(AppState app, String name) async {
  await app.createNamedPart(name);
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
  app.finishPartSketch();
  final p = app.currentPart!;
  final f = ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: p.childSketches.single.model.name,
    profiles: [ProfileSel(20, 15, 1200)],
    distanceA: 12,
  )..output = 'new';
  f.seq = p.nextSeq();
  p.appendFeature(f);
  recomputeAllFeatures(p, app.partKernel);
}

/// Every 3D session flag, as one answer.
bool _anyOpen(AppState app) =>
    app.extrudeSession != null ||
    app.edgeSession != null ||
    app.patternSession != null ||
    app.holeSession != null ||
    app.combineSession != null ||
    app.splitSession != null ||
    app.workPlaneMethodArm != null ||
    app.workAxisArm != null ||
    app.workPointArm != null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M230 — going home closes them', () {
    test('the hole panel does not follow you to the gallery', () async {
      final app = await _app();
      await _buildPart(app, 'A');
      app.openHole();
      expect(app.holeSession, isNotNull);

      app.goHome();
      expect(app.holeSession, isNull,
          reason: 'it holds a sketch name from a part that is no longer open');
      expect(_anyOpen(app), isFalse);
    });

    test('so do the others', () async {
      final app = await _app();
      await _buildPart(app, 'A');
      app.openFillet();
      expect(app.edgeSession, isNotNull);
      app.goHome();
      expect(app.edgeSession, isNull);

      // ... and a work-feature command, which arms a PICK rather than a panel.
      await _buildPart(app, 'B');
      app.startWorkAxis(WorkAxisMethod.throughTwoPoints);
      expect(app.workAxisArm, isNotNull);
      app.goHome();
      expect(app.workAxisArm, isNull);
    });
  });

  group('M230 — and so does leaving the part behind', () {
    test('closing the tab', () async {
      final app = await _app();
      await _buildPart(app, 'A');
      app.openSplit();
      expect(app.splitSession, isNotNull);
      await app.closeTab('A');
      expect(_anyOpen(app), isFalse);
      expect(app.pickPlane, isFalse,
          reason: "and the split's plane pick goes with it");
    });

    test('deleting the part', () async {
      final app = await _app();
      await _buildPart(app, 'A');
      app.openHole();
      await app.deletePart('A');
      expect(_anyOpen(app), isFalse);
    });
  });

  group('M230 — an undo replaces the model under them', () {
    test('a panel open across an undo is cancelled, not left pointing', () async {
      final app = await _app();
      await _buildPart(app, 'A');
      final p = app.currentPart!;
      // A second body, so Combine has something to work with...
      final second = ExtrudeFeature(
        name: 'Extrusion2',
        bodyName: 'Solid2',
        sketchName: p.childSketches.single.model.name,
        profiles: [ProfileSel(20, 15, 1200)],
      )..output = 'new';
      second.seq = p.nextSeq();
      p.appendFeature(second);
      recomputeAllFeatures(p, app.partKernel);
      expect(p.bodyNames.length, 2);

      // ... and something UNDOABLE: deleting a feature checkpoints first.
      await app.deleteFeature(second);
      expect(p.bodyNames.length, 1);

      app.openHole();
      expect(app.holeSession, isNotNull);

      await app.undoPart();
      expect(app.holeSession, isNull,
          reason: 'the model it pointed into was just replaced wholesale');
      expect(_anyOpen(app), isFalse);
    });
  });
}
