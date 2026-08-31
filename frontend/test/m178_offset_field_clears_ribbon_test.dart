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
// `RibbonMetrics.contentTop`, which these tests pinned for the field too.
//
// M290 — the bug is now impossible rather than guarded. The band takes a row
// of the layout instead of floating over the content Stack, so the field's box
// begins where the band ends and `top: 14` is measured from there. There is no
// inset to read, no post-frame value to be stranded by, and no way for a panel
// added tomorrow to forget the contract — because there is no contract. What
// is left to pin is the thing the report was actually about: the field sits at
// the top of the content area and nothing of the ribbon is above it.
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
import 'package:prototype/ribbon_dock.dart';
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
  setUp(RibbonDock.resetForTest);
  tearDown(RibbonDock.resetForTest);

  group('M178 — the offset field clears the ribbon', () {
    testWidgets('it sits at the top of the content area', (t) async {
      final app = _editingApp();
      await _pump(t, app);
      expect(_fieldTop(t), 14,
          reason: 'the band is no longer in this coordinate space');
    });

    testWidgets('and does not move when the band is docked elsewhere',
        (t) async {
      // The whole point of M290: the field's offset is a constant on every
      // dock, because the box it is laid out in has already had the band
      // taken out of it. Under M284 each of these four would have needed the
      // field to subtract a different edge.
      for (final p in RibbonPosition.values) {
        RibbonDock.set(p);
        final app = _editingApp();
        await _pump(t, app);
        expect(_fieldTop(t), 14, reason: '$p');
      }
    });

    testWidgets('a closed field still occupies nothing', (t) async {
      final app = _editingApp();
      app.workPlaneOffsetEditing = false;
      await _pump(t, app);
      expect(t.getSize(find.byType(WorkPlaneOffsetField)), Size.zero);
    });
  });
}
