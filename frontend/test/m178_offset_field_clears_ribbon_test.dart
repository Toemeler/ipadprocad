// M178 — the work plane's offset field was being drawn UNDER the ribbon.
//
// Reported from the device: "at the top there is something behind the ribbon".
// The something was this field. M146 turned the ribbon into a floating glass
// card that shares the content Stack's coordinate space, and the field — added
// afterwards in M169 — still pinned itself to `top: 14` as if it owned the top
// of the screen. What you actually saw was the field refracted through the
// glass: a smear of a title, a text box and a blue button inside the ribbon.
//
// The ViewCube had exactly this bug and M146 fixed it by anchoring to
// `RibbonMetrics.contentTop`. These tests pin the same contract for the field,
// because "reads contentTop" is the only thing standing between it and the
// glass, and nothing else in the widget would fail if it were removed.
//
// The OTHER half of M178 — iPadOS floating its keyboard shortcuts bar over the
// app's own tab bar, reported in the same breath — is not here and cannot be:
// the bar belongs to the engine's text input view and is suppressed in Swift
// (KeyboardBar.swift). The m5 job greps the built bundle for it instead. Noted
// so nobody reads a green suite as covering that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/work_plane_offset_field.dart';

AppState _editingApp() {
  final w = WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
      'Offset 10.00 mm from XY', offsetPlaneFrame(planeFrame('xy'), 10),
      base: planeFrame('xy'), offset: 10);
  final app = AppState();
  final p = PartModel('P');
  p.workPlanes.add(w);
  app.parts['P'] = p;
  app.curTab = 'P';
  app.selectWorkPlane(w);
  app.workPlaneOffsetEditing = true;
  return app;
}

/// The field lives in the content Stack, exactly as main.dart builds it.
Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF101214))),
        WorkPlaneOffsetField(app: app),
      ]),
    ),
  ));
  await t.pump();
}

double _fieldTop(WidgetTester t) =>
    t.getTopLeft(find.byType(WorkPlaneOffsetField)).dy;

void main() {
  setUp(() {
    RibbonMetrics.extent.value = 0;
    RibbonMetrics.resetForTest();
  });
  tearDown(() {
    RibbonMetrics.extent.value = 0;
    RibbonMetrics.resetForTest();
  });

  group('M178 — the offset field clears the ribbon', () {
    testWidgets('it starts below the measured ribbon, not at the top edge',
        (t) async {
      RibbonMetrics.extent.value = 120;
      final app = _editingApp();
      await _pump(t, app);
      expect(_fieldTop(t), greaterThanOrEqualTo(RibbonMetrics.contentTop),
          reason: 'anything above contentTop is behind the glass');
      expect(_fieldTop(t), RibbonMetrics.contentTop + 14);
    });

    testWidgets('with no ribbon measured it keeps its old top inset',
        (t) async {
      // Off iOS the ribbon takes a row of the Column and insets nothing, so
      // the field must not be pushed down by a stale value.
      final app = _editingApp();
      await _pump(t, app);
      expect(RibbonMetrics.contentTop, 0);
      expect(_fieldTop(t), 14);
    });

    testWidgets('it follows the ribbon when the ribbon is measured later',
        (t) async {
      // The field can open before the post-frame measurement lands, and the
      // ribbon changes height with the active tab. Reading contentTop once at
      // build time would leave the field stranded under the glass.
      final app = _editingApp();
      await _pump(t, app);
      expect(_fieldTop(t), 14);

      RibbonMetrics.extent.value = 96;
      await t.pump();
      expect(_fieldTop(t), 96 + RibbonMetrics.gap + 14);
    });

    testWidgets('a closed field still occupies nothing', (t) async {
      RibbonMetrics.extent.value = 120;
      final app = _editingApp();
      app.workPlaneOffsetEditing = false;
      await _pump(t, app);
      expect(t.getSize(find.byType(WorkPlaneOffsetField)), Size.zero);
    });
  });
}
