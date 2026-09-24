// M444 — a few words about what is happening, instead of paragraphs to read.
//
// "Ich will nur in wenigen Worten wissen was gerade getan wird ... alles
// andere komplett im Hintergrund."
//
// Two claims are under test here, and they are different in kind.
//
//   THE STATUS IS THE APP'S OWN. It is derived from the work the app is
//   actually doing, never from the model narrating itself. A narrated status
//   arrives only when the model does — after the work — and is one more thing
//   it can get wrong. So the test drives a real send() and watches the phase
//   change while the request is still in flight.
//
//   EVERY OP HAS A WORD. `AiActivity.work` ends in a `_ => working` default,
//   so adding an op and forgetting to give it a word compiles and then shows
//   the user "Working…" forever. Nothing but a test catches that.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';

const _document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');

void main() {
  AiController controllerWith(_Backend backend) {
    final c = AiController(backend: backend)..initializeInMemory();
    addTearDown(c.dispose);
    c
      ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
      ..updateWorkspace(current: _document, documents: const [_document]);
    return c;
  }

  group('every op the assistant can run has a word for it', () {
    test('no op falls through to the generic label', () {
      final generic = <String>[];
      for (final op in kAiOps) {
        if (AiActivity(AiPhase.working, op: op).work == AiWork.working) {
          generic.add(op);
        }
      }
      expect(generic, isEmpty,
          reason: 'these ops would show the user "Working…" and nothing more: '
              '${generic.join(", ")}. Give each one a word in AiActivity.work.');
    });

    test('the words group work rather than naming every op', () {
      // The point is a few words, not a log line per action: several ops must
      // share a word or the status is just the protocol read aloud.
      final words = {for (final op in kAiOps) AiActivity(AiPhase.working, op: op).work};
      expect(words.length, lessThan(kAiOps.length));
      expect(AiActivity(AiPhase.working, op: 'sketch_rect').work,
          AiActivity(AiPhase.working, op: 'sketch_circle').work);
    });

    test('with no op in flight the phase is thinking, not working', () {
      expect(AiActivity(AiPhase.thinking).work, AiWork.thinking);
      expect(AiActivity.none.isBusy, isFalse);
      expect(AiActivity(AiPhase.thinking).isBusy, isTrue);
    });
  });

  group('the status tracks the work as it happens', () {
    test('thinking while the provider is answering', () async {
      final held = Completer<AiReply>();
      final backend = _Backend((_) => held.future);
      final controller = controllerWith(backend);
      controller.updateDraft('Make a plate');
      final sending = controller.send();

      await backend.firstRequest.future;
      // Still in flight: the panel must already be saying something.
      expect(controller.activity.phase, AiPhase.thinking);
      expect(controller.activity.isBusy, isTrue);

      held.complete(const AiReply('Done.', 'test'));
      await sending;
      expect(controller.activity.phase, AiPhase.idle);
    });

    test('working, naming the op, while a block runs', () async {
      final seen = <AiActivity>[];
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? 'Building.\n```cad\n{"actions":[{"op":"create_sketch"},'
                  '{"op":"extrude","distance":5}]}\n```'
              : 'Done.',
          'test'));
      final controller = controllerWith(backend);
      controller.actionRunner = (batch, {onStep}) async {
        for (var i = 0; i < batch.length; i++) {
          onStep?.call(batch[i].op, i + 1, batch.length);
          seen.add(controller.activity);
        }
        return AiActionReport(outcomes: [
          for (final a in batch) AiActionOutcome(a.op),
        ]);
      };
      controller.updateDraft('Make a plate');
      await controller.send();

      expect(seen.map((a) => a.phase), everyElement(AiPhase.working));
      expect(seen.map((a) => a.op), ['create_sketch', 'extrude']);
      expect(seen.map((a) => a.work), [AiWork.sketching, AiWork.building]);
      // It counts, so a long block does not look stuck.
      expect(seen.first.step, 1);
      expect(seen.first.total, 2);
      expect(controller.activity.phase, AiPhase.idle);
    });

    test('cancelling puts the status back to idle', () async {
      final held = Completer<AiReply>();
      final backend = _Backend((_) => held.future);
      final controller = controllerWith(backend);
      controller.updateDraft('Make a plate');
      final sending = controller.send();
      await backend.firstRequest.future;
      controller.cancel();
      expect(controller.activity.phase, AiPhase.idle);
      held.complete(const AiReply('too late', 'test'));
      await sending;
      expect(controller.activity.phase, AiPhase.idle);
    });
  });

  group('issue #70 — small fast steps, visible as they land', () {
    test('a block is capped small enough to arrive quickly', () {
      // 24 let a model answer "make me an espresso cup" by planning the whole
      // part and emitting it at once: a minute of one unchanging word, and
      // nothing at all if any of it failed. Six then cost a round trip per
      // half-step (#83: 21 rounds for a cable clip). Twelve is one whole step,
      // and a failure no longer loses the steps before it (partial commit).
      expect(kAiMaxActionsPerBlock, lessThanOrEqualTo(12));
      // ...and the round budget has to allow the same part to still finish.
      expect(kAiMaxActionRounds, greaterThanOrEqualTo(8));
    });

    test('the instructions say to act now rather than plan', () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Make an espresso cup');
      await controller.send();
      final sent = backend.requests.first.instructions;
      expect(sent, contains('START NOW, IN SMALL STEPS'));
      expect(sent, contains('Do not plan the whole part before acting'));
      expect(sent, contains('stop and run its first step instead'));
    });

    test('many small blocks are allowed to finish the job', () async {
      // Four rounds used to be the ceiling, which with six-action blocks would
      // leave a cup with no handle.
      var rounds = 0;
      final backend = _Backend((i) async => AiReply(
          i < 6
              ? 'Step.\n```cad\n{"actions":[{"op":"create_sketch"}]}\n```'
              : 'Done.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async {
            rounds++;
            return AiActionReport(
                outcomes: [for (final a in batch) AiActionOutcome(a.op)]);
          });
      controller.updateDraft('Make an espresso cup');
      await controller.send();
      expect(rounds, 6, reason: 'every step should have been allowed to run');
      expect(controller.currentSession.messages.last.text, contains('Done.'));
    });

    test('the status carries how long it has been going', () async {
      final activity = AiActivity(AiPhase.thinking,
          since: DateTime.now().subtract(const Duration(seconds: 42)));
      // One unchanging word for a minute reads as a hang; a counter does not.
      expect(activity.elapsed.inSeconds, greaterThanOrEqualTo(42));
    });
  });

  group('the assistant is told to be brief', () {
    test('the instructions demand two sentences and a bare question',
        () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend);
      controller.updateDraft('Make a plate');
      await controller.send();
      final sent = backend.requests.first.instructions;
      expect(sent, contains('AT MOST TWO SHORT SENTENCES'));
      expect(sent, contains('QUESTION ALONE'));
      // The app already shows what it did; the model restating it is the
      // reading the user asked to stop doing.
      expect(sent, contains('the app already shows'));
    });
  });
}

/// Replies by round index, so a test can hold the first one open.
class _Backend implements AiBackend {
  _Backend(this.reply);
  final FutureOr<AiReply> Function(int round) reply;
  final requests = <AiRequest>[];
  final firstRequest = Completer<void>();

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    final round = requests.length;
    requests.add(AiRequest(
        id: request.id,
        instructions: request.instructions,
        context: request.context,
        messages: request.messages.toList()));
    if (!firstRequest.isCompleted) firstRequest.complete();
    return reply(round);
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<bool> hasKey(AiProvider provider) async => false;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}
