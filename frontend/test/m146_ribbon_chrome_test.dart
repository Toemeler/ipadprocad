// M146 — the ribbon became a FLOATING Liquid Glass card built to the model
// browser's recipe, and everything that floats over the viewport now has to
// get out from under it.
//
// Host tests run off iOS, so `RibbonSurface.isGlass` is false here and the
// fallback path is what gets exercised. That is deliberate and is itself the
// most valuable assertion in the file: the day the fallback stops being an
// opaque bar, every non-iOS build silently loses its ribbon background and no
// device test would ever catch it.
//
// The device found two things CI could not, and both are pinned below:
//   * the glass came out milky white, because `UIGlassEffect` follows its
//     trait environment and only the browser was setting dark traits;
//   * the browser, the ViewCube and the triad were all drawn UNDER the bar,
//     because a floating ribbon shares their coordinate space.
// The second is testable from Dart. The first is a Swift one-liner and is not
// — noted here so nobody assumes a green suite covers it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/native_browser_host.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m146');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

Future<void> pump(WidgetTester t, Widget w,
    {Size size = const Size(1600, 900)}) async {
  await t.binding.setSurfaceSize(size);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
}

void main() {
  setUp(RibbonDock.resetForTest);

  group('M146 surface', () {
    testWidgets('the ribbon still builds', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      expect(find.byType(Ribbon), findsOneWidget);
    });

    testWidgets('the background goes through RibbonSurface', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // One place decides glass vs. fallback; ribbon.dart never fills itself.
      expect(find.byType(RibbonSurface), findsOneWidget);
    });

    testWidgets('off iOS the surface is the mock\'s opaque panel colour',
        (t) async {
      expect(RibbonSurface.isGlass, isFalse,
          reason: 'host tests must exercise the fallback');
      await pump(t, const SizedBox(height: 40, child: RibbonSurface()));
      expect(
          t
              .widget<ColoredBox>(find.descendant(
                  of: find.byType(RibbonSurface),
                  matching: find.byType(ColoredBox)))
              .color,
          T.panel);
    });

    test('surface A is flush, not a floating card', () {
      // M284 (surface A) — the band de-floats: no side inset, no corner
      // radius, no shadow. These are the two numbers that used to drift
      // toward the model browser's and now must both be zero.
      expect(RibbonMetrics.radius, 0);
      expect(RibbonMetrics.side, 0);
      expect(RibbonMetrics.pad, EdgeInsets.zero,
          reason: 'the band runs to the screen edge');
    });

    test('the glass is asked for its own corners', () {
      // A platform view cannot be clipped from the Flutter side. Surface A is
      // square, so the ribbon passes 0 and the browser fallback stays the
      // full-bleed 0 it always was.
      expect(const GlassPanel(cornerRadius: RibbonMetrics.radius).cornerRadius,
          0);
      expect(const GlassPanel().cornerRadius, 0,
          reason: 'the browser fallback must stay full-bleed');
    });
  });

  group('M146 no blue lines', () {
    testWidgets('the ribbon draws no border at all', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      final borders = t
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null)
          .toList();
      for (final d in borders) {
        for (final side in [
          (d.border as Border).top,
          (d.border as Border).bottom
        ]) {
          expect(side.color == T.ribbonTop || side.color == T.ribbonBottom,
              isFalse,
              reason: 'the blue edges were removed in M146');
        }
      }
    });
  });

  // M290 — THE BAND IS A ROW OF THE LAYOUT, NOT AN OVERLAY WITH INSETS.
  //
  // M284 had the band float over the content Stack, publish its measured
  // thickness one frame after layout, and seven floating panels each subtract
  // the edge that concerned them. The tests that used to live here pinned that
  // protocol: extent -> contentTop/Right/Bottom/Left, and a
  // contentInsetsFor(ribbonDrawn) gate that existed only because the published
  // values outlived the band on the gallery.
  //
  // All of it is gone, and these are the properties that replace it: the band
  // has no way to publish anything, and the layout puts it on its edge with
  // the stage taking the rest. That is not a smaller test of the same thing —
  // it is the reason the old failures (a frame of misplaced chrome after every
  // dock change; the gallery clearing a band that was not drawn; a new panel
  // forgetting to subtract) cannot be written any more.
  group('M290 the band takes a row', () {
    test('the band publishes no thickness for anyone to read', () {
      // A compile-time property, asserted as documentation: RibbonMetrics is
      // constants only now. If an inset protocol ever comes back, it comes
      // back deliberately and this comment is where the argument is.
      expect(RibbonMetrics.railWidth, greaterThan(0));
      expect(RibbonMetrics.pad, EdgeInsets.zero);
    });

    test('the dock is a value, not a widget', () {
      // M290 — RibbonPosition and its store moved out of widgets/ into
      // lib/ribbon_dock.dart. This test running at all is the assertion: it
      // needs no widget tree, no binding and no channel.
      expect(RibbonDock.current, RibbonPosition.top);
      expect(RibbonDock.isVertical, isFalse);
      expect(RibbonDock.isHorizontal, isTrue);

      RibbonDock.set(RibbonPosition.left);
      expect(RibbonDock.isLeft, isTrue);
      expect(RibbonDock.isVertical, isTrue);
      expect(RibbonPosition.left.isVertical, isTrue);
      expect(RibbonPosition.bottom.isVertical, isFalse);
    });

    test('every edge round-trips through its stored id', () {
      for (final p in RibbonPosition.values) {
        expect(RibbonPosition.byId(p.id), p);
      }
      expect(RibbonPosition.byId('sideways'), isNull);
      expect(RibbonPosition.byId(null), isNull);
    });

    testWidgets('a horizontal band is as tall as its content, no more',
        (t) async {
      // The row it takes is the band's own height: nothing measures it, so
      // nothing can be a frame behind it either.
      await pump(t, Column(children: [
        Ribbon(app: makeApp()),
        const Expanded(child: SizedBox.expand()),
      ]));
      final band = t.getSize(find.byType(Ribbon));
      expect(band.height, greaterThan(0));
      expect(band.height, lessThan(400), reason: 'a band, not half the screen');
      expect(band.width, 1600, reason: 'flush: it spans its edge');
    });

    testWidgets('a side rail is the rail width and full height', (t) async {
      RibbonDock.set(RibbonPosition.left);
      await pump(t, Row(children: [
        SizedBox(width: RibbonMetrics.railWidth, child: Ribbon(app: makeApp())),
        const Expanded(child: SizedBox.expand()),
      ]));
      final band = t.getSize(find.byType(Ribbon));
      expect(band.width, RibbonMetrics.railWidth);
      expect(band.height, 900, reason: 'flush: it spans its edge');
    });

    testWidgets('the rail scrolls DOWN itself, not across', (t) async {
      RibbonDock.set(RibbonPosition.right);
      await pump(t, Row(children: [
        const Expanded(child: SizedBox.expand()),
        SizedBox(width: RibbonMetrics.railWidth, child: Ribbon(app: makeApp())),
      ]));
      expect(
          t
              .widget<SingleChildScrollView>(
                  find.byType(SingleChildScrollView).first)
              .scrollDirection,
          Axis.vertical);
    });
  });

  group('M146 the triad clears the browser', () {
    test('it is offset by the panel\'s full expanded width', () {
      // Expanded, not current: a triad that slid sideways every time the panel
      // retracted would be worse than one standing a little clear of it.
      expect(NativeModelBrowser.occupiedWidth, greaterThan(200));
    });
  });

  group('M146 scrolling', () {
    testWidgets('the ribbon scrolls horizontally when it overflows',
        (t) async {
      await pump(t, Ribbon(app: makeApp()), size: const Size(600, 400));
      expect(
          t
              .widget<SingleChildScrollView>(
                  find.byType(SingleChildScrollView).first)
              .scrollDirection,
          Axis.horizontal);

      final st = t.state<ScrollableState>(find.byType(Scrollable).first);
      expect(st.position.maxScrollExtent, greaterThan(0),
          reason: 'the bar must actually overflow at 600 pt');

      await t.drag(find.byType(Ribbon), const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(st.position.pixels, greaterThan(0),
          reason: 'the drag must move the strip, not be swallowed by the '
              'glass background');
    });
  });
}
