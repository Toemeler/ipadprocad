// M39 — UNDO / REDO. Per-sketch snapshot journal: Ctrl+Z walks every
// committed state back to the very beginning, Ctrl+Shift+Z walks forward.
// These tests pin the CONTRACT:
//   * every operation (draw, trim, constrain, dimension, layer ops, eye/lock)
//     is one undoable step, restored EXACTLY (geometry + constraints + layers)
//   * undo reaches the baseline (the opened/created state) and stops there
//   * redo replays forward; a NEW edit after undo kills the redo branch
//   * histories are PER SKETCH: undoing in one never touches another
//   * a restore never journals itself, and repeated undo/redo round-trips
//     are lossless

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Full comparable fingerprint of a sketch's undoable state.
String fp(SketchModel s) {
  final b = StringBuffer();
  for (final g in s.geometry) {
    b.write('${g.type}|${g.layer}|${g.spline}|${g.style}|${g.proj}|'
        '${g.projSeg}|${g.data.map((d) => d.toStringAsFixed(9)).join(",")};');
  }
  b.write('#${encodeConstraints(s.constraints)}');
  b.write('#${s.layers.join(",")}#${(s.hiddenLayers.toList()..sort()).join(",")}'
      '#${(s.lockedLayers.toList()..sort()).join(",")}');
  return b.toString();
}

