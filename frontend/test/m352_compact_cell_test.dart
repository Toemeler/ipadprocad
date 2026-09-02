// M352 — one cell, and a rail that lines up on it.
//
//   "They are not aligned and are very weird. It doesn't look good."
//
// Two screenshots of the compact vertical rail, and what they showed was five
// different boxes in one column. M349 took the words away and M351 made every
// glyph 24 pt, but each control kept the FRAME it was given when it had a word
// under it: a Create button was as wide as the 46 x 26 flyout pill hanging
// below it (which with no label above it read as an empty grey lozenge), a
// small row was 26 pt tall and laid out from the LEFT while its neighbours
// centred, a constraint was a 30 pt square on a 1 pt gap, an Appearance
// dropdown a 36 pt square with a permanent fill and border on a gap of none.
// A panel holding a single button stretched it to the rail's full width; a
// panel holding three did not.
//
// So the measurements this file makes are all the same measurement, taken from
// three directions:
//
//   * every control in a nameless band is ONE size — RibbonMetrics.compactCell
//     square, whatever widget draws it;
//   * in a RAIL they sit on two x-columns, and in a BAND on two y-lines;
//   * and the band got THINNER doing it, rather than trading raggedness for
//     height — 94 pt against the named band's 112, with a glyph four points
//     BIGGER than M351's ("I think the icons could be bigger").
//
// The behaviour that changed with the shape is tested too: a split button's
// list is now a LONG PRESS, because the chip that used to open it is bigger
// than the cell it would hang under.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/display_mode.dart';
import 'package:prototype/materials.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _screen = Size(1600, 900);

AppState _sketch() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m352s');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

AppState _part() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m352p');
  app.parts['P'] = PartModel('P');
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

Future<Size> _pump(WidgetTester t, AppState app,
    {required bool names, required RibbonPosition dock}) async {
  RibbonDock.set(dock);
  RibbonLabels.set(names);
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(app: app, stage: const SizedBox.expand()),
    ),
  ));
  await t.pump();
  return t.getSize(find.byType(Ribbon));
}

