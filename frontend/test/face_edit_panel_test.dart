// The face-edit panel: Delete Face, Direct Edit and Shell can be APPLIED.
//
// M217 built the three face commands down to the kernel and the viewport's
// face picking, and never built the panel with the OK button: `applyFaceEdit`
// had no caller, so a user could pick faces and then do nothing with them.
// These tests drive the panel the way a user does — open the command, pick a
// face, type the number, tap OK — and check that a feature lands.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/gen/app_l10n_en.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart' show kFacePlane;
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/face_edit_dialog.dart';

import 'support/shape_fixtures.dart';

final en = AppL10nEn();

Future<AppState> _plate(WidgetTester t) async {
  final app = AppState()..partKernel = BoxKernel();
  await t.runAsync(() async {
    app.docsDirForTest =
        Directory.systemTemp.createTempSync('prototype_face_panel_');
    await app.createNamedPart('Work');
    final r = await AiCad(app).run(const [
      AiAction('create_sketch', {'plane': 'xz'}),
      AiAction('sketch_rect', {'width': 60, 'height': 40}),
      AiAction('extrude', {'distance': 10}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
  });
  return app;
}

/// The box fixture's first face: z = 0, normal -Z, 60 x 40.
FacePick _bottom() => FacePick(30, 20, 0, 0, 0, -1, 2400, kFacePlane);

Future<void> _pump(WidgetTester t, AppState app) async {
  t.view.physicalSize = const Size(2200, 2800);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (_, __) => Stack(children: [FaceEditDialog(app: app)]),
      ),
    ),
  ));
  await t.pump();
  while (t.takeException() != null) {}
}

Future<void> _tapOk(WidgetTester t) async {
  // The first "OK" is the panel's; a second one is the keypad's Done while a
  // field is being edited.
  await t.tap(find.text(en.ok).first);
  // applyFaceEdit rebuilds and saves; let its real I/O finish.
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await t.pump();
  while (t.takeException() != null) {}
}

/// Lets the app's debounced saves fire, so no timer outlives the test.
Future<void> _settle(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() {
    L.set(kEn);
    T.palette = kEmber;
  });

  testWidgets('Shell: pick the open face, set the wall, OK builds it',
      (t) async {
    final app = await _plate(t);
    app.openShell();
    expect(app.faceEdit?.kind, FaceEditKind.shell);
    await _pump(t, app);
    expect(find.text(en.cmdShell), findsOneWidget);
    expect(app.faceEditReady, isFalse, reason: 'no face picked yet');

    app.toggleFacePick(_bottom(), 0);
    await t.pump();
    expect(find.text(en.lblFaceCount(1)), findsOneWidget);
    await t.enterText(find.byType(EditableText).first, '1.5');
    await t.pump();
    expect(app.faceEdit!.thickness, 1.5);
    expect(app.faceEditReady, isTrue);

    await _tapOk(t);
    final f = app.currentPart!.features.last;
    expect(f, isA<ShellFeature>());
    expect((f as ShellFeature).thickness, 1.5);
    expect(f.computeError, isNull);
    expect(app.faceEdit, isNull, reason: 'the panel closes on success');
    await _settle(t);
  });

  testWidgets('Delete Face: OK applies the pick', (t) async {
    final app = await _plate(t);
    app.openDeleteFace();
    await _pump(t, app);
    app.toggleFacePick(_bottom(), 0);
    await t.pump();
    await _tapOk(t);
    expect(app.currentPart!.features.last, isA<DeleteFaceFeature>());
    await _settle(t);
  });

  testWidgets('Move: a distance along the picked face\'s own normal',
      (t) async {
    final app = await _plate(t);
    app.openDirectMove();
    await _pump(t, app);
    app.toggleFacePick(_bottom(), 0);
    await t.enterText(find.byType(EditableText).first, '3');
    await t.pump();
    await _tapOk(t);
    final f = app.currentPart!.features.last as DirectEditFeature;
    expect(f.op, DirectOp.move);
    // The bottom face points -Z, so "3 mm out of it" is dz = -3.
    expect([f.dx, f.dy, f.dz], [0, 0, -3]);
    await _settle(t);
  });

  testWidgets('OK stays disabled until the command has what it needs',
      (t) async {
    final app = await _plate(t);
    app.openDirectScale();
    expect(app.faceEditReady, isFalse, reason: 'a factor of 1 changes nothing');
    app.setFaceEditValue(factor: 2);
    expect(app.faceEditReady, isTrue, reason: 'scale takes no faces');
    app.cancelFaceEdit();
    app.openShell();
    app.toggleFacePick(_bottom(), 0);
    app.setFaceEditValue(thickness: 0);
    expect(app.faceEditReady, isFalse);
    await _settle(t);
  });
}
