// M209 — A POINT IS A POINT, AND A CLICK ON A WINDOW IS NOT A CLICK ON THE
// CANVAS.
//
// "The point tool is placing a circle not a point."
//
// It was. The QCAD core's type set is line/circle/arc/polyline, so the tool
// built a circle of radius 0.35 mm — which at any working zoom is a visible
// ring with four quadrant grips, a rim things snap onto and a diameter you can
// dimension. The carrier stays a circle (nothing else round-trips), but it is
// TAGGED now, and everything that made it behave like a circle asks the tag.
//
// "On the freehand spline, when i click finish it sets a last spline point.
// This shouldn't happen."
//
// The modeless windows float inside the same Stack that the viewport's raw
// pointer Listener wraps, and Flutter delivers a pointer to every target on
// its hit path — so the Listener saw the up over Finish as well as the button
// did, and with a tool armed that up was a tool click. M61 met this once with
// the Gear window and guarded that ONE rectangle by hand; six windows later it
// was still the only one guarded.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/tools.dart';
import 'package:prototype/widgets/viewport.dart';
import 'package:prototype/widgets/viewport_window.dart';

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m208');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Places one sketch point through the real tool.
Geo _placePoint(AppState app, Offset at) {
  app.tool = Tool.point;
  app.toolClick(at);
  app.tool = Tool.none;
  return app.current!.geometry.last;
}

void main() {
  group('the point tool places a POINT', () {
    test('it is tagged, and it knows it', () {
      final app = _app();
      final g = _placePoint(app, const Offset(10, 5));
      expect(g.isSketchPoint, isTrue);
      expect(g.spline, Geo.pointTag);
    });

    test('it has ONE grip — its position, not a radius', () {
      final app = _app();
      _placePoint(app, const Offset(10, 5));
      final grips = gripsOf(app.current!.geometry);
      expect(grips.length, 1, reason: 'a point cannot be dragged into a ring');
      expect(grips.first.kind, 'center');
      expect(grips.first.pos, const Offset(10, 5));
    });

    test('an ordinary circle keeps its five', () {
      final app = _app();
      app.current!.geometry.add(Geo(Geo.circle, [0, 0, 10]));
      expect(gripsOf(app.current!.geometry).length, 5,
          reason: 'centre plus four quadrants — unchanged');
    });

    test('nothing lands on its rim', () {
      final app = _app();
      final g = _placePoint(app, const Offset(10, 5));
      // A point 0.35 mm away is ON the carrier circle and was being bound
      // there — 0.35 mm from the point everyone could see.
      expect(pointLandsOn(g, const Offset(10 + kSketchPointRadius, 5)), isFalse);
      final circle = Geo(Geo.circle, [10, 5, kSketchPointRadius]);
      expect(pointLandsOn(circle, const Offset(10 + kSketchPointRadius, 5)),
          isTrue,
          reason: 'an untagged circle of the same size still binds');
    });

    test('it samples to itself, so it is not a tiny profile loop', () {
      final app = _app();
      final g = _placePoint(app, const Offset(3, 4));
      expect(sampleEntity(g), [const Offset(3, 4)]);
    });

    test('and it is still selectable — one sample is not "infinitely far"', () {
      final app = _app();
      _placePoint(app, const Offset(3, 4));
      expect(distToEntity(app.current!.geometry.last, const Offset(3, 4.4)),
          closeTo(0.4, 1e-9));
      app.selectAt(const Offset(3, 4.2), 1.0);
      expect(app.selection, {0});
    });

    test('a box select still catches it', () {
      final app = _app();
      final g = _placePoint(app, const Offset(3, 4));
      expect(entityInRect(g, const Rect.fromLTRB(0, 0, 10, 10), crossing: false),
          isTrue);
      expect(entityInRect(g, const Rect.fromLTRB(20, 20, 30, 30),
              crossing: true),
          isFalse);
    });
  });

  group('a click on a floating window stays on the window', () {
    testWidgets('the freehand Finish button does not also place a point',
        (t) async {
      final app = _app();
      app.selectTool(Tool.splineFree);
      await t.binding.setSurfaceSize(const Size(1200, 800));
      // AnimatedBuilder, like main.dart: the viewport is rebuilt when the app
      // notifies, which is what puts the fit window on screen.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
              animation: app, builder: (_, __) => Viewport2D(app: app)),
        ),
      ));
      await t.pump();

      // Draw ink and lift: the fit window opens.
      app.freehandBegin(const Offset(0, 0));
      for (var i = 1; i <= 20; i++) {
        app.freehandExtend(Offset(i * 2.0, i * 1.0));
      }
      app.freehandEnd();
      await t.pumpAndSettle();
      // The test font's glyphs are much wider than the shipped one's, so rows
      // that fit on the device overflow here. Those are diagnostics about a
      // font that does not ship (see m180_every_number_scrubs_test).
      while (t.takeException() != null) {}
      expect(ViewportWindow.count, greaterThan(0),
          reason: 'the fit window registered itself');

      final before = app.current!.geometry.length;
      final points = app.toolPoints.length;
      // A tap on the window: down and up inside its rectangle.
      final at = t.getCenter(find.text('Freehand Spline'));
      final g = await t.startGesture(at);
      await g.up();
      await t.pumpAndSettle();
      while (t.takeException() != null) {}

      expect(app.toolPoints.length, points,
          reason: 'the viewport must not read that up as a tool click');
      expect(app.current!.geometry.length, before);
    });

    testWidgets('a tap on the canvas still works', (t) async {
      // The guard is the window RECTANGLE, not "a window is open".
      final app = _app();
      app.selectTool(Tool.line);
      await t.binding.setSurfaceSize(const Size(1200, 800));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
              animation: app, builder: (_, __) => Viewport2D(app: app)),
        ),
      ));
      await t.pump();

      final g = await t.startGesture(const Offset(400, 400));
      await g.up();
      await t.pumpAndSettle();
      expect(app.toolPoints.length, 1, reason: 'a canvas click still places');
    });
  });

  group('ViewportWindow', () {
    testWidgets('reports the rectangle it occupies, and forgets it on dispose',
        (t) async {
      var show = true;
      late StateSetter set;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (_, s) {
            set = s;
            return Stack(children: [
              if (show)
                Positioned(
                  left: 100,
                  top: 50,
                  child: ViewportWindow(
                      child: Container(width: 200, height: 80)),
                ),
            ]);
          }),
        ),
      ));
      expect(ViewportWindow.hits(const Offset(150, 90)), isTrue);
      expect(ViewportWindow.hits(const Offset(400, 400)), isFalse);

      set(() => show = false);
      await t.pumpAndSettle();
      expect(ViewportWindow.hits(const Offset(150, 90)), isFalse,
          reason: 'a closed window blocks nothing');
    });
  });
}
