// M146 — the ribbon's surface became a native Liquid Glass panel and its two
// blue borders became lit edges. The CONTENT did not change, and these tests
// exist mostly to prove that.
//
// Host tests run off iOS, so `RibbonSurface.isGlass` is false here and the
// fallback path is what gets exercised. That is deliberate and is itself the
// most valuable assertion in the file: the day the fallback stops being an
// opaque bar, every non-iOS build silently loses its ribbon background and no
// device test would ever catch it.
//
// The palette assertions are the guard against "fancy" quietly meaning "a
// different blue". The edges may gain a ramp, a sheen and a glow; they may not
// leave `T.ribbonTop` / `T.ribbonBottom`, which come from the binding mock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/theme.dart';
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

Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(1600, 900)}) async {
  await t.binding.setSurfaceSize(size);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
}

void main() {
  group('M146 surface', () {
    testWidgets('the ribbon still builds', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      expect(tester_ok, isTrue);
    });

    testWidgets('the bar draws its background through RibbonSurface',
        (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // Not a hardcoded fill in ribbon.dart: the surface is one widget, so
      // there is exactly one place that decides glass vs. fallback.
      expect(find.byType(RibbonSurface), findsOneWidget);
    });

    testWidgets('off iOS the surface is the mock\'s opaque panel colour',
        (t) async {
      expect(RibbonSurface.isGlass, isFalse,
          reason: 'host tests must exercise the fallback');
      await pump(t, const SizedBox(height: 40, child: RibbonSurface()));
      final box = t.widget<ColoredBox>(find.descendant(
          of: find.byType(RibbonSurface), matching: find.byType(ColoredBox)));
      expect(box.color, T.panel);
    });
  });

  group('M146 edges', () {
    test('thickness is still the mock\'s 2 pt', () {
      expect(RibbonEdgeLine.thickness, 2);
    });

    test('the palette is unchanged', () {
      expect(const RibbonEdgeLine(top: true).core, T.ribbonTop);
      expect(const RibbonEdgeLine(top: false).core, T.ribbonBottom);
      // The sheen is a lightened core, never a new hue: same channel ORDER as
      // the core, just pulled toward white.
      for (final top in [true, false]) {
        final e = RibbonEdgeLine(top: top);
        expect(e.sheen.r, greaterThan(e.core.r));
        expect(e.sheen.b, greaterThanOrEqualTo(e.core.b * 0.9));
      }
    });

    testWidgets('the ribbon has exactly one top and one bottom edge',
        (t) async {
      await pump(t, Ribbon(app: makeApp()));
      final edges = t
          .widgetList<RibbonEdgeLine>(find.byType(RibbonEdgeLine))
          .toList();
      expect(edges.length, 2);
      expect(edges.where((e) => e.top).length, 1);
      expect(edges.where((e) => !e.top).length, 1);
    });

    testWidgets('edges never take touches', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // A 2 pt strip spanning the whole bar sits directly over the top row of
      // every button; if it were hit-testable it would eat those taps.
      expect(
          find.descendant(
              of: find.byType(RibbonEdgeLine),
              matching: find.byType(IgnorePointer)),
          findsNWidgets(2));
    });
  });

  group('M146 scrolling', () {
    testWidgets('the ribbon scrolls horizontally when it overflows',
        (t) async {
      // Narrow enough that the sketch ribbon's panels cannot all fit.
      await pump(t, Ribbon(app: makeApp()), size: const Size(600, 400));
      final sc = t.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).first);
      expect(sc.scrollDirection, Axis.horizontal);

      final st = t.state<ScrollableState>(find.byType(Scrollable).first);
      expect(st.position.maxScrollExtent, greaterThan(0),
          reason: 'the bar must actually overflow at 600 pt');

      await t.drag(find.byType(Ribbon), const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(st.position.pixels, greaterThan(0),
          reason: 'the drag must move the strip, not be swallowed by the '
              'glass background or an edge line');
    });
  });
}

/// Reaching this at all means the pump above did not blow the stack (M51).
const tester_ok = true;
