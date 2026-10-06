// M472 — 2D sketching through the UI tool paths (HUD typing, tools, deletes),
// pinned one user-visible defect per group.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/hud.dart';
import 'package:prototype/l10n/l.dart';

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

/// Every key the viewport hands the HUD; the HUD must claim each of them
/// (an unclaimed key falls through to the tool shortcuts and is lost).
void typeKeys(AppState app, String keys) {
  for (final ch in keys.split('')) {
    expect(app.hudType(ch), isTrue, reason: 'the HUD takes "$ch"');
  }
}

void main() {
  group('HUD typing reads what a German user types', () {
    List<double?> dimsAfterTyping(String w, String h) {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.hoverWorld = const Offset(30, 20);
      expect(app.hudActive, isTrue);
      expect(hudFieldsFor(app.tool, app.toolPoints.length), hasLength(2));
      typeKeys(app, w);
      app.hudTab();
      typeKeys(app, h);
      app.hudEnter();
      return [
        for (final c in s.constraints)
          if (c.type == CType.dimension) c.value
      ];
    }

    test('a decimal comma is a decimal point ("10,5" is not 105)', () {
      final v = dimsAfterTyping('10,5', '7,25');
      expect(v, hasLength(2));
      expect(v, containsAll([closeTo(10.5, 1e-9), closeTo(7.25, 1e-9)]));
    });

    test('an expression is evaluated ("20/2" is 10, "(40-6)/2" is 17)', () {
      final v = dimsAfterTyping('20/2', '(40-6)/2');
      expect(v, containsAll([closeTo(10, 1e-9), closeTo(17, 1e-9)]));
    });

    test('a click places with the typed expression too, not only Enter', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.hoverWorld = const Offset(30, 20);
      typeKeys(app, '12,5');
      app.hudTab();
      typeKeys(app, '30/3');
      app.toolClick(const Offset(30, 20)); // a tap, the value still pending
      final v = [
        for (final c in s.constraints)
          if (c.type == CType.dimension) c.value
      ];
      expect(v, containsAll([closeTo(12.5, 1e-9), closeTo(10, 1e-9)]));
    });

    test('a minus after a digit subtracts, a leading one negates', () {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.hoverWorld = const Offset(30, 20);
      typeKeys(app, '30-5');
      expect(app.hudInput, '30-5');
      typeKeys(app, '..');
      expect(app.hudInput, '30-5.', reason: 'one separator per number');
      app.hudInput = '';
      typeKeys(app, '--');
      expect(app.hudInput, isEmpty, reason: 'a second minus undoes the first');
      expect(app.hudType('l'), isFalse,
          reason: 'letters stay tool shortcuts while the HUD is up');
    });
  });

  group('the line tool', () {
    test('closing the loop ends the chain; the next click starts afresh', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.line;
      for (final p in const [
        Offset(10, 10), Offset(50, 10), Offset(50, 30), Offset(10, 30),
        Offset(10, 10), // back on the start: the profile is closed
      ]) {
        app.toolClick(p);
      }
      expect(s.geometry, hasLength(4));
      expect(app.tool, Tool.line, reason: 'the command stays armed');
      expect(app.toolPoints, isEmpty,
          reason: 'no rubber band hangs off the closed corner');
      app.toolClick(const Offset(80, 80));
      expect(s.geometry, hasLength(4),
          reason: 'the next click is the first point of a NEW line');
      expect(app.toolPoints, [const Offset(80, 80)]);
    });

    test('landing on some other line\'s end keeps the chain going', () {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.line;
      app.toolClick(const Offset(10, 60));
      app.toolClick(const Offset(40, 60));
      app.cancelTool(); // Esc: the first chain ends, tool stays
      expect(app.tool, Tool.line);
      for (final p in const [Offset(10, 10), Offset(40, 10), Offset(40, 60)]) {
        app.toolClick(p);
      }
      expect(s.geometry, hasLength(3));
      expect(app.toolPoints, hasLength(1),
          reason: 'only the chain\'s own start closes it');
    });
  });

  group('typing a dimension value', () {
    (AppState, SketchModel) circleWithDiameter() {
      final app = makeApp();
      final s = app.current!;
      app.tool = Tool.circleCenter;
      app.toolClick(const Offset(20, 20));
      app.toolClick(const Offset(30, 20));
      app.cancelTool();
      app.tool = Tool.dimension;
      app.toolClick(const Offset(30, 20)); // the rim
      app.toolClick(const Offset(40, 40)); // place
      expect(app.pendingDim?.dimKind, 'dia');
      return (app, s);
    }

    for (final typed in ['0', '-5', '0,0']) {
      test('"$typed" for a diameter is refused and said why', () {
        final (app, s) = circleWithDiameter();
        app.message = null;
        expect(app.confirmDimensionText(typed), isFalse);
        final circle = s.geometry.singleWhere((g) => g.type == Geo.circle);
        expect(circle.data[2], closeTo(10, 1e-6),
            reason: 'the circle did not collapse to a point');
        final dim = s.constraints.singleWhere((c) => c.type == CType.dimension);
        expect(dim.value, closeTo(20, 1e-6),
            reason: 'the dimension keeps its measured value');
        expect(app.message, L.current.msgDimensionPositive);
      });
    }

    test('a German decimal comma and an expression still go in', () {
      final (app, s) = circleWithDiameter();
      expect(app.confirmDimensionText('10,5'), isTrue);
      final circle = s.geometry.singleWhere((g) => g.type == Geo.circle);
      expect(circle.data[2], closeTo(5.25, 1e-6));
    });
  });
}
