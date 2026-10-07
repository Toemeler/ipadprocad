// M490 — desktop UX flows found by driving the real Linux app like a
// first-time Inventor user (mouse + keyboard), one group per finding.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/menus.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/quick_tools.dart';
import 'package:prototype/widgets/viewport.dart';

import 'm56_part_test.dart' show FakeKernel;

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  // A close-enough sRGB linearisation (gamma 2) for a contrast floor.
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('tooltips are readable', () {
    // The ribbon on a desktop is icons only; its tooltip is the only name a
    // tool has. On the light palette the text was near-white on white.
    for (final (name, p) in [('light', kChalk), ('dark', kEmber)]) {
      test('$name palette: tooltip text contrasts with its surface', () {
        final th = materialTheme(p).tooltipTheme;
        final fg = th.textStyle!.color!;
        final bg = (th.decoration! as BoxDecoration).color!;
        expect(_contrast(fg, bg), greaterThan(4.5),
            reason: 'text $fg on $bg');
      });
    }
  });

  group('the sketch status line speaks the UI language', () {
    testWidgets('German: "N Bemaßungen erforderlich", not English', (t) async {
      final app = AppState();
      final s = SketchModel('t');
      app.sketches['t'] = s;
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 30));
      expect(app.analysis, isNotNull);
      final dof = app.analysis!.dof;
      expect(dof, greaterThan(1));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
      await t.pump();
      expect(find.textContaining('dimensions needed'), findsNothing);
      expect(find.text('$dof Bemaßungen erforderlich'), findsOneWidget);
    });
  });

  group('a typed diameter or radius shows up as a dimension', () {
    // Drawing a circle and typing 8 sized it, but the diameter dimension sat
    // on the centre — and a radial label on its own centre is not drawn.
    // Steps: an Offset is a click, a String is typed at the cursor + Enter.
    Future<void> draw(WidgetTester t, Tool tool, List<Object> steps) async {
      final app = AppState();
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      app.tool = tool;
      for (final st in steps) {
        if (st is Offset) {
          app.hoverWorld = st;
          app.toolClick(st);
        } else {
          app.hoverWorld = app.toolPoints.last + const Offset(3, 2);
          for (final ch in (st as String).split('')) {
            app.hudType(ch);
          }
          app.hudEnter();
        }
      }
      final dims = [
        for (final c in app.current!.constraints)
          if (c.type == CType.dimension) c
      ];
      expect(dims, isNotEmpty);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
      await t.pump();
      for (final d in dims) {
        expect(app.dimLabelRects.any((e) => identical(e.$1, d)), isTrue,
            reason: '${d.dimKind} ${d.value} has a label on screen');
      }
    }

    testWidgets('circle: centre, type 8, Enter -> a visible diameter',
        (t) => draw(t, Tool.circleCenter, [const Offset(10, 5), '8']));
    testWidgets('centre arc: a typed radius is labelled',
        (t) => draw(t, Tool.arcCenter,
            [const Offset(0, 0), '10', const Offset(-10, 0)]));
  });

  group('right-click in an idle part sketch offers Finish Sketch', () {
    // Inventor's right-click in a sketch leads with "Finish 2D Sketch". Here
    // the desktop menu offered a dark OK and Cancel and nothing to leave by.
    tearDown(() => QuickToolsMenu.isMenuOverrideForTest = null);

    test('offered when idle, runs Finish Sketch, gone while a tool runs',
        () async {
      QuickToolsMenu.isMenuOverrideForTest = true;
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      expect(await app.createNamedPart('P'), isTrue);
      app.startPartSketch();
      app.planePicked('xy');
      expect(app.activeChild, isNotNull);
      app.cancelTool();

      List<String> ids() => [
            for (final i in buildQuickTools(app))
              if (!i.separator) i.id
          ];
      expect(ids().first, QuickToolId.finishSketch);

      app.selectTool(Tool.line);
      expect(ids(), isNot(contains(QuickToolId.finishSketch)),
          reason: 'with a command running, the menu is that command\'s');
      app.cancelTool();

      runQuickTool(app, QuickToolId.finishSketch);
      expect(app.activeChild, isNull, reason: 'back in the part');
      expect(ids(), isNot(contains(QuickToolId.finishSketch)));
    });

    test('the touch rail is unchanged', () async {
      QuickToolsMenu.isMenuOverrideForTest = false;
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      expect(await app.createNamedPart('P'), isTrue);
      app.startPartSketch();
      app.planePicked('xy');
      app.cancelTool();
      expect(buildQuickTools(app).map((i) => i.id),
          isNot(contains(QuickToolId.finishSketch)));
    });
  });

  group('Esc closes the right-click menu', () {
    tearDown(() {
      QuickToolsMenu.resetForTest();
      OpenMenus.reset();
    });

    testWidgets('first Esc takes the menu down, the tool stays armed',
        (t) async {
      QuickToolsMenu.isMenuOverrideForTest = true;
      await t.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final app = AppState();
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      app.selectTool(Tool.line);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [QuickToolsBar(app: app)]))));
      final g = await t.startGesture(const Offset(300, 300),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await t.pump();
      expect(QuickToolsMenu.visible.value, isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(QuickToolsMenu.visible.value, isFalse);
      expect(app.tool, Tool.line,
          reason: 'the Esc that closed the menu is not also a cancel');
      expect(OpenMenus.any, isFalse);
    });
  });

  group('Finish Sketch swings back to the view the sketch was opened from', () {
    Future<AppState> part() async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      expect(await app.createNamedPart('P'), isTrue);
      return app;
    }

    test('a fresh part: iso before, front while sketching, iso after',
        () async {
      final app = await part();
      final cam = app.currentPart!.camera;
      final before = cam.copy();
      app.startPartSketch();
      app.planePicked('xy');
      expect(cam.az, isNot(closeTo(before.az, 1e-6)),
          reason: 'the sketch looks down its plane');
      app.finishPartSketch();
      expect(cam.az, closeTo(before.az, 1e-9));
      expect(cam.pol, closeTo(before.pol, 1e-9));
      expect(cam.halfH, closeTo(before.halfH, 1e-9));
    });

    test('reopening a sketch from the browser and finishing it', () async {
      final app = await part();
      app.startPartSketch();
      app.planePicked('xz');
      app.finishPartSketch();
      final cam = app.currentPart!.camera;
      cam
        ..az = 1.1
        ..pol = 0.7
        ..halfH = 80;
      app.openChildSketch(app.currentPart!.childSketches.first.model.name);
      expect(cam.halfH, isNot(80));
      app.finishPartSketch();
      expect([cam.az, cam.pol, cam.halfH], [1.1, 0.7, 80]);
    });
  });
}
