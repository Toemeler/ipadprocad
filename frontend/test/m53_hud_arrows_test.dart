// M53 follow-up — HUD field walking. Pins that arrow keys map to
// hudTab()/hudTabBack(): on a rectangle the two boxes are w and h, and the
// user can hop between them in BOTH directions, with a typed value locking
// into the box being left (Inventor's Tab contract, extended to arrows).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/hud.dart';

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

void main() {
  test('rect: hudTab and hudTabBack hop between w and h, locking input', () {
    final app = makeApp();
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0)); // first corner -> phase 1: [w, h]
    app.hoverWorld = const Offset(30, 20);
    expect(app.hudActive, isTrue);
    expect(hudFieldsFor(app.tool, app.toolPoints.length).length, 2);
    expect(app.hudFocus, 0);

    app.hudInput = '50';
    app.hudTab(); // lock w=50, focus h
    expect(app.hudFocus, 1);
    expect(app.hudLocked[0], 50);
    expect(app.hudInput, isEmpty);

    app.hudInput = '25';
    app.hudTabBack(); // lock h=25, back to w
    expect(app.hudFocus, 0);
    expect(app.hudLocked[1], 25);

    app.hudTabBack(); // wraps: 0 -> 1
    expect(app.hudFocus, 1);
    app.hudTab(); // wraps: 1 -> 0
    expect(app.hudFocus, 0);
  });

  test('hudTabBack is a no-op without an active HUD', () {
    final app = makeApp();
    app.hudTabBack(); // no tool, no fields — must not throw or move focus
    expect(app.hudFocus, 0);
  });
}
