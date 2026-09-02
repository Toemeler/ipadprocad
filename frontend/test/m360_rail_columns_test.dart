// M360 — the rail stacks its commands under each other until they stop fitting.
//
//   "They should be under each other not next to each other until there's not
//    enough space."
//
// One column is the shape a rail wants: a strip you read down, 46 points wide
// against two columns' 84. It is not always possible — the full sketch ribbon
// is 33 cells over eight panels, which stacked singly comes to some 1300
// points against an iPad's 834 — so the rule is a fit test, not a preference,
// and the same document can answer it differently in portrait and landscape.
//
// HOW THE FIT IS DECIDED, because it is the whole of this milestone. Every
// compact panel lays its cells out in a Wrap, and a Wrap can say how tall it
// would be at any width. So the rail asks its own content
// `getMaxIntrinsicHeight` at ONE CELL's width — the exact height of the
// one-column layout, computed by the very widgets that would draw it, and
// computed at that fixed width whatever the rail is currently doing. That last
// part is what makes it stable: a measurement of the CURRENT layout would flip
// for ever (one column overflows, so use two, which fits, so use one).
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

const Size _landscape = Size(1194, 834); // iPad Pro 11"
const Size _portrait = Size(834, 1194);

AppState _sketch() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m360s');
  a.sketches['t'] = SketchModel('t');
  a.curTab = 't';
  a.editingLayer = kDefaultLayer;
  return a;
}

AppState _part() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m360p');
  a.parts['P'] = PartModel('P');
  a.openTabs.add('P');
  a.curTab = 'P';
  return a;
}

AppState _assembly() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m360a');
  a.assemblies['A'] = AssemblyModel('A');
  a.openTabs.add('A');
  a.curTab = 'A';
  return a;
}

Future<Size> _pump(WidgetTester t, AppState app,
    {Size screen = _landscape,
    RibbonPosition dock = RibbonPosition.right,
    bool names = false}) async {
  RibbonDock.set(dock);
  RibbonLabels.set(names);
  await t.binding.setSurfaceSize(screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(app: app, stage: const SizedBox.expand()),
    ),
  ));
  // The decision is taken during layout and published on the frame after it,
  // like every other value this band measures about itself.
  await t.pump();
  await t.pump();
  return t.getSize(find.byType(Ribbon));
}

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
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonRail.resetForTest();
    RibbonBleed.resetForTest();
  });
  tearDown(() {
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonRail.resetForTest();
    RibbonBleed.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('under each other, where they fit', () {
    testWidgets('an assembly rail is ONE column, and half the width for it',
        (t) async {
      final band = await _pump(t, _assembly());
      expect(RibbonRail.columns.value, 1);
      expect(band.width, RibbonMetrics.railWidthCompact1);
      expect(band.width, lessThan(RibbonMetrics.railWidthCompact * 0.6));
      // Under each other means exactly that: one x, top to bottom.
      expect({for (final c in _cells(t)) c.left}, hasLength(1));
    });

    testWidgets('and every cell is still on the rail\'s centre line', (t) async {
      final band = await _pump(t, _assembly());
      final rect = t.getTopLeft(find.byType(Ribbon)) & band;
      for (final c in _cells(t)) {
        expect((c.center.dx - rect.center.dx).abs(), lessThanOrEqualTo(1.5));
      }
    });

    testWidgets('a sketch rail cannot, and says so by being two', (t) async {
      // 33 cells over eight panels is some 1300 points in one column.
      final band = await _pump(t, _sketch());
      expect(RibbonRail.columns.value, 2);
      expect(band.width, RibbonMetrics.railWidthCompact);
      expect({for (final c in _cells(t)) c.left}.length, greaterThan(1));
    });
  });

  // -------------------------------------------------------------------------
  group('it is about the SPACE, not the document', () {
    testWidgets('the same part is one column in portrait and two in landscape',
        (t) async {
      // The clearest statement of the rule there is: nothing about the
      // document changed, only how much room it was given.
      final land = await _pump(t, _part(), screen: _landscape);
      expect(RibbonRail.columns.value, 2, reason: 'landscape');
      expect(land.width, RibbonMetrics.railWidthCompact);

      RibbonRail.resetForTest();
      final port = await _pump(t, _part(), screen: _portrait);
      expect(RibbonRail.columns.value, 1, reason: 'portrait');
      expect(port.width, RibbonMetrics.railWidthCompact1);
    });

    testWidgets('a band is never asked the question', (t) async {
      // Across a band the scarce axis is the other one and the answer is
      // already "one row" (M359); the rail's column count must not leak into
      // it or a top dock would start reflowing on rotation.
      RibbonRail.resetForTest();
      await _pump(t, _assembly(), dock: RibbonPosition.top);
      expect(RibbonRail.columns.value, 2,
          reason: 'a horizontal band publishes nothing, so the value is left '
              'at its default');
    });

    testWidgets('names on, the rail is the named rail and nothing measures',
        (t) async {
      final band = await _pump(t, _assembly(), names: true);
      expect(band.width, RibbonMetrics.railWidthNamed);
    });
  });

  // -------------------------------------------------------------------------
  group('and it settles', () {
    testWidgets('the answer does not flip from frame to frame', (t) async {
      // The oscillation this design exists to avoid: one column overflows, so
      // use two, which fits, so use one, for ever. The measurement is taken at
      // ONE COLUMN'S width whatever the rail is drawing, so it is the same
      // number in both states.
      await _pump(t, _part());
      final settled = RibbonRail.columns.value;
      for (var i = 0; i < 6; i++) {
        await t.pump();
        expect(RibbonRail.columns.value, settled, reason: 'flipped on pump $i');
      }
    });

    testWidgets('and it does not depend on where it started', (t) async {
      // Same document, same screen, opposite starting guess.
      RibbonRail.resetForTest(); // starts at 2
      await _pump(t, _assembly());
      final fromTwo = RibbonRail.columns.value;
      RibbonRail.publish(1);
      await t.pump();
      await _pump(t, _assembly());
      expect(RibbonRail.columns.value, fromTwo);
    });
  });
}
