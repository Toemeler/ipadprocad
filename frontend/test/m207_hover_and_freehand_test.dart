// M207 — TWO WAYS A PREVIEW FOLLOWED SOMETHING IT SHOULD NOT HAVE.
//
// "When i hover and the hover is interrupted because the distance from pencil
// to screen is too far, the preview should stay exactly like it was for this
// moment until the hover with pencil is back. Right now the preview goes
// somewhere in the top left corner for a moment, which results in a weird long
// line over the screen."
//
// "On the freehand spline, even when the spline is finished and the freehand
// spline dialog comes, on hover with pencil it still goes on. Since it is
// finished the preview should only change with the sliders in the dialog."
//
// Different symptoms, one shape: `hoverWorld` was being fed by events that
// were not the user pointing at anything. The first is the synthetic (0,0)
// that arrives as a hovering pointer is torn down — fed through _toWorld it is
// the viewport's top-left corner, hence the line across the screen. The second
// is an ordinary, perfectly real hover that simply has no business moving a
// curve that has already been drawn.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/widgets/viewport.dart';

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m207');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1200, 800));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Viewport2D(app: app))));
  await t.pump();
}

/// Sends a raw hover, the way a Pencil in range does.
Future<void> _hover(WidgetTester t, Offset global) async {
  final g = TestPointer(1, PointerDeviceKind.stylus);
  await t.sendEventToBinding(g.hover(global));
  await t.pump();
}

void main() {
  group('a hover at the window origin is the pointer leaving, not a move', () {
    testWidgets('it does not move the preview', (t) async {
      final app = _app();
      app.selectTool(Tool.line);
      await _pump(t, app);

      await _hover(t, const Offset(600, 400));
      final held = app.hoverWorld;
      expect(held, isNotNull, reason: 'a real hover must be followed');

      // The Pencil leaves range. What arrives is (0,0).
      await _hover(t, Offset.zero);
      expect(app.hoverWorld, held,
          reason: 'the preview holds its last real position — it must not '
              'jump to the corner and draw a line across the screen');
    });

    testWidgets('and the preview resumes when the tip comes back', (t) async {
      final app = _app();
      app.selectTool(Tool.line);
      await _pump(t, app);

      await _hover(t, const Offset(600, 400));
      await _hover(t, Offset.zero);
      await _hover(t, const Offset(620, 410));
      expect(app.hoverWorld, isNotNull);
      // It followed the NEW position, not the held one.
      final again = app.hoverWorld!;
      await _hover(t, const Offset(700, 500));
      expect(app.hoverWorld, isNot(again));
    });

    testWidgets('a hover the user really made near the corner still counts',
        (t) async {
      // The guard is the WINDOW origin exactly, not "near the top left" — a
      // Pencil an inch in from the corner is a real hover and must be
      // followed.
      final app = _app();
      app.selectTool(Tool.line);
      await _pump(t, app);
      await _hover(t, const Offset(600, 400));
      final before = app.hoverWorld;
      await _hover(t, const Offset(1, 1));
      expect(app.hoverWorld, isNot(before));
    });
  });

  group('a finished freehand stroke is not a rubber band', () {
    testWidgets('hover does not move the preview while the fit window is up',
        (t) async {
      final app = _app();
      app.selectTool(Tool.splineFree);
      await _pump(t, app);

      // Draw an ink stroke and lift: the session survives, drawing == false,
      // and the fit window opens.
      app.freehandBegin(const Offset(0, 0));
      for (var i = 1; i <= 20; i++) {
        app.freehandExtend(Offset(i * 2.0, i * 1.0));
      }
      app.freehandEnd();
      await t.pump();
      expect(app.freehand, isNotNull);
      expect(app.freehand!.drawing, isFalse, reason: 'the stroke is finished');

      final settled = app.hoverWorld;
      await _hover(t, const Offset(900, 200));
      expect(app.hoverWorld, settled,
          reason: 'the curve is decided; only the dialog may change it');
    });

    testWidgets('an ordinary tool still follows the hover', (t) async {
      // The guard is on the freehand session, not on hovering in general.
      final app = _app();
      app.selectTool(Tool.line);
      await _pump(t, app);
      await _hover(t, const Offset(500, 300));
      expect(app.hoverWorld, isNotNull);
    });
  });

  group('the freehand fit is decided, not optional', () {
    test('closing on meeting ends and snapping to points are constants', () {
      // "close if ends meet should be standard and snap ends to points also,
      // and not be a toggle in the dialog."
      expect(FreehandSession.snapClosed, isTrue);
      expect(FreehandSession.snapToPoints, isTrue);
    });
  });
}
