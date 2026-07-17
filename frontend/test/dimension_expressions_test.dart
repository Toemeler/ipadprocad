// M41 — Inventors Parameter-/Ausdrucks-System für Bemaßungen.
//   * Auto-Namen d0, d1, … pro Skizze; Umbenennen per "Name = expr"
//   * volles Ausdrucks-Parsing (Operatoren, Einheiten, Funktionen, PI/E)
//   * Referenzen auf andere Bemaßungen; Änderung propagiert durch die Kette
//   * Zyklen werden abgelehnt; ungültige Syntax committet nicht
//   * fx-Anzeige: expr nur gesetzt, wenn KEINE bloße Zahl eingegeben wurde
//   * Sidecar-JSON round-trippt Name + Ausdruck (und damit das Undo-Journal)

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

/// Draws a line from a to b and returns its entity index.
int drawLine(AppState app, Offset a, Offset b) {
  app.tool = Tool.line;
  app.toolClick(a);
  app.toolClick(b);
  app.tool = Tool.none;
  return app.current!.geometry.length - 1;
}

/// Places a dist dimension between the endpoints of line [e] and confirms
/// it with [text] through the full edit-box path.
Constraint dimLine(AppState app, int e, String text) {
  final s = app.current!;
  final d = Constraint(CType.dimension,
      pts: [PRef(e, 0), PRef(e, 1)],
      dimKind: 'dist',
      textPos: const Offset(0, -10));
  app.pendingDim = d;
  app.confirmDimensionText(text);
  expect(s.constraints.contains(d), isTrue);
  return d;
}

double lineLen(AppState app, int e) {
  final g = app.current!.geometry[e];
  return (Offset(g.data[0], g.data[1]) - Offset(g.data[2], g.data[3]))
      .distance;
}

