// M400 — #26: "while i want to extrude to a face. i have no face highlight.
// i can select a face and it works but i dont have a highlight."
//
// The viewport pre-lights the planar face under the pointer, and the gate that
// decides whether to bother listed the two modes that existed when it was
// written:
//
//     if ((app.pickPlane || app.pickWorkGeometry) && region == null)
//
// The tap path grew a third — `pickingExtentFace`, the "To face" extent — and
// it takes its pick through the very same `_pickSolidFace`. So the face could
// be chosen and was never shown: a pick command with the lights off, which is
// the phrase M260 used about the last one of these.
//
// The fix is one getter both halves read, so what can be TAPPED as a planar
// face is exactly what pre-lights. These tests are on that getter, because the
// gate is the whole bug — the pick underneath it was always right.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart';

AppState appWithPart() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('m400');
  final p = PartModel('Part1');
  app.parts['Part1'] = p;
  app.curTab = 'Part1';
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  test('nothing armed, nothing pre-lights', () {
    final app = appWithPart();
    expect(app.pickingPlanarFace, isFalse);
  });

  test('the sketch-plane pick pre-lights, as it always did', () {
    final app = appWithPart()..pickPlane = true;
    expect(app.pickingPlanarFace, isTrue);
  });

  test('a work-feature pick pre-lights, as it always did', () {
    final app = appWithPart();
    app.workPlaneMethodArm = WorkPlaneMethod.auto;
    expect(app.pickWorkGeometry, isTrue);
    expect(app.pickingPlanarFace, isTrue);
  });

  test('THE REPORT: the "to face" extent pre-lights too', () {
    final app = appWithPart()..pickingExtentFace = true;
    // What the old gate answered, spelled out so the difference is on record:
    expect(app.pickPlane || app.pickWorkGeometry, isFalse,
        reason: 'neither of the two modes the gate knew about');
    expect(app.pickingPlanarFace, isTrue,
        reason: 'and yet the tap path picks a planar face here — '
            '_pickSolidFace, the same call the highlight uses');
  });

  test('and it stops when the pick is cancelled', () {
    final app = appWithPart()..pickingExtentFace = true;
    app.cancelPickExtentFace();
    expect(app.pickingExtentFace, isFalse);
    expect(app.pickingPlanarFace, isFalse,
        reason: 'a highlight that outlives its command is the mirror bug');
  });

  test('every mode that can tap a planar face is in the getter', () {
    // The guard against the next one drifting off: each of the three, alone,
    // must light the face.
    final each = <String, void Function(AppState)>{
      'pickPlane': (a) => a.pickPlane = true,
      'pickWorkGeometry': (a) => a.workAxisArm = WorkAxisMethod.throughTwoPoints,
      'pickingExtentFace': (a) => a.pickingExtentFace = true,
    };
    each.forEach((name, arm) {
      final app = appWithPart();
      expect(app.pickingPlanarFace, isFalse, reason: '$name: before');
      arm(app);
      expect(app.pickingPlanarFace, isTrue, reason: '$name: after');
    });
  });
}
