// M448 — issue #71: the user sees a title, the model keeps working, and it
// asks before it guesses.
//
// Three complaints, one turn of the loop apart:
//
//   "I CURRENTLY SEE THE JSON OUTPUT." The panel showed the reply with the
//   fenced block stripped out — except that stripping a reply which is
//   NOTHING BUT a block left the empty string, and the old code treated empty
//   as "nothing to strip" and printed the whole thing. The one case the strip
//   existed for was the one case it did not handle.
//
//   "IT SHOULD WORK UNTIL IT IS PRODUCTION READY." The app cannot judge a tea
//   cup. It can hold the model to the definition of done the MODEL wrote: the
//   "must" requirements in this document's brief. Stopping with some open is
//   pushed back on, with the list; stopping to ASK is not, because a question
//   is waiting on the user and pushing past it is how a dimension gets
//   guessed.
//
//   "IT SHOULD ASK HOW IT IS MADE." A cup for FDM and a cup for injection
//   moulding are different cups. That one is a prompt rule, so the test is on
//   the prompt — the only thing about it this app can actually assert.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';

const _document = AiDocument(id: 'doc', name: 'Cup', kind: 'part');

void main() {
  AiController controllerWith(_Backend backend) {
    final c = AiController(backend: backend)..initializeInMemory();
    addTearDown(c.dispose);
    c
      ..contextReader = ((id) async => {'id': id, 'name': 'Cup'})
      ..updateWorkspace(current: _document, documents: const [_document]);
    return c;
  }

  group('the JSON never reaches the user', () {
    test('a reply that is only a block shows nothing at all', () {
      const reply = '```cad\n{"actions":[{"op":"extrude","distance":5}]}\n```';
      expect(aiReplyWithoutActions(reply), isEmpty);
    });

    test('a reply with prose around a block keeps only the prose', () {
      const reply = 'Rim is 2 mm.\n\n```cad\n{"actions":[{"op":"look"}]}\n```\n';
      expect(aiReplyWithoutActions(reply), 'Rim is 2 mm.');
    });

    test('bare JSON is executed rather than printed', () {
      const reply =
          '{"title":"Drawing the body","actions":[{"op":"create_sketch"}]}';
      final block = parseAiActions(reply);
      expect(block.actions.map((a) => a.op), ['create_sketch']);
      expect(block.title, 'Drawing the body');
      expect(aiReplyWithoutActions(reply), isEmpty);
    });

    test('bare JSON amid prose leaves the prose', () {
      const reply = 'Starting.\n'
          '{"actions":[{"op":"create_sketch","plane":"xy"}]}\n'
          'Next the wall.';
      expect(parseAiActions(reply).actions, hasLength(1));
      expect(aiReplyWithoutActions(reply), 'Starting.\n\nNext the wall.');
    });

    test('a json-tagged fence counts as a block', () {
      const reply = '```json\n{"actions":[{"op":"describe_part"}]}\n```';
      expect(parseAiActions(reply).actions.single.op, 'describe_part');
      expect(aiReplyWithoutActions(reply), isEmpty);
    });

    test('an example beside a real block is NOT executed', () {
      // A reply that uses the agreed fence is parsed strictly: anything
      // outside it is prose, including prose that happens to look like JSON.
      const reply = 'A block looks like {"actions": [{"op": "extrude"}]}.\n'
          '```cad\n{"actions":[{"op":"describe_part"}]}\n```';
      final block = parseAiActions(reply);
      expect(block.actions.map((a) => a.op), ['describe_part']);
      expect(aiReplyWithoutActions(reply),
          'A block looks like {"actions": [{"op": "extrude"}]}.');
    });

    test('prose with a JSON-looking object but no ops is left alone', () {
      const reply = 'Use {"depth": 5} as the parameter.';
      expect(parseAiActions(reply).actions, isEmpty);
      expect(aiReplyWithoutActions(reply), reply);
    });

    test('a block cut off mid-JSON is not shown as text', () {
      // What a truncated reply leaves: nothing closes, so nothing parses —
      // and printing the fragment is worse than printing nothing.
      const reply = '{"title":"Drawing","actions":[{"op":"extru';
      expect(aiReplyWithoutActions(reply), isEmpty);
    });

    test('braces inside a string do not truncate the block', () {
      const reply =
          '{"actions":[{"op":"rename_feature","feature":"f","name":"a } b"}]}';
      final block = parseAiActions(reply);
      expect(block.actions.single.text('name'), 'a } b');
      expect(aiReplyWithoutActions(reply), isEmpty);
    });
  });

  group('the title is what the user reads', () {
    test('it is parsed off the block', () {
      const reply = '```cad\n{"title":"Rounding the rim",'
          '"actions":[{"op":"fillet","radius":1}]}\n```';
      expect(parseAiActions(reply).title, 'Rounding the rim');
    });

    test('a missing title is not a parse error — the block still runs', () {
      const reply = '```cad\n{"actions":[{"op":"describe_part"}]}\n```';
      final block = parseAiActions(reply);
      expect(block.parseError, isNull);
      expect(block.actions, hasLength(1));
      expect(block.title, isNull);
    });

    test('an essay of a title is clamped, not shown whole', () {
      final long = 'Now I am going to draw the outer profile of the cup body '
          'and then extrude it upwards by fifty millimetres';
      final block = parseAiActions(
          '```cad\n${jsonEncode({'title': long, 'actions': [
            {'op': 'look'}
          ]})}\n```');
      expect(block.title!.length, lessThanOrEqualTo(kAiTitleMaxLength));
      expect(block.title, startsWith('Now I am going to draw'));
    });

    test('it rides the activity while the block runs', () async {
      final seen = <String?>[];
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Drawing the body",'
                  '"actions":[{"op":"create_sketch"},{"op":"extrude"}]}\n```'
              : 'Done.',
          'test'));
      final controller = controllerWith(backend);
      controller.actionRunner = (batch, {onStep}) async {
        for (var i = 0; i < batch.length; i++) {
          onStep?.call(batch[i].op, i + 1, batch.length);
          seen.add(controller.activity.title);
        }
        return AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]);
      };
      controller.updateDraft('Make a cup');
      await controller.send();
      expect(seen, ['Drawing the body', 'Drawing the body']);
    });

    test('it survives into the stored transcript', () async {
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Hollowing the cup",'
                  '"actions":[{"op":"extrude","distance":-2}]}\n```'
              : 'Done.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.updateDraft('Hollow it');
      await controller.send();
      final tool =
          controller.currentSession.messages.firstWhere((m) => m.role == 'tool');
      expect(AiActionReport.decode(tool.text)!.title, 'Hollowing the cup');
    });
  });

  group('it keeps working while its own requirements are open', () {
    test('stopping with an open "must" is pushed back on', () async {
      // Round 0 builds. Round 1 says it is done while the brief still has an
      // open must; the app tells it so, and round 2 builds again.
      final backend = _Backend((i) async => AiReply(
          i == 0 || i == 2
              ? '```cad\n{"title":"Building","actions":[{"op":"extrude"}]}\n```'
              : 'All finished.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.briefs.add(
          'doc',
          AiRequirement(
              text: 'It must have a handle.', kind: AiRequirementKind.must));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(backend.requests.length, greaterThan(2),
          reason: 'the model must have been asked to continue');
      final nudge = controller.currentSession.messages.firstWhere((m) =>
          m.role == 'tool' && m.text.contains('openRequirements'));
      expect(jsonDecode(nudge.text)['openRequirements'],
          contains('It must have a handle.'));
    });

    test('the push-back is bounded, not a loop', () async {
      var builds = 0;
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Building","actions":[{"op":"extrude"}]}\n```'
              : 'All finished.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async {
            // The push-back reads the part back before it nags, so only a
            // batch that CHANGES something counts as a build here.
            if (batch.any((a) => !kAiReadOnlyOps.contains(a.op))) builds++;
            return AiActionReport(
                outcomes: [for (final a in batch) AiActionOutcome(a.op)]);
          });
      controller.briefs.add(
          'doc',
          AiRequirement(
              text: 'It must have a handle.', kind: AiRequirementKind.must));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(builds, 1);
      final nudges = controller.currentSession.messages
          .where((m) => m.text.contains('openRequirements'))
          .length;
      expect(nudges, kAiMaxDoneChecks);
    });

    test('a question is never pushed past — it is waiting on the user',
        () async {
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Building","actions":[{"op":"extrude"}]}\n```'
              : 'Wie soll die Tasse gefertigt werden?',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.briefs.add('doc',
          AiRequirement(text: 'Must hold 200 ml.', kind: AiRequirementKind.must));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(backend.requests, hasLength(2));
      expect(
          controller.currentSession.messages
              .any((m) => m.text.contains('openRequirements')),
          isFalse);
    });

    test('a conversation that built nothing is left alone', () async {
      final backend = _Backend((_) async => const AiReply('A cup is a cup.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.briefs.add('doc',
          AiRequirement(text: 'Must hold 200 ml.', kind: AiRequirementKind.must));
      controller.updateDraft('What makes a good cup?');
      await controller.send();
      expect(backend.requests, hasLength(1));
    });

    test('an assumption is not a definition of done', () async {
      // Only "must" holds the loop open. The assistant cannot invent work for
      // itself by recording its own guesses.
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Building","actions":[{"op":"extrude"}]}\n```'
              : 'Done.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.briefs.add('doc',
          AiRequirement(text: 'Probably 80 mm tall.'));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(backend.requests, hasLength(2));
    });

    test('the push-back hands over the part as it actually is now', () async {
      // ISSUE #72 — told only "keep going", with no state, the model re-added
      // a duplicate of the base plate it had already built and then deleted
      // it again. The reminder carries the shape now.
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Building","actions":[{"op":"extrude"}]}\n```'
              : 'All finished.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async {
            if (batch.single.op == 'describe_shape') {
              return AiActionReport(outcomes: const [
                AiActionOutcome('describe_shape',
                    detail: {'shape': 'SHAPE Solid1 — 140 x 70 x 8 mm'})
              ]);
            }
            return AiActionReport(
                outcomes: [for (final a in batch) AiActionOutcome(a.op)]);
          });
      controller.briefs.add('doc',
          AiRequirement(text: 'Must have a floor.', kind: AiRequirementKind.must));
      controller.updateDraft('Make me a holder');
      await controller.send();
      final nudge = controller.currentSession.messages
          .firstWhere((m) => m.text.contains('openRequirements'));
      final decoded = jsonDecode(nudge.text) as Map;
      expect(decoded['partNow'], contains('140 x 70 x 8'));
      expect(decoded['note'], contains('Do not rebuild anything'));
    });

    test('the round budget allows a whole part, and still ends', () {
      expect(kAiMaxActionRounds, greaterThanOrEqualTo(30));
      expect(kAiMaxDoneChecks, lessThanOrEqualTo(5));
    });
  });

  group('it asks how the thing is made', () {
    test('the instructions name the processes and the geometry each needs',
        () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      final sent = backend.requests.single.instructions;
      expect(sent, contains('BUILD FIRST — DO NOT ASK'));
      for (final process in [
        'FDM',
        'SLA',
        'Casting',
        'Injection moulding',
        'CNC',
      ]) {
        expect(sent, contains(process));
      }
      // Asking is worthless if the answer changes nothing, so the rules the
      // answer implies are in the prompt too.
      expect(sent, contains('draft'));
      expect(sent, contains('undercuts'));
    });

    test('the instructions scale the effort to the ask', () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Add a hole');
      await controller.send();
      final sent = backend.requests.single.instructions;
      expect(sent, contains('MATCH THE EFFORT TO THE ASK'));
      expect(sent, contains('no questions, no extras'));
      expect(sent, contains('EVERY BLOCK CARRIES A TITLE'));
      expect(sent, contains('WORK UNTIL IT IS DONE'));
    });

    test('a model that cannot edit is told none of it', () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend); // no runner attached
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(backend.requests.single.instructions,
          isNot(contains('MATCH THE EFFORT TO THE ASK')));
    });
  });
}

/// Replies by round index.
class _Backend implements AiBackend {
  _Backend(this.reply);
  final FutureOr<AiReply> Function(int round) reply;
  final requests = <AiRequest>[];

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