void main() {
  group('expression engine', () {
    test('operators, precedence, units, constants, functions', () {
      final p = <String, double>{'d0': 10, 'Width': 4};
      expect(evalExpr('2 + 3 * 4', p), closeTo(14, 1e-12));
      expect(evalExpr('(2 + 3) * 4', p), closeTo(20, 1e-12));
      expect(evalExpr('2 ^ 3 ^ 2', p), closeTo(512, 1e-12)); // right assoc
      expect(evalExpr('7 % 4', p), closeTo(3, 1e-12));
      expect(evalExpr('1 cm + 5 mm', p), closeTo(15, 1e-12));
      expect(evalExpr('0.5 m', p), closeTo(500, 1e-12));
      expect(evalExpr('1,5 cm', p), closeTo(15, 1e-12)); // EU decimal comma
      expect(evalExpr('d0 / 2 + Width', p), closeTo(9, 1e-12));
      expect(evalExpr('sqrt(16) + abs(-2)', p), closeTo(6, 1e-12));
      expect(evalExpr('min(3; 7) + max(2; 5)', p), closeTo(8, 1e-12));
      expect(evalExpr('2 * PI', p), closeTo(6.283185307, 1e-6));
      expect(evalExpr('sin(30)', p), closeTo(0.5, 1e-12)); // deg like Inventor
      expect(evalExpr('atan(1)', p), closeTo(45, 1e-9));
      // angle domain: rad literal converts to degrees
      expect(evalExpr('0.5 rad', p, angle: true),
          closeTo(28.647889757, 1e-6));
      // errors -> null (Inventor red)
      expect(evalExpr('2 +', p), isNull);
      expect(evalExpr('nope * 2', p), isNull);
      expect(evalExpr('2 & 2', p), isNull);
      expect(evalExpr('1 / 0', p), isNull); // non-finite
    });

    test('plain-number detection and assignment split', () {
      expect(isPlainNumber('12'), isTrue);
      expect(isPlainNumber('1,5 cm'), isTrue);
      expect(isPlainNumber('d0*2'), isFalse);
      expect(isPlainNumber('10+2'), isFalse);
      expect(splitAssignment('W = d0/2'), ('W', 'd0/2'));
      expect(splitAssignment('42'), (null, '42'));
      expect(isValidParamName('Width_2'), isTrue);
      expect(isValidParamName('mm'), isFalse); // reserved
      expect(isValidParamName('2x'), isFalse);
      expect(exprRefs('d0/2 + sin(Width) * PI'), {'d0', 'Width'});
    });
  });

  group('parameters on dimensions', () {
    test('auto names d0, d1 assigned; plain entry stores value, no expr', () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      final a = dimLine(app, e0, '40');
      final b = dimLine(app, e1, '25');
      expect(a.paramName, 'd0');
      expect(b.paramName, 'd1');
      expect(a.expr, isNull); // bare number -> no fx
      expect(a.value, closeTo(40, 1e-6));
      expect(lineLen(app, e0), closeTo(40, 1e-6));
    });

    test('expression references another dimension and follows its changes',
        () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      final a = dimLine(app, e0, '40');
      final b = dimLine(app, e1, 'd0 / 2 + 5');
      expect(b.expr, 'd0 / 2 + 5');
      expect(b.value, closeTo(25, 1e-6));
      expect(lineLen(app, e1), closeTo(25, 1e-6));
      // change the referenced parameter -> the dependent recalculates AND
      // the geometry follows
      app.setDimensionValue(a, 60);
      expect(b.value, closeTo(35, 1e-6));
      expect(lineLen(app, e1), closeTo(35, 1e-6));
      // chained: c = d1 * 2 tracks through the chain
      final e2 = drawLine(app, const Offset(0, 40), const Offset(30, 40));
      final c = dimLine(app, e2, 'd1 * 2');
      expect(c.value, closeTo(70, 1e-6));
      app.setDimensionValue(a, 20);
      expect(b.value, closeTo(15, 1e-6));
      expect(c.value, closeTo(30, 1e-6));
      expect(lineLen(app, e2), closeTo(30, 1e-6));
    });

    test('rename via "Name = expr" updates references in other expressions',
        () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      final a = dimLine(app, e0, '40');
      final b = dimLine(app, e1, 'd0 / 2');
      expect(app.setDimensionText(a, 'Width = 50'), isTrue);
      expect(a.paramName, 'Width');
      expect(b.expr, 'Width / 2'); // reference followed the rename
      expect(b.value, closeTo(25, 1e-6));
      // the new name is usable
      expect(app.setDimensionText(b, 'Width / 5'), isTrue);
      expect(b.value, closeTo(10, 1e-6));
      // name collision rejected
      expect(app.setDimensionText(b, 'Width = 1'), isFalse);
    });

    test('cycles and self references are rejected', () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      final a = dimLine(app, e0, '40');
      final b = dimLine(app, e1, 'd0 / 2');
      expect(app.setDimensionText(a, 'd0 * 2'), isFalse); // self
      expect(app.setDimensionText(a, 'd1 + 1'), isFalse); // d1 depends on d0
      expect(a.expr, isNull); // nothing stuck
      expect(a.value, closeTo(40, 1e-6));
      // invalid syntax / unknown param don't commit either
      expect(app.setDimensionText(a, '2 +'), isFalse);
      expect(app.setDimensionText(a, 'ghost * 2'), isFalse);
      expect(app.dimTextValid(a, 'd1 + 1'), isFalse);
      expect(app.dimTextValid(b, 'd0 * 3'), isTrue);
    });

    test('driven (reference) dimension can be referenced and its dependents '
        'track the measurement', () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      // driven dim on e0 (measures, does not drive)
      final drv = Constraint(CType.dimension,
          pts: [PRef(e0, 0), PRef(e0, 1)],
          dimKind: 'dist',
          textPos: const Offset(0, -10));
      app.pendingDim = drv;
      app.confirmDimension(null, driven: true);
      expect(drv.driven, isTrue);
      expect(drv.paramName, isNotNull);
      final dep = dimLine(app, e1, '${drv.paramName} / 2');
      expect(dep.value, closeTo(25, 1e-6));
      // driven dims cannot take expressions themselves
      expect(app.setDimensionText(drv, '10'), isFalse);
    });

    test('expression + name survive the sidecar JSON round-trip', () {
      final c = Constraint(CType.dimension,
          pts: [PRef(0, 0), PRef(0, 1)],
          dimKind: 'dist',
          textPos: const Offset(1, 2))
        ..value = 25
        ..paramName = 'Width'
        ..expr = 'd0 / 2 + 5';
      final back = Constraint.fromJson(c.toJson());
      expect(back.paramName, 'Width');
      expect(back.expr, 'd0 / 2 + 5');
      expect(back.value, closeTo(25, 1e-12));
    });

    test('undo/redo round-trips expressions through the journal', () {
      final app = makeApp();
      final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
      final e1 = drawLine(app, const Offset(0, 20), const Offset(30, 20));
      dimLine(app, e0, '40');
      final b = dimLine(app, e1, 'd0 / 2');
      expect(b.value, closeTo(20, 1e-6));
      final s = app.current!;
      // confirmDimensionText journals TWO steps: create (measured value),
      // then apply the expression — undo peels them individually
      app.undo(); // drop the expression, keep the dimension
      final bMid = s.constraints
          .lastWhere((c) => c.type == CType.dimension && c.paramName == 'd1');
      expect(bMid.expr, isNull);
      app.undo(); // drop dim b entirely
      expect(
          s.constraints.where((c) => c.type == CType.dimension).length, 1);
      app.redo();
      app.redo();
      final b2 = s.constraints
          .lastWhere((c) => c.type == CType.dimension && c.expr != null);
      expect(b2.expr, 'd0 / 2');
      expect(b2.paramName, 'd1');
      expect(b2.value, closeTo(20, 1e-6));
    });
  });
}
