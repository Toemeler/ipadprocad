// M359 — the band centres what it holds, and holds it symmetrically.
//
//   "Currently the items in the ribbon are at the top. They should be centered
//    and always use all space available. If its possible they should be under
//    each other and if not they should have 2 rows. But always symmetrical if
//    its possible so not 3 on the right and 1 on the left just 2 and 2 for
//    example. Everywhere its possible. But most important stuff should be in
//    1 row."
//
// Four claims, and they are separable, so they are tested separately:
//
//   CENTRED DOWN THE RAIL. A scroll view shrink-wraps its child, so a rail
//   whose panels came to 630 points on an 834 point screen drew them from the
//   top and left 200 points of empty glass underneath. The content now has the
//   viewport's extent as a FLOOR, so a short ribbon centres in the rail and a
//   long one still scrolls.
//
//   CENTRED ACROSS THE BAND. M352 aligned every cell to the band's TOP line,
//   and said why: centring made neighbouring panels disagree by seven points,
//   because a panel with an overflow chevron had less body to centre in than
//   one without. That is fixed at the cause — every compact panel reserves the
//   same title strip (RibbonMetrics.compactTitleH) — so centring lines up now,
//   and the compact panel padding is symmetric top to bottom, which was one
//   further point of "not centred" on every cell in the band.
//
//   SYMMETRIC. A panel with an odd number of commands used to leave its last
//   cell hanging on the leading edge with a hole beside it. Runs are centred
//   now: a lone cell sits ON the centre line and a pair straddles it.
//
//   ONE ROW WHERE ONE ROW FITS. Nothing in the part or assembly band wraps at
//   all, so those bands are one cell tall plus their chrome — 57 points
//   against the 119 the named band takes.
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

AppState _sketch() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m359s');
  a.sketches['t'] = SketchModel('t');
  a.curTab = 't';
  a.editingLayer = kDefaultLayer;
  return a;
}

AppState _part() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m359p');
  a.parts['P'] = PartModel('P');
  a.openTabs.add('P');
  a.curTab = 'P';
  return a;
}

AppState _assembly() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m359a');
  a.assemblies['A'] = AssemblyModel('A');
  a.openTabs.add('A');
  a.curTab = 'A';
  return a;
}

