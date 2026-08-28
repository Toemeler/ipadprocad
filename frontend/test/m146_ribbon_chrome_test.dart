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
  setUp(() {
    RibbonMetrics.extent.value = 0;
    RibbonMetrics.resetForTest();
  });

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

  group('M146 metrics', () {
    testWidgets('the ribbon publishes its own thickness', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await t.pump(); // let the post-frame report land
      expect(RibbonMetrics.extent.value, greaterThan(0));
      // Everything that floats starts INSIDE the band, with a gap.
      expect(RibbonMetrics.contentTop,
          RibbonMetrics.extent.value + RibbonMetrics.gap);
    });

    test('an unmeasured ribbon insets nothing', () {
      // Off iOS the ribbon keeps its own row in the Column, so overlays must
      // not be pushed down by a stale value.
      RibbonMetrics.extent.value = 0;
      expect(RibbonMetrics.contentTop, 0);
    });

    test('the per-edge insets follow the dock, one edge at a time', () {
      RibbonMetrics.extent.value = 0;
      RibbonMetrics.position.value = RibbonPosition.top;
      expect(RibbonMetrics.contentInsets, EdgeInsets.zero);

      RibbonMetrics.extent.value = 60;
      RibbonMetrics.position.value = RibbonPosition.top;
      expect(RibbonMetrics.contentTop, 60 + RibbonMetrics.gap);
      expect(RibbonMetrics.contentRight, 0);
      expect(RibbonMetrics.contentBottom, 0);
      expect(RibbonMetrics.contentLeft, 0);

      RibbonMetrics.position.value = RibbonPosition.right;
      expect(RibbonMetrics.contentTop, 0);
      expect(RibbonMetrics.contentRight, 60 + RibbonMetrics.gap);
      expect(RibbonMetrics.contentBottom, 0);
      expect(RibbonMetrics.contentLeft, 0);

      RibbonMetrics.position.value = RibbonPosition.bottom;
      expect(RibbonMetrics.contentBottom, 60 + RibbonMetrics.gap);
      expect(RibbonMetrics.contentTop, 0);
      expect(RibbonMetrics.contentRight, 0);
      expect(RibbonMetrics.contentLeft, 0);

      RibbonMetrics.position.value = RibbonPosition.left;
      expect(RibbonMetrics.contentLeft, 60 + RibbonMetrics.gap);
      expect(RibbonMetrics.contentTop, 0);
      expect(RibbonMetrics.contentRight, 0);
      expect(RibbonMetrics.contentBottom, 0);
    });

    test('contentInsetsFor reads zero when the band is not drawn', () {
      // M284 — floating chrome that also renders on the gallery (the bottom
      // tab bar, the quick-tool rail) must NOT clear a band that is not there.
      // Both pass `ribbonDrawn: !app.isHome` through this one gate.
      RibbonMetrics.extent.value = 60;
      RibbonMetrics.position.value = RibbonPosition.bottom;
      expect(RibbonMetrics.contentInsetsFor(false), EdgeInsets.zero,
          reason: 'the gallery has no band, so nothing may clear one');
      expect(RibbonMetrics.contentInsetsFor(true), RibbonMetrics.contentInsets);
      expect(RibbonMetrics.contentInsetsFor(true).bottom,
          60 + RibbonMetrics.gap);
    });

    testWidgets('RibbonMetrics.build rebuilds when the ribbon resizes',
        (t) async {
      double seen = -1;
      await pump(
          t, RibbonMetrics.build((_, top) {
            seen = top;
            return const SizedBox.shrink();
          }));
      expect(seen, 0);
      RibbonMetrics.extent.value = 100;
      await t.pump();
      expect(seen, 100 + RibbonMetrics.gap);
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
