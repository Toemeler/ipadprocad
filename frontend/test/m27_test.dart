// M27 — tap/double-tap on an existing dimension opens the inline editor.
//
// The old hit test compared the tap against textPos, but for 'dist' kinds the
// painter RECOMPUTES the label position (midpoint of the dimension line + a
// 10px normal offset) — the text is not at textPos at all, which made
// dimensions nearly untappable. The painter now records the screen rect of
// every label it draws (AppState.dimLabelRects); taps hit-test those rects.
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/widgets/viewport.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  s.engine.addLine(-40, 0, 40, 0);
  s.refresh();
  // a driving length dimension on the line, text parked above it
  s.constraints.add(Constraint(CType.dimension,
      pts: [PRef(0, 0), PRef(0, 1)],
      dimKind: 'dist',
      value: 80,
      textPos: const Offset(0, 12)));
  return app;
}

Future<void> pumpViewport(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
  await t.pump();
}

void main() {
  testWidgets('painter records the REAL screen rect of the dimension label',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    expect(app.dimLabelRects, hasLength(1));
    final (c, r) = app.dimLabelRects.single;
    expect(c.dimKind, 'dist');
    // the label must be wide enough for "80.00 mm" — a 14px disc around the
    // anchor (the old test) could never cover it
    expect(r.width, greaterThan(40));
    expect(r.height, greaterThan(10));
  });

  testWidgets('tap on the painted label opens the inline value editor',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    final (_, r) = app.dimLabelRects.single;
    // tap the EDGE of the label, far from the textPos anchor — the spot the
    // old anchor test missed
    await t.tapAt(Offset(r.left + 2, r.center.dy));
    await t.pump();
    expect(find.byType(TextField), findsOneWidget,
        reason: 'inline editor must open on a label tap');
    expect(
        (t.widget<TextField>(find.byType(TextField)).controller!).text,
        '80.00');
  });

  testWidgets('second tap of a double tap keeps the editor open', (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    final (_, r) = app.dimLabelRects.single;
    await t.tapAt(r.center);
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    // double tap: the second tap lands on the same label — it must NOT hit
    // the "click elsewhere commits" branch and close the field
    await t.tapAt(r.center);
    await t.pump();
    expect(find.byType(TextField), findsOneWidget,
        reason: 'double tap must not commit-close the editor it just opened');
  });

  testWidgets('tap elsewhere while editing commits and closes (Inventor)',
      (t) async {
    final app = makeApp();
    await pumpViewport(t, app);
    final (_, r) = app.dimLabelRects.single;
    await t.tapAt(r.center);
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    await t.tapAt(r.center + const Offset(160, 120)); // far away
    await t.pump();
    expect(find.byType(TextField), findsNothing,
        reason: 'clicking away commits, the dimension stays');
    expect(app.current!.constraints.single.value, closeTo(80, 1e-9));
  });

  testWidgets(
      'Dimension tool active: tapping an existing label edits it '
      'instead of starting a new pick', (t) async {
    final app = makeApp();
    app.tool = Tool.dimension;
    await pumpViewport(t, app);
    final (_, r) = app.dimLabelRects.single;
    await t.tapAt(r.center);
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(app.conPts, isEmpty, reason: 'no dimension pick was started');
    expect(app.conEnts, isEmpty);
  });
}
