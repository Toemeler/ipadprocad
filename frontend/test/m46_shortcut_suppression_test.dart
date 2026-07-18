// M46 — Tastenkuerzel duerfen NICHT feuern, waehrend ein Textfeld getippt
// wird: das Parameters-Fenster, der parametrische Text-Editor, oder das
// Inline-Bemassungsfeld. In diesen Modi soll 'l' den Buchstaben schreiben,
// nicht das Linien-Werkzeug starten.

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/inserts.dart';
import 'package:ipadprocad/widgets/viewport.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Future<void> pumpViewport(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
  await t.pump();
}

void main() {
  testWidgets('baseline: L selects the line tool when no editor is open',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.line);
  });

  testWidgets('Parameters window open: L does NOT start the line tool',
      (t) async {
    final app = makeApp();
    app.toggleParams(); // showParams = true
    await pumpViewport(t, app);
    expect(app.showParams, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.none, reason: 'shortcut suppressed while typing');
    // C, R, D likewise suppressed
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(app.tool, Tool.none);
  });

  testWidgets('Text editor window open: L does NOT start the line tool',
      (t) async {
    final app = makeApp();
    final txt = app.addText(const Offset(0, 0), '', placeholder: true);
    app.beginTextEdit(txt, isNew: true);
    await pumpViewport(t, app);
    expect(app.editingText, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.none, reason: 'shortcut suppressed in text editor');
  });

  testWidgets('closing the Parameters window restores shortcuts', (t) async {
    final app = makeApp();
    app.toggleParams();
    await pumpViewport(t, app);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.none);
    app.toggleParams(); // close
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.line, reason: 'shortcut works again once closed');
  });

  testWidgets('Ctrl+Z (undo) is also suppressed while an editor is open',
      (t) async {
    final app = makeApp();
    // make an undoable change first
    final tool = app.addText(const Offset(1, 1), 'keep');
    expect(app.current!.texts, hasLength(1));
    app.toggleParams();
    await pumpViewport(t, app);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(app.current!.texts, hasLength(1),
        reason: 'undo must not fire while the window is capturing keys');
    // silence unused
    expect(tool.template, 'keep');
  });
}