Future<Rect> _pump(WidgetTester t, AppState app,
    {required RibbonPosition dock, bool names = false}) async {
  RibbonDock.set(dock);
  RibbonLabels.set(names);
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(app: app, stage: const SizedBox.expand()),
    ),
  ));
  await t.pump();
  return t.getTopLeft(find.byType(Ribbon)) & t.getSize(find.byType(Ribbon));
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
    RibbonBleed.resetForTest();
  });
  tearDown(() {
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonBleed.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('centred down the rail', () {
    testWidgets('a rail with room to spare puts its panels in the middle',
        (t) async {
      for (final dock in [RibbonPosition.left, RibbonPosition.right]) {
        final band = await _pump(t, _part(), dock: dock);
        final cells = _cells(t);
        final top = cells.map((c) => c.top).reduce((a, b) => a < b ? a : b);
        final bot = cells.map((c) => c.bottom).reduce((a, b) => a > b ? a : b);
        final above = top - band.top;
        final below = band.bottom - bot;
        expect(above, greaterThan(20),
            reason: '$dock: the part rail has room to spare and should be '
                'using it on BOTH sides, not stacking from the top');
        expect((above - below).abs(), lessThanOrEqualTo(3),
            reason: '$dock: $above above, $below below');
      }
    });

    testWidgets('and a rail that is full still scrolls rather than squashing',
        (t) async {
      // The floor is a MINIMUM, so it can never cap: the full sketch ribbon
      // is taller than an 11-inch iPad in landscape and keeps its scroll.
      final band = await _pump(t, _sketch(), dock: RibbonPosition.right);
      expect(band.height, _screen.height);
      expect(find.byType(Ribbon), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('symmetric, not ragged', () {
    testWidgets('every rail RUN is centred on the rail', (t) async {
      // The report, exactly: "not 3 on the right and 1 on the left just 2 and
      // 2". Asserted RUN BY RUN, and that is the point — checking only that
      // the rail's cell positions mirror each other passes even when every run
      // is packed left, because the two columns mirror one another whatever
      // sits in them. What was wrong was the SHORT run, so the short run is
      // what has to be measured: each row's own midpoint against the rail's.
      final band = await _pump(t, _sketch(), dock: RibbonPosition.right);
      final rows = <double, List<Rect>>{};
      for (final c in _cells(t)) {
        rows.putIfAbsent((c.top * 2).roundToDouble() / 2, () => []).add(c);
      }
      expect(rows.length, greaterThan(8), reason: 'a rail this full should '
          'have plenty of runs to get wrong');
      var short = 0;
      for (final entry in rows.entries) {
        final r = entry.value;
        final mid = (r.map((c) => c.left).reduce((a, b) => a < b ? a : b) +
                r.map((c) => c.right).reduce((a, b) => a > b ? a : b)) /
            2;
        expect((mid - band.center.dx).abs(), lessThanOrEqualTo(1.5),
            reason: 'the run at y=${entry.key} (${r.length} cells) is centred '
                'on $mid, the rail on ${band.center.dx}');
        if (r.length == 1) short++;
      }
      expect(short, greaterThan(0),
          reason: 'no odd run in the whole rail means this test proves '
              'nothing — the short run is the one that used to hang');
    });

    testWidgets('the constraint grid shares its cells out evenly', (t) async {
      // Eleven cells, six columns: six and five, not six and one-with-a-hole.
      // The row of five is centred under the row of six.
      await _pump(t, _sketch(), dock: RibbonPosition.top);
      final l = L.current;
      final cells = [
        for (final name in [
          l.conCoincident, l.conCollinear, l.conConcentric, l.conLock,
          l.conParallel, l.conPerpendicular, l.conHorizontal, l.conVertical,
          l.conTangent, l.conSymmetric, l.conEqual,
        ])
          t.getTopLeft(find.byTooltip(name)) & t.getSize(find.byTooltip(name))
      ];
      final rows = <double, List<Rect>>{};
      for (final c in cells) {
        rows.putIfAbsent(c.top, () => []).add(c);
      }
      expect(rows.length, 2);
      final counts = rows.values.map((r) => r.length).toList()..sort();
      expect(counts, [5, 6], reason: 'shared out evenly, not 6 and 5 ragged');
      // Both rows are centred on the same vertical line.
      final mids = [
        for (final r in rows.values)
          (r.map((c) => c.left).reduce((a, b) => a < b ? a : b) +
                  r.map((c) => c.right).reduce((a, b) => a > b ? a : b)) /
              2
      ];
      expect((mids[0] - mids[1]).abs(), lessThanOrEqualTo(1.5),
          reason: 'the short row hangs off an edge: $mids');
    });
  });

  // -------------------------------------------------------------------------
  group('one row where one row fits', () {
    for (final (label, make) in [
      ('part', _part),
      ('assembly', _assembly),
    ]) {
      testWidgets('$label: the whole band is one row of cells', (t) async {
        // "most important stuff should be in 1 row." Neither of these tabs has
        // an eleven-cell grid in it, so nothing has to wrap.
        final band = await _pump(t, make(), dock: RibbonPosition.top);
        expect({for (final c in _cells(t)) c.top}, hasLength(1));
        expect(band.height,
            lessThan(RibbonMetrics.compactCell + RibbonMetrics.compactTitleH + 12),
            reason: 'one row plus its chrome, and no more: ${band.height}');
      });

      testWidgets('$label: and it is far thinner than the named band',
          (t) async {
        final compact = await _pump(t, make(), dock: RibbonPosition.top);
        final named = await _pump(t, make(), dock: RibbonPosition.top,
            names: true);
        expect(compact.height, lessThan(named.height * 0.6),
            reason: '${compact.height} against ${named.height}');
      });
    }

    testWidgets('the sketch band is two, because of the grid it was allowed',
        (t) async {
      // "just on the constraint icons in the sketch mode they can be 2 rowed"
      // — still the one exception, and still the only thing setting this
      // band's height.
      final band = await _pump(t, _sketch(), dock: RibbonPosition.top);
      expect({for (final c in _cells(t)) c.top}.length, greaterThan(1));
      expect(band.height, lessThan(100));
    });
  });
}
