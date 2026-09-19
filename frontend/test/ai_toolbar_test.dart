import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/bug_button.dart';
import 'package:prototype/widgets/quick_tools.dart';

void main() {
  AppState makeApp() {
    final dir = Directory.systemTemp.createTempSync('ipc_ai_toolbar');
    final app = AppState()..docsDirForTest = dir;
    addTearDown(() {
      app.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return app;
  }

  test('AI stays available across gallery and every document kind', () {
    final app = makeApp();
    void expectAvailable() {
      final items =
          buildQuickTools(app).where((item) => item.id == QuickToolId.ai);
      expect(items, hasLength(1));
      expect(items.single.enabled, isTrue);
      expect(items.single.symbol, isNotEmpty);
      expect(items.single.fallback, isNotEmpty);
    }

    expectAvailable();
    app.sketches['Sketch'] = SketchModel('Sketch');
    app.curTab = 'Sketch';
    expectAvailable();
    app.parts['Part'] = PartModel('Part');
    app.curTab = 'Part';
    expectAvailable();
    app.assemblies['Assembly'] = AssemblyModel('Assembly');
    app.curTab = 'Assembly';
    expectAvailable();
  });

  test('toolbar toggles the composer without arming a CAD tool', () {
    final app = makeApp();
    final originalTool = app.tool;
    expect(app.ai.isOpen, isFalse);
    runQuickTool(app, QuickToolId.ai);
    expect(app.ai.isOpen, isTrue);
    expect(
        buildQuickTools(app)
            .firstWhere((item) => item.id == QuickToolId.ai)
            .selected,
        isTrue);
    expect(app.tool, originalTool);
    runQuickTool(app, QuickToolId.ai);
    expect(app.ai.isOpen, isFalse);
  });

  testWidgets(
      'AI is visible without a right click, even with reporting disabled',
      (tester) async {
    BugReport.enabled = false;
    addTearDown(() => BugReport.enabled = true);
    final app = makeApp();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [QuickToolsBar(app: app)]))));
    expect(find.bySemanticsLabel(L.current.aiTitle), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(L.current.aiTitle));
    expect(app.ai.isOpen, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
