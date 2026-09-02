// M50 — RIBBON SLIMMING + CHROME REMOVAL, and the M51 regression guard.
//
// The FIRST test in this file is the important one. M50 originally shipped a
// `_panel` that did this:
//     Widget title = Row(...);
//     title = Builder(builder: (_) => GestureDetector(child: title));
// A Dart closure captures the VARIABLE, not the value, so by the time the
// builder ran `title` pointed at the Builder itself and every frame inflated
// Builder -> GestureDetector -> Builder -> ... The device died with a stack
// overflow in ComponentElement.performRebuild on every single frame, which
// showed up as "the arrows are missing" and "pan/zoom is broken". Simply
// PUMPING the ribbon catches it — which is exactly why this suite exists.
//
// Beyond that the tests keep two operations apart on purpose:
//  * MOVED, not deleted. Rarely-used commands lost their permanent ribbon
//    width and now sit behind the ▼ next to their panel's title. Every one
//    must still be REACHABLE — a test that only checked "it's gone from the
//    ribbon" would pass on a regression that deleted the command outright,
//    the exact opposite of what was asked for.
//  * REMOVED. Dead chrome is gone for good and must not come back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';
import 'package:prototype/widgets/model_browser.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/l10n/l.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m50');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
}

/// Opens the ▼ next to a panel title.
///
/// M234 — scrolls to it first. The ribbon is a horizontal scroller by
/// construction ("the bar is only as wide as the screen and its panels
/// routinely overflow"), and the German panel titles push the last panel past
/// the right edge of this test's 1600 px surface. Tapping a widget that is
/// off-screen is a test artefact, not a defect: on a device the user flicks
/// the ribbon, which is what ensureVisible does here.
Future<void> openOverflow(WidgetTester t, String panel) async {
  await t.ensureVisible(find.text(panel));
  await t.pumpAndSettle();
  await t.tap(find.text(panel));
  await t.pumpAndSettle();
}

/// The panel-title arrows. Since M205 they are the ONLY ▼ glyphs left in the
/// ribbon — the split buttons' and the small rows' openers are drawn chips
/// with a real icon — but the font-size probe stays, because it is what tells
/// a title's arrow from anything a later panel might add.
final panelArrows = find.byWidgetPredicate(
    (w) => w is Text && w.data == '▼' && w.style?.fontSize == 8);