/// Every command cell the band drew, as (rect). A cell is what the whole
/// compact band is made of, so finding them by their tooltip — the only name a
/// nameless button has — would miss the ones whose label happens to repeat;
/// they are found by their SIZE instead, which is the claim itself.
List<Rect> _cells(WidgetTester t) {
  final out = <Rect>[];
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro is RenderBox &&
        ro.hasSize &&
        e.widget.runtimeType.toString() == '_CompactCell') {
      out.add(ro.localToGlobal(Offset.zero) & ro.size);
    }
    e.visitChildren(walk);
  }
  walk(find.byType(Ribbon).evaluate().single);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    L.set(kDe);
    RibbonLabels.resetForTest();
    RibbonDock.resetForTest();
  });
  tearDown(() {
    RibbonLabels.resetForTest();
    RibbonDock.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('one shape', () {
    for (final dock in RibbonPosition.values) {
      testWidgets('$dock: every control is the same square', (t) async {
        await _pump(t, _sketch(), names: false, dock: dock);
        final cells = _cells(t);
        expect(cells.length, greaterThan(20),
            reason: 'the sketch ribbon should be mostly cells by now');
        expect({for (final c in cells) c.size}, {
          const Size(RibbonMetrics.compactCell, RibbonMetrics.compactCell)
        }, reason: 'a rail of boxes of five widths is the report itself');
      });
    }

    testWidgets('the part band too, Appearance dropdowns included', (t) async {
      await _pump(t, _part(), names: false, dock: RibbonPosition.right);
      expect({for (final c in _cells(t)) c.size}, {
        const Size(RibbonMetrics.compactCell, RibbonMetrics.compactCell)
      });
    });

    testWidgets('and with the names on, nothing is a cell at all', (t) async {
      // The named band keeps M205's chip, M235's label floors and the two
      // icon sizes M351 kept for it. This milestone is about the OTHER band.
      await _pump(t, _sketch(), names: true, dock: RibbonPosition.top);
      expect(_cells(t), isEmpty);
      expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  group('a grid, not a column of odds and ends', () {
    testWidgets('a rail puts every cell on one of two columns', (t) async {
      await _pump(t, _sketch(), names: false, dock: RibbonPosition.right);
      final xs = {for (final c in _cells(t)) c.left};
      expect(xs, hasLength(2),
          reason: 'two columns of 32 and a 2 pt gap is what the rail is '
              'WIDE for; anything else is a cell that stretched: $xs');
      final sorted = xs.toList()..sort();
      // The gap between the two columns IS the cell plus the band's one gap:
      // no cell is wider than the square, so no column can start later.
      expect(sorted[1] - sorted[0],
          RibbonMetrics.compactCell + RibbonMetrics.compactGap);
    });

    testWidgets('a band puts every cell on one of two lines', (t) async {
      // Two, because the constraint grid is two rows deep by request and
      // nothing else in the band is deeper than that.
      await _pump(t, _sketch(), names: false, dock: RibbonPosition.top);
      final ys = {for (final c in _cells(t)) c.top};
      expect(ys, hasLength(2), reason: 'panels centred their own content and '
          'a panel with a title had less to centre in, so neighbouring cells '
          'sat seven points apart: $ys');
      final sorted = ys.toList()..sort();
      expect(sorted[1] - sorted[0],
          RibbonMetrics.compactCell + RibbonMetrics.compactGap);
    });

    testWidgets('a panel holding one button does not stretch it', (t) async {
      // Project Geometry and Start New Layer come to _panel as a bare button
      // rather than through _flow, so the panel's own `stretch` (rail) and
      // `Expanded` (band) reached them: 68 x 32 in a rail of 32s, 32 x 80 in
      // a band of 32s.
      for (final dock in RibbonPosition.values) {
        await _pump(t, _sketch(), names: false, dock: dock);
        for (final label in [
          L.current.btnProjectGeometry,
          L.current.btnStartNewLayer,
        ]) {
          expect(t.getSize(find.byTooltip(label.replaceAll('\n', ' '))),
              const Size(RibbonMetrics.compactCell, RibbonMetrics.compactCell),
              reason: '$dock / $label');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('and it is still the thinner band', () {
    testWidgets('the cell size is set by the BAND, not by the rail', (t) async {
      // The first cut of this milestone measured 118 pt at exactly today's
      // cell size — a compact band TALLER than the one it replaced — because
      // three panels still stacked their small rows three deep instead of
      // reflowing. The cell is not the knob; the reflow is.
      final named =
          await _pump(t, _sketch(), names: true, dock: RibbonPosition.top);
      final compact =
          await _pump(t, _sketch(), names: false, dock: RibbonPosition.top);
      expect(compact.height, lessThan(named.height * 0.85),
          reason: 'measured 112 -> 94: ${compact.height} vs ${named.height}');
    });

    testWidgets('and the rail is narrower than M351 left it', (t) async {
      final compact =
          await _pump(t, _sketch(), names: false, dock: RibbonPosition.right);
      expect(compact.width, RibbonMetrics.railWidthCompact);
      expect(compact.width, lessThan(88),
          reason: 'two cells fit in less rail than M351 needed for cells that '
              'were SMALLER, because the panel padding came in with them');
      // Two cells, their gap, and the panel's padding — and the two points of
      // slack that keep a rounding error from being an overflow.
      expect(
          compact.width,
          greaterThanOrEqualTo(
              2 * RibbonMetrics.compactCell + RibbonMetrics.compactGap + 8));
    });

    testWidgets('every dock lays out without overflowing, both ways',
        (t) async {
      // A RenderFlex overflow throws in a test, so pumping IS the assertion.
      for (final app in [_sketch, _part]) {
        for (final dock in RibbonPosition.values) {
          for (final names in [true, false]) {
            final size = await _pump(t, app(), names: names, dock: dock);
            expect(size.width, greaterThan(0), reason: '$dock names=$names');
          }
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the flyout, and what it costs', () {
    testWidgets('a cell with a list says so in its corner', (t) async {
      await _pump(t, _sketch(), names: false, dock: RibbonPosition.top);
      // Rectangle is a split button (M85); Point is not.
      expect(
          find.descendant(
              of: find.byTooltip(L.current.btnRectangle),
              matching: find.text('▾')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byTooltip(L.current.btnPoint),
              matching: find.text('▾')),
          findsNothing);
    });

    testWidgets('a tap runs the default command', (t) async {
      final app = _sketch();
      await _pump(t, app, names: false, dock: RibbonPosition.top);
      await t.tap(find.byTooltip(L.current.btnRectangle));
      await t.pump();
      expect(app.tool, Tool.rectTwoPoint,
          reason: 'the body is still the default tool, as in Inventor');
    });

    testWidgets('a long press opens the list', (t) async {
      // The trade M352 makes and states: M205's 46 x 26 chip is bigger than
      // the cell it would hang under, so in the compact band the opener is the
      // gesture iOS already uses for "show me the options". Turn the names
      // back on and the chip is there, at full size.
      final app = _sketch();
      await _pump(t, app, names: false, dock: RibbonPosition.top);
      expect(find.text(L.current.flySlotB), findsNothing);
      await t.longPress(find.byTooltip(L.current.btnRectangle));
      await t.pumpAndSettle();
      expect(find.text(L.current.flySlotB), findsWidgets,
          reason: 'the variants of a split button must stay reachable');
    });

    testWidgets('an Appearance dropdown opens on a plain tap', (t) async {
      // It has no default command to run — the list IS what the control does,
      // so it must not need the long press the split buttons now take.
      final app = _part();
      await _pump(t, app, names: false, dock: RibbonPosition.top);
      final l = L.current;
      final chip = find.byTooltip(
          '${l.panelAppearance}: ${displayModeName(l, app.displayMode)}');
      expect(chip, findsOneWidget);
      await t.tap(chip);
      await t.pumpAndSettle();
      expect(find.text(displayModeName(l, DisplayMode.values.last)),
          findsWidgets, reason: 'the whole list, one tap in');
    });

    testWidgets('a disabled cell takes neither gesture', (t) async {
      // The material is a body's, and nothing is selected: M351 already drew
      // it dim, and a cell that looks dead has to BE dead.
      final app = _part();
      await _pump(t, app, names: false, dock: RibbonPosition.top);
      expect(app.canSetMaterial, isFalse);
      final chip = find.byTooltip(
          '${L.current.panelAppearance}: ${L.current.matPickBody}');
      await t.tap(chip);
      await t.pumpAndSettle();
      expect(find.text(materialName(L.current, kMaterialSteel)), findsNothing);
    });
  });
}
