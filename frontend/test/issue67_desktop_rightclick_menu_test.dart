// #67 — "when i rightclick on a extrusion a sketch or something in windows i
// only get the toolbar but not the normal rightclick menu. i want to get both
// in a normal rightclickmenu all of the options"
//
// Every row of this tree ALREADY has a full menu. `_featureMenu`,
// `_sketchMenu` and `_bodyMenu` build them, `_onMenuSelection` dispatches
// them, and until now only UIKit could put one on screen. Off iOS the rows
// fell back to whatever single action seemed most likely at the time:
//
//   sketch LAYER row   -> a real menu, through _showCtx
//   FEATURE row        -> _confirmDeleteFeature, and nothing else
//   work feature row   -> onDelete, and nothing else
//   child SKETCH row   -> nothing at all
//   solid BODY row     -> nothing at all
//
// So Edit, Show/Hide, Rename, Share, Copy, Cut, "to document", Make Part —
// all defined, all reachable by long-pressing on an iPad, none of them
// reachable with a mouse. That is the report, and "i only get the toolbar"
// is the ribbon changing under the selection being the only thing that
// responded.
//
// The fix is one bridge rather than five menus: `_showNativeStyleCtx` renders
// the SAME NativeMenuItem groups and routes the taps to the SAME
// `_onMenuSelection`. What this file pins is that the desktop menu is the
// native one — because the way this drifted in the first place is a menu
// being added on one platform and forgotten on the other.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/model_browser.dart';

import 'm56_part_test.dart' show FakeKernel;

AppState _app() {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_i67_');
  app.volatileDirsForTest = const [];
  final p = PartModel('P');
  app.parts['P'] = p;
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

/// An extrusion, as the browser lists one.
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

/// A right-click on [finder], as a mouse delivers one.
Future<void> _rightClick(WidgetTester t, Finder finder) async {
  // startGesture allocates a FRESH pointer id each time. Reusing one (as
  // createGesture + downWithCustomEvent does) trips the binding's own
  // `!_hitTests.containsKey(event.pointer)` on the second click.
  final g = await t.startGesture(t.getCenter(finder),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('THE REPORT: an extrusion opens the full menu, not a delete',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);

    final row = find.text('Extrusion1');
    expect(row, findsOneWidget, reason: 'the row this report right-clicks');

    await _rightClick(t, row);

    final l = L.of(t.element(find.byType(ModelBrowser)));
    // Every item _featureMenu defines, which is what "all of the options"
    // means. Before this, a right-click went straight to the delete
    // confirmation and the other three could not be reached with a mouse.
    expect(find.text(l.ctxEditFeature), findsOneWidget);
    expect(find.text(l.hide), findsOneWidget);
    expect(find.text(l.rename), findsOneWidget);
    expect(find.text(l.delete), findsOneWidget);
  });

  testWidgets('and it is a MENU — the delete confirmation does not appear',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);
    await _rightClick(t, find.text('Extrusion1'));

    // The old behaviour, stated as the thing that must not happen: a right
    // click is a question about what you want, not the execution of one
    // answer. The confirmation belongs behind the Delete row.
    expect(find.text(l10nDeleteTitle(t, 'Extrusion1')), findsNothing);
  });

  testWidgets('Delete is separated from the rest, the way UIKit groups it',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    await _pump(t, app);
    await _rightClick(t, find.text('Extrusion1'));

    // _featureMenu returns TWO groups, and the second one is Delete alone.
    // Rendering them as one list would read as a fifth ordinary action.
    expect(find.byType(ModelBrowser), findsOneWidget);
    final sep = find.byWidgetPredicate((w) =>
        w is Container &&
        w.child == null &&
        w.margin == const EdgeInsets.symmetric(vertical: 4));
    expect(sep, findsWidgets,
        reason: 'the group separator the native menu draws');
  });

  testWidgets('a second right-click replaces the menu rather than stacking',
      (t) async {
    final app = _app();
    _extrusion(app, 'Extrusion1');
    _extrusion(app, 'Extrusion2');
    await _pump(t, app);

    await _rightClick(t, find.text('Extrusion1'));
    await _rightClick(t, find.text('Extrusion2'));

    final l = L.of(t.element(find.byType(ModelBrowser)));
    // One Rename, not two: _showNativeStyleCtx closes whatever is open first.
    expect(find.text(l.rename), findsOneWidget);
  });
}

/// The confirmation's own title, so the assertion above names the real string
/// rather than a guess at it.
String l10nDeleteTitle(WidgetTester t, String name) =>
    L.of(t.element(find.byType(ModelBrowser))).dlgDeleteNamed(name);
