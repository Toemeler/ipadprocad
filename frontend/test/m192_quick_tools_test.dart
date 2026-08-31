// M192 — the quick tools moved out of the long-press menu onto a permanent bar.
//
// The pixels are Swift and untestable from here. What IS testable is the part
// that can be silently wrong: which buttons the bar offers, which of them are
// live, and what a tap actually calls. A button that looks enabled and does
// nothing is the exact failure this file exists to prevent.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';
import 'package:prototype/widgets/quick_tools.dart';
import 'package:prototype/ribbon_dock.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m192');
  return app;
}

/// A sketch, open, in edit mode — the state the drawing buttons need.
AppState editingApp() {
  final app = makeApp();
  final s = SketchModel('A');
  s.layers.add('Layer 1');
  app.sketches['A'] = s;
  app.openTabs.add('A');
  app.curTab = 'A'; // isHome is curTab == null
  app.editingLayer = 'Layer 1';
  return app;
}

List<String> idsOf(AppState app) =>
    [for (final i in buildQuickTools(app)) i.id];

/// Ids of the real buttons, without the hairline rules between the groups.
List<String> buttonIdsOf(AppState app) => [
      for (final i in buildQuickTools(app))
        if (!i.separator) i.id
    ];

GlassToolItem item(AppState app, String id) =>
    buildQuickTools(app).firstWhere((i) => i.id == id);

