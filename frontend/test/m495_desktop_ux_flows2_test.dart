// M495 — desktop UX flows, part 2: found by driving the real Linux app like a
// first-time Inventor user (mouse + keyboard), one group per finding.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/home_view.dart';
import 'package:prototype/widgets/quick_tools.dart';
import 'package:prototype/widgets/ribbon.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

Future<void> _pumpRibbon(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
  await t.pump();
}

List<String> _tips(WidgetTester t) => [
      for (final w in t.widgetList<Tooltip>(find.byType(Tooltip)))
        if (w.message != null) w.message!
    ];

void main() {
  group('ribbon tooltips name the single-key commands', () {
    // The part letters (S/E/R/H/F/M) and the sketch letters (L/C/R/D) were
    // undiscoverable: the tooltip said "Extrusion", Inventor's says
    // "Extrude (E)".
    setUp(RibbonDock.resetForTest);
    tearDown(RibbonLabels.resetForTest);

    testWidgets('part: Extrusion (E), Bohrung (H), …', (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.partKernel = FakeKernel();
      await t.runAsync(() async {
        expect(await app.createNamedPart('P'), isTrue);
      });
      await _pumpRibbon(t, app);
      final tips = _tips(t);
      for (final want in [
        'Extrusion (E)',
        'Drehung (R)',
        'Verrundung (F)',
        'Bohrung (H)',
        'Messen (M)',
      ]) {
        expect(tips, contains(want), reason: 'tooltips: $tips');
      }
      expect(tips.any((s) => s.endsWith('(S)')), isTrue,
          reason: 'Start 2D Sketch names S');
    });

    testWidgets('sketch: Linie (L), Kreis (C), Rechteck (R), Bemaßung (D)',
        (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      await _pumpRibbon(t, app);
      final tips = _tips(t);
      for (final want in [
        'Linie (L)',
        'Kreis (C)',
        'Rechteck (R)',
        'Bemaßung (D)',
      ]) {
        expect(tips, contains(want), reason: 'tooltips: $tips');
      }
    });
  });

  group('the gallery "+" menu draws Open as a folder', () {
    // The Flutter menu (Linux, Windows) drew "Öffnen…" with the 3D-part cube,
    // so it read as a second "New 3D Part".
    testWidgets('a folder glyph, and not the part cube', (t) async {
      final app = AppState()
        ..docsDirForTest =
            Directory.systemTemp.createTempSync('prototype_m495_');
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: HomeView(app: app)))));
      await t.pump();
      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      final row = find.ancestor(
          of: find.text(L.current.openEllipsis), matching: find.byType(Row));
      expect(
          find.descendant(
              of: row, matching: find.byIcon(Icons.folder_open_outlined)),
          findsOneWidget);
    });
  });

  group('right-click on empty sketch paper offers no Copy/Cut', () {
    // With nothing selected, Copy took the whole sketch and Cut of a part's
    // sketch deleted it — from a right-click on empty paper.
    tearDown(() => QuickToolsMenu.isMenuOverrideForTest = null);

    List<String> ids(AppState app) => [
          for (final i in buildQuickTools(app))
            if (!i.separator) i.id
        ];

    test('part sketch: none until something is selected', () async {
      QuickToolsMenu.isMenuOverrideForTest = true;
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.partKernel = FakeKernel();
      expect(await app.createNamedPart('P'), isTrue);
      app.startPartSketch();
      app.planePicked('xy');
      app.cancelTool();
      addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
      expect(ids(app), isNot(contains(QuickToolId.copy)));
      expect(ids(app), isNot(contains(QuickToolId.cut)));
      app.selection.add(0);
      expect(ids(app), containsAll([QuickToolId.copy, QuickToolId.cut]));
    });

    test('the touch rail keeps them (copy the whole sketch)', () async {
      QuickToolsMenu.isMenuOverrideForTest = false;
      final app = AppState();
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      expect(ids(app), contains(QuickToolId.copy));
    });
  });

  group('typed geometry stays on screen', () {
    // A new part's first sketch opens ~55 mm tall: a 40 x 30 rectangle typed
    // at the origin ran off the right edge, its 30 mm dimension with it.
    Future<AppState> sketch() async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.partKernel = FakeKernel();
      expect(await app.createNamedPart('P'), isTrue);
      app.startPartSketch();
      app.planePicked('xy');
      // The default Linux window's stage beside the ribbon and browser.
      app.viewportSize = const Size(988, 948);
      app.fitSketchZoom(948);
      return app;
    }

    Rect view(AppState app) => Rect.fromCenter(
        center: app.pan,
        width: app.viewportSize.width / app.zoom,
        height: app.viewportSize.height / app.zoom);

    test('40 x 30 rectangle typed at the origin: all of it in view', () async {
      final app = await sketch();
      final zoom0 = app.zoom;
      app.selectTool(Tool.rectTwoPoint);
      app.hoverWorld = Offset.zero;
      app.toolClick(Offset.zero);
      app.hoverWorld = const Offset(5, 4);
      for (final ch in '40'.split('')) {
        app.hudType(ch);
      }
      app.hudTab();
      for (final ch in '30'.split('')) {
        app.hudType(ch);
      }
      app.hudEnter();
      final s = app.current!;
      expect(s.geometry, isNotEmpty);
      final v = view(app);
      for (final p in [const Offset(0, 0), const Offset(40, 30)]) {
        expect(v.deflate(2).contains(p), isTrue, reason: '$p in $v');
      }
      expect(app.zoom, lessThan(zoom0), reason: 'zoomed out to show it');
    });

    test('a small typed circle leaves the view alone', () async {
      final app = await sketch();
      final zoom0 = app.zoom, pan0 = app.pan;
      app.selectTool(Tool.circleCenter);
      app.hoverWorld = Offset.zero;
      app.toolClick(Offset.zero);
      app.hoverWorld = const Offset(3, 2);
      app.hudType('8');
      app.hudEnter();
      expect(app.zoom, zoom0);
      expect(app.pan, pan0);
    });
  });
}
