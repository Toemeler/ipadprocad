// M407 — the other half of #26.
//
// M400 fixed the gate: the face under the pointer pre-lights for every command
// that can TAP a planar face, the To-face extent included. It did not fix what
// stands in front of that gate.
//
// The gate is `pickingPlanarFace && region == null`, and `region` is the sketch
// PROFILE region under the pointer — computed whenever an extrude session is
// open with a sketch locked in, which is exactly the state the To-face pick
// runs in. So a ray landing inside a profile on that plane put the lights back
// out, over the body, next to the sketch being extruded: the reported bug, in
// the one place the pick is used.
//
// It also advertised a pick that cannot happen. The tap path tests
// pickingExtentFace FIRST and takes the face, so a region highlighting under
// the cursor was offering something the tap had already decided against.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

AppState appWithPart() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('m407');
  app.parts['Part1'] = PartModel('Part1');
  app.curTab = 'Part1';
  return app;
}

void main() {
  test('no dialog, no region hover', () {
    // Nothing to pick profiles for: the whole computation is skipped, as it
    // always has been.
    expect(appWithPart().hoveringProfileRegions, isFalse);
  });

  test('the extrude dialog hovers profile regions', () {
    final app = appWithPart()..openExtrude();
    expect(app.extrudeSession, isNotNull);
    expect(app.hoveringProfileRegions, isTrue);
  });

  test('but not while the To-face extent is the pick in hand', () {
    final app = appWithPart()..openExtrude();
    app.beginPickExtentFace();
    expect(app.pickingExtentFace, isTrue);
    expect(app.hoveringProfileRegions, isFalse,
        reason: 'a region here would put the face highlight out');
    // And the face IS what pre-lights instead — M400's half, which only works
    // because this one stopped competing with it.
    expect(app.pickingPlanarFace, isTrue);
  });

  test('and it comes back the moment that pick ends', () {
    final app = appWithPart()..openExtrude();
    app.beginPickExtentFace();
    app.cancelPickExtentFace();
    expect(app.hoveringProfileRegions, isTrue);
    expect(app.pickingPlanarFace, isFalse);
  });

  test('the two never both claim the pointer', () {
    // The invariant under both halves: whatever the tap would take is what
    // lights up, and never two things at once.
    final app = appWithPart()..openExtrude();
    for (final picking in [false, true, false]) {
      if (picking) {
        app.beginPickExtentFace();
      } else {
        app.cancelPickExtentFace();
      }
      expect(app.hoveringProfileRegions && app.pickingExtentFace, isFalse);
    }
  });
}
