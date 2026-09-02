// M207 — THE POLYGON'S SIDE COUNT STOPS BEING A MODAL.
//
// "In the polygon input field the small number input field doesn't work — it
// just closes directly when i want to input something. Also this polygon input
// field needs to be redone, it should be similar to the radius input field.
// Also on the radius input field the cross at top left isn't needed, remove
// it."
//
// The first sentence and the second have the same answer. The count lived in
// an AlertDialog: modal, with a barrier under everything the app puts on top
// of it, and blocking — the tool was not armed until it had been answered. The
// 2D Fillet radius has never worked that way; it rides beside the live tool in
// a modeless window, and the number applies to the next corner. The polygon
// gets the same window, the same number row, the same scrub and the same pad.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/widgets/pattern_dialog.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/scrub_field.dart';
import 'package:prototype/widgets/value_pad.dart';
import 'package:prototype/l10n/l.dart';

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m207p');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(1400, 900));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
}

void main() {
  // M349 — the ribbon's names are off by default now, and this suite reaches
  // its commands by their WORDS. Which of the two modes a suite drives is a
  // property of the suite: this one is about what the ribbon offers, so it
  // drives the ribbon that spells it out.
  setUp(() => RibbonLabels.set(true));
  tearDown(RibbonLabels.resetForTest);
  group('picking Polygon arms the tool at once', () {
    testWidgets('no modal is pushed, and the tool is live', (t) async {
      final app = _app();
      await _pump(t, Ribbon(app: app));

      // Reach Polygon through the Rectangle flyout, the way the ribbon does.
      // The chip under the split button opens the list (M205).
      await t.tap(find.byIcon(Icons.arrow_drop_down).at(3));
      await t.pumpAndSettle();
      expect(find.text(L.current.flyTwoPointSub), findsOneWidget, reason: 'the rect flyout');
      await t.tap(find.text(L.current.flyPolygonB).last);
      await t.pumpAndSettle();

      expect(app.tool, Tool.polygon,
          reason: 'the tool arms immediately — nothing to answer first');
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.toolParams['sides'],
          PolygonDialog.defaultSides.toDouble());
    });
  });

  group('the window itself', () {
    testWidgets('shows the count, and typing into it changes the tool',
        (t) async {
      final app = _app();
      app.selectTool(Tool.polygon);
      app.toolParams = {'sides': 6.0};
      await _pump(t, PolygonDialog(app: app));

      expect(find.text(L.current.flyPolygonB), findsOneWidget);
      expect(find.widgetWithText(TextField, '6'), findsOneWidget);

      await t.enterText(find.byType(TextField), '8');
      await t.pump();
      expect(app.toolParams['sides'], 8.0,
          reason: 'the value applies to the NEXT polygon, live');
    });

    testWidgets('it is a ScrubField with the pad, like every other number',
        (t) async {
      final app = _app();
      app.selectTool(Tool.polygon);
      await _pump(t, PolygonDialog(app: app));
      expect(find.byType(ScrubField), findsOneWidget);

      // No modal barrier over it: focusing the field raises the app's pad and
      // the pad stays up, which is the whole of "it just closes directly".
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      expect(find.byType(ValuePad), findsOneWidget);
      await t.tap(find.text('9'));
      await t.pumpAndSettle();
      expect(find.byType(ValuePad), findsOneWidget,
          reason: 'a keystroke must not dismiss the pad');
    });

    testWidgets('the count is clamped to what a polygon can be', (t) async {
      final app = _app();
      app.selectTool(Tool.polygon);
      app.toolParams = {'sides': 6.0};
      await _pump(t, PolygonDialog(app: app));

      await t.enterText(find.byType(TextField), '2');
      await t.pump();
      expect(app.toolParams['sides'],
          PolygonDialog.minSides.toDouble(), reason: 'two sides is not a shape');

      await t.enterText(find.byType(TextField), '999');
      await t.pump();
      expect(app.toolParams['sides'], PolygonDialog.maxSides.toDouble());
    });

    testWidgets('it carries no ✕ — and neither does the radius window',
        (t) async {
      // "on the radius input field the cross at top left isn't needed."
      // Esc and the quick-tool bar's Cancel are the two ways out, and they
      // were already there.
      final app = _app();
      app.selectTool(Tool.polygon);
      await _pump(t, PolygonDialog(app: app));
      expect(find.byIcon(Icons.close), findsNothing);

      app.selectTool(Tool.fillet);
      await _pump(t, FilletChamferDialog(app: app));
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
