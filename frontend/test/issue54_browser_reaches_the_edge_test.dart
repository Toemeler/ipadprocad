// #54 — "when the ribbon is retracted, the Modell Browser should Move to the
// left."
//
// Filed from a 390x844 phone on build b49fc80, and traced rather than guessed
// at. The browser has no left offset of its OWN: main.dart parks it in an
// `Align(alignment: Alignment.topLeft)` with only a bottom padding, and M290
// deleted the last thing that reserved space for the band when the band became
// a real row of the layout. What was still standing at the screen's left edge
// in b49fc80 was the RIBBON's retract handle — an 18 pt strip that kept a row
// of the layout while the band it belonged to was away, so everything in the
// stage, the browser included, began 18 pt in.
//
// #52's fix (f59e99a) takes that handle out of the tree while the band is
// retracted, which is what moves the browser. That fix was about how the strip
// LOOKED, though, and its test measures the grabber and the hit target; the
// thing this report is about — that the stage reaches the screen's edge once
// the band is away — was not pinned by anything. It is now, because it is one
// `if` away from coming back and it comes back invisibly: a panel 18 pt in
// from the edge looks like a panel.
//
// What is left between the edge and the CARD after this is
// `ModelBrowser.cardInsetLeft`, the 14 pt the floating card is inset by on
// every platform (GlassBrowserView's own geometry, M121/M204). That is the
// card's margin rather than anything the ribbon reserved, so it does not move
// when the band does — and the last case below says so in the one place
// someone reading this report would look for it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/device_class.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/model_browser.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _phone = Size(393, 852);
const Key _stageKey = Key('stage');

AppState _document() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('issue54');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Mounted the way main.dart mounts it — see issue52_phone_band_chrome_test,
/// which this borrows its harness from. The stage is a bare box with a key on
/// it, so what is measured is where the LAYOUT puts the floating chrome and
/// nothing about what the chrome then draws inside itself.
Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(_phone);
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: _phone),
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
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    isPhoneOverride = true;
    RibbonRetract.resetForTest();
    RibbonDock.resetForTest();
    RibbonDock.set(RibbonPosition.left);
    RibbonSurface.glassOverride = false;
  });
  tearDown(() {
    isPhoneOverride = null;
    RibbonRetract.resetForTest();
    RibbonDock.resetForTest();
    RibbonSurface.glassOverride = null;
  });

  testWidgets('with the band away, the stage starts at the screen edge',
      (t) async {
    RibbonRetract.set(true);
    await _pump(t, _document());

    expect(t.getTopLeft(find.byKey(_stageKey)).dx, 0,
        reason: 'nothing may keep a row of the layout on the edge the band '
            'retracted from — that 18 pt strip IS this report');
    expect(t.getSize(find.byKey(_stageKey)).width, _phone.width,
        reason: 'and the stage has the whole width, not the width less a strip');
  });

  testWidgets('with the band out, the stage starts beside it', (t) async {
    // The other half of the measurement: without this the case above would
    // also pass on a build that never gave the band a row at all.
    RibbonRetract.set(false);
    await _pump(t, _document());

    expect(t.getTopLeft(find.byKey(_stageKey)).dx,
        greaterThanOrEqualTo(RibbonMetrics.railWidth),
        reason: 'docked, the band takes a real row and the stage is what is '
            'left (M290)');
  });

  test('what remains at the edge is the card\'s own margin, not a band', () {
    // 14 pt, and it belongs to the CARD: GlassBrowserView's inset
    // (top 12, left 14, bottom 12, right 0), which the Flutter card matches so
    // the two renderers draw the same panel rather than two versions of it.
    // Nothing about the ribbon changes it, which is why retracting the band
    // cannot close it and why this report's fix is the strip above.
    expect(ModelBrowser.cardInsetLeft, 14);
    expect(ModelBrowser.cardWide, 264 - ModelBrowser.cardInsetLeft);
  });
}
