// #52 — "this is Not a clean design. the ribbon doesnt go to the top. the
// right bar on the ribbon looks awful and this is not a apple native
// Animation".
//
// Filed against build b49fc80, which is to say against #49's FIRST fix. Three
// complaints, and the animation is the one 5a1c0ff already answered
// (issue49_ribbon_edge_swipe_test pins it). These are the other two.
//
//   THE RIBBON DOESN'T GO TO THE TOP. The whole shell sits in a SafeArea, so
//   on a 390x844 phone the band began ~47 points down with a strip of ground
//   colour over it. On an iPad that inset is small enough that it never
//   showed. The inset now belongs to the STAGE — the floating chrome — and
//   the band takes the window's real top edge, which is M389's answer to the
//   identical shape on Windows.
//
//   THE RIGHT BAR LOOKS AWFUL. It was an 18 pt slab of T.hover6 running the
//   FULL HEIGHT of the screen beside the band. What is drawn now is one 4x36
//   grabber, centred, on nothing — while the 18 pt HIT TARGET is unchanged,
//   which is why `grabberIsNotABar` measures the paint and `handleIsStillHittable`
//   measures the touch area separately. A test that only looked at the strip
//   would have passed before and after.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/device_class.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _phone = Size(393, 852);

/// What an iPhone with an island reserves at the top. The number the report
/// was looking at.
const double _statusBar = 47;

const Key _stageKey = Key('stage');

AppState _document() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('issue52');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Mounted as main.dart mounts it, with the status bar's inset still in the
/// MediaQuery — which is the point: main.dart hands a phone the real top edge
/// (`SafeArea(top: !isPhoneDevice())`) and this widget re-applies the inset to
/// the stage. Here the inset arrives unconsumed, exactly as it would there.
Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(_phone);
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: _phone,
        padding: EdgeInsets.only(top: _statusBar),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: RibbonRetract.retracted,
        builder: (_, __, ___) => RibbonDockLayout(
          app: app,
          stage: const SizedBox.expand(key: _stageKey),
          bleed: const SizedBox.expand(),
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUp(() {
    isPhoneOverride = true;
    RibbonRetract.resetForTest();
    RibbonDock.resetForTest();
    RibbonSurface.glassOverride = false;
  });
  tearDown(() {
    isPhoneOverride = null;
    RibbonRetract.resetForTest();
    RibbonDock.resetForTest();
    RibbonSurface.glassOverride = null;
  });

  testWidgets('the band reaches the top of the screen', (t) async {
    RibbonRetract.set(false); // out, which is when you can see where it starts
    await _pump(t, _document());

    expect(t.getTopLeft(find.byKey(kRibbonBandSlot)).dy, 0,
        reason: 'no strip of ground colour over the ribbon any more');
    expect(t.getSize(find.byKey(kRibbonBandSlot)).height, _phone.height,
        reason: 'and it runs the whole height, as it does on an iPad');
  });

  testWidgets('...and the floating chrome still clears the status bar',
      (t) async {
    RibbonRetract.set(false);
    await _pump(t, _document());

    // The inset did not vanish, it MOVED. The browser, the tab bar and the
    // quick tools all live in the stage; none of them may sit under the clock.
    expect(t.getTopLeft(find.byKey(_stageKey)).dy, _statusBar);
  });

  testWidgets('the handle draws a grabber, not a bar down the screen',
      (t) async {
    RibbonRetract.set(false);
    await _pump(t, _document());

    final grab = t.getSize(find.byKey(kRibbonGrabber));
    expect(grab.height, lessThan(_phone.height / 4),
        reason: 'an 18x852 slab beside the band is what was reported');
    expect(grab.height, 36);
    expect(grab.width, 4);
  });

  testWidgets('the handle is still 18 points of hit target', (t) async {
    RibbonRetract.set(false);
    await _pump(t, _document());

    // The paint shrank; the touch area did not. A grabber you cannot reliably
    // hit would be a worse answer than the bar it replaced — so this is
    // measured on the strip, not on the pill inside it.
    final band = t.getSize(find.byKey(kRibbonBandSlot)).width;
    await t.tapAt(Offset(band + 9, _phone.height / 2));
    await t.pumpAndSettle();
    expect(RibbonRetract.on, isTrue, reason: 'tapped beside the band: away');
  });

  testWidgets('dragging the handle back to the edge puts the band away',
      (t) async {
    RibbonRetract.set(false);
    await _pump(t, _document());
    final band = t.getSize(find.byKey(kRibbonBandSlot)).width;

    // The same gesture that opens it from the screen edge, run backwards —
    // and it must track on the way, not wait for the finger to lift.
    final g = await t.startGesture(Offset(band + 9, 400));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-8, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(t.getSize(find.byKey(kRibbonBandSlot)).width, lessThan(band),
        reason: 'the band follows the thumb back in');

    await g.up();
    await t.pumpAndSettle();
    expect(RibbonRetract.on, isTrue);
  });

  testWidgets('an iPad keeps the inset it has always had', (t) async {
    isPhoneOverride = false;
    await _pump(t, _document());

    // Off a phone this widget applies nothing: main.dart's SafeArea is still
    // the thing that insets the shell, so the stage starts where the box it
    // was handed starts.
    expect(t.getTopLeft(find.byKey(_stageKey)).dy, 0);
    expect(find.byKey(kRibbonGrabber), findsNothing,
        reason: 'and there is no handle, because there is no retract here');
  });
}