void main() {
  // M349 — the ribbon's names are off by default now, and this suite reaches
  // its commands by their WORDS. Which of the two modes a suite drives is a
  // property of the suite: this one is about what the ribbon offers, so it
  // drives the ribbon that spells it out.
  setUp(() => RibbonLabels.set(true));
  tearDown(RibbonLabels.resetForTest);
  group('M51 regression: the ribbon must build at all', () {
    testWidgets('pumping the ribbon does not recurse', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // If _panel ever closes over its own title variable again, this never
      // returns (host) / blows the stack (device) and the titles never render.
      expect(find.text(L.current.panelConstrain), findsOneWidget);
      expect(find.text(L.current.panelModify), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the three panel titles really carry a ▼', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      expect(panelArrows, findsNWidgets(3));
    });
  });

  group('Constrain: three commands moved behind the title ▼', () {
    testWidgets('they are NOT on the panel face', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // the grid is icon-only, so tooltips are the probe
      for (final label in [
        L.current.btnSmoothG2,
        L.current.btnConstraintSettings,
        L.current.btnShowConstraints,
      ]) {
        expect(find.byTooltip(label), findsNothing, reason: label);
      }
      for (final label in [
        L.current.conCoincident,
        L.current.conParallel,
        L.current.conEqual,
      ]) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the ▼ reaches all three, and Smooth still starts',
        (t) async {
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await openOverflow(t, L.current.panelConstrain);
      expect(find.text(L.current.btnSmoothG2), findsOneWidget);
      expect(find.text(L.current.btnConstraintSettings), findsOneWidget);
      expect(find.text(L.current.btnShowConstraints), findsOneWidget);
      await t.tap(find.text(L.current.btnSmoothG2));
      await t.pumpAndSettle();
      expect(app.tool, Tool.cSmooth);
    });

    testWidgets('the menu opens DOWNWARD, below the title', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      final titleY = t.getCenter(find.text(L.current.panelConstrain)).dy;
      await openOverflow(t, L.current.panelConstrain);
      final itemY = t.getCenter(find.text(L.current.btnShowConstraints)).dy;
      expect(itemY, greaterThan(titleY),
          reason: 'upward menus climb over the ribbon into the status bar');
    });
  });

  group('Insert = Insert + Format + Manage in one panel', () {
    testWidgets('only the four kept commands are on the face', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      for (final label in [
        L.current.btnImage,
        L.current.btnAcad,
        L.current.btnConstruction,
        L.current.btnParameters,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Format'), findsNothing);
      expect(find.text('Manage'), findsNothing);
      for (final label in [
        L.current.btnPointsTool,
        L.current.btnShowFormat,
        L.current.btnCenterPoint,
        L.current.btnCenterline,
        L.current.btnDrivenDimension,
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the ▼ reaches all five moved commands', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await openOverflow(t, L.current.panelInsert);
      for (final label in [
        L.current.btnPointsTool,
        L.current.btnCenterline,
        L.current.btnCenterPoint,
        L.current.btnDrivenDimension,
        L.current.btnShowFormat,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Parameters still toggles the fx window', (t) async {
      final app = makeApp();
      expect(app.showParams, isFalse);
      await pump(t, Ribbon(app: app));
      await t.tap(find.text(L.current.btnParameters));
      await t.pumpAndSettle();
      expect(app.showParams, isTrue);
    });
  });

  group('Modify: only Trim / Split / Offset keep their width', () {
    testWidgets('the transform family left the panel face', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      for (final label in [
        L.current.btnTrim,
        L.current.btnSplitCurve,
        L.current.btnOffsetCurve,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in [
        L.current.btnExtend,
        L.current.flyMoveB,
        L.current.btnCopy,
        L.current.flyRotateB,
        L.current.flyScaleB,
        L.current.btnStretch,
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the ▼ reaches all six, and they still start', (t) async {
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await openOverflow(t, L.current.panelModify);
      for (final label in [
        L.current.btnExtend,
        L.current.flyMoveB,
        L.current.btnCopy,
        L.current.flyRotateB,
        L.current.flyScaleB,
        L.current.btnStretch,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await t.tap(find.text(L.current.btnExtend));
      await t.pumpAndSettle();
      expect(app.tool, Tool.extendT);
    });
  });

  group('down arrows that pointed at nothing are gone', () {
    testWidgets('Start New Layer, Create and Finish keep their buttons',
        (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // exactly three panel arrows exist, and they belong to the panels WITH
      // an overflow — so none is left on Create / Start New Layer / Finish
      expect(panelArrows, findsNWidgets(3));
      expect(find.text(L.current.btnStartNewLayer), findsOneWidget);
      expect(find.text(L.current.create), findsOneWidget);
      expect(find.text(L.current.btnFinish), findsOneWidget);
    });
  });

  group('model browser chrome', () {
    testWidgets('+, search and hamburger are gone', (t) async {
      await pump(t, ModelBrowser(app: makeApp()));
      // the tree's own expander glyphs are a different, smaller style — only
      // the header's + was removed
      expect(
          find.byWidgetPredicate(
              (w) => w is Text && w.data == '+' && w.style?.fontSize == 15),
          findsNothing);
      expect(find.text('🔍'), findsNothing);
      expect(find.text('☰'), findsNothing);
      expect(find.text(L.current.browserTitle), findsOneWidget); // the header itself stays
    });

    testWidgets('only a LOCKED layer shows a padlock', (t) async {
      final app = makeApp();
      // a layer only gets a browser row once it is IN the sketch's layer list
      app.current!.layers.add(kDefaultLayer);
      app.current!.geometry.add(Geo(Geo.line, const [0, 0, 10, 0]));
      await pump(
          t,
          AnimatedBuilder(
              animation: app,
              builder: (_, __) => ModelBrowser(app: app)));
      expect(find.byIcon(Icons.lock_outline), findsNothing,
          reason: 'unlocked layers carry no padlock');
      expect(find.byIcon(Icons.lock_open_outlined), findsNothing,
          reason: 'the open padlock is gone entirely');

      app.toggleLayerLocked(kDefaultLayer);
      await t.pump();
      expect(find.byIcon(Icons.lock_outline), findsOneWidget,
          reason: 'a locked layer is marked');
    });
  });

  group('bottom tab bar', () {
    testWidgets('no hamburger, no "Home" word', (t) async {
      await pump(t, BottomTabBar(app: makeApp()));
      expect(find.text('☰'), findsNothing);
      expect(find.text('Home'), findsNothing);
    });
  });
}
