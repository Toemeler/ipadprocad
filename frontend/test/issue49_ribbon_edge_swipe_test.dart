// #49 — "if the ribbon is retracted on ios there shouldbt be this Vertical
// bar. and it should only come expand when I swipe right from the left edge
// with a clean native Apple style animation".
//
// The report is three claims, and the first fix for it only answered one:
//
//   1. retracted, there is no bar. It painted nothing after that fix — but
//      the strip was still an 18 pt row child with HitTestBehavior.opaque on
//      it, so the bar was invisible rather than gone and went on eating every
//      tap and orbit that landed at the screen edge. `noBar` and `noDeadZone`
//      below are the difference, and only the second of them would have
//      failed against that fix;
//   2. a swipe right from the left edge opens it. The handle's flick needed
//      50 px/s AT RELEASE, so a slow deliberate drag did nothing at all —
//      `slowDrag` is that case, and it fails without the tracking gesture;
//   3. with a native animation. There was none: the rail was
//      `SizedBox(width: retracted ? 0 : railWidth)`, absent to full width
//      between two frames. `animates` pins that the width is strictly partial
//      partway through, which no snap can satisfy.
//
// isPhoneOverride is what makes any of this testable: the band retracts on a
// phone and nowhere else, and per m405_ribbon_retract_test the host must never
// be made into one globally.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/device_class.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

/// An iPhone 15's logical size — the shape the report was filed from.
const Size _phone = Size(393, 852);
const Key _stageKey = Key('stage');

AppState _document() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('issue49');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Taps that reach the stage — the viewport's stand-in. A tap landing at the
/// screen edge MUST arrive here: that is the whole of `noDeadZone`.
int _stageTaps = 0;

/// Mounted the way main.dart mounts it: the shell listens to the retract flag,
/// because the band's row changes the stage's edges. Testing it any other way
/// would be testing a widget the app does not run.
Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(_phone);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: RibbonRetract.retracted,
        builder: (_, __, ___) => RibbonDockLayout(
          app: app,
          stage: GestureDetector(
            key: _stageKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => _stageTaps++,
            child: const SizedBox.expand(),
          ),
          bleed: const SizedBox.expand(),
        ),
      ),
    ),
  ));
  await t.pump();
}

/// How much of the band is SHOWING. Not the ribbon's own box: mid-reveal the
/// band keeps its full width and is clipped to a fraction of it — that is what
/// makes it slide rather than squash — so the ribbon measures the same at
/// every stage of the animation and only the slot moves.
double _bandWidth(WidgetTester t) =>
    t.getSize(find.byKey(kRibbonBandSlot)).width;

void main() {
  setUp(() {
    _stageTaps = 0;
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

  testWidgets('retracted — no bar down the edge', (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    // The handle is the only thing that ever drew a bar there, and retracted
    // it is not in the tree at all — not merely painted transparent.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(_bandWidth(t), 0, reason: 'the band takes no width either');
  });

  testWidgets('retracted — and the edge is not a dead zone', (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    // A tap 4 points from the left edge: inside the swipe zone, and meant for
    // the model behind it. The swipe zone is translucent and claims no tap, so
    // it must fall through. This is the assertion the first fix would fail.
    await t.tapAt(const Offset(4, 400));
    await t.pump();
    expect(_stageTaps, 1, reason: 'the viewport still gets edge taps');
    expect(RibbonRetract.on, isTrue, reason: 'and a tap does not open it');
  });

  testWidgets('a slow swipe right from the left edge opens it', (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    // Deliberate, not a flick: 20 steps over a second is far below the 50 px/s
    // the old handle demanded at release, and well under this gesture's own
    // flick threshold — so it can only pass on distance.
    final g = await t.startGesture(const Offset(4, 400));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(6, 0));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(RibbonRetract.drag.value, isNotNull,
        reason: 'the band tracks the finger while it is down');
    expect(_bandWidth(t), greaterThan(0),
        reason: 'and is already partly out mid-drag');

    await g.up();
    await t.pumpAndSettle();
    expect(RibbonRetract.on, isFalse, reason: 'released past halfway: open');
    expect(RibbonRetract.drag.value, isNull, reason: 'the transient is gone');
    expect(_bandWidth(t), RibbonMetrics.railWidth);
  });

  testWidgets('a swipe that turns back does not open it', (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    final g = await t.startGesture(const Offset(4, 400));
    await g.moveBy(const Offset(30, 0));
    await t.pump(const Duration(milliseconds: 50));
    final peek = _bandWidth(t);
    expect(peek, greaterThan(0));

    // Changed their mind: back to the edge, slowly, and released there.
    await g.moveBy(const Offset(-30, 0));
    await t.pump(const Duration(milliseconds: 50));
    expect(_bandWidth(t), lessThan(peek), reason: 'it follows the finger back');
    await g.up();
    await t.pumpAndSettle();
    expect(RibbonRetract.on, isTrue, reason: 'short of halfway: still away');
  });

  testWidgets('the reveal ANIMATES rather than snapping', (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    RibbonRetract.set(false);
    await t.pump(); // the frame that starts it
    await t.pump(const Duration(milliseconds: 120));

    final mid = _bandWidth(t);
    expect(mid, greaterThan(0), reason: 'already moving');
    expect(mid, lessThan(RibbonMetrics.railWidth),
        reason: 'but not there yet — a snap would already be at full width');

    await t.pumpAndSettle();
    expect(_bandWidth(t), RibbonMetrics.railWidth, reason: 'and it arrives');
  });

  testWidgets('out — the handle is back, and puts it away', (t) async {
    RibbonRetract.set(false);
    await _pump(t, _document());

    // The band is out, so the handle is the affordance again: drawn, and
    // pointing at the edge the band will hide into.
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    expect(RibbonRetract.on, isTrue);
  });

  testWidgets('an iPad is untouched: no handle, no swipe zone, no clip',
      (t) async {
    isPhoneOverride = false;
    await _pump(t, _document());

    expect(find.byIcon(Icons.chevron_left), findsNothing,
        reason: 'the retract is not offered here at all');
    expect(_bandWidth(t), RibbonMetrics.railWidth,
        reason: 'and the band is simply out, at full width');

    // Nothing overlays the leading edge, so an edge tap is the viewport's.
    await t.tapAt(const Offset(4, 400));
    await t.pump();
    expect(_stageTaps, 0,
        reason: 'at x=4 an iPad has RIBBON there, not the stage');
  });
}
