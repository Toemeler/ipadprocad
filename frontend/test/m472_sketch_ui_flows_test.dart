// M472 — 2D sketching through the UI tool paths (HUD typing, tools, deletes),
// pinned one user-visible defect per group.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/hud.dart';

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
}
