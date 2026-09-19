import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/ai_composer.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/viewport_window.dart';

void main() {
  const a = AiDocument(id: 'a', name: 'Bracket', kind: 'part');
  const b = AiDocument(id: 'b', name: 'Mounting sketch', kind: 'sketch');

  AppState appForTest() {
    final dir = Directory.systemTemp.createTempSync('ipc_ai_composer');
    final app = AppState()..docsDirForTest = dir;
    app.ai.initializeInMemory();
    app.ai.updateWorkspace(current: a, documents: const [a, b]);
    app.ai.toggle();
    addTearDown(() {
      app.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return app;
  }

  Future<void> pumpComposer(WidgetTester tester, AppState app,
      {Size size = const Size(900, 740),
      double scale = 1,
      double keyboard = 0}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: Scaffold(
            body: DialogDockScope(
                size: size, child: Stack(children: [AiComposer(app: app)]))),
      ),
    ));
    await tester.pump();
  }

  String draftOnScreen(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('ai-draft')))
      .controller!
      .text;

  testWidgets('each named session restores its own draft', (tester) async {
    final app = appForTest();
    await pumpComposer(tester, app);
    final original = app.ai.currentSession.id;
    await tester.enterText(
        find.byKey(const ValueKey('ai-draft')), 'Keep the mounting pattern');
    app.ai.newSession();
    await tester.pump();
    expect(draftOnScreen(tester), isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('ai-draft')), 'Explore another handle');
    app.ai.selectSession(original);
    await tester.pump();
    expect(draftOnScreen(tester), 'Keep the mounting pattern');
    expect(app.ai.sessions, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tab context switches do not transfer drafts or attachments',
      (tester) async {
    final app = appForTest();
    await pumpComposer(tester, app);
    app.ai.updateDraft('Only for the bracket');
    app.ai.addAttachment(AiAttachment.fromBytes(
        name: 'reference.txt',
        bytes: Uint8List.fromList(utf8.encode('Mating dimensions'))));
    app.ai.updateWorkspace(current: b, documents: const [a, b]);
    await tester.pump();
    expect(draftOnScreen(tester), isEmpty);
    expect(find.text('reference.txt'), findsNothing);
    app.ai.updateWorkspace(current: a, documents: const [a, b]);
    await tester.pump();
    expect(draftOnScreen(tester), 'Only for the bracket');
    expect(find.text('reference.txt'), findsOneWidget);
    await tester.tap(find.byTooltip(L.current.aiRemoveAttachment));
    await tester.pump();
    expect(app.ai.currentSession.attachments, isEmpty);
    expect(ViewportWindow.count, 1);
    app.ai.close();
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-draft')), findsNothing);
    app.ai.toggle();
    await tester.pump();
    expect(draftOnScreen(tester), 'Only for the bracket');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ViewportWindow.count, 0);
  });

  testWidgets('linked documents are explicit and removable', (tester) async {
    final app = appForTest();
    app.ai.setContextDocument(b.id, true);
    await pumpComposer(tester, app);
    expect(find.text(b.name), findsOneWidget);
    await tester.tap(find.byTooltip(L.current.aiRemoveContext));
    await tester.pump();
    expect(app.ai.currentSession.contextDocumentIds, isEmpty);
    expect(find.text(b.name), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact panel remains bounded with a keyboard and large text',
      (tester) async {
    final app = appForTest();
    await pumpComposer(tester, app,
        size: const Size(360, 600), scale: 1.6, keyboard: 280);
    expect(find.byKey(const ValueKey('ai-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(ViewportWindow));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.bottom, lessThanOrEqualTo(320));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
