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

import 'm56_part_test.dart' show FakeKernel;

/// A part with one finished sketch holding a closed profile — which is what
/// `openExtrude` requires before it will open at all ("Zuerst eine 2D-Skizze
/// anlegen"), and therefore what any test of the dialog's picks needs.
Future<AppState> appWithProfile() async {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('m407_');
  app.partKernel = FakeKernel();
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  final sk = app.activeChild!;
  sk.engine.setCurrentLayer(app.editingLayer!);
  sk.engine.addCircle(0, 0, 15);
  sk.refresh();
  app.finishPartSketch();
  return app;
}

void main() {
  test('no dialog, no region hover', () async {
    // Nothing to pick profiles for: the whole computation is skipped, as it
    // always has been.
    final app = await appWithProfile();
    expect(app.extrudeSession, isNull);
    expect(app.hoveringProfileRegions, isFalse);
  });

  test('the extrude dialog hovers profile regions', () async {
    final app = await appWithProfile();
    app.openExtrude();
    expect(app.extrudeSession, isNotNull);
    expect(app.hoveringProfileRegions, isTrue);
  });

  test('but not while the To-face extent is the pick in hand', () async {
    final app = await appWithProfile();
    app.openExtrude();
    app.beginPickExtentFace();
    expect(app.pickingExtentFace, isTrue);
    expect(app.hoveringProfileRegions, isFalse,
        reason: 'a region here would put the face highlight out');
    // And the face IS what pre-lights instead — M400's half, which only works
    // because this one stopped competing with it.
    expect(app.pickingPlanarFace, isTrue);
  });

  test('and it comes back the moment that pick ends', () async {
    final app = await appWithProfile();
    app.openExtrude();
    app.beginPickExtentFace();
    app.cancelPickExtentFace();
    expect(app.hoveringProfileRegions, isTrue);
    expect(app.pickingPlanarFace, isFalse);
  });

  test('the two never both claim the pointer', () async {
    // The invariant under both halves: whatever the tap would take is what
    // lights up, and never two things at once.
    final app = await appWithProfile();
    app.openExtrude();
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
