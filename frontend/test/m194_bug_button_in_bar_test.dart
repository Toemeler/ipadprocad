// M194 — the bug reporter moved into the quick-tool bar.
//
// It used to be a red circle floating over the canvas, draggable because a bug
// reporter that covers the bug is useless. In the bar it covers nothing, so the
// dragging went with it. What these tests pin is reachability: the old button
// could be pressed from EVERY view, including the home gallery, and a report
// you cannot file where the bug is is worth nothing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/bug_button.dart';
import 'package:prototype/widgets/quick_tools.dart';

AppState homeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m194');
  return app;
}

AppState sketchApp({bool editing = true}) {
  final app = homeApp();
  final s = SketchModel('A');
  s.layers.add('Layer 1');
  app.sketches['A'] = s;
  app.openTabs.add('A');
  app.curTab = 'A';
  if (editing) app.editingLayer = 'Layer 1';
  return app;
}

AppState partApp() {
  final app = homeApp();
  app.parts['P'] = PartModel('P');
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

GlassToolItem? bugOf(AppState app) {
  for (final i in buildQuickTools(app)) {
    if (i.id == QuickToolId.bug) return i;
  }
  return null;
}

void main() {
  test('it is reachable from every view the floating button reached', () {
    // Home, a part, a sketch outside edit mode and a sketch inside it. The
    // third and fourth are the ones a code path can silently drop: they leave
    // buildQuickTools through early returns.
    for (final entry in {
      'home': homeApp(),
      'part': partApp(),
      'sketch (not editing)': sketchApp(editing: false),
      'sketch (editing)': sketchApp(),
    }.entries) {
      expect(bugOf(entry.value), isNotNull, reason: entry.key);
    }
  });

  test('it is the LAST button, everywhere', () {
    for (final app in [homeApp(), partApp(), sketchApp()]) {
      final ids = [
        for (final i in buildQuickTools(app))
          if (!i.separator) i.id
      ];
      expect(ids.last, QuickToolId.bug);
    }
  });

  test('it is red, carries a glyph with a fallback, and is never dark', () {
    final b = bugOf(sketchApp())!;
    expect(b.destructive, isTrue, reason: 'it kept the red of the old circle');
    expect(b.enabled, isTrue, reason: 'a bug can be filed at any moment');
    expect(b.symbol, isNotEmpty);
    expect(b.fallback, isNotEmpty,
        reason: 'ladybug is SF Symbols 4 — an older OS must not get a blank '
            'button where the reporter is');
    expect(b.label, isNotEmpty);
  });

  test('the master switch removes it and leaves the rest of the bar', () {
    addTearDown(() => BugReport.enabled = true);
    final app = sketchApp();
    expect(bugOf(app), isNotNull);

    BugReport.enabled = false;
    expect(bugOf(app), isNull);
    expect([for (final i in buildQuickTools(app)) i.id],
        contains(QuickToolId.undo),
        reason: 'flipping the debug switch must not empty the bar');
  });

  test('with the switch off the home bar disappears entirely', () {
    addTearDown(() => BugReport.enabled = true);
    BugReport.enabled = false;
    expect(buildQuickTools(homeApp()), isEmpty,
        reason: 'the gallery has nothing else to offer');
  });

  test('no separator is left dangling when the bar is otherwise empty', () {
    // A rule above the first button would be a hairline floating in the glass.
    final items = buildQuickTools(homeApp());
    expect(items.length, 1);
    expect(items.single.separator, isFalse);
  });

  test('tapping it without a context does nothing rather than throwing', () {
    // The host suite presses every id; the reporter is the one that needs a
    // BuildContext, and it must degrade instead of crashing the sweep.
    final app = sketchApp();
    expect(() => runQuickTool(app, QuickToolId.bug), returnsNormally);
  });
}
