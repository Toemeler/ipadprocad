// M351 — one icon size, one row, and the Appearance panel inside its band.
//
// Two reports, both about the band M349 left behind:
//
//   "When the names are hidden every icon should be the same size in the
//    ribbon." — it drew two: 34 pt for a Create button (a size that only made
//    sense under a word) and 18 pt for a row in a list. With the words gone
//    that distinction carries nothing, and a grid of pictures in two sizes
//    reads as a mistake.
//
//   "The dropdowns in Aussehen also have to be redesigned with icons because
//    they go over the edge currently." — they did, measurably: five chips of
//    130 pt and up, stacked 150 pt tall in a band that is 78, and 30 to 115
//    pixels wider than a 168 pt rail. That last one was there with the names
//    ON as well, which makes it a bug this milestone inherited rather than one
//    it created.
//
// And one clarification, which is why the constraint grid is tested apart from
// everything else: "just on the constraint icons in the sketch mode they can
// be 2 rowed."
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _screen = Size(1600, 900);

AppState _sketch() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m351s');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

AppState _part() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m351p');
  app.parts['P'] = PartModel('P');
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

Future<void> _pump(WidgetTester t, AppState app,
    {required bool names, RibbonPosition dock = RibbonPosition.top}) async {
  RibbonDock.set(dock);
  RibbonLabels.set(names);
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(app: app, stage: const SizedBox.expand()),
    ),
  ));
  await t.pump();
}

/// Every icon the band actually drew, as its rendered size.
Set<Size> _iconSizes(WidgetTester t) => {
      for (final e in find
          .descendant(
              of: find.byType(Ribbon), matching: find.byType(SvgPicture))
          .evaluate())
        (e.renderObject! as RenderBox).size
    };

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
  group('one icon size', () {
    testWidgets('every icon in the compact band is the same size', (t) async {
      await _pump(t, _sketch(), names: false);
      final sizes = _iconSizes(t);
      expect(sizes, isNotEmpty, reason: 'the band drew no icons at all');
      expect(sizes, hasLength(1),
          reason: 'a grid of pictures in two sizes reads as a mistake: $sizes');
      expect(sizes.single,
          const Size(RibbonMetrics.compactIcon, RibbonMetrics.compactIcon));
    });

    testWidgets('the part band too, where the Appearance glyphs are',
        (t) async {
      await _pump(t, _part(), names: false);
      expect(_iconSizes(t), hasLength(1));
    });

    testWidgets('with the names on it keeps the two sizes that mean something',
        (t) async {
      // 34 under a word is a Create button; 18 beside one is a row. The
      // distinction is only empty once the words are gone.
      await _pump(t, _sketch(), names: true);
      final sizes = _iconSizes(t);
      expect(sizes, contains(const Size(RibbonMetrics.bigIconNamed,
          RibbonMetrics.bigIconNamed)));
      expect(sizes, contains(const Size(RibbonMetrics.smallIconNamed,
          RibbonMetrics.smallIconNamed)));
    });
  });

  // -------------------------------------------------------------------------
  group('one row, and the one exception', () {
    /// Three boxes through [smallStack], which is the helper every panel of
    /// small rows goes through.
    Future<List<Offset>> stack(WidgetTester t, {required bool names}) async {
      RibbonLabels.set(names);
      RibbonDock.set(RibbonPosition.top);
      await t.binding.setSurfaceSize(_screen);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            smallStack(const [
              SizedBox(key: Key('a'), width: 20, height: 20),
              SizedBox(key: Key('b'), width: 20, height: 20),
              SizedBox(key: Key('c'), width: 20, height: 20),
            ])
          ]),
        ),
      ));
      await t.pump();
      return [
        for (final k in ['a', 'b', 'c']) t.getTopLeft(find.byKey(Key(k)))
      ];
    }

    testWidgets('a panel of small rows lies flat when compact', (t) async {
      final p = await stack(t, names: false);
      expect({p[0].dy, p[1].dy, p[2].dy}, hasLength(1),
          reason: 'one row: same top for all three');
      expect(p[0].dx < p[1].dx && p[1].dx < p[2].dx, isTrue,
          reason: 'and they run across, in order');
    });

    testWidgets('and stacks them when the names are on', (t) async {
      final p = await stack(t, names: true);
      expect({p[0].dx, p[1].dx, p[2].dx}, hasLength(1));
      expect(p[0].dy < p[1].dy && p[1].dy < p[2].dy, isTrue);
    });

    /// Where the eleven constraint cells sit, by their tooltips — which is
    /// how that grid has named its icon-only cells since M10.
    List<Offset> cells(WidgetTester t) {
      final l = L.current;
      return [
        for (final name in [
          l.conCoincident,
          l.conCollinear,
          l.conConcentric,
          l.conLock,
          l.conParallel,
          l.conPerpendicular,
          l.conHorizontal,
          l.conVertical,
          l.conTangent,
          l.conSymmetric,
          l.conEqual,
        ])
          t.getTopLeft(find.byTooltip(name))
      ];
    }

    testWidgets('the constraint grid keeps its two rows', (t) async {
      // "just on the constraint icons in the sketch mode they can be 2 rowed"
      // — the one panel that may, because eleven icons in a line would be a
      // panel the width of the screen.
      await _pump(t, _sketch(), names: false);
      final rows = {for (final p in cells(t)) p.dy};
      expect(rows, hasLength(2), reason: 'six wide and two deep');
    });

    testWidgets('and three with the names on, as it always had', (t) async {
      await _pump(t, _sketch(), names: true);
      expect({for (final p in cells(t)) p.dy}, hasLength(3));
    });
  });

  // -------------------------------------------------------------------------
  group('the Appearance panel fits its band', () {
    // A RenderFlex overflow throws in a test, so pumping IS the assertion —
    // and it is the assertion that would have failed before this milestone on
    // the two named rails (by 30, 88 and 115 pixels).
    for (final dock in RibbonPosition.values) {
      for (final names in [true, false]) {
        testWidgets('$dock, names=$names: nothing runs over the edge',
            (t) async {
          await _pump(t, _part(), names: names, dock: dock);
          expect(find.byType(Ribbon), findsOneWidget);
        });
      }
    }

    testWidgets('compact, the five controls are glyphs at the band size',
        (t) async {
      await _pump(t, _part(), names: false);
      // The material's glyph is its SWATCH — the value is a colour, so no icon
      // had to be drawn for it — and it is the same size as the rest.
      final swatches = find
          .descendant(of: find.byType(Ribbon), matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size)
          .where((s) =>
              s.width == RibbonMetrics.compactIcon &&
              s.height == RibbonMetrics.compactIcon);
      expect(swatches, isNotEmpty,
          reason: 'the appearance swatch is drawn at the band s icon size');
    });

    testWidgets('and they still name themselves', (t) async {
      // The word is gone from the chip, so the tooltip carries the control AND
      // its current value: a glyph can only say one of the two.
      await _pump(t, _part(), names: false);
      final tips = find
          .descendant(of: find.byType(Ribbon), matching: find.byType(Tooltip))
          .evaluate()
          .map((e) => (e.widget as Tooltip).message)
          .whereType<String>()
          .where((m) => m.startsWith('${L.current.panelAppearance}: '));
      expect(tips, isNotEmpty);
    });

    testWidgets('with names on the chips are still chips', (t) async {
      await _pump(t, _part(), names: true);
      expect(find.text(L.current.matPickBody), findsOneWidget,
          reason: 'the material chip says what it is set to, in words');
    });
  });
}
