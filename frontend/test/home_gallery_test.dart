// Home gallery (Procreate-style start page).
//
//  * A fresh install (no saved sketches) shows the empty state, NOT the old
//    six design-dummy cards — those fake, unopenable cards are gone.
//  * Saved sketches render as thumbnail cards showing name + date; tapping a
//    card opens that sketch (a tab appears, we leave home).
//  * The header "+" button creates a new sketch.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/widgets/home_view.dart';

AppState makeApp() {
  final app = AppState();
  // openSketch / createNewSketch probe the sketch directory on disk; give them
  // a scratch dir so the host test has no platform channel dependency.
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_home_test');
  return app;
}

Future<void> pumpHome(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: HomeView(app: app)))));
  await t.pump();
}

void main() {
  testWidgets('fresh install shows empty state, no dummy sketch cards',
      (t) async {
    final app = makeApp();
    expect(app.saved, isEmpty);
    await pumpHome(t, app);

    // Empty state is ONE line of text and nothing else — the cube glyph and
    // the "No sketches yet" heading were decoration.
    expect(find.text('Tap  +  to create a new sketch'), findsOneWidget);
    expect(find.text('No sketches yet'), findsNothing);
    // None of the old design-dummy names leak through.
    for (final name in const [
      'Bracket_v2',
      'Flange',
      'Plate_120x80',
      'Gasket',
      'Shaft_Profile',
      'Cam_Outline',
    ]) {
      expect(find.text(name), findsNothing, reason: '$name must be gone');
    }
  });

  testWidgets('saved sketches render as cards and open on tap', (t) async {
    final app = makeApp();
    app.saved = [
      SavedSketchInfo('Bracket_v2', DateTime(2026, 6, 24, 17, 27), null),
      SavedSketchInfo('Flange', DateTime(2026, 7, 7, 10, 18), null),
    ];
    await pumpHome(t, app);

    expect(find.text('Bracket_v2'), findsOneWidget);
    expect(find.text('Flange'), findsOneWidget);
    expect(find.text('No sketches yet'), findsNothing);

    // Tapping a card opens that sketch and leaves the home view.
    await t.tap(find.text('Bracket_v2'));
    await t.pump();
    expect(app.isHome, isFalse);
    expect(app.curTab, 'Bracket_v2');
    expect(app.openTabs, contains('Bracket_v2'));
  });

  testWidgets('plus button asks for a name before creating anything',
      (t) async {
    final app = makeApp();
    await pumpHome(t, app);
    expect(app.openTabs, isEmpty);

    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();

    // Nothing exists yet — the prompt comes FIRST.
    expect(find.text('New sketch'), findsOneWidget);
    expect(app.openTabs, isEmpty);
    // Pre-filled with the next free name so Create alone is enough.
    expect(find.text(app.suggestedSketchName()), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Bracket');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(app.isHome, isFalse);
    expect(app.curTab, 'Bracket');
    // ...and we land INSIDE a fresh layer, ready to draw.
    expect(app.inEditMode, isTrue);
    expect(app.editingLayer, isNotNull);
  });

  testWidgets('cancelling the name prompt creates nothing', (t) async {
    final app = makeApp();
    await pumpHome(t, app);

    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(app.openTabs, isEmpty);
    expect(app.isHome, isTrue);
  });

  testWidgets('the name prompt refuses a name that is already taken',
      (t) async {
    final app = makeApp();
    await app.createNamedSketch('Taken');
    app.goHome();
    await pumpHome(t, app);

    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Taken');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(find.text('A sketch with that name already exists'), findsOneWidget);
  });
}
