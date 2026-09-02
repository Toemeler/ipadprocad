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

/// M359 — the cells are laid out SYMMETRICALLY about the band's centre line.
///
/// Stated on the centres rather than the edges, because that is what symmetry
/// is: for every cell centre there is a matching one the same distance the
/// other side of the band's own middle. A lone cell on the centre matches
/// itself; a pair straddling it matches each other; a row packed against one
/// edge — which is what this replaced — matches nothing.
void _symmetric(WidgetTester t, List<Rect> cells, {required bool horizontal}) {
  expect(cells, isNotEmpty);
  final band = t.getTopLeft(find.byType(Ribbon)) & t.getSize(find.byType(Ribbon));
  // Down a rail the middle is the band's own; across a band the cells centre
  // in the panel BODY, which is the band less the title strip every compact
  // panel reserves at its foot (RibbonMetrics.compactTitleH).
  final mid = horizontal
      ? band.center.dx
      : band.top + (band.height - RibbonMetrics.compactTitleH) / 2;
  double at(Rect c) => horizontal ? c.center.dx : c.center.dy;
  final centres = {for (final c in cells) (at(c) * 2).round() / 2};
  for (final c in centres) {
    final mirror = 2 * mid - c;
    expect(centres.any((o) => (o - mirror).abs() <= 1.5), isTrue,
        reason: 'a cell at $c has nothing at ${mirror.toStringAsFixed(1)}; '
            'centres=$centres, band middle=${mid.toStringAsFixed(1)}');
  }
  // And the block as a whole sits on that line, rather than merely being
  // mirror-shaped somewhere else on the band.
  final lo = cells.map(at).reduce((a, b) => a < b ? a : b);
  final hi = cells.map(at).reduce((a, b) => a > b ? a : b);
  expect(((lo + hi) / 2 - mid).abs(), lessThanOrEqualTo(1.5));
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
    testWidgets('a rail is symmetric about its own centre line', (t) async {
      // M352 asserted TWO columns here, packed to the leading edge. M359
      // replaced that claim on report: a panel with an odd number of commands
      // left its last cell hanging on the left with a hole beside it, seven
      // times down the rail — "not 3 on the right and 1 on the left just 2 and
      // 2". The runs are centred now, so a lone cell sits on the rail's own
      // centre line and a pair straddles it. Symmetry is the stronger claim,
      // and it is the one that was actually wanted.
      await _pump(t, _sketch(), names: false, dock: RibbonPosition.right);
      _symmetric(t, _cells(t), horizontal: true);
    });

    testWidgets('a band is symmetric about its own centre line', (t) async {
      // The same replacement on the other axis. M352 put every cell on the
      // band's TOP line because centring made neighbouring panels disagree by
      // seven points: a panel with an overflow " + chevron + " had less body
      // to centre in than one without. M359 reserves that strip on every
      // compact panel, so the bodies match and centring lines up — a one-row
      // panel sits on the band's centre, the constraint grid straddles it.
      await _pump(t, _sketch(), names: false, dock: RibbonPosition.top);
      _symmetric(t, _cells(t), horizontal: false);
    });

    testWidgets('and a band with no grid in it is ONE row', (t) async {
      // "most important stuff should be in 1 row" — the part tab has no
      // eleven-cell grid, so nothing in it wraps: one row of cells, and a band
      // that is that row plus its chrome.
      await _pump(t, _part(), names: false, dock: RibbonPosition.top);
      expect({for (final c in _cells(t)) c.top}, hasLength(1));
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
