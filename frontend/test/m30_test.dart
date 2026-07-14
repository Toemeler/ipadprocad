// M30 — keyboard shortcuts in the viewport:
//   D dimension, L line, C circle (center), R rectangle (two-point),
//   S finish editing the layer / start+enter a new one when not editing,
//   Ctrl(or Cmd)+S save. Never while the inline dimension editor is typing.
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/widgets/viewport.dart';

AppState makeApp({bool editing = true}) {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  if (editing) app.editingLayer = kDefaultLayer;
  return app;
}

Future<void> pumpViewport(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
  await t.pump();
}

void main() {
  testWidgets('D/L/C/R select the tools while editing a layer', (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    await t.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(app.tool, Tool.dimension);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.line);
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(app.tool, Tool.circleCenter);
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(app.tool, Tool.rectTwoPoint);
  });

  testWidgets('S finishes the layer; S outside a layer starts a new one',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    expect(app.inEditMode, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(app.inEditMode, isFalse, reason: 'S ends layer editing');
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(app.inEditMode, isTrue, reason: 'S starts + enters a new layer');
    expect(app.current!.layers, contains('Layer 1'));
    expect(app.editingLayer, 'Layer 1');
  });

  testWidgets('tool keys outside a layer only hint, tool stays none',
      (t) async {
    final app = makeApp(editing: false);
    await pumpViewport(t, app);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(app.tool, Tool.none,
        reason: 'selectTool blocks outside edit mode (toast hint)');
    await t.pump(const Duration(seconds: 6)); // let the toast timer expire
  });

  testWidgets('Ctrl+S saves instead of toggling the layer', (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(app.inEditMode, isTrue,
        reason: 'Ctrl+S must NOT end the layer — it saves');
    await t.pump(const Duration(seconds: 6)); // let the toast timer expire
  });
}