void main() {
  test('the home gallery carries the bug reporter and nothing else', () {
    // M194 — no document, so no command has anything to act on; the bug
    // reporter stays, because a bug in the gallery is still a bug (it is what
    // the old floating red circle was reachable for there).
    final app = makeApp();
    expect(app.isHome, isTrue);
    expect(idsOf(app), [QuickToolId.bug]);
  });

  test('OK and Cancel lead the bar wherever the sketcher is live', () {
    // The whole point is a fixed target under the thumb: a button that appears
    // and disappears cannot be hit without looking. Leaving edit mode must not
    // move them.
    final app = editingApp();
    expect(idsOf(app).take(2), [QuickToolId.ok, QuickToolId.cancel]);
    expect(idsOf(app), containsAll([QuickToolId.undo, QuickToolId.redo]));

    app.editingLayer = null; // out of edit mode, still in the sketch
    expect(idsOf(app).take(2), [QuickToolId.ok, QuickToolId.cancel]);
    expect(idsOf(app), containsAll([QuickToolId.undo, QuickToolId.redo]));
  });

  test('the drawing tools appear only inside edit mode', () {
    final app = editingApp();
    expect(idsOf(app), contains(QuickToolId.line));
    app.editingLayer = null;
    expect(idsOf(app), isNot(contains(QuickToolId.line)));
  });

  test('OK is dark until a variable-length tool has enough points', () {
    final app = editingApp();
    expect(item(app, QuickToolId.ok).enabled, isFalse,
        reason: 'nothing is running');

    // A fixed-point tool commits itself on the last pick — OK must NOT claim
    // to be able to finish it.
    app.tool = Tool.line;
    app.toolPoints.add(const Offset(0, 0));
    expect(item(app, QuickToolId.ok).enabled, isFalse);

    // A spline is variable: it can only ever be finished by Enter/OK.
    app.tool = Tool.splineCV;
    app.toolPoints.addAll([const Offset(1, 0), const Offset(2, 1)]);
    expect(item(app, QuickToolId.ok).enabled, isTrue);
  });

  test('Cancel is dark with nothing to cancel and lit by a tool or selection',
      () {
    final app = editingApp();
    expect(item(app, QuickToolId.cancel).enabled, isFalse);

    app.tool = Tool.circleCenter;
    expect(item(app, QuickToolId.cancel).enabled, isTrue);

    app.tool = Tool.none;
    app.selection.add(0);
    expect(item(app, QuickToolId.cancel).enabled, isTrue,
        reason: 'Esc drops the selection, so the button must too');
  });

  test('only Cancel and the bug reporter are red', () {
    // Red is a promise: this either aborts something or files a report. A
    // drawing tool that borrowed the colour would make both meaningless.
    final app = editingApp();
    final red = [
      for (final i in buildQuickTools(app))
        if (i.destructive) i.id
    ];
    expect(red, [QuickToolId.cancel, QuickToolId.bug]);
  });

  test('tapping Cancel really cancels the running tool', () {
    final app = editingApp();
    app.tool = Tool.line;
    app.toolPoints.add(const Offset(0, 0));
    // First Esc drops the pending picks, the command stays armed (M53).
    runQuickTool(app, QuickToolId.cancel);
    expect(app.toolPoints, isEmpty);
    expect(app.tool, Tool.line);
    // Second Esc leaves the command.
    runQuickTool(app, QuickToolId.cancel);
    expect(app.tool, Tool.none);
  });

  test('the freehand window owns OK and Cancel while it is up', () {
    final app = editingApp();
    app.tool = Tool.splineFree;
    final f = FreehandSession();
    f.drawing = true;
    app.freehand = f;
    expect(item(app, QuickToolId.ok).enabled, isFalse,
        reason: 'the stroke is still being drawn');

    f.drawing = false;
    expect(item(app, QuickToolId.ok).enabled, isTrue);

    // Cancel throws the ink away and leaves the tool armed for the next
    // stroke — it must NOT fall through to cancelTool().
    runQuickTool(app, QuickToolId.cancel);
    expect(app.freehand, isNull);
    expect(app.tool, Tool.splineFree);
  });

  test('the four drawing buttons arm exactly the tools they draw', () {
    final app = editingApp();
    const wired = {
      QuickToolId.line: Tool.line,
      QuickToolId.circle: Tool.circleCenter,
      QuickToolId.rect: Tool.rectTwoPoint,
      QuickToolId.dimension: Tool.dimension,
    };
    wired.forEach((id, tool) {
      runQuickTool(app, id);
      expect(app.tool, tool, reason: id);
      expect(item(app, id).selected, isTrue,
          reason: '$id must read as armed once it is');
    });
  });

  test('Trim enters the modify family and then cycles it, like right-click',
      () {
    final app = editingApp();
    runQuickTool(app, QuickToolId.trim);
    expect(app.tool, Tool.trim);
    expect(item(app, QuickToolId.trim).selected, isTrue);

    // M49's ring: Split -> Trim -> Extend.
    runQuickTool(app, QuickToolId.trim);
    expect(app.tool, Tool.extendT);
    expect(item(app, QuickToolId.trim).selected, isTrue,
        reason: 'every member of the family lights the same button');
    runQuickTool(app, QuickToolId.trim);
    expect(app.tool, Tool.split);
  });

  test('Undo/Redo follow the SKETCH journal in a sketch', () {
    final app = editingApp();
    final s = app.current!;
    expect(item(app, QuickToolId.undo).enabled, isFalse,
        reason: 'a fresh sketch sits on its baseline');
    expect(item(app, QuickToolId.redo).enabled, isFalse);

    s.checkpoint(); // one committed state past the baseline
    expect(app.canUndo, isTrue);
    expect(item(app, QuickToolId.undo).enabled, isTrue);
    expect(item(app, QuickToolId.redo).enabled, isFalse,
        reason: 'nothing has been undone yet');
  });

  test('Undo/Redo follow the PART journal when no sketch is open', () {
    final app = makeApp();
    app.parts['P'] = PartModel('P');
    app.openTabs.add('P');
    app.curTab = 'P';
    expect(app.current, isNull, reason: 'a part with no child sketch open');
    // Empty part journal: both dark, and neither may consult the sketch
    // journal of a sketch that is not open.
    expect(item(app, QuickToolId.undo).enabled, isFalse);
    expect(item(app, QuickToolId.redo).enabled, isFalse);
    // No sketch tool can be running here, so OK and Cancel would be dark
    // forever. A button that can never light up does not belong on the bar.
    expect(buttonIdsOf(app),
        [QuickToolId.undo, QuickToolId.redo, QuickToolId.bug]);
  });

  test('every id the bar emits is dispatched — no dead buttons', () {
    final app = editingApp();
    app.tool = Tool.splineCV;
    app.toolPoints.addAll([const Offset(0, 0), const Offset(1, 0)]);
    for (final i in buildQuickTools(app)) {
      if (i.separator) continue;
      expect(
          [
            QuickToolId.ok,
            QuickToolId.cancel,
            QuickToolId.undo,
            QuickToolId.redo,
            QuickToolId.line,
            QuickToolId.circle,
            QuickToolId.rect,
            QuickToolId.dimension,
            QuickToolId.trim,
            QuickToolId.delete,
            QuickToolId.bug,
          ],
          contains(i.id),
          reason: 'runQuickTool has no case for "${i.id}"');
    }
  });

  test('every button carries a glyph and a VoiceOver label', () {
    // An icons-only bar has exactly one fatal defect: a blank button.
    final app = editingApp();
    for (final i in buildQuickTools(app)) {
      if (i.separator) continue;
      expect(i.symbol, isNotEmpty, reason: i.id);
      expect(i.label, isNotEmpty, reason: i.id);
    }
  });

  test('the wire format survives a round trip through the codec', () {
    // Swift reads these exact keys; a rename here is a silently blank bar.
    final m = const GlassToolItem(
            id: 'x', symbol: 's', fallback: 'f', label: 'L', selected: true)
        .toMap();
    expect(m.keys.toSet(), {
      'id',
      'symbol',
      'fallback',
      'label',
      'enabled',
      'selected',
      'destructive',
      'separator',
    });
    expect(m['enabled'], isA<bool>());
    expect(m['separator'], false);
    expect(const GlassToolItem.separator('s').toMap()['separator'], true);
  });

  test('the bar is sized from the same arithmetic UIKit lays out', () {
    // Dart sizes the platform view before UIKit ever sees it, so the two sides
    // duplicate these constants. If they drift, the glass clips its own last
    // button.
    final items = buildQuickTools(editingApp());
    final buttons = items.where((i) => !i.separator).length;
    final rules = items.length - buttons;
    expect(
        GlassToolBar.heightFor(items),
        2 * GlassToolBar.padding +
            GlassToolBar.spacing * (items.length - 1) +
            buttons * GlassToolBar.buttonSize +
            rules * GlassToolBar.separatorSlot);
    expect(GlassToolBar.width,
        GlassToolBar.buttonSize + 2 * GlassToolBar.padding);
    expect(GlassToolBar.buttonSize, greaterThanOrEqualTo(44),
        reason: "Apple's HIG floor for a touch target is the point of this bar");
    expect(GlassToolBar.heightFor(const []), 0);
  });

  // M290 — the rail no longer clears anything, on any screen.
  //
  // M284 had it subtract the band's measured thickness on three edges and gate
  // that on whether the band was drawn at all, because on the gallery there is
  // no ribbon and a stale inset would have lifted the rail off nothing (that
  // gate was itself a device bug, #3). The band takes a row of the layout now:
  // this Stack's edges are already inside it, so the rail's numbers are
  // constants — and are the SAME constants on the gallery and in a document,
  // which is the property that bug could not have.
  group('M290 the rail is placed by constants', () {
    setUp(RibbonDock.resetForTest);

    Future<void> pumpBar(WidgetTester t, AppState app) async {
      await t.binding.setSurfaceSize(const Size(1600, 900));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [QuickToolsBar(app: app)]))));
      await t.pump();
    }

    testWidgets('same placement on every dock, gallery and document alike',
        (t) async {
      for (final dock in RibbonPosition.values) {
        RibbonDock.set(dock);
        for (final app in [makeApp(), editingApp()]) {
          await pumpBar(t, app);
          final p = t.widget<Positioned>(find.byType(Positioned));
          expect(p.top, 0, reason: '$dock');
          expect(p.right, QuickToolsBar.margin, reason: '$dock');
          expect(p.bottom, BottomTabBar.floatingHeightFor(app),
              reason: '$dock');
        }
      }
    });

    test('the width it claims is its own, with no band in it', () {
      RibbonDock.set(RibbonPosition.right);
      expect(QuickToolsBar.occupiedWidth,
          GlassToolBar.width + QuickToolsBar.margin,
          reason: 'a right-docked band is outside this box entirely');
    });
  });
}
