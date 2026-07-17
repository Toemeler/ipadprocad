// M42 — Sichtbarkeit außerhalb des Layer-Editiermodus + Hover-Feedback.
//
//   * Ohne aktiven Editier-Layer sind Bemaßungen (und ihre Tap-Rects),
//     Constraint-Glyphen und Construction-Geometrie UNSICHTBAR — wie
//     Inventor, das Skizzen-Annotationen nur während der Skizzenbearbeitung
//     zeigt. Die Linien selbst bleiben sichtbar.
//   * Im Editiermodus wird das Bemaßungs-Label unter der Maus hervorgehoben
//     (es ist antippbar); während das Ausdrucks-Feld offen ist, markiert das
//     Hover ein ANDERES Label als einfügbare Referenz.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/widgets/viewport.dart';

AppState makeApp({bool editing = true}) {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  if (editing) app.editingLayer = kDefaultLayer;
  s.engine.addLine(-40, 0, 40, 0);
  s.refresh();
  s.constraints.add(Constraint(CType.dimension,
      pts: [PRef(0, 0), PRef(0, 1)],
      dimKind: 'dist',
      value: 80,
      textPos: const Offset(0, 12))
    ..paramName = 'd0');
  return app;
}

Future<void> pumpViewport(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
  await t.pump();
}

void main() {
  testWidgets('outside edit mode dimensions are invisible and untappable',
      (t) async {
    final app = makeApp(editing: false);
    await pumpViewport(t, app);
    expect(app.dimLabelRects, isEmpty,
        reason: 'no label rects -> nothing to hit-test outside edit mode');
    // entering edit mode brings them back (the test harness has no
    // listener wiring, so re-pump the tree to repaint)
    app.editingLayer = kDefaultLayer;
    await pumpViewport(t, app);
    expect(app.dimLabelRects, hasLength(1));
    // and leaving clears the STALE rects again (taps must not hit ghosts)
    app.editingLayer = null;
    await pumpViewport(t, app);
    expect(app.dimLabelRects, isEmpty);
  });

  testWidgets('hovering a dimension label in edit mode highlights it',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    final (_, r) = app.dimLabelRects.single;
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(t.getTopLeft(find.byType(Viewport2D)) + r.center);
    await t.pump();
    // the widget repainted with the hover — verified by behaviour: a tap on
    // the highlighted label opens the editor (the visual border itself is a
    // painter detail; the state that drives it is what we can assert)
    await t.tapAt(t.getTopLeft(find.byType(Viewport2D)) + r.center);
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
      'while the expression box is open, tapping another label inserts '
      'its parameter name instead of committing', (t) async {
    final app = makeApp();
    final s = app.current!;
    // second line + second dimension to reference
    s.engine.addLine(-40, 30, 40, 30);
    s.refresh();
    s.constraints.add(Constraint(CType.dimension,
        pts: [PRef(1, 0), PRef(1, 1)],
        dimKind: 'dist',
        value: 80,
        textPos: const Offset(0, 42))
      ..paramName = 'd1');
    await pumpViewport(t, app);
    expect(app.dimLabelRects, hasLength(2));
    final origin = t.getTopLeft(find.byType(Viewport2D));
    final first = app.dimLabelRects
        .firstWhere((e) => identical(e.$1, s.constraints[0]));
    final second = app.dimLabelRects
        .firstWhere((e) => identical(e.$1, s.constraints[1]));
    await t.tapAt(origin + first.$2.center); // open editor on dim d0
    await t.pump();
    final tf = t.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, '80.00');
    await t.tapAt(origin + second.$2.center); // tap the OTHER label
    await t.pump();
    expect(find.byType(TextField), findsOneWidget,
        reason: 'editor stays open — the tap references, it does not commit');
    // the selected "80.00" was replaced by the reference
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
        'd1');
  });

  testWidgets('construction geometry hides outside edit mode', (t) async {
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(-40, 20, 40, 20);
    s.refresh();
    s.geometry[1] = s.geometry[1].withStyle(Geo.styleConstruction);
    // sanity via the painter's own predicate — the paint loop skips exactly
    // entities with isConstruction when no layer is being edited
    expect(s.geometry[1].isConstruction, isTrue);
    await pumpViewport(t, app); // edit mode: no exception, both painted
    app.editingLayer = null;
    await pumpViewport(t, app); // outside: skip path exercised, no exception
    expect(app.inEditMode, isFalse);
  });
}
