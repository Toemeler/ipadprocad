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
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/widgets/bottom_tabbar.dart';
import 'package:ipadprocad/widgets/model_browser.dart';
import 'package:ipadprocad/widgets/ribbon.dart';

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
Future<void> openOverflow(WidgetTester t, String panel) async {
  await t.tap(find.text(panel));
  await t.pumpAndSettle();
}

/// The panel-title arrows only — `_SmallRow` also renders a ▼ (and a hidden
/// one at opacity 0), so the font size is what tells them apart.
final panelArrows = find.byWidgetPredicate(
    (w) => w is Text && w.data == '▼' && w.style?.fontSize == 8);

void main() {
  group('M51 regression: the ribbon must build at all', () {
    testWidgets('pumping the ribbon does not recurse', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // If _panel ever closes over its own title variable again, this never
      // returns (host) / blows the stack (device) and the titles never render.
      expect(find.text('Constrain'), findsOneWidget);
      expect(find.text('Modify'), findsOneWidget);
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
      for (final label in const [
        'Smooth (G2)',
        'Constraint Settings',
        'Show Constraints',
      ]) {
        expect(find.byTooltip(label), findsNothing, reason: label);
      }
      for (final label in const ['Coincident', 'Parallel', 'Equal']) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the ▼ reaches all three, and Smooth still starts',
        (t) async {
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await openOverflow(t, 'Constrain');
      expect(find.text('Smooth (G2)'), findsOneWidget);
      expect(find.text('Constraint Settings'), findsOneWidget);
      expect(find.text('Show Constraints'), findsOneWidget);
      await t.tap(find.text('Smooth (G2)'));
      await t.pumpAndSettle();
      expect(app.tool, Tool.cSmooth);
    });

    testWidgets('the menu opens DOWNWARD, below the title', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      final titleY = t.getCenter(find.text('Constrain')).dy;
      await openOverflow(t, 'Constrain');
      final itemY = t.getCenter(find.text('Show Constraints')).dy;
      expect(itemY, greaterThan(titleY),
          reason: 'upward menus climb over the ribbon into the status bar');
    });
  });

  group('Insert = Insert + Format + Manage in one panel', () {
    testWidgets('only the four kept commands are on the face', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      for (final label in const [
        'Image',
        'ACAD',
        'Construction',
        'Parameters',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Format'), findsNothing);
      expect(find.text('Manage'), findsNothing);
      for (final label in const [
        'Points',
        'Show Format',
        'Center Point',
        'Centerline',
        'Driven Dimension',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the ▼ reaches all five moved commands', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await openOverflow(t, 'Insert');
      for (final label in const [
        'Points',
        'Centerline',
        'Center Point',
        'Driven Dimension',
        'Show Format',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Parameters still toggles the fx window', (t) async {
      final app = makeApp();
      expect(app.showParams, isFalse);
      await pump(t, Ribbon(app: app));
      await t.tap(find.text('Parameters'));
      await t.pumpAndSettle();
      expect(app.showParams, isTrue);
    });
  });

  group('Modify: only Trim / Split / Offset keep their width', () {
    testWidgets('the transform family left the panel face', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      for (final label in const ['Trim', 'Split', 'Offset']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in const [
        'Extend',
        'Move',
        'Copy',
        'Rotate',
        'Scale',
        'Stretch',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the ▼ reaches all six, and they still start', (t) async {
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await openOverflow(t, 'Modify');
      for (final label in const [
        'Extend',
        'Move',
        'Copy',
        'Rotate',
        'Scale',
        'Stretch',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await t.tap(find.text('Extend'));
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
      expect(find.textContaining('Start'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
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
      expect(find.text('Model'), findsOneWidget); // the header itself stays
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
