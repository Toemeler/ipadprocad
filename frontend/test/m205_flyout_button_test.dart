// M205 — THE FLYOUT OPENER, AND WHAT COUNTS AS CANCELLING A MENU.
//
// Two reports from the same three minutes of the 2026-08-05 session:
//
//   "the arrow to expand the list on rectangle or circle for example is really
//    small and difficult to hit with pencil or touch. fix this and try to show
//    it more. not just a tiny arrow maybe a swift button or something i can
//    actually see is a button"
//
//   "when a context menu is open and i click anywhere else this should count
//    as a cancel."
//
// The first was a 7.5-pixel glyph in an invisible 40x14 box. The second was a
// barrier built on GestureDetector.onTap: a tap has to WIN THE GESTURE ARENA,
// and a trackpad click that jitters, a Pencil that rolls, or a press that
// turns into a drag is legitimately not a tap — so the menu stayed up. Both
// are geometry and plumbing, both are testable on the host, and neither can
// regress quietly again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/menus.dart';
import 'package:prototype/widgets/quick_tools.dart';
import 'package:prototype/widgets/ribbon.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m205');
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

/// The flyout chip belonging to a named ribbon button — the one directly
/// BELOW its label, which is where the split button puts it.
Finder chipUnder(WidgetTester t, String label) {
  final anchor = t.getCenter(find.text(label));
  Element? best;
  var bestScore = double.infinity;
  for (final e in find.byIcon(Icons.arrow_drop_down).evaluate()) {
    final box = e.renderObject! as RenderBox;
    final c = box.localToGlobal(box.size.center(Offset.zero));
    if (c.dy < anchor.dy) continue; // the chip hangs under the label
    final score = (c.dx - anchor.dx).abs() * 4 + (c.dy - anchor.dy);
    if (score < bestScore) {
      bestScore = score;
      best = e;
    }
  }
  expect(best, isNotNull, reason: 'no flyout chip under "$label"');
  return find.byWidget(best!.widget);
}

/// The tappable box around a chip's glyph.
Size chipTarget(WidgetTester t, String label) => t.getSize(find
    .ancestor(of: chipUnder(t, label), matching: find.byType(GestureDetector))
    .first);

void main() {
  setUp(OpenMenus.reset);

  group('the opener is a button you can see and hit', () {
    testWidgets('every split button carries a drawn chip, not a bare glyph',
        (t) async {
      await pump(t, Ribbon(app: makeApp()));
      // Line, Circle, Arc, Rectangle on the Create panel, plus the small rows
      // that have flyouts (Fillet, Text). If this ever drops back to a Text
      // widget the icon disappears with it.
      expect(find.byIcon(Icons.arrow_drop_down),
          findsAtLeastNWidgets(4));
    });

    testWidgets('the target is far bigger than the 40x14 it replaced',
        (t) async {
      await pump(t, Ribbon(app: makeApp()));
      for (final label in const ['Line', 'Circle', 'Arc', 'Rectangle']) {
        final s = chipTarget(t, label);
        expect(s.width, greaterThanOrEqualTo(44), reason: label);
        expect(s.height, greaterThanOrEqualTo(26), reason: label);
        expect(s.width * s.height, greaterThan(40 * 14 * 2),
            reason: '$label: more than double the old area');
      }
    });

    testWidgets('tapping the chip opens that button\'s list', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await t.tap(chipUnder(t, 'Rectangle'));
      await t.pumpAndSettle();
      // The Rectangle flyout, and no other: "Two Point" is its first variant.
      expect(find.text('Two Point'), findsOneWidget);
      // ...and only the Rectangle one. (Not "Center Point" as the probe: the
      // Slot variants in this very list have one.)
      expect(find.text('Ellipse'), findsNothing, reason: 'that is Circle');
    });

    testWidgets('the chip is BESIDE the body, not on top of it', (t) async {
      // A miss on the old arrow landed on the button body and started the
      // default tool instead of opening the list. The two targets must not
      // overlap.
      await pump(t, Ribbon(app: makeApp()));
      final chip = t.getRect(find
          .ancestor(
              of: chipUnder(t, 'Rectangle'), matching: find.byType(GestureDetector))
          .first);
      final label = t.getRect(find.text('Rectangle'));
      expect(chip.top, greaterThanOrEqualTo(label.bottom - 1));
    });
  });

  group('a click anywhere else cancels the menu', () {
    testWidgets('a bare pointer DOWN closes it — no tap required', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await t.tap(chipUnder(t, 'Rectangle'));
      await t.pumpAndSettle();
      expect(find.text('Two Point'), findsOneWidget);

      // Down and nothing else. This never becomes a tap, which is exactly the
      // case the old GestureDetector barrier could not see.
      final g = await t.startGesture(const Offset(800, 700));
      await t.pump();
      expect(find.text('Two Point'), findsNothing);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('a press that turns into a DRAG closes it too', (t) async {
      await pump(t, Ribbon(app: makeApp()));
      await t.tap(chipUnder(t, 'Rectangle'));
      await t.pumpAndSettle();

      final g = await t.startGesture(const Offset(800, 700));
      await g.moveBy(const Offset(120, 60));
      await t.pump();
      expect(find.text('Two Point'), findsNothing,
          reason: 'a drag is not a tap, and it still means "not the menu"');
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('a click ON the menu still picks, and does not self-cancel',
        (t) async {
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await t.tap(chipUnder(t, 'Rectangle'));
      await t.pumpAndSettle();
      await t.tap(find.text('Three Point'));
      await t.pumpAndSettle();
      expect(app.tool, Tool.rect3P);
      expect(find.text('Two Point'), findsNothing, reason: 'picking closes it');
    });
  });

  group('a tap on NATIVE chrome is a click somewhere else', () {
    testWidgets('the quick-tool bar closes an open flyout', (t) async {
      // The bar is a UIKit platform view: its tap comes back over a method
      // channel, past every Flutter barrier. Without the register this was the
      // one click that left a menu standing.
      final app = makeApp();
      await pump(t, Ribbon(app: app));
      await t.tap(chipUnder(t, 'Rectangle'));
      await t.pumpAndSettle();
      expect(OpenMenus.any, isTrue);

      runQuickTool(app, QuickToolId.cancel);
      await t.pumpAndSettle();
      expect(find.text('Two Point'), findsNothing);
      expect(OpenMenus.any, isFalse);
    });
  });

  group('OpenMenus', () {
    test('closeAll runs every closer exactly once and empties the register',
        () {
      var a = 0, b = 0;
      late VoidCallback ca, cb;
      // Each closer unregisters itself on the way out, like the real ones.
      ca = () {
        a++;
        OpenMenus.unregister(ca);
      };
      cb = () {
        b++;
        OpenMenus.unregister(cb);
      };
      OpenMenus.register(ca);
      OpenMenus.register(cb);
      expect(OpenMenus.count, 2);

      OpenMenus.closeAll();
      expect([a, b], [1, 1]);
      expect(OpenMenus.any, isFalse);

      OpenMenus.closeAll();
      expect([a, b], [1, 1], reason: 'nothing left to close');
    });

    test('registering the same closer twice registers it once', () {
      void c() {}
      OpenMenus.register(c);
      OpenMenus.register(c);
      expect(OpenMenus.count, 1);
      OpenMenus.reset();
    });
  });
}