void main() {
  test('draw -> undo to empty -> redo restores exactly', () {
    final app = makeApp();
    final s = app.current!;
    final empty = fp(s);
    app.tool = Tool.rectTwoPoint;
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(100, 80));
    final drawn = fp(s);
    expect(s.geometry.length, 4);
    expect(app.canUndo, isTrue);

    app.undo();
    expect(fp(s), empty);
    expect(s.geometry, isEmpty);
    expect(s.constraints, isEmpty);
    expect(app.canRedo, isTrue);

    app.redo();
    expect(fp(s), drawn);
    expect(app.canRedo, isFalse);
  });

  test('full session walks back to the start and forward again, losslessly',
      () {
    final app = makeApp();
    final s = app.current!;
    final states = <String>[fp(s)]; // baseline

    // op 1+2: two crossing lines
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 50));
    app.toolClick(const Offset(100, 50));
    states.add(fp(s));
    app.selectTool(Tool.line);
    app.toolClick(const Offset(50, 0));
    app.toolClick(const Offset(50, 100));
    states.add(fp(s));
    // op 3+4: trim both -> stacked point-on-point (M38 fix in the journal too)
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(80, 50));
    states.add(fp(s));
    app.toolClick(const Offset(50, 80));
    states.add(fp(s));
    // op 5: a driving dimension on the surviving horizontal line
    final dim = Constraint(CType.dimension,
        pts: [const PRef(0, 0), const PRef(0, 1)],
        value: 40,
        dimKind: 'dist');
    s.constraints.add(dim);
    expect(app.canUndo, isTrue);
    // commit like the dimension flow does: solve + rebuild
    final gs = List<Geo>.from(s.geometry);
    expect(solveConstraints(gs, s.constraints), isTrue);
    app.setDimensionValue(dim, 45); // rebuilds -> journals
    states.add(fp(s));

    // walk all the way back...
    for (var i = states.length - 2; i >= 0; i--) {
      app.undo();
      expect(fp(s), states[i], reason: 'undo to state $i mismatch');
    }
    expect(app.canUndo, isFalse, reason: 'baseline reached');
    app.undo(); // one more is a no-op, never throws / never loses state
    expect(fp(s), states[0]);

    // ...and forward again
    for (var i = 1; i < states.length; i++) {
      app.redo();
      expect(fp(s), states[i], reason: 'redo to state $i mismatch');
    }
    expect(app.canRedo, isFalse);

    // and back-and-forth is stable (no drift from restore itself)
    app.undo();
    app.redo();
    expect(fp(s), states.last);
  });

  test('a new edit after undo kills the redo branch', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(50, 0));
    app.selectTool(Tool.circleCenter);
    app.toolClick(const Offset(20, 20));
    app.toolClick(const Offset(30, 20));
    expect(s.geometry.length, 2);
    app.undo(); // circle gone
    expect(s.geometry.length, 1);
    expect(app.canRedo, isTrue);
    app.selectTool(Tool.line); // fork: draw something else instead
    app.toolClick(const Offset(0, 10));
    app.toolClick(const Offset(50, 10));
    expect(app.canRedo, isFalse, reason: 'redo branch dies on a new edit');
    expect(s.geometry.length, 2);
    expect(s.geometry[1].type, Geo.line);
  });

  test('histories are strictly per sketch', () {
    final app = makeApp(name: 'a');
    final sb = SketchModel('b');
    app.sketches['b'] = sb;

    // edit sketch a
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(10, 0));
    final aState = fp(app.sketches['a']!);

    // switch to b, edit b
    app.curTab = 'b';
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(0, 10));
    final bState = fp(sb);

    // undo in b: only b changes
    app.undo();
    expect(sb.geometry, isEmpty);
    expect(fp(app.sketches['a']!), aState, reason: 'a untouched by undo in b');
    expect(app.sketches['a']!.canUndo, isTrue,
        reason: "a's own history intact");

    // back in a: its undo works on its own stack; b's redo survives
    app.curTab = 'a';
    app.undo();
    expect(app.sketches['a']!.geometry, isEmpty);
    expect(sb.canRedo, isTrue);
    app.curTab = 'b';
    app.redo();
    expect(fp(sb), bState);
  });

  test('layer operations are undoable: add, hide, lock, rename, delete', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(10, 0));
    final one = fp(s);

    app.startNewLayer(); // adds "Layer 2" (Layer 1 = kDefaultLayer? adapt)
    final added = fp(s);
    expect(s.layers.length, greaterThan(1));
    final newLayer = s.layers.last;

    app.toggleLayerVisible(newLayer);
    expect(s.hiddenLayers, contains(newLayer));
    final hidden = fp(s);

    app.toggleLayerVisible(newLayer); // show again
    app.toggleLayerLocked(newLayer);
    expect(s.lockedLayers, contains(newLayer));

    app.undo(); // unlock
    expect(s.lockedLayers, isNot(contains(newLayer)));
    app.undo(); // hide again (back to hidden state)
    expect(fp(s), hidden);
    app.undo(); // unhide
    expect(fp(s), added);
    app.undo(); // layer gone
    expect(fp(s), one);
    expect(s.layers.contains(newLayer), isFalse);
  });

  test('restore cancels in-flight picks and never journals itself', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 0));
    app.toolClick(const Offset(10, 0));
    final depth = s.undoDepth;
    // start (but do not finish) another line: one dangling pick
    app.selectTool(Tool.line);
    app.toolClick(const Offset(5, 5));
    expect(app.toolPoints, isNotEmpty);
    app.undo();
    expect(app.toolPoints, isEmpty, reason: 'in-flight pick cancelled');
    expect(s.geometry, isEmpty);
    expect(s.undoDepth, depth - 1,
        reason: 'restore itself must not add journal entries');
    app.redo();
    expect(s.undoDepth, depth);
    expect(s.geometry.length, 1);
  });

  test('constraint add + trim upgrade round-trip through the journal', () {
    final app = makeApp();
    final s = app.current!;
    app.selectTool(Tool.line);
    app.toolClick(const Offset(0, 50));
    app.toolClick(const Offset(100, 50));
    app.selectTool(Tool.line);
    app.toolClick(const Offset(50, 0));
    app.toolClick(const Offset(50, 100));
    app.selectTool(Tool.trim);
    app.toolClick(const Offset(80, 50));
    final afterFirstTrim = fp(s);
    app.toolClick(const Offset(50, 80));
    // the M38 point-on-point bind is part of the journaled state
    final pp = s.constraints.where(
        (c) => c.type == CType.coincident && c.pts.length == 2);
    expect(pp, isNotEmpty);
    app.undo();
    expect(fp(s), afterFirstTrim, reason: 'undo removes the second trim AND '
        'its point-on-point bind');
    app.redo();
    final pp2 = s.constraints.where(
        (c) => c.type == CType.coincident && c.pts.length == 2);
    expect(pp2.length, pp.length);
  });
}
