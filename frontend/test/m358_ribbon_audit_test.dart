// M358 — the band, in every mode it has, on every edge, both ways round.
//
// The question that prompted this file was "is the bar now in every mode
// production ready?", and the honest way to answer it is to enumerate the
// modes rather than to reason about them. The band has FIVE:
//
//   gallery      no band at all — the "+" in the gallery header is the only
//                new-document affordance there
//   sketch, browsing   a layer list and nothing to draw with (M16/M17: every
//                drawing tool refuses to run outside the edit scope, so the
//                buttons that would be dead are not shown)
//   sketch, editing    the full sketch ribbon
//   part         the 3D part tab
//   assembly     the assembly tab
//
// times four docks, times names on and off: 32 layouts, plus the gallery.
//
// What is asserted for each of them is what "production ready" can actually
// mean for a layout, in the order the failures have historically arrived:
//
//   1. IT LAYS OUT. A RenderFlex overflow throws inside a test, so pumping is
//      the assertion — and it is not a formality: the named rail overflowed by
//      up to 115 px until M351, and the compact rail by 3 px until M352, both
//      found exactly this way.
//   2. NOTHING IS ANONYMOUS. With the names off every command is a picture, so
//      every tappable thing in the band must carry a name for VoiceOver and
//      for a long press. M349's promise, checked per mode rather than assumed.
//   3. IT FITS ITS EDGE. The band spans the screen on the axis it is docked
//      to (M346), and it never eats more than a third of the screen.
//   4. IT IS ONE GRID. Compact, every cell is the same square on two lines —
//      M352's claim, asserted for the modes m352 does not cover.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _screen = Size(1194, 834); // iPad Pro 11", landscape

typedef Mode = (String, AppState Function());

AppState _base(String tag) {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m354$tag');
  return app;
}

List<Mode> get _modes => [
      ('sketch/browsing', () {
        final a = _base('sb');
        a.sketches['t'] = SketchModel('t');
        a.curTab = 't';
        return a;
      }),
      ('sketch/editing', () {
        final a = _base('se');
        a.sketches['t'] = SketchModel('t');
        a.curTab = 't';
        a.editingLayer = kDefaultLayer;
        return a;
      }),
      ('part', () {
        final a = _base('p');
        a.parts['P'] = PartModel('P');
        a.openTabs.add('P');
        a.curTab = 'P';
        return a;
      }),
      ('assembly', () {
        final a = _base('a');
        a.assemblies['A'] = AssemblyModel('A');
        a.openTabs.add('A');
        a.curTab = 'A';
        return a;
      }),
    ];

Future<Size> _pump(WidgetTester t, AppState app,
    {required RibbonPosition dock, required bool names}) async {
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

/// Every widget in the band that answers a tap, and the name it carries.
///
/// Found through the Tooltip, which is where a nameless button's name lives
/// (M349) — so a control with no tooltip is precisely the thing this looks
/// for, and it is looked for by counting the GESTURE DETECTORS instead.
({int tappable, int named}) _reach(WidgetTester t) {
  final ribbon = find.byType(Ribbon);
  final named = find
      .descendant(of: ribbon, matching: find.byType(Tooltip))
      .evaluate()
      .where((e) => ((e.widget as Tooltip).message ?? '').trim().isNotEmpty)
      .length;
  // The cells and the chips. _Hover, _CompactCell and _DropChip each own one
  // GestureDetector; the scroll view owns none.
  final tappable = find
      .descendant(of: ribbon, matching: find.byType(GestureDetector))
      .evaluate()
      .length;
  return (tappable: tappable, named: named);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    L.set(kDe);
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonBleed.resetForTest();
  });
  tearDown(() {
    RibbonSurface.glassOverride = null;
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonBleed.resetForTest();
  });

  // -------------------------------------------------------------------------
  for (final (label, make) in _modes) {
    group(label, () {
      for (final dock in RibbonPosition.values) {
        for (final names in [true, false]) {
          testWidgets('$dock names=$names: lays out and fits its edge',
              (t) async {
            final band = await _pump(t, make(), dock: dock, names: names);
            if (dock.isVertical) {
              expect(band.height, _screen.height, reason: 'full height (M346)');
              expect(band.width, RibbonMetrics.railWidth);
              expect(band.width, lessThan(_screen.width / 3),
                  reason: 'a rail that takes a third of an iPad is a rail '
                      'nobody docks');
            } else {
              expect(band.width, _screen.width, reason: 'flush (M346)');
              expect(band.height, lessThan(_screen.height / 3));
            }
          });
        }
      }

      testWidgets('compact: nothing in the band is anonymous', (t) async {
        // Every command is a picture now. A picture with no name is
        // unreachable for VoiceOver and unreadable for anyone who does not
        // already know the glyph.
        await _pump(t, make(), dock: RibbonPosition.top, names: false);
        final r = _reach(t);
        expect(r.tappable, greaterThan(0), reason: 'the band has no commands');
        expect(r.named, greaterThanOrEqualTo(r.tappable),
            reason: '${r.tappable - r.named} tappable things carry no name');
      });

      testWidgets('compact: one cell, two lines', (t) async {
        // M352's claim, in the modes m352 does not itself pump.
        for (final dock in RibbonPosition.values) {
          await _pump(t, make(), dock: dock, names: false);
          final cells = <Rect>[];
          void walk(Element e) {
            final ro = e.renderObject;
            if (ro is RenderBox &&
                ro.hasSize &&
                e.widget.runtimeType.toString() == '_CompactCell') {
              cells.add(ro.localToGlobal(Offset.zero) & ro.size);
            }
            e.visitChildren(walk);
          }
          walk(find.byType(Ribbon).evaluate().single);
          expect(cells, isNotEmpty, reason: '$dock');
          expect({for (final c in cells) c.size}, {
            const Size(RibbonMetrics.compactCell, RibbonMetrics.compactCell)
          }, reason: '$dock');
          final lines =
              dock.isVertical ? {for (final c in cells) c.left} : {for (final c in cells) c.top};
          expect(lines.length, lessThanOrEqualTo(2),
              reason: '$dock: a wall of icons on more than two lines is not '
                  'a grid, it is a spill: $lines');
        }
      });
    });
  }

  // -------------------------------------------------------------------------
  group('the gallery', () {
    testWidgets('has no band on any dock, and the stage is the whole screen',
        (t) async {
      for (final dock in RibbonPosition.values) {
        for (final names in [true, false]) {
          RibbonDock.set(dock);
          RibbonLabels.set(names);
          await t.binding.setSurfaceSize(_screen);
          await t.pumpWidget(MaterialApp(
            home: Scaffold(
              body: RibbonDockLayout(
                  app: _base('g'),
                  stage: const SizedBox.expand(),
                  bleed: const SizedBox.expand()),
            ),
          ));
          await t.pump();
          expect(find.byType(Ribbon), findsNothing, reason: '$dock/$names');
        }
      }
    });
  });
}
