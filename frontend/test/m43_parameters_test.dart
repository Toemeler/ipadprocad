// M43 — Inventors Parameters dialog: User-Parameter im fx-Fenster.
//   * anlegen (Auto-Name User_1), Wert/Ausdruck setzen, umbenennen
//     ("Name = expr" UND Name-Zelle), Referenzen ziehen nach
//   * Bemaßungen dürfen User-Parameter referenzieren und umgekehrt;
//     Änderung propagiert durch die gemischte Kette bis in die Geometrie
//   * Zyklen über beide Arten hinweg abgelehnt; Löschen nur unreferenziert
//   * Sidecar-Codec + Undo-Journal round-trippen User-Parameter

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/params.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

int drawLine(AppState app, Offset a, Offset b) {
  app.tool = Tool.line;
  app.toolClick(a);
  app.toolClick(b);
  app.tool = Tool.none;
  return app.current!.geometry.length - 1;
}

Constraint dimLine(AppState app, int e, String text) {
  final d = Constraint(CType.dimension,
      pts: [PRef(e, 0), PRef(e, 1)],
      dimKind: 'dist',
      textPos: const Offset(0, -10));
  app.pendingDim = d;
  app.confirmDimensionText(text);
  return d;
}

double lineLen(AppState app, int e) {
  final g = app.current!.geometry[e];
  return (Offset(g.data[0], g.data[1]) - Offset(g.data[2], g.data[3]))
      .distance;
}

void main() {
  test('user params: create, expression, rename with reference follow-up',
      () {
    final app = makeApp();
    final s = app.current!;
    final u1 = app.addUserParam();
    expect(u1.name, 'User_1');
    expect(app.setUserParamText(u1, '25'), isTrue);
    expect(u1.value, closeTo(25, 1e-9));
    expect(u1.expr, isNull); // plain number
    final u2 = app.addUserParam();
    expect(u2.name, 'User_2');
    expect(app.setUserParamText(u2, 'User_1 * 2 + 5'), isTrue);
    expect(u2.value, closeTo(55, 1e-9));
    // rename via the equation cell's "Name = expr" form
    expect(app.setUserParamText(u1, 'Width = 30'), isTrue);
    expect(u1.name, 'Width');
    expect(u2.expr, 'Width * 2 + 5'); // reference followed
    expect(u2.value, closeTo(65, 1e-9));
    // rename via the NAME cell too
    expect(app.renameUserParam(u2, 'Depth'), isTrue);
    expect(s.userParams[1].name, 'Depth');
    // duplicates rejected either way
    expect(app.renameUserParam(u1, 'Depth'), isFalse);
    expect(app.setUserParamText(u1, 'Depth = 1'), isFalse);
  });

  test('dimension drives from a user param, and a user param from a dim '
      '(mixed chain propagates into geometry)', () {
    final app = makeApp();
    final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
    final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
    final w = app.addUserParam();
    app.setUserParamText(w, 'Width = 40');
    final a = dimLine(app, e0, 'Width'); // dim <- user param
    expect(a.value, closeTo(40, 1e-6));
    expect(lineLen(app, e0), closeTo(40, 1e-6));
    final half = app.addUserParam(); // user param <- dim
    app.setUserParamText(half, 'Half = ${a.paramName} / 2');
    expect(half.value, closeTo(20, 1e-9));
    final b = dimLine(app, e1, 'Half + 5'); // dim <- user <- dim <- user
    expect(b.value, closeTo(25, 1e-6));
    // change the root: everything follows, including geometry
    expect(app.setUserParamText(w, '60'), isTrue);
    expect(a.value, closeTo(60, 1e-6));
    expect(half.value, closeTo(30, 1e-9));
    expect(b.value, closeTo(35, 1e-6));
    expect(lineLen(app, e1), closeTo(35, 1e-6));
  });

  test('cycles across kinds rejected; delete only when unreferenced', () {
    final app = makeApp();
    final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
    final w = app.addUserParam();
    app.setUserParamText(w, 'Width = 40');
    final a = dimLine(app, e0, 'Width');
    // user param referencing the dim that references it = cycle
    expect(app.setUserParamText(w, '${a.paramName} / 2'), isFalse);
    expect(w.expr, isNull); // untouched
    expect(w.value, closeTo(40, 1e-9));
    // in use -> delete refused; after freeing the reference it works
    expect(app.deleteUserParam(w), isFalse);
    expect(app.setDimensionText(a, '40'), isTrue);
    expect(app.deleteUserParam(w), isTrue);
    expect(app.current!.userParams, isEmpty);
  });

  test('validation mirrors commit rules', () {
    final app = makeApp();
    final u = app.addUserParam();
    app.setUserParamText(u, '10');
    final v = app.addUserParam();
    expect(app.userParamTextValid(v, 'User_1 * 2'), isTrue);
    expect(app.userParamTextValid(v, 'ghost * 2'), isFalse);
    expect(app.userParamTextValid(v, '2 +'), isFalse);
    expect(app.userParamTextValid(v, '${v.name} + 1'), isFalse); // self
    expect(app.userParamTextValid(v, 'mm = 3'), isFalse); // reserved name
  });

  test('user params survive the sidecar codec and the undo journal', () {
    final ps = [UserParam('Width', 30, null), UserParam('Depth', 65, 'Width*2+5')];
    final back = decodeUserParams(encodeUserParams(ps));
    expect(back[0].name, 'Width');
    expect(back[0].expr, isNull);
    expect(back[1].expr, 'Width*2+5');
    expect(back[1].value, closeTo(65, 1e-12));

    final app = makeApp();
    final u = app.addUserParam(); // journal step 1
    app.setUserParamText(u, 'Width = 30'); // journal step 2
    expect(app.current!.userParams.single.name, 'Width');
    app.undo(); // back to unnamed zero param
    expect(app.current!.userParams.single.name, 'User_1');
    expect(app.current!.userParams.single.value, closeTo(0, 1e-12));
    app.undo(); // back to no user params at all
    expect(app.current!.userParams, isEmpty);
    app.redo();
    app.redo();
    expect(app.current!.userParams.single.name, 'Width');
    expect(app.current!.userParams.single.value, closeTo(30, 1e-12));
  });
}
