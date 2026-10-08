// The part's Parameters window (Manage > Parameters): lists the part's user
// parameters and the sketch dimensions by their part-wide names; Add makes a
// row, the equation cell commits, the unit cell cycles mm / deg / ul.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/fmt.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/ios_kit.dart';
import 'package:prototype/widgets/parameters_dialog.dart';

import 'm56_part_test.dart' show FakeKernel;

void main() {
  Future<AppState> part(WidgetTester t) async {
    final app = AppState()
      ..partKernel = FakeKernel()
      ..docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m500d_');
    await t.runAsync(() => app.createNamedPart('Table'));
    return app;
  }

  Future<void> pump(WidgetTester t, AppState app) async {
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: DialogDockScope(
          size: const Size(1200, 800),
          child: ListenableBuilder(
            listenable: app,
            builder: (_, __) =>
                Stack(children: [PartParametersDialog(app: app)]),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('a value field driven by a parameter says fx: and its value',
      (t) async {
    final app = await part(t);
    app.addPartParam(raw: 'Thick = 4');
    final c = TextEditingController(text: 'Thick * 2');
    final n = TextEditingController(text: 'Holes');
    Widget rows() => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              iosValueRow(
                  app: app,
                  label: 'Distance',
                  controller: c,
                  unit: 'mm',
                  onChanged: (_) {}),
              iosValueRow(
                  app: app,
                  label: 'Count',
                  controller: n,
                  integer: true,
                  onChanged: (_) {}),
            ]),
          ),
        );
    await t.pumpWidget(rows());
    expect(find.text('fx: ${Fmt.fixed(8, 2)} mm'), findsOneWidget);
    expect(find.text(L.current.msgUnknownParam('Holes')), findsOneWidget,
        reason: 'an unknown name is named, not just a red field');
    // a count field takes a name too (it used to filter to digits)
    await t.enterText(find.byType(TextField).at(1), 'Thick+1');
    expect(n.text, 'Thick+1');
    await t.pumpWidget(rows());
    expect(find.text('fx: ${Fmt.fixed(5, 2)}'), findsOneWidget);
    // a plain number shows no fx line
    c.text = '12';
    await t.pumpWidget(rows());
    expect(find.textContaining('fx:'), findsOneWidget);
  });

  testWidgets('Manage > Parameters opens the part table', (t) async {
    final app = await part(t);
    expect(app.showPartParams, isFalse);
    app.togglePartParams();
    expect(app.showPartParams, isTrue);
    app.addPartParam(raw: 'Thick = 4');
    await pump(t, app);
    expect(find.text('Thick'), findsOneWidget);
    expect(find.text('${Fmt.fixed(4, 2)} mm'), findsOneWidget);
    // Add another row
    final words = L.of(t.element(find.byType(PartParametersDialog)));
    expect(find.text(words.hintPartParameters), findsOneWidget);
    await t.tap(find.text(words.btnAddNumericParameter));
    await t.pump();
    expect(app.currentPart!.params.map((u) => u.name), ['Thick', 'User_1']);
    // the unit cell cycles
    await t.tap(find.text('${Fmt.fixed(4, 2)} mm'));
    await t.pump();
    expect(app.currentPart!.params.first.unit, 'deg');
    expect(find.text('${Fmt.fixed(4, 2)}°'), findsOneWidget);
    // the equation cell commits an expression naming another parameter
    final eq = find.byType(TextField).at(3); // User_1: name, equation
    await t.enterText(eq, 'Thick * 3');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(app.currentPart!.params[1].value, 12);
    expect(app.currentPart!.params[1].expr, 'Thick * 3');
  });
}
