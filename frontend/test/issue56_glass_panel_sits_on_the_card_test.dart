// #56 — the model browser's glass surface, and the card it is supposed to be.
//
// Measured twice off real window grabs, on two different windows:
//
//              window        card box        glass rim   gap
//   bundle A   2560x1400     x 60 .. 310     x 98        38
//   bundle B   1376x1032     x 60 .. 310     x 98        38
//
// Card 1284 pt tall in one and 916 in the other; the gap did not move. Top and
// bottom rims land exactly on the card's own edges in both, so the disagreement
// is in X alone and is a CONSTANT 38 pt — not a fraction of anything, not a
// function of the window, the card or the backdrop.
//
// And 38 is `cardInsetLeft` (14) + `_kHandle` (24): two of this widget's own
// layout constants, added together. That is not a shape an engine bug has.
//
// WHY NOTHING CAUGHT IT. `GlassPanel.isSupported` decides the browser's whole
// layout — a floating card inset 14 with a 24 pt retract strip beside it where
// it is true, an opaque wall beside the viewport where it is false — and on the
// test host it is always false. So the branch that ships to every iPad and
// every desktop was the one branch the suite could not mount, and the panel's
// geometry inside it was never once measured. `GlassPanel.supportedOverride`
// exists so that it can be, and this is the measurement: where the glass
// surface lands, against where the card is.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart' show GlassPanel;
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/widgets/model_browser.dart';

AppState _part(String tag) {
  final app = AppState()
    ..docsDirForTest = Directory.systemTemp.createTempSync(tag)
    ..volatileDirsForTest = const [];
  return app;
}

void main() {
  setUp(() => GlassPanel.supportedOverride = true);
  tearDown(() => GlassPanel.supportedOverride = null);

  testWidgets('the glass surface is the card, not 38 pt to the side',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1376, 1032));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final app = _part('issue56');
    await app.createNamedPart('littlejoint');

    // The host's slot, as native_browser_host hands it over: the panel's whole
    // footprint, card plus retract strip, with the card pinned to the left of
    // it and the strip on the right.
    await t.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 288, // NativeModelBrowser.occupiedWidth
          height: 1032,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: 24, // _kHandle
              child: ModelBrowser(app: app),
            ),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();

    final card = find.byType(DecoratedBox).first;
    final glass = find.byType(GlassPanel);
    expect(glass, findsOneWidget,
        reason: 'the glass branch is what this file exists to measure');

    final cardLeft = t.getTopLeft(card).dx;
    final glassLeft = t.getTopLeft(glass).dx;

    expect(cardLeft, ModelBrowser.cardInsetLeft,
        reason: 'the card floats its own inset in from the panel edge');
    expect(glassLeft, cardLeft,
        reason: 'THE REPORT: the surface and the card it fills are one box. '
            'On the device they were 38 pt apart — exactly cardInsetLeft + '
            'the retract strip');
    expect(t.getSize(glass).width, ModelBrowser.cardWide,
        reason: 'and it is the card\'s width, not the panel\'s');
  });
}
