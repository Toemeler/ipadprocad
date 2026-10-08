// M490 — desktop UX flows found by driving the real Linux app like a
// first-time Inventor user (mouse + keyboard), one group per finding.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/desktop_radius.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/menus.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/view_cube.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/extrude_dialog.dart';
import 'package:prototype/widgets/quick_tools.dart';
import 'package:prototype/widgets/viewport.dart';
import 'package:prototype/widgets/viewport3d.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

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
      app.toolClick(const Offset(0, 0)); // a line half drawn
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Stack(children: [
        Positioned.fill(child: Viewport2D(app: app)),
        QuickToolsBar(app: app),
      ]))));
      await t.pump();
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
      expect(app.toolPoints, isNotEmpty,
          reason: 'the half-drawn line is still there');
      expect(OpenMenus.any, isFalse);

      // The next Esc is the viewport's again.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(app.toolPoints, isEmpty);
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

  group('the right-click menu opens at the pointer', () {
    tearDown(() {
      QuickToolsMenu.resetForTest();
      OpenMenus.reset();
    });

    // The viewport stack starts right of the left-docked ribbon and under
    // the title bar; the menu used the GLOBAL click position as a local one
    // and opened a ribbon's width to the right of the pointer.
    testWidgets('inside an offset stack, top-left corner on the pointer',
        (t) async {
      QuickToolsMenu.isMenuOverrideForTest = true;
      await t.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final app = AppState();
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.only(left: 88, top: 37),
                  child: Stack(children: [QuickToolsBar(app: app)])))));
      const click = Offset(400, 200);
      final g = await t.startGesture(click,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await t.pump();
      expect(QuickToolsMenu.visible.value, isTrue);
      final menu = find.descendant(
          of: find.byType(CustomSingleChildLayout).last,
          matching: find.byType(Listener));
      expect(t.getTopLeft(menu.first), click);
    });
  });

  group('a docked command panel keeps OK on screen', () {
    tearDown(() => debugDesktopCornersOverride = null);

    // The default Linux window (1376 x 1032) leaves a stage of about
    // 1288 x 948 beside the ribbon and under the caption. The Extrusion panel parked from a 620 pt
    // estimate, grew to ~900 on the desktop, and was capped only by the
    // window: its OK / Cancel row hung below the bottom edge.
    testWidgets('Extrusion: OK and Cancel inside the stage', (t) async {
      debugDesktopCornersOverride = true;
      // A short window (the test font sets the panel ~600 tall; the real
      // one is ~900 in a 948 stage — the same overflow).
      const stage = Size(1288, 560);
      await t.binding.setSurfaceSize(const Size(1376, 650));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      await t.runAsync(() async {
        expect(await app.createNamedPart('P'), isTrue);
      });
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      expect(app.extrudeSession, isNotNull);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomRight,
                  child: SizedBox.fromSize(
                      size: stage,
                      child: DialogDockScope(
                          size: stage,
                          child: Stack(children: [ExtrudeDialog(app: app)])))))));
      await t.pump();
      final stageBox = t.getRect(find.byType(DialogDockScope));
      for (final label in ['OK', 'Abbrechen']) {
        final r = t.getRect(find.text(label).last);
        expect(r.bottom, lessThanOrEqualTo(stageBox.bottom),
            reason: '$label at $r, stage $stageBox');
      }
      app.cancelExtrude();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('Enter is OK in a 3D command', () {
    testWidgets('Extrude panel open, profile picked: Enter commits it',
        (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      await t.runAsync(() async {
        expect(await app.createNamedPart('P'), isTrue);
      });
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      final s = app.extrudeSession!;
      expect(s.profiles, isNotEmpty, reason: 'one region: picked for you');
      await t.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
          MaterialApp(home: Scaffold(body: Viewport3D(app: app))));
      await t.pump();
      await t.runAsync(() async {
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      expect(app.extrudeSession, isNull, reason: 'Enter pressed OK');
      expect(app.currentPart!.features, isNotEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('the ViewCube Home button', () {
    testWidgets('a click on the house goes Home', (t) async {
      final cam = PartCamera(az: 0.1, pol: 1.5, halfH: 80, ox: 7, oy: -3);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: ViewCube(camera: cam, onChanged: () {})))));
      final cube = t.getTopLeft(find.byType(ViewCube));
      await t.tapAt(cube + const Offset(11, 11)); // the 22 x 22 house
      await t.pumpAndSettle();
      final home = PartCamera()..home();
      expect(cam.halfH, closeTo(home.halfH, 1e-6),
          reason: 'Home resets the zoom (the click reached Home)');
      expect(cam.ox, closeTo(0, 1e-6));
      expect(cam.pol, closeTo(home.pol, 1e-3));
    });
  });

  group('the ViewCube roll arrows', () {
    // The cube is docked 10 px from the viewport's right edge; the roll pair
    // stuck 12 px out of the cube's box, so the clockwise arrow was cut in
    // half by the window edge in every face view.
    testWidgets('stay inside the cube box in a face view', (t) async {
      final cam = PartCamera(az: 0, pol: math.pi / 2); // FRONT
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topRight,
                  child: ViewCube(camera: cam, onChanged: () {})))));
      final box = t.getRect(find.byType(ViewCube));
      final strings = L.current;
      for (final label in [strings.cubeRollLeft, strings.cubeRollRight]) {
        final r = t.getRect(find.bySemanticsLabel(label));
        expect(box.contains(r.topLeft) && r.right <= box.right + 1e-6, isTrue,
            reason: '$label at $r, cube box $box');
      }
    });
  });

  group('ViewCube face labels read upright in their own view', () {
    // In the TOP view (front at the bottom, Inventor's convention) the TOP
    // label read "dOT": its decal basis had text-up pointing at FRONT.
    for (final (label, n) in kCubeFaces) {
      test('$label', () {
        final (u, v) = faceBasis(n);
        final up = cubeUpFor(n); // screen up, looking at this face
        final right = (n * -1).cross(up);
        expect(v.dot(up), closeTo(1, 1e-9), reason: 'text up = screen up');
        expect(u.dot(right), closeTo(1, 1e-9),
            reason: 'text runs left to right');
      });
    }
  });

  group('Inventor single-key commands in a part', () {
    testWidgets('S starts a sketch, E opens Extrude, a letter never swaps a '
        'running command', (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m490_');
      app.partKernel = FakeKernel();
      await t.runAsync(() async {
        expect(await app.createNamedPart('P'), isTrue);
      });
      await t.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
          MaterialApp(home: Scaffold(body: Viewport3D(app: app))));
      await t.pump();

      await t.sendKeyEvent(LogicalKeyboardKey.keyS);
      await t.pump();
      expect(app.pickPlane, isTrue, reason: 'S = Start 2D Sketch');
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
      app.finishPartSketch();
      await t.pump();

      await t.sendKeyEvent(LogicalKeyboardKey.keyE);
      await t.pump();
      expect(app.extrudeSession, isNotNull, reason: 'E = Extrude');
      await t.sendKeyEvent(LogicalKeyboardKey.keyH);
      await t.pump();
      expect(app.holeSession, isNull,
          reason: 'H while Extrude runs does not start a hole');
      expect(app.extrudeSession, isNotNull);
      app.cancelExtrude();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });
}
