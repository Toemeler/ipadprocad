// M450 — the panel is the size of whoever has to act next.
//
// The redesign has exactly one rule, and these are the cases of it:
//   * the assistant is working and needs nothing -> a circle in the corner
//   * the user has to do something               -> the full card
// plus the ordering fix: the title of a task is on screen BEFORE the task
// runs, not after it finishes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/ai_composer.dart';
import 'package:prototype/widgets/ai_stage.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/viewport_window.dart';

void main() {
  const a = AiDocument(id: 'a', name: 'Bracket', kind: 'part');

  AppState appForTest() {
    final dir = Directory.systemTemp.createTempSync('ipc_ai_stage');
    final app = AppState()..docsDirForTest = dir;
    app.ai.initializeInMemory();
    app.ai.updateWorkspace(current: a, documents: const [a]);
    app.ai.toggle();
    addTearDown(() {
      app.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return app;
  }

  /// Advances past the retract/expand morph.
  ///
  /// NOT `pumpAndSettle`: the parked orb turns for as long as the work lasts,
  /// so the tree deliberately never reaches a settled state. Settling is only
  /// meaningful in the reduced-motion test at the bottom, which is the one
  /// case where the loops are supposed to stop.
  Future<void> morph(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(kAiMorphDuration + const Duration(milliseconds: 60));
  }

  /// Waits out the announcement dwell and the retract that follows it.
  ///
  /// The leading bare pump is load-bearing: the dwell timer is started by the
  /// build that first sees the task, so the clock must not be advanced until
  /// that build has happened. Advance first and the timer is scheduled for
  /// later than the moment it was meant to fire, and nothing ever retracts.
  Future<void> announceThenRetract(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(kAiAnnounceDwell + const Duration(milliseconds: 50));
    await morph(tester);
  }

  Future<void> pump(WidgetTester tester, AppState app,
      {Size size = const Size(900, 740)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: DialogDockScope(
              size: size, child: Stack(children: [AiComposer(app: app)])),
        ),
      ),
    ));
    await tester.pump();
  }

  /// The stage's current footprint, which is the whole subject of this file.
  Size stage(WidgetTester tester) =>
      tester.getRect(find.byType(ViewportWindow)).size;

  bool collapsed(WidgetTester tester) =>
      find.byType(AiOrbCore).evaluate().isNotEmpty;

  /// The parked circle itself. Deliberately not [stage], which measures the
  /// whole footprint — that includes the status pill sitting to the orb's
  /// left, so it is legitimately taller and much wider than the circle.
  Size orb(WidgetTester tester) => tester.getSize(find.byType(AiOrbCore));

  testWidgets('a task announces its title before it runs, then retracts',
      (tester) async {
    final app = appForTest();
    await pump(tester, app);

    // Idle: the full card, asking the Shortcuts question.
    expect(collapsed(tester), isFalse);
    expect(find.text(L.current.aiWelcomeTitle), findsOneWidget);
    expect(find.text(L.current.aiWelcomeExample), findsOneWidget);

    // A task begins. The TITLE IS ALREADY THERE — this is the ordering the
    // redesign exists to fix; it used to arrive a provider round later.
    app.ai.debugSetActivity(
        AiActivity(AiPhase.thinking, title: 'Make me a capstan drive'));
    await tester.pump();
    expect(find.text('Make me a capstan drive'), findsOneWidget);
    expect(collapsed(tester), isFalse,
        reason: 'the announcement must be readable before it retracts');
    final announced = stage(tester);
    expect(announced.width, greaterThan(300));

    // ...and once it has been on screen long enough, it gets out of the way.
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);
    expect(orb(tester).width, closeTo(kAiOrbSize, 1));
    expect(orb(tester).height, closeTo(kAiOrbSize, 1));
    // The whole footprint — circle plus the status pill beside it — is still
    // a fraction of the card it replaced.
    expect(stage(tester).width, lessThan(announced.width));

    // The circle still says what it is doing, which is the other half of the
    // requirement: retracting must not mean going quiet.
    expect(find.text('Make me a capstan drive'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the parked orb keeps naming the op it is on', (tester) async {
    final app = appForTest();
    await pump(tester, app);
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);

    // A block starts running: the second line follows the ops, so a minute of
    // one unchanging word can never look like a hang (issue #70).
    app.ai.debugSetActivity(AiActivity(AiPhase.working,
        op: 'extrude', step: 2, total: 5, title: 'Build it'));
    await tester.pump();
    expect(find.textContaining(L.current.aiWorkBuilding), findsOneWidget);
    expect(find.textContaining(L.current.aiStepOf(2, 5)), findsOneWidget);
    expect(collapsed(tester), isTrue, reason: 'running a block needs nobody');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('it comes back the moment the work is over', (tester) async {
    final app = appForTest();
    await pump(tester, app);
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);

    app.ai.debugSetActivity(AiActivity.none);
    await morph(tester);
    expect(collapsed(tester), isFalse);
    // ...and you can type into it again, which is the whole reason it grew.
    expect(find.byKey(const ValueKey('ai-draft')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the parked orb opens it back up mid-task',
      (tester) async {
    final app = appForTest();
    await pump(tester, app);
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);

    await tester.tap(find.byType(AiOrbCore));
    await morph(tester);
    // Still working — but the user asked to watch, so it stays open.
    expect(app.ai.activity.isBusy, isTrue);
    expect(collapsed(tester), isFalse);
    expect(find.byKey(const ValueKey('ai-draft')), findsOneWidget);

    // The next task retracts again: one look is not a preference.
    app.ai.debugSetActivity(AiActivity.none);
    await tester.pump();
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Again'));
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a circle cannot show an error, so an error keeps the card up',
      (tester) async {
    final app = appForTest();
    await pump(tester, app);
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    expect(collapsed(tester), isTrue);

    app.ai.currentSession.errorCode = 'quota';
    app.ai.debugNotify();
    await morph(tester);
    expect(collapsed(tester), isFalse,
        reason: 'something is wrong and a 62pt circle cannot say what');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the parked stage stays inside the screen', (tester) async {
    final app = appForTest();
    await pump(tester, app, size: const Size(390, 700));
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    final rect = tester.getRect(find.byType(ViewportWindow));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion holds the animations still', (tester) async {
    final app = appForTest();
    await tester.binding.setSurfaceSize(const Size(900, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(900, 740), disableAnimations: true),
        child: Scaffold(
          body: DialogDockScope(
              size: const Size(900, 740),
              child: Stack(children: [AiComposer(app: app)])),
        ),
      ),
    ));
    await tester.pump();
    app.ai.debugSetActivity(AiActivity(AiPhase.thinking, title: 'Build it'));
    await announceThenRetract(tester);
    // Settles AT ALL, which is the real assertion here: a controller left
    // repeating under `disableAnimations` makes this time out instead.
    await tester.pumpAndSettle();
    expect(collapsed(tester), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
