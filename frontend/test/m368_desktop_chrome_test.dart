// M368 — the floating chrome, off iOS.
//
// M367 put the desktop app on the same material the iPad uses, and stopped
// there: the model browser got the glass but not the CARD it belongs to, and
// the tab bar got the glass but stayed one pill. Side by side with the device
// the difference was not the material at all, it was everything around it —
//
//   * the Flutter card carried a "Modell ✕" tab strip across its top, which
//     the iPad's browser has never had. The tree starts at the document's own
//     root row there, and the bar along the bottom is what says which document
//     is open; a second tab strip inside the card said it twice.
//   * the card did not retract. On the iPad it is retracted by DEFAULT
//     (M242) — 264 pt of a 1024 pt screen, and the thing being drawn is the
//     point of the app — and one tap on the chevron brings the labels back.
//     Off iOS it stood open over the drawing with no way to move it.
//   * the bar was one pill with the house inside it and nothing on the right,
//     which is the M260 slab again, only smaller. The bar is THREE objects:
//     the house, the documents, and the island that lists them all.
//
// The pixels of those three are Dart now rather than Swift, but the surface
// they live on is not available on the flutter_test host (Impeller is off, so
// `GlassPanel.isSupported` is false and every one of them falls back). So what
// is pinned here is what CAN be: the geometry both sides share, and the rule
// that the fallbacks are untouched — a platform with no material still gets
// the opaque wall, header and all.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';
import 'package:prototype/widgets/model_browser.dart';
import 'package:prototype/widgets/native_browser_host.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m368');
  return app;
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
}

void main() {
  group('M368 — the card is GlassBrowserView\'s card', () {
    test('the slab plus its inset is the panel width the host publishes', () {
      // GlassBrowserView insets its glass 12/14/12/0 inside a 264 pt panel, so
      // the slab you can see is 250 wide and starts 14 in. Getting this wrong
      // is not subtle on a device — the Flutter card was a full 264 wide,
      // which put its right edge 14 pt further out than the iPad's.
      expect(ModelBrowser.cardInsetLeft + ModelBrowser.cardWide, 264);
      expect(ModelBrowser.cardInsetLeft + ModelBrowser.cardNarrow, 56);
    });

    test('and it morphs across exactly the distance the panel does', () {
      expect(
          NativeModelBrowser.occupiedWidth - NativeModelBrowser.collapsedWidth,
          ModelBrowser.cardWide - ModelBrowser.cardNarrow,
          reason: 'the strip beside the card is the same width in both '
              'states, so the card and the panel travel together');
    });

    test('the glyph column fits inside the retracted card', () {
      // "when its retracted i cant use the icons" was M204's bug and it was
      // this shape: a column of glyphs drawn where the panel no longer is.
      expect(ModelBrowser.glyphX,
          lessThanOrEqualTo(ModelBrowser.cardInsetLeft + ModelBrowser.cardNarrow),
          reason: 'the icons have to be ON the retracted card');
      expect(ModelBrowser.glyphX, greaterThan(ModelBrowser.cardInsetLeft),
          reason: 'and past its leading inset');
    });

    test('the column is measured, not guessed', () {
      // The chevron stands just past this edge, so it has to be the row's own
      // arithmetic rather than a number that happens to look right.
      expect(
          ModelBrowser.glyphX,
          ModelBrowser.cardInsetLeft +
              ModelBrowser.rowPadH +
              ModelBrowser.rowGap +
              ModelBrowser.rowIcon);
    });
  });

  group('M368 — the bar is GlassTabBarView\'s bar', () {
    test('a group, plus the height it floats, is the bar', () {
      expect(BottomTabBar.kGroupH + BottomTabBar.kBarInset.bottom,
          BottomTabBar.kNativeHeight);
    });

    test('the groups sit closer to each other than to the screen', () {
      // "one object broken up rather than three unrelated ones": the gap
      // INSIDE the bar has to read as smaller than the margin around it, or
      // the three groups stop being one bar.
      expect(BottomTabBar.kGroupGap,
          lessThan(BottomTabBar.kBarInset.left));
      expect(BottomTabBar.kBarInset.left, BottomTabBar.kBarInset.right,
          reason: 'the bar is symmetric; the browser is not');
      expect(BottomTabBar.kBarInset.left, 14,
          reason: 'the ribbon, the browser card and the bar float on ONE '
              'shared edge — GlassTabBarView.inset and GlassBrowserView\'s '
              'card inset are the same 14');
    });

    test('a chip is its OWN height, not the capsule less its padding', () {
      // UIKit sizes the chip to its content (4 pt above and below a 12 pt
      // symbol beside a 12.5 pt label) and centres it; the row padding is the
      // minimum clearance around the row, not the chip's height. A chip
      // stretched to `kGroupH - 2 * kRowPad` is a plate with a hairline of
      // glass around it, which is exactly what the capsule must not look like.
      expect(BottomTabBar.kChipH, 23);
      expect(BottomTabBar.kChipH,
          lessThan(BottomTabBar.kGroupH - 2 * BottomTabBar.kRowPad),
          reason: 'there has to be glass left to see');
    });

    test('folded is the resting state, and it waits before it folds', () {
      expect(BottomTabBar.kIdleFold, const Duration(seconds: 3));
      expect(BottomTabBar.kFold.inMilliseconds, lessThan(400),
          reason: 'brevity and precision — a chevron tap is not direct '
              'manipulation, so this is an ease and a short one');
    });
  });

  group('M368 — the opaque fallback is untouched', () {
    testWidgets('with no material the browser keeps its header', (t) async {
      // The header went away on the CARD, where the iPad has never had one.
      // Without glass the panel is a wall beside the viewport with nothing
      // else on it, and that is the one place the document tab still belongs.
      expect(GlassPanel.isSupported, isFalse,
          reason: 'flutter_test runs without Impeller; this whole group '
              'depends on it');
      await pump(t, ModelBrowser(app: makeApp()));
      expect(find.text(L.current.browserTitle), findsOneWidget);
    });

    testWidgets('and it does not retract', (t) async {
      // A wall that retracts leaves a hole: the viewport starts to the RIGHT
      // of this panel rather than underneath it.
      final app = makeApp();
      await pump(t, ModelBrowser(app: app, collapsed: true));
      expect(find.text(L.current.browserTitle), findsOneWidget,
          reason: 'the header is still there');
      expect(find.text(L.current.nodeEndOfSketch), findsOneWidget,
          reason: 'and so are the row labels');
    });

    testWidgets('the bar is still the opaque strip', (t) async {
      final app = makeApp();
      app.sketches['A'] = SketchModel('A');
      app.openTabs.add('A');
      app.curTab = 'A';
      await pump(t, BottomTabBar(app: app));
      expect(find.text('A'), findsOneWidget);
      expect(BottomTabBar.floatingHeight, 0,
          reason: 'with no glass the bar takes a row of the Column and '
              'nothing floats above it');
    });
  });

  group('M368 — what the triad follows', () {
    test('with no material it follows the wall, not a floating card', () {
      expect(NativeModelBrowser.opaqueWidth, greaterThan(200));
      expect(NativeModelBrowser.triadInset(NativeModelBrowser.opaqueWidth),
          NativeModelBrowser.opaqueWidth,
          reason: 'only the RETRACTED floating panel frees the corner');
    });
  });
}
