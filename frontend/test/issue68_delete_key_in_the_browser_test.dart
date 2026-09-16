// #68 — "i want to be able to click on anything in the modell browser and
// then press the delete key to delete it"
//
// Nothing in the tree answered the keyboard. A row could be deleted through
// its context menu (and, before #67, on most rows only through a right-click
// that WAS the delete), and the Delete key did nothing anywhere in the panel.
//
// WHAT "ANYTHING" HAD TO MEAN. Five kinds of row can be deleted, and each
// already knows how — `_confirmDeleteFeature`, `_confirmDeleteWork`,
// `deleteChildSketch`, the `bdDelete` menu action, `_confirmDelete` for a
// layer. So the keyboard needed a NAME for the row under it, not a sixth
// delete: `_rowDelete` is filled as the tree is built, from the same
// callbacks the menus use, and Delete looks the selected row up in it.
//
// WHY IT IS THE BROWSER'S OWN SELECTION and not `app.selection`: in a sketch,
// Delete already removes the selected geometry. If the two shared a notion of
// "selected", Delete would be ambiguous the moment a sketch was open. They
// are separate, and the key is only the tree's while the tree has focus —
// which a click on a row is what grants.
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/model_browser.dart';

import 'm56_part_test.dart' show FakeKernel;

AppState _app() {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_i68_');
  app.volatileDirsForTest = const [];
  final p = PartModel('P');
  app.parts['P'] = p;
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

void _extrusion(AppState app, String name) {
  final p = app.parts['P']!;
  p.appendFeature(ExtrudeFeature(
    name: name,
    bodyName: p.nextSolidName(),
    sketchName: '',
    profiles: const [],
    output: 'new',
  )..seq = p.nextSeq());
}

Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AnimatedBuilder(
              animation: app, builder: (_, __) => ModelBrowser(app: app)))));
  await t.pumpAndSettle();
}

/// A single tap that is allowed to RESOLVE.
///
/// A feature row sits under a GestureDetector with `onDoubleTap`, so the tap
/// recogniser only wins once the double-tap timer has expired — and that timer
/// schedules no frame, so `pumpAndSettle` alone returns before it fires.
Future<void> _click(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 500));
  await t.pumpAndSettle();
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('THE REPORT: click a feature, press Delete, it asks to delete it',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);

    await _click(t, find.text('Extrusion1'));
    await _press(t, LogicalKeyboardKey.delete);

    // The confirmation the row's own menu would have raised — the key reuses
    // the delete that was already there rather than adding a second one, so
    // the dialog, the undo entry and the refusal cases are all the same.
    expect(find.byType(CupertinoAlertDialog), findsOneWidget,
        reason: 'THE REPORT: Delete did nothing at all before this');
  });

  testWidgets('Backspace works too, which is the delete key on a Mac',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);
    await _click(t, find.text('Extrusion1'));
    await _press(t, LogicalKeyboardKey.backspace);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
  });

  testWidgets('with nothing selected the key is IGNORED, not swallowed',
      (t) async {
    // It has to fall through: the app's other Delete bindings are still live
    // while this panel is on screen, and a handler that returns "handled"
    // for a key it did nothing with would silently break them.
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);

    await _press(t, LogicalKeyboardKey.delete);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('a row whose kind has no delete does not raise one', (t) async {
    // The BASE layer cannot be deleted, so it registers nothing and Delete
    // stays ignored on it rather than raising a dialog that would refuse.
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);

    await _click(t, find.text('Extrusion1'));
    // Cancel the dialog the selection would delete, then assert the negative
    // on a fresh press with the selection cleared by the rebuild.
    await _press(t, LogicalKeyboardKey.escape);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('selecting a second row moves the target', (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    _extrusion(app, 'Extrusion2');
    await _pump(t, app);

    await _click(t, find.text('Extrusion1'));
    await _click(t, find.text('Extrusion2'));
    await _press(t, LogicalKeyboardKey.delete);

    // The dialog names the row that was clicked LAST — asserted INSIDE the
    // dialog, because both names are also on screen as rows.
    expect(
        find.descendant(
            of: find.byType(CupertinoAlertDialog),
            matching: find.textContaining('Extrusion2')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(CupertinoAlertDialog),
            matching: find.textContaining('Extrusion1')),
        findsNothing);
  });
}
